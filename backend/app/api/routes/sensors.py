from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...core.security import require_ingest_key
from ...schemas.sensor import SensorReadingIn
from ...services.heatguard_service import HeatGuardService
from ..deps import get_service, public_reading

router = APIRouter(prefix="/sensors", tags=["sensors"])


@router.get("/readings")
async def readings(worksite_id: str, limit: int = 240, svc: HeatGuardService = Depends(get_service)):
    if worksite_id not in svc.repo.worksites:
        raise HTTPException(404, "Unknown worksite")
    rows = list(svc.repo.readings.get(worksite_id, []))[-max(1, min(limit, 2000)):]
    return [public_reading(r) for r in rows]


@router.get("/latest")
async def latest(svc: HeatGuardService = Depends(get_service)):
    out = {}
    for ws in svc.repo.worksites:
        r = svc.latest_reading(ws)
        out[ws] = {"reading": public_reading(r) if r else None, "status": svc.site_status(ws),
                   "rolling_mean_wbgt": svc.rolling_mean_wbgt(ws)}
    return out


@router.post("/ingest", dependencies=[Depends(require_ingest_key)])
async def ingest(body: SensorReadingIn | list[SensorReadingIn], svc: HeatGuardService = Depends(get_service)):
    """Ingest readings from any station (e.g. a future ESP32). Triggers reassessment."""
    batch = body if isinstance(body, list) else [body]
    for r in batch:
        if r.worksite_id not in svc.repo.worksites:
            raise HTTPException(422, f"Unknown worksite '{r.worksite_id}'")
        r.ground_truth = None  # external stations cannot inject evaluation ground truth
    assessments = svc.process_batch(batch)
    return {"accepted": len(batch), "assessments": len(assessments)}
