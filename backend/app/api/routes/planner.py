"""Shift planner for supervisors: crew-level, no individual data."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from ...core.security import require_supervisor
from ...services.heatguard_service import HeatGuardService
from ...services.planner_service import PlannerService
from ..deps import get_service

router = APIRouter(tags=["planning"])


@router.get("/planner/{worksite_id}", dependencies=[Depends(require_supervisor)])
async def shift_plan(worksite_id: str, hours: int = Query(6, ge=1, le=12), step: int = Query(30, ge=15, le=60),
                     svc: HeatGuardService = Depends(get_service)):
    if worksite_id not in svc.repo.worksites:
        raise HTTPException(404, "Unknown worksite")
    return PlannerService(svc).plan(worksite_id, hours=hours, step=step)
