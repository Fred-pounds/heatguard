"""Alert engine: turns assessments into managed alerts.

Rules
* Heat-risk alerts are raised per crew for categories Caution and above.
* Data-quality alerts are raised per worksite when environmental data are
  unavailable/invalid, or per crew when its work context is incomplete.
* Duplicate suppression: one open alert per (worksite, crew, type); repeats
  only increment a counter. A higher severity escalates the open alert and
  requires re-acknowledgement.
* Alerts are NEVER cleared automatically. After `sustained_readings`
  consecutive assessments below the alert's severity the alert is marked
  "conditions_improving"; a supervisor must resolve it with a note.
* Missing data never counts as improvement.
* Unacknowledged alerts escalate after `escalate_after_seconds`.
"""
from __future__ import annotations

from datetime import datetime

from ..repositories.repository import HeatGuardRepository
from ..schemas.alert import Alert, AlertEvent
from ..schemas.assessment import Assessment
from ..schemas.common import new_id, now_iso, utcnow
from .risk_engine import CATEGORY_LABELS

SITE_SCOPE = "__site__"
DATA_ALERT_LEVEL = 2
ESCALATION_TARGETS = {1: "Site OHS officer notified", 2: "Site manager notified", 3: "Emergency coordinator notified"}


def _event(event: str, detail: str = "", actor: str = "system") -> dict:
    return AlertEvent(timestamp=now_iso(), event=event, detail=detail, actor=actor).model_dump()


class AlertEngine:
    def __init__(self, repo: HeatGuardRepository, sustained_readings: int = 10, escalate_after_seconds: float = 120):
        self.repo = repo
        self.sustained = sustained_readings
        self.escalate_after = escalate_after_seconds

    # ------------------------------------------------------------------ lookup
    def open_alert(self, worksite_id: str, crew_id: str, alert_type: str) -> dict | None:
        for a in self.repo.alerts.values():
            if (a["worksite_id"] == worksite_id and a["crew_id"] == crew_id and a["alert_type"] == alert_type
                    and a["resolution_status"] != "resolved"):
                return a
        return None

    # ------------------------------------------------------------------ process
    def process(self, a: Assessment, worksite_name: str) -> list[dict]:
        changed: list[dict] = self._regulatory(a, worksite_name)
        if a.risk_category == "unavailable":
            scope = SITE_SCOPE if not a.data_quality.environmental_data_available else a.crew_id
            name = "All crews at site" if scope == SITE_SCOPE else a.crew_name
            changed += self._raise_or_repeat(a, "data_quality", scope, name, worksite_name, "data_unavailable", DATA_ALERT_LEVEL)
            # Missing data must not count as improvement for an open heat alert.
            heat = self.open_alert(a.worksite_id, a.crew_id, "heat_risk")
            if heat and heat["improving_streak"]:
                heat["improving_streak"] = 0
                if heat["resolution_status"] == "conditions_improving":
                    heat["resolution_status"] = "open"
                    heat["history"].append(_event("improvement_interrupted", "Assessment unavailable: missing data is not evidence of improvement."))
                self.repo.save_alert(heat)
                changed.append(heat)
            return changed

        # Valid assessment: data-quality alerts for this crew / site can recover
        for scope in (SITE_SCOPE, a.crew_id):
            dq = self.open_alert(a.worksite_id, scope, "data_quality")
            if dq:
                self._improve(dq, a, "data restored")
                changed.append(dq)

        if a.risk_level >= 1:
            changed += self._raise_or_repeat(a, "heat_risk", a.crew_id, a.crew_name, worksite_name, a.risk_category, a.risk_level)
        else:
            heat = self.open_alert(a.worksite_id, a.crew_id, "heat_risk")
            if heat:
                self._improve(heat, a, "below alert threshold")
                changed.append(heat)
        return changed

    def _regulatory(self, a: Assessment, worksite_name: str) -> list[dict]:
        """One site-level alert while a legal restriction (UAE midday break) is in force."""
        existing = self.open_alert(a.worksite_id, SITE_SCOPE, "regulatory")
        if a.regulatory_flags:
            f = a.regulatory_flags[0]
            if existing:
                existing["duplicate_count"] = existing.get("duplicate_count", 0) + 1
                if existing["improving_streak"]:
                    existing["improving_streak"] = 0
                    existing["resolution_status"] = "open"
                self.repo.save_alert(existing)
                return [existing]
            action = next((r.model_dump() for r in a.recommended_actions if r.priority == "urgent"), None)
            alert = Alert(
                alert_id=new_id("alr"), timestamp=now_iso(), updated_at=now_iso(),
                worksite_id=a.worksite_id, worksite_name=worksite_name, crew_id=SITE_SCOPE, crew_name="All outdoor crews",
                alert_type="regulatory", severity="regulatory", severity_level=3, peak_severity="regulatory",
                explanation=f"{f['detail']} {f['verification_note']}",
                contributing_factors=[{"factor": f["title"], "detail": f["detail"], "direction": "increases_concern"}],
                recommendations=[action] if action else [],
                assessment_id=a.assessment_id, latest_category=a.risk_category, data_origin=a.data_origin,
                history=[AlertEvent(timestamp=now_iso(), event="created", detail=f"{f['title']} ({f['authority']})")],
            ).model_dump()
            self.repo.save_alert(alert)
            return [alert]
        if existing:
            self._improve(existing, a, "outside the midday-break window")
            return [existing]
        return []

    # ------------------------------------------------------------------ generic alerts (worker checks, maintenance, escalations)
    def raise_simple(self, *, worksite_id: str, worksite_name: str, crew_id: str, crew_name: str, alert_type: str,
                     severity: str, level: int, explanation: str, recommendations: list[dict], factors: list[dict] | None = None,
                     escalation_id: str | None = None, dedupe: bool = True) -> dict:
        existing = self.open_alert(worksite_id, crew_id, alert_type) if dedupe else None
        if existing:
            existing["duplicate_count"] = existing.get("duplicate_count", 0) + 1
            existing["updated_at"] = now_iso()
            if existing["improving_streak"]:
                existing["improving_streak"] = 0
                if existing["resolution_status"] == "conditions_improving":
                    existing["resolution_status"] = "open"
            if level > existing["severity_level"]:
                existing.update(severity=severity, severity_level=level, peak_severity=severity)
                if existing["acknowledgement_status"] == "acknowledged":
                    existing["acknowledgement_status"] = "unacknowledged"
            existing["explanation"] = explanation
            existing["recommendations"] = recommendations
            self.repo.save_alert(existing)
            return existing
        alert = Alert(
            alert_id=new_id("alr"), timestamp=now_iso(), updated_at=now_iso(), worksite_id=worksite_id,
            worksite_name=worksite_name, crew_id=crew_id, crew_name=crew_name, alert_type=alert_type,  # type: ignore[arg-type]
            severity=severity, severity_level=level, peak_severity=severity,  # type: ignore[arg-type]
            explanation=explanation, recommendations=recommendations, contributing_factors=factors or [],
            escalation_id=escalation_id,
            history=[AlertEvent(timestamp=now_iso(), event="created", detail=explanation[:140])],
        ).model_dump()
        self.repo.save_alert(alert)
        return alert

    def clear_simple(self, worksite_id: str, crew_id: str, alert_type: str, why: str) -> dict | None:
        existing = self.open_alert(worksite_id, crew_id, alert_type)
        if existing:
            self._improve(existing, None, why)
        return existing

    def close_for_escalation(self, escalation_id: str, note: str, actor: str) -> None:
        for alert in self.repo.alerts.values():
            if alert.get("escalation_id") == escalation_id and alert["resolution_status"] != "resolved":
                alert["acknowledgement_status"] = "acknowledged"
                alert["acknowledged_at"] = alert.get("acknowledged_at") or now_iso()
                alert["resolution_status"] = "resolved"
                alert["resolved_at"] = now_iso()
                alert["resolved_by"] = actor
                alert["resolution_note"] = note
                alert["history"].append(_event("resolved", note, actor))
                self.repo.save_alert(alert)

    def _raise_or_repeat(self, a: Assessment, alert_type: str, crew_id: str, crew_name: str, worksite_name: str,
                         severity: str, level: int) -> list[dict]:
        existing = self.open_alert(a.worksite_id, crew_id, alert_type)
        if existing is None:
            alert = Alert(
                alert_id=new_id("alr"),
                timestamp=now_iso(),
                updated_at=now_iso(),
                worksite_id=a.worksite_id,
                worksite_name=worksite_name,
                crew_id=crew_id,
                crew_name=crew_name,
                alert_type=alert_type,  # type: ignore[arg-type]
                severity=severity,  # type: ignore[arg-type]
                severity_level=level,
                peak_severity=severity,  # type: ignore[arg-type]
                explanation=a.explanation,
                contributing_factors=[f.model_dump() for f in a.contributing_factors],
                recommendations=[r.model_dump() for r in a.recommended_actions],
                assessment_id=a.assessment_id,
                latest_category=a.risk_category,
                data_origin=a.data_origin,
                history=[AlertEvent(timestamp=now_iso(), event="created",
                                    detail=f"{CATEGORY_LABELS.get(severity, severity)} alert generated from assessment {a.assessment_id}")],
            ).model_dump()
            self.repo.save_alert(alert)
            return [alert]

        existing["updated_at"] = now_iso()
        existing["latest_category"] = a.risk_category
        if level > existing["severity_level"]:
            prev = existing["severity"]
            existing.update(severity=severity, severity_level=level, peak_severity=severity, explanation=a.explanation,
                            contributing_factors=[f.model_dump() for f in a.contributing_factors],
                            recommendations=[r.model_dump() for r in a.recommended_actions],
                            assessment_id=a.assessment_id, improving_streak=0, resolution_status="open")
            existing["history"].append(_event("severity_increased", f"{CATEGORY_LABELS.get(prev, prev)} -> {CATEGORY_LABELS.get(severity, severity)}"))
            if existing["acknowledgement_status"] == "acknowledged":
                existing["acknowledgement_status"] = "unacknowledged"
                existing["history"].append(_event("reacknowledgement_required", "Severity increased after acknowledgement"))
        elif level < existing["severity_level"] and alert_type == "heat_risk":
            self._improve(existing, a, f"now {CATEGORY_LABELS.get(a.risk_category, a.risk_category)}")
            return [existing]
        else:
            existing["duplicate_count"] = existing.get("duplicate_count", 0) + 1
            if existing["improving_streak"]:
                existing["improving_streak"] = 0
                if existing["resolution_status"] == "conditions_improving":
                    existing["resolution_status"] = "open"
                    existing["history"].append(_event("conditions_worsened", "Conditions returned to alert severity"))
            existing["explanation"] = a.explanation
            existing["contributing_factors"] = [f.model_dump() for f in a.contributing_factors]
            existing["recommendations"] = [r.model_dump() for r in a.recommended_actions]
            existing["assessment_id"] = a.assessment_id
        self.repo.save_alert(existing)
        return [existing]

    def _improve(self, alert: dict, a: Assessment | None, why: str) -> None:
        alert["improving_streak"] = alert.get("improving_streak", 0) + 1
        if a is not None:
            alert["latest_category"] = a.risk_category
        alert["updated_at"] = now_iso()
        needed = 3 if alert["alert_type"] in ("data_quality", "regulatory", "maintenance", "worker_check") else self.sustained
        if alert["resolution_status"] == "open" and alert["improving_streak"] >= needed:
            alert["resolution_status"] = "conditions_improving"
            alert["history"].append(_event(
                "conditions_improving",
                f"{alert['improving_streak']} consecutive assessments {why}. Supervisor review required to resolve."))
        self.repo.save_alert(alert)

    # ------------------------------------------------------------------ actions
    def acknowledge(self, alert_id: str, supervisor_id: str, note: str | None) -> dict:
        alert = self.repo.alerts[alert_id]
        alert["acknowledgement_status"] = "acknowledged"
        if not alert.get("acknowledged_at"):
            alert["acknowledged_at"] = now_iso()
        alert["acknowledged_by"] = supervisor_id
        alert["updated_at"] = now_iso()
        alert["history"].append(_event("acknowledged", note or "", supervisor_id))
        self.repo.save_alert(alert)
        return alert

    def resolve(self, alert_id: str, supervisor_id: str, note: str, override: bool) -> dict:
        alert = self.repo.alerts[alert_id]
        if alert["resolution_status"] == "resolved":
            raise ValueError("Alert already resolved")
        if alert["acknowledgement_status"] != "acknowledged":
            raise ValueError("Acknowledge the alert before resolving it")
        if alert["resolution_status"] != "conditions_improving" and not override:
            raise PermissionError(
                "Conditions have not shown sustained improvement. Resolve only with override_active_conditions=true "
                "and a note explaining the protective measures in place.")
        alert["resolution_status"] = "resolved"
        alert["resolved_at"] = now_iso()
        alert["resolved_by"] = supervisor_id
        alert["resolution_note"] = note
        alert["updated_at"] = now_iso()
        alert["history"].append(_event("resolved" + ("_with_override" if override and alert.get("improving_streak", 0) < self.sustained else ""),
                                       note, supervisor_id))
        self.repo.save_alert(alert)
        return alert

    def check_escalations(self) -> list[dict]:
        changed = []
        now = utcnow()
        for alert in self.repo.alerts.values():
            if alert["resolution_status"] == "resolved" or alert["acknowledgement_status"] == "acknowledged":
                continue
            ref = alert.get("escalated_at") or alert["timestamp"]
            if (now - datetime.fromisoformat(ref)).total_seconds() >= self.escalate_after and alert["escalation_level"] < 3:
                alert["escalation_level"] += 1
                alert["escalated_at"] = now_iso()
                alert["history"].append(_event("escalated", ESCALATION_TARGETS[alert["escalation_level"]] + " (unacknowledged)"))
                self.repo.save_alert(alert)
                changed.append(alert)
        return changed
