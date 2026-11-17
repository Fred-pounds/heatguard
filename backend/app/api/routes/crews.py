from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...core.security import require_supervisor
from ...schemas.common import new_id, now_iso
from ...schemas.crew import Crew, CrewCreate, CrewUpdate
from ...services.heatguard_service import HeatGuardService
from ..deps import get_service

router = APIRouter(tags=["worksites & crews"])


@router.get("/worksites")
async def list_worksites(svc: HeatGuardService = Depends(get_service)):
    return [{**ws, "status": svc.site_status(ws["worksite_id"])} for ws in svc.repo.worksites.values()]


@router.get("/crews")
async def list_crews(worksite_id: str | None = None, svc: HeatGuardService = Depends(get_service)):
    crews = [c for c in svc.repo.crews.values() if worksite_id in (None, c["worksite_id"])]
    return sorted(crews, key=lambda c: (c["worksite_id"], c["name"]))


def _check(svc: HeatGuardService, worksite_id: str, zone: str, clothing: str) -> None:
    ws = svc.repo.worksites.get(worksite_id)
    if not ws:
        raise HTTPException(422, f"Unknown worksite '{worksite_id}'")
    if zone not in ws.get("zones", []):
        raise HTTPException(422, f"Zone '{zone}' is not defined for {ws['name']}")
    if clothing != "unknown" and svc.guideline.clothing(clothing) is None:
        raise HTTPException(422, f"Unknown clothing category '{clothing}'")


@router.post("/crews", status_code=201, dependencies=[Depends(require_supervisor)])
async def create_crew(body: CrewCreate, svc: HeatGuardService = Depends(get_service)):
    _check(svc, body.worksite_id, body.zone, body.clothing)
    ts = now_iso()
    crew = Crew(**body.model_dump(), crew_id=new_id("crew"), created_at=ts, updated_at=ts).model_dump()
    svc.repo.save_crew(crew)
    svc.assess_crew(crew)
    return crew


@router.put("/crews/{crew_id}", dependencies=[Depends(require_supervisor)])
async def update_crew(crew_id: str, body: CrewUpdate, svc: HeatGuardService = Depends(get_service)):
    crew = svc.repo.crews.get(crew_id)
    if not crew:
        raise HTTPException(404, "Crew not found")
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    merged = {**crew, **changes}
    _check(svc, merged["worksite_id"], merged["zone"], merged["clothing"])
    merged["updated_at"] = now_iso()
    crew = Crew(**merged).model_dump()
    svc.repo.save_crew(crew)
    assessment = svc.assess_crew(crew) if crew.get("active", True) else None
    return {"crew": crew, "assessment": assessment}


@router.delete("/crews/{crew_id}", dependencies=[Depends(require_supervisor)])
async def delete_crew(crew_id: str, svc: HeatGuardService = Depends(get_service)):
    if crew_id not in svc.repo.crews:
        raise HTTPException(404, "Crew not found")
    open_alerts = [a for a in svc.repo.alerts.values() if a["crew_id"] == crew_id and a["resolution_status"] != "resolved"]
    if open_alerts:
        raise HTTPException(409, f"Crew has {len(open_alerts)} unresolved alert(s); resolve them before removing the crew")
    svc.repo.delete_crew(crew_id)
    return {"deleted": crew_id}
