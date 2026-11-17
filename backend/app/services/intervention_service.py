"""Intervention tracking: alerts lead to documented protective actions with follow-up assessments."""
from __future__ import annotations

from ..repositories.repository import HeatGuardRepository
from ..schemas.alert import AlertEvent
from ..schemas.common import new_id, now_iso
from ..schemas.intervention import (
    INTERVENTION_LABELS,
    FollowUp,
    Intervention,
    InterventionComplete,
    InterventionCreate,
)
from .risk_engine import CATEGORY_LABELS

LEVEL = {"routine": 0, "caution": 1, "elevated": 2, "high": 3, "critical": 4}
MAX_FOLLOW_UPS = 30


def follow_up_from(assessment: dict | None, note: str) -> FollowUp:
    if not assessment:
        return FollowUp(timestamp=now_iso(), assessment_id=None, risk_category="unavailable", effective_wbgt=None, note=note)
    return FollowUp(timestamp=now_iso(), assessment_id=assessment["assessment_id"], risk_category=assessment["risk_category"],
                    effective_wbgt=assessment.get("effective_wbgt"), note=note)


class InterventionService:
    def __init__(self, repo: HeatGuardRepository):
        self.repo = repo

    def create(self, req: InterventionCreate) -> dict:
        crew = self.repo.crews.get(req.crew_id)
        if not crew:
            raise KeyError(f"Crew {req.crew_id} not found")
        alert = None
        if req.alert_id:
            alert = self.repo.alerts.get(req.alert_id)
            if not alert:
                raise KeyError(f"Alert {req.alert_id} not found")
            if alert["crew_id"] not in (req.crew_id, "__site__"):
                raise ValueError("Alert does not belong to this crew")
        changes: dict = {}
        if req.new_workload and req.new_workload != crew["workload"]:
            changes["workload"] = {"from": crew["workload"], "to": req.new_workload}
            crew["workload"] = req.new_workload
        if req.new_work_rest_regime and req.new_work_rest_regime != crew["work_rest_regime"]:
            changes["work_rest_regime"] = {"from": crew["work_rest_regime"], "to": req.new_work_rest_regime}
            crew["work_rest_regime"] = req.new_work_rest_regime
        if changes:
            crew["updated_at"] = now_iso()
            self.repo.save_crew(crew)

        iv = Intervention(
            intervention_id=new_id("int"),
            alert_id=req.alert_id,
            worksite_id=crew["worksite_id"],
            crew_id=req.crew_id,
            crew_name=crew["name"],
            action=req.action,
            action_label=INTERVENTION_LABELS[req.action],
            status="active",
            start_time=now_iso(),
            planned_duration_minutes=req.duration_minutes,
            supervisor_id=req.supervisor_id,
            notes=req.notes,
            context_changes=changes,
            baseline_assessment=follow_up_from(self.repo.latest_assessments.get(req.crew_id), "Assessment when intervention was recorded"),
        ).model_dump()
        self.repo.save_intervention(iv)

        if alert:
            if alert["acknowledgement_status"] != "acknowledged":
                alert["acknowledgement_status"] = "acknowledged"
                alert["acknowledged_at"] = alert.get("acknowledged_at") or now_iso()
                alert["acknowledged_by"] = req.supervisor_id
                alert["history"].append(AlertEvent(timestamp=now_iso(), event="acknowledged",
                                                   detail="Acknowledged by recording an intervention", actor=req.supervisor_id).model_dump())
            alert.setdefault("intervention_ids", []).append(iv["intervention_id"])
            alert["history"].append(AlertEvent(timestamp=now_iso(), event="intervention_recorded",
                                               detail=f"{iv['action_label']}" + (f" ({', '.join(changes)} updated)" if changes else ""),
                                               actor=req.supervisor_id).model_dump())
            alert["updated_at"] = now_iso()
            self.repo.save_alert(alert)
        return iv

    def record_follow_up(self, assessment: dict) -> None:
        """Called after every crew assessment: log follow-ups on category change for active interventions."""
        for iv in self.repo.interventions.values():
            if iv["status"] != "active" or iv["crew_id"] != assessment["crew_id"]:
                continue
            fus = iv.setdefault("follow_up_assessments", [])
            last_cat = fus[-1]["risk_category"] if fus else (iv.get("baseline_assessment") or {}).get("risk_category")
            if assessment["risk_category"] != last_cat or not fus:
                fus.append(follow_up_from(assessment, "Reassessment after intervention"
                                          if not fus else f"Category changed from {CATEGORY_LABELS.get(last_cat, last_cat)}").model_dump())
                del fus[:-MAX_FOLLOW_UPS]
                self.repo.save_intervention(iv)

    def complete(self, intervention_id: str, req: InterventionComplete) -> dict:
        iv = self.repo.interventions[intervention_id]
        if iv["status"] == "completed":
            raise ValueError("Intervention already completed")
        final = follow_up_from(self.repo.latest_assessments.get(iv["crew_id"]), "Follow-up assessment at completion")
        iv.setdefault("follow_up_assessments", []).append(final.model_dump())
        iv["status"] = "completed"
        iv["end_time"] = now_iso()
        iv["completion_notes"] = req.notes
        base = (iv.get("baseline_assessment") or {}).get("risk_category")
        if base in LEVEL and final.risk_category in LEVEL:
            diff = LEVEL[final.risk_category] - LEVEL[base]
            iv["outcome"] = ("improved" if diff < 0 else "worsened" if diff > 0 else "unchanged") + \
                f": {CATEGORY_LABELS[base]} -> {CATEGORY_LABELS[final.risk_category]}"
        else:
            iv["outcome"] = "not assessable: assessment unavailable at start or completion"
        self.repo.save_intervention(iv)
        if iv.get("alert_id") and iv["alert_id"] in self.repo.alerts:
            alert = self.repo.alerts[iv["alert_id"]]
            alert["history"].append(AlertEvent(timestamp=now_iso(), event="intervention_completed",
                                               detail=f"{iv['action_label']} completed; {iv['outcome']}", actor=req.supervisor_id).model_dump())
            self.repo.save_alert(alert)
        return iv
