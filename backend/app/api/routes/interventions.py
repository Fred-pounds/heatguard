from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...core.security import require_supervisor
from ...schemas.intervention import INTERVENTION_LABELS, InterventionComplete, InterventionCreate
from ...services.heatguard_service import HeatGuardService
from ..deps import get_service

router = APIRouter(prefix="/interventions", tags=["interventions"])


@router.get("/types")
async def types():
    return INTERVENTION_LABELS


@router.get("")
async def list_interventions(status: str | None = None, crew_id: str | None = None, svc: HeatGuardService = Depends(get_service)):
    rows = [i for i in svc.repo.interventions.values()
            if status in (None, i["status"]) and crew_id in (None, i["crew_id"])]
    return sorted(rows, key=lambda i: i["start_time"], reverse=True)


@router.post("", status_code=201, dependencies=[Depends(require_supervisor)])
async def create(body: InterventionCreate, svc: HeatGuardService = Depends(get_service)):
    try:
        iv = svc.interventions.create(body)
    except KeyError as exc:
        raise HTTPException(404, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    # Reassess immediately so the effect of any context change is visible
    crew = svc.repo.crews[body.crew_id]
    svc.assess_crew(crew)
    return svc.repo.interventions[iv["intervention_id"]]


@router.post("/{intervention_id}/complete", dependencies=[Depends(require_supervisor)])
async def complete(intervention_id: str, body: InterventionComplete, svc: HeatGuardService = Depends(get_service)):
    if intervention_id not in svc.repo.interventions:
        raise HTTPException(404, "Intervention not found")
    try:
        return svc.interventions.complete(intervention_id, body)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
