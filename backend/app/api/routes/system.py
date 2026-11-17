from __future__ import annotations

from collections import Counter

from fastapi import APIRouter, Depends, HTTPException

from ...schemas.intervention import INTERVENTION_LABELS
from ...services.heatguard_service import HeatGuardService
from ...services.risk_engine import CATEGORY_LABELS
from ...services.simulation_service import scenario_catalog
from ..deps import get_service, public_reading

router = APIRouter(tags=["system"])


@router.get("/health")
async def health(svc: HeatGuardService = Depends(get_service)):
    return svc.health()


@router.get("/meta")
async def meta(svc: HeatGuardService = Depends(get_service)):
    g = svc.guideline
    return {
        "guideline": g.summary(),
        "guideline_reference": g.reference,
        "workloads": g.workload_options(),
        "clothing": g.clothing_options(),
        "regimes": g.regimes,
        "categories": CATEGORY_LABELS,
        "intervention_types": INTERVENTION_LABELS,
        "scenarios": scenario_catalog(),
        "settings": {
            "stale_after_seconds": svc.settings.stale_after_seconds,
            "escalate_after_seconds": svc.settings.escalate_after_seconds,
            "sustained_improvement_readings": svc.settings.sustained_improvement_readings,
            "tick_seconds": svc.settings.tick_seconds,
            "retention": {"readings_per_site": svc.settings.retention_readings_per_site,
                          "assessments": svc.settings.retention_assessments,
                          "days": svc.settings.retention_days},
            "storage_backend": svc.backend.name,
        },
    }


@router.get("/overview")
async def overview(svc: HeatGuardService = Depends(get_service)):
    repo = svc.repo
    alerts = list(repo.alerts.values())
    active = [a for a in alerts if a["resolution_status"] != "resolved"]
    latest = list(repo.latest_assessments.values())
    crews = [c for c in repo.crews.values() if c.get("active", True)]
    worst = None
    for a in latest:
        if worst is None or a["risk_level"] > worst["risk_level"] or (a["risk_level"] == -1 and worst["risk_level"] < 2):
            worst = a
    ivs = list(repo.interventions.values())
    sites = []
    for ws_id, ws in repo.worksites.items():
        r = svc.latest_reading(ws_id)
        sites.append({**ws, "status": svc.site_status(ws_id), "latest_reading": public_reading(r) if r else None,
                      "rolling_mean_wbgt": svc.rolling_mean_wbgt(ws_id)})
    return {
        "worksites": sites,
        "counts": {
            "worksites": len(repo.worksites),
            "active_crews": len(crews),
            "workers": sum(c["worker_count"] for c in crews),
            "active_alerts": len(active),
            "unacknowledged_alerts": sum(1 for a in active if a["acknowledgement_status"] == "unacknowledged"),
            "escalated_alerts": sum(1 for a in active if a.get("escalation_level", 0) > 0),
            "active_interventions": sum(1 for i in ivs if i["status"] == "active"),
            "completed_interventions": sum(1 for i in ivs if i["status"] == "completed"),
        },
        "highest_concern": worst,
        "crew_status": Counter(a["risk_category"] for a in latest),
        "alert_distribution": Counter(a["peak_severity"] for a in alerts),
        "recent_alerts": sorted(alerts, key=lambda a: a["updated_at"], reverse=True)[:6],
        "recent_events": list(repo.events)[-12:][::-1],
        "health": svc.health(),
        "simulation": svc.sim.status(),
    }


WORKER_MESSAGES = {
    "routine": ("notice.routine", "Conditions are within safe working guidance. Keep drinking water regularly."),
    "caution": ("notice.caution", "It is getting hot. Drink water often and tell your supervisor if you feel unwell."),
    "elevated": ("notice.elevated", "Heat risk is raised. Take your scheduled rest breaks in the shade and drink water every 15-20 minutes."),
    "high": ("notice.high", "High heat risk. Follow the work-rest schedule from your supervisor. Rest in shade or a cool area."),
    "critical": ("notice.critical", "Very high heat risk. Strenuous work should stop. Follow your supervisor's instructions now."),
    "unavailable": ("notice.unavailable", "Heat conditions cannot be checked right now. This does NOT mean it is safe. Keep drinking water and take breaks."),
}


# Plain-language actions a worker can take themselves (supervisor actions stay on the dashboard).
WORKER_ACTIONS = {
    "routine": ["Drink water regularly, even if you are not thirsty", "Tell your supervisor if you feel unwell"],
    "caution": ["Drink water often - about 1 cup every 15-20 minutes", "Check on your co-workers (buddy system)",
                "Tell your supervisor straight away if you feel dizzy, sick or very tired"],
    "elevated": ["Take your rest breaks in the shade or a cool area", "Drink water every 15-20 minutes",
                 "Follow the work-rest schedule from your supervisor", "Watch your co-workers for signs of heat illness"],
    "high": ["Follow the work-rest schedule from your supervisor", "Rest in shade or a cool area during breaks",
             "Drink water every 15-20 minutes", "Slow down - do not rush heavy tasks", "Report any symptoms immediately"],
    "critical": ["Stop strenuous work and follow your supervisor's instructions", "Move to shade or a cool area",
                 "Drink water", "Report any symptoms immediately - yours or a co-worker's"],
    "unavailable": ["Do not assume conditions are safe", "Keep drinking water and taking breaks in the shade",
                    "Tell your supervisor if you feel unwell"],
}


@router.get("/worker/crews")
async def worker_crews(svc: HeatGuardService = Depends(get_service)):
    """Minimal crew list for the worker app crew picker (no assessments of other crews)."""
    return [{"crew_id": c["crew_id"], "name": c["name"], "worksite_id": c["worksite_id"],
             "worksite_name": svc.repo.worksites.get(c["worksite_id"], {}).get("name", "")}
            for c in svc.repo.crews.values() if c.get("active", True)]


@router.get("/worker/{crew_id}")
async def worker_notice(crew_id: str, svc: HeatGuardService = Depends(get_service)):
    """Worker-facing notice: only this crew's information, plain language, no surveillance data."""
    crew = svc.repo.crews.get(crew_id)
    if not crew:
        raise HTTPException(404, "Crew not found")
    a = svc.repo.latest_assessments.get(crew_id)
    cat = a["risk_category"] if a else "unavailable"
    key, text = WORKER_MESSAGES[cat]
    regime = crew["work_rest_regime"]
    reg = next((r for r in svc.guideline.regimes if r["id"] == regime), None)
    actions = [{"action": t, "key": f"worker_action.{cat}.{i}"} for i, t in enumerate(WORKER_ACTIONS[cat])]
    active_ivs = [{"action_label": i["action_label"], "start_time": i["start_time"]}
                  for i in svc.repo.interventions.values() if i["crew_id"] == crew_id and i["status"] == "active"]
    return {
        "crew_name": crew["name"],
        "worksite_name": svc.repo.worksites.get(crew["worksite_id"], {}).get("name", ""),
        "category": cat,
        "message_key": key,
        "message": text,
        "wbgt": a.get("wbgt") if a else None,
        "updated_at": a["timestamp"] if a else None,
        "sim_clock": a.get("sim_clock") if a else None,
        "work_rest": reg["label"] if reg and regime != "continuous" else None,
        "actions": actions,
        "active_protective_actions": active_ivs,
        "water_reminder": cat != "routine",
        "emergency": ["If a co-worker is confused, collapses or stops sweating: call for help immediately and follow the site emergency plan.",
                      "Move them to shade, loosen clothing and cool them with water while help comes.",
                      "Tell your supervisor about any dizziness, headache, nausea or cramps."],
        "data_origin": a.get("data_origin", "SIMULATED") if a else "SIMULATED",
    }
