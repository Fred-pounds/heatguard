"""Consented worker signals, symptom check-ins and clinical escalation.

Access model:
  worker      - own consent, own signal status, symptom reports
  supervisor  - crew-level counts, badges to check on, redacted escalations (no values, no symptoms)
  ohs / admin - individual signal values and symptom details
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...core.security import current_role, require_ohs, require_supervisor
from ...schemas.worker import AGE_BANDS, OUTCOMES, SYMPTOMS_FIRST_AID, SYMPTOMS_RED_FLAG, ConsentRequest, EscalationUpdate, SignalIn, SymptomReportIn
from ...services.heatguard_service import HeatGuardService
from ..deps import get_service

router = APIRouter(tags=["workers & escalation"])


@router.get("/workers/catalog")
async def catalog():
    return {"age_bands": AGE_BANDS, "symptoms_red_flag": SYMPTOMS_RED_FLAG, "symptoms_first_aid": SYMPTOMS_FIRST_AID, "outcomes": OUTCOMES}


@router.get("/workers/summary", dependencies=[Depends(require_supervisor)])
async def summary(svc: HeatGuardService = Depends(get_service)):
    return {c["crew_id"]: {"crew_name": c["name"], **svc.workers.crew_summary(c)} for c in svc.repo.crews.values()}


@router.get("/workers", dependencies=[Depends(require_ohs)])
async def list_workers(svc: HeatGuardService = Depends(get_service)):
    out = []
    for w in sorted(svc.repo.workers.values(), key=lambda x: x["badge"]):
        crew = svc.repo.crews.get(w["crew_id"], {})
        out.append({**w, "crew_name": crew.get("name", ""), "signal": svc.workers.status(w, crew.get("acclimatization", "unknown"))})
    return out


@router.get("/worker/badges/{crew_id}")
async def badges(crew_id: str, svc: HeatGuardService = Depends(get_service)):
    return [{"worker_id": w["worker_id"], "badge": w["badge"], "sharing": w["consent"]["status"] == "granted"}
            for w in svc.workers.workers_for_crew(crew_id)]


@router.get("/worker/me/{worker_id}")
async def me(worker_id: str, svc: HeatGuardService = Depends(get_service)):
    """A worker's own consent and signal status (their own data)."""
    w = svc.repo.workers.get(worker_id)
    if not w:
        raise HTTPException(404, "Unknown badge")
    crew = svc.repo.crews.get(w["crew_id"], {})
    return {"badge": w["badge"], "consent": w["consent"], "age_band": w.get("age_band"),
            "signal": svc.workers.status(w, crew.get("acclimatization", "unknown"))}


@router.post("/worker/me/{worker_id}/consent")
async def consent(worker_id: str, body: ConsentRequest, svc: HeatGuardService = Depends(get_service)):
    if worker_id not in svc.repo.workers:
        raise HTTPException(404, "Unknown badge")
    try:
        w = svc.workers.set_consent(worker_id, body)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return {"badge": w["badge"], "consent": w["consent"]}


@router.post("/workers/signals")
async def ingest_signal(body: SignalIn | list[SignalIn], svc: HeatGuardService = Depends(get_service)):
    """Wearable gateway ingest. Signals without active consent are discarded, never stored."""
    batch = body if isinstance(body, list) else [body]
    accepted = sum(1 for s in batch if svc.workers.ingest_signal(s) is not None)
    return {"accepted": accepted, "discarded": len(batch) - accepted}


@router.post("/symptoms", status_code=201)
async def report_symptoms(body: SymptomReportIn, role: str = Depends(current_role), svc: HeatGuardService = Depends(get_service)):
    try:
        esc = svc.workers.report_symptoms(body)
    except KeyError as exc:
        raise HTTPException(404, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    ws = svc.repo.worksites.get(esc["worksite_id"], {})
    emergency = esc["level"] == "emergency"
    recs = ([{"action": "Call 998 now", "priority": "urgent", "source": "UAE emergency services",
              "detail": "Possible heat stroke signs. Call an ambulance and the site first aider."},
             {"action": "Start cooling immediately", "priority": "urgent", "source": "NIOSH 2016",
              "detail": "Move to shade, remove outer clothing, cool with water and fanning while help arrives."}]
            if emergency else
            [{"action": "Send the first aider", "priority": "required", "source": "NIOSH 2016",
              "detail": "Assess the worker, rest in a cool area, give water; watch for confusion or collapse."}])
    svc.alerts.raise_simple(
        worksite_id=esc["worksite_id"], worksite_name=ws.get("name", ""), crew_id=esc["crew_id"], crew_name=esc["crew_name"],
        alert_type="escalation", severity="critical" if emergency else "high", level=4 if emergency else 3,
        explanation=WorkerServiceRedact.summary(esc), recommendations=recs, escalation_id=esc["escalation_id"], dedupe=False)
    return svc.workers.redact(esc) if role not in ("ohs", "admin") else esc


class WorkerServiceRedact:
    @staticmethod
    def summary(esc: dict) -> str:
        who = f"badge {esc['badge']}" if esc.get("badge") else "a worker"
        if esc["level"] == "emergency":
            return f"Emergency: {who} in {esc['crew_name']} has signs that may indicate heat stroke. Call 998 and the first aider now."
        return f"{who.capitalize()} in {esc['crew_name']} reported heat-related symptoms. First-aid check needed."


@router.get("/escalations")
async def list_escalations(role: str = Depends(require_supervisor), svc: HeatGuardService = Depends(get_service)):
    rows = sorted(svc.repo.escalations.values(), key=lambda e: e["created_at"], reverse=True)
    return rows if role in ("ohs", "admin") else [svc.workers.redact(e) for e in rows]


@router.post("/escalations/{esc_id}")
async def update_escalation(esc_id: str, body: EscalationUpdate, role: str = Depends(require_supervisor),
                            svc: HeatGuardService = Depends(get_service)):
    if esc_id not in svc.repo.escalations:
        raise HTTPException(404, "Escalation not found")
    if body.action == "close" and role not in ("ohs", "admin"):
        raise HTTPException(403, "Only the OHS role (first aider / OHS officer) records the clinical outcome")
    try:
        esc = svc.workers.update_escalation(esc_id, body)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    if esc["status"] == "closed":
        svc.alerts.close_for_escalation(esc_id, f"Escalation closed: {OUTCOMES[esc['outcome']]}", body.responder_id)
    else:
        for alert in svc.repo.alerts.values():
            if alert.get("escalation_id") == esc_id and alert["acknowledgement_status"] != "acknowledged":
                svc.alerts.acknowledge(alert["alert_id"], body.responder_id, f"Escalation {body.action}")
    return esc if role in ("ohs", "admin") else svc.workers.redact(esc)
