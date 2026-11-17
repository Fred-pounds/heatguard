from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...services.heatguard_service import HeatGuardService
from ..deps import get_service

router = APIRouter(prefix="/assessments", tags=["assessments"])


@router.get("/latest")
async def latest(worksite_id: str | None = None, svc: HeatGuardService = Depends(get_service)):
    out = []
    for crew_id, a in svc.repo.latest_assessments.items():
        crew = svc.repo.crews.get(crew_id)
        if crew and worksite_id in (None, a["worksite_id"]):
            out.append({**a, "crew": crew})
    return sorted(out, key=lambda a: (-a["risk_level"] if a["risk_level"] >= 0 else -2.5, a["crew_name"]))


@router.get("/history")
async def history(crew_id: str | None = None, worksite_id: str | None = None, limit: int = 200,
                  svc: HeatGuardService = Depends(get_service)):
    rows = [a for a in svc.repo.assessments if crew_id in (None, a["crew_id"]) and worksite_id in (None, a["worksite_id"])]
    return rows[-max(1, min(limit, 2000)):]


@router.get("/{crew_id}")
async def for_crew(crew_id: str, svc: HeatGuardService = Depends(get_service)):
    a = svc.repo.latest_assessments.get(crew_id)
    if not a:
        raise HTTPException(404, "No assessment for crew")
    return a
