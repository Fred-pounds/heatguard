from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response

from ...core.security import require_supervisor
from ...services import evaluation_service, reports_service
from ...services.heatguard_service import HeatGuardService
from ..deps import get_service

router = APIRouter(tags=["reports & evaluation"])


@router.get("/reports/summary")
async def summary(svc: HeatGuardService = Depends(get_service)):
    return reports_service.summary(svc)


@router.get("/reports/export")
async def export(kind: str = "summary", worksite_id: str | None = None, svc: HeatGuardService = Depends(get_service)):
    try:
        text, filename = reports_service.export(svc, kind, worksite_id)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return Response(content=text, media_type="text/csv",
                    headers={"Content-Disposition": f'attachment; filename="{filename}"'})


@router.get("/evaluation")
async def latest_evaluation(svc: HeatGuardService = Depends(get_service)):
    return svc.repo.evaluation or {"cases": [], "summary": None}


@router.post("/evaluation/run", dependencies=[Depends(require_supervisor)])
async def run_evaluation(svc: HeatGuardService = Depends(get_service)):
    result = await asyncio.to_thread(evaluation_service.run_all, svc.settings)
    svc.repo.set_evaluation(result)
    return result
