from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...core.security import require_supervisor
from ...schemas.alert import AcknowledgeRequest, ResolveRequest
from ...services.heatguard_service import HeatGuardService
from ..deps import get_service

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("")
async def list_alerts(status: str | None = None, worksite_id: str | None = None, severity: str | None = None,
                      limit: int = 500, svc: HeatGuardService = Depends(get_service)):
    rows = list(svc.repo.alerts.values())
    if status == "active":
        rows = [a for a in rows if a["resolution_status"] != "resolved"]
    elif status == "unacknowledged":
        rows = [a for a in rows if a["acknowledgement_status"] == "unacknowledged" and a["resolution_status"] != "resolved"]
    elif status == "resolved":
        rows = [a for a in rows if a["resolution_status"] == "resolved"]
    if worksite_id:
        rows = [a for a in rows if a["worksite_id"] == worksite_id]
    if severity:
        rows = [a for a in rows if a["severity"] == severity]
    rows.sort(key=lambda a: a["timestamp"], reverse=True)
    return rows[:limit]


@router.get("/{alert_id}")
async def get_alert(alert_id: str, svc: HeatGuardService = Depends(get_service)):
    a = svc.repo.alerts.get(alert_id)
    if not a:
        raise HTTPException(404, "Alert not found")
    ivs = [svc.repo.interventions[i] for i in a.get("intervention_ids", []) if i in svc.repo.interventions]
    return {**a, "interventions": ivs}


@router.post("/{alert_id}/acknowledge", dependencies=[Depends(require_supervisor)])
async def acknowledge(alert_id: str, body: AcknowledgeRequest, svc: HeatGuardService = Depends(get_service)):
    if alert_id not in svc.repo.alerts:
        raise HTTPException(404, "Alert not found")
    return svc.alerts.acknowledge(alert_id, body.supervisor_id, body.note)


@router.post("/{alert_id}/resolve", dependencies=[Depends(require_supervisor)])
async def resolve(alert_id: str, body: ResolveRequest, svc: HeatGuardService = Depends(get_service)):
    if alert_id not in svc.repo.alerts:
        raise HTTPException(404, "Alert not found")
    try:
        return svc.alerts.resolve(alert_id, body.supervisor_id, body.note, body.override_active_conditions)
    except PermissionError as exc:
        raise HTTPException(409, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
