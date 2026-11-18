from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ...core.security import require_supervisor
from ...services.heatguard_service import HeatGuardService
from ...services.simulation_service import scenario_catalog
from ..deps import get_service

router = APIRouter(prefix="/simulation", tags=["simulation (SIMULATED data)"])
guard = [Depends(require_supervisor)]


class ScenarioRequest(BaseModel):
    worksite_id: str
    scenario_id: str


class SpeedRequest(BaseModel):
    speed: float = Field(ge=0.25, le=20)


class AdjustRequest(BaseModel):
    worksite_id: str
    tdb_offset: float = Field(default=0.0, ge=-10, le=10)
    rh_offset: float = Field(default=0.0, ge=-40, le=40)
    solar_scale: float = Field(default=1.0, ge=0, le=1.5)
    wind_offset: float = Field(default=0.0, ge=-3, le=5)


class OverrideRequest(BaseModel):
    worksite_id: str
    dry_bulb: float | None = None
    natural_wet_bulb: float | None = None
    globe_temperature: float | None = None
    clear: bool = False


class SensorFaultRequest(BaseModel):
    worksite_id: str
    sensor: Literal["dry_bulb", "wet_bulb", "globe", "humidity", "all"] = "all"
    mode: Literal["missing", "invalid"] = "missing"


class WorksiteRequest(BaseModel):
    worksite_id: str


class ResetRequest(BaseModel):
    worksite_id: str | None = None
    clear_history: bool = False


class JumpRequest(BaseModel):
    worksite_id: str
    sim_clock: str = Field(pattern=r"^\d{2}:\d{2}$", description="Target site time (HH:MM) within the current scenario day")


class StationFieldRequest(BaseModel):
    worksite_id: str
    enabled: bool = True


class StrainRequest(BaseModel):
    worker_id: str
    level: float = Field(default=1.0, ge=0, le=1)


class ToggleRequest(BaseModel):
    enabled: bool


def _status(svc: HeatGuardService) -> dict:
    svc._publish_simulation()  # noqa: SLF001
    return svc.sim.status()


def _station(svc: HeatGuardService, worksite_id: str):
    try:
        return svc.sim.station(worksite_id)
    except KeyError as exc:
        raise HTTPException(404, str(exc)) from exc


@router.get("")
async def status(svc: HeatGuardService = Depends(get_service)):
    return svc.sim.status()


@router.get("/scenarios")
async def scenarios():
    return scenario_catalog()


@router.post("/start", dependencies=guard)
async def start(svc: HeatGuardService = Depends(get_service)):
    svc.sim.start()
    svc._event("simulation_started", None, "Simulation started")  # noqa: SLF001
    return _status(svc)


@router.post("/pause", dependencies=guard)
async def pause(svc: HeatGuardService = Depends(get_service)):
    svc.sim.pause()
    return _status(svc)


@router.post("/resume", dependencies=guard)
async def resume(svc: HeatGuardService = Depends(get_service)):
    svc.sim.resume()
    return _status(svc)


@router.post("/stop", dependencies=guard)
async def stop(svc: HeatGuardService = Depends(get_service)):
    svc.sim.stop()
    svc._event("simulation_stopped", None, "Simulation stopped: no new readings will arrive; data will become stale")  # noqa: SLF001
    return _status(svc)


@router.post("/step", dependencies=guard)
async def step(svc: HeatGuardService = Depends(get_service)):
    """Advance every station by one simulated minute (works while paused)."""
    svc.process_batch(svc.sim.poll_all(), from_sim=True)
    return _status(svc)


@router.post("/jump", dependencies=guard)
async def jump(body: JumpRequest, svc: HeatGuardService = Depends(get_service)):
    """Move a station's simulated clock to a given site time (e.g. to show the 12:30 midday break) and take a reading."""
    st = _station(svc, body.worksite_id)
    sh, sm = (int(x) for x in st.scenario.start_clock.split(":"))
    th, tm = (int(x) for x in body.sim_clock.split(":"))
    target = (th * 60 + tm) - (sh * 60 + sm)
    if not 0 <= target < st.scenario.duration_min:
        raise HTTPException(422, f"{body.sim_clock} is outside this scenario ({st.scenario.start_clock} for {st.scenario.duration_min} min)")
    st.sim_minute = target
    svc.process_batch(svc.sim.poll_all(), from_sim=True)
    svc._event("simulation_jump", body.worksite_id, f"Site clock moved to {body.sim_clock}")  # noqa: SLF001
    return _status(svc)


@router.post("/reset", dependencies=guard)
async def reset(body: ResetRequest, svc: HeatGuardService = Depends(get_service)):
    svc.sim.reset(body.worksite_id)
    if body.clear_history:
        svc.repo.clear_operational_data()
        svc._site_state.clear()  # noqa: SLF001
        svc._last_valid.clear()  # noqa: SLF001
        svc._crew_counter.clear()  # noqa: SLF001
        # Take a first reading immediately so the empty store is never mistaken for a station outage
        svc.process_batch(svc.sim.poll_all(), from_sim=True)
    svc._event("simulation_reset", body.worksite_id, "Simulation reset" + (" and operational history cleared" if body.clear_history else ""))  # noqa: SLF001
    return _status(svc)


@router.post("/scenario", dependencies=guard)
async def set_scenario(body: ScenarioRequest, svc: HeatGuardService = Depends(get_service)):
    ws = svc.repo.worksites.get(body.worksite_id)
    if not ws:
        raise HTTPException(404, "Unknown worksite")
    try:
        svc.sim.set_scenario(body.worksite_id, body.scenario_id, ws["environment"])
    except (ValueError, KeyError) as exc:
        raise HTTPException(422, str(exc)) from exc
    svc._event("scenario_selected", body.worksite_id, f"Scenario '{body.scenario_id}' selected")  # noqa: SLF001
    return _status(svc)


@router.post("/speed", dependencies=guard)
async def set_speed(body: SpeedRequest, svc: HeatGuardService = Depends(get_service)):
    svc.sim.set_speed(body.speed)
    return _status(svc)


@router.post("/adjust", dependencies=guard)
async def adjust(body: AdjustRequest, svc: HeatGuardService = Depends(get_service)):
    st = _station(svc, body.worksite_id)
    st.adjustments.tdb_offset = body.tdb_offset
    st.adjustments.rh_offset = body.rh_offset
    st.adjustments.solar_scale = body.solar_scale
    st.adjustments.wind_offset = body.wind_offset
    return _status(svc)


@router.post("/override", dependencies=guard)
async def override(body: OverrideRequest, svc: HeatGuardService = Depends(get_service)):
    st = _station(svc, body.worksite_id)
    if body.clear:
        st.overrides.dry_bulb = st.overrides.natural_wet_bulb = st.overrides.globe_temperature = None
        return _status(svc)
    # Apply dry-bulb first (it drives the derived components), then validate the others against it
    try:
        if body.dry_bulb is not None:
            st.validate_override("dry_bulb", body.dry_bulb)
            st.overrides.dry_bulb = body.dry_bulb
        for field in ("natural_wet_bulb", "globe_temperature"):
            value = getattr(body, field)
            if value is not None:
                st.validate_override(field, value)
                setattr(st.overrides, field, value)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return _status(svc)


@router.post("/sensor-failure", dependencies=guard)
async def sensor_failure(body: SensorFaultRequest, svc: HeatGuardService = Depends(get_service)):
    st = _station(svc, body.worksite_id)
    st.manual_faults[body.sensor] = body.mode
    svc._event("sensor_failure_simulated", body.worksite_id, f"{body.sensor} sensor set to '{body.mode}'")  # noqa: SLF001
    return _status(svc)


@router.post("/sensor-restore", dependencies=guard)
async def sensor_restore(body: WorksiteRequest, svc: HeatGuardService = Depends(get_service)):
    st = _station(svc, body.worksite_id)
    st.manual_faults.clear()
    svc._event("sensor_restore_simulated", body.worksite_id, "Simulated sensor faults cleared")  # noqa: SLF001
    return _status(svc)


@router.post("/network-failure", dependencies=guard)
async def network_failure(body: WorksiteRequest, svc: HeatGuardService = Depends(get_service)):
    st = _station(svc, body.worksite_id)
    st.network_up = False
    svc._event("network_failure_simulated", body.worksite_id, "Station uplink disconnected; readings are queued at the edge")  # noqa: SLF001
    return _status(svc)


@router.post("/network-restore", dependencies=guard)
async def network_restore(body: WorksiteRequest, svc: HeatGuardService = Depends(get_service)):
    st = _station(svc, body.worksite_id)
    st.network_up = True
    svc._event("network_restore_simulated", body.worksite_id, f"Station uplink restored; {len(st.buffer)} queued readings will synchronise")  # noqa: SLF001
    return _status(svc)


@router.post("/battery-fault", dependencies=guard)
async def battery_fault(body: StationFieldRequest, svc: HeatGuardService = Depends(get_service)):
    """Failing battery/panel: the station battery drains about 3% per simulated minute; at 0% the station goes silent."""
    st = _station(svc, body.worksite_id)
    st.battery_fault = body.enabled
    if not body.enabled:
        st.battery_pct = max(st.battery_pct, 85.0)
    svc._event("battery_fault_simulated" if body.enabled else "battery_replaced_simulated", body.worksite_id,  # noqa: SLF001
               "Station battery failing" if body.enabled else "Station battery replaced")
    return _status(svc)


@router.post("/dust", dependencies=guard)
async def dust(body: StationFieldRequest, svc: HeatGuardService = Depends(get_service)):
    """Dust event: fouling of globe and wick builds up quickly. enabled=false cleans the station."""
    st = _station(svc, body.worksite_id)
    if body.enabled:
        st.dust_boost = 0.05
    else:
        st.dust_boost = 0.0
        st.dust = 0.0
    svc._event("dust_simulated" if body.enabled else "station_cleaned_simulated", body.worksite_id,  # noqa: SLF001
               "Dust is fouling the globe and wick" if body.enabled else "Station cleaned: globe and wick serviced")
    return _status(svc)


@router.post("/worker-strain", dependencies=guard)
async def worker_strain(body: StrainRequest, svc: HeatGuardService = Depends(get_service)):
    """Make one consented worker's simulated wearable show physiological strain (or recover with level 0)."""
    w = svc.repo.workers.get(body.worker_id)
    if not w:
        raise HTTPException(404, "Unknown worker")
    if w["consent"]["status"] != "granted":
        raise HTTPException(409, "This worker has not consented to share signals")
    svc.sim.wearable(w).strain = body.level
    svc._event("worker_strain_simulated", None, f"Badge {w['badge']}: simulated strain {body.level:.0%}")  # noqa: SLF001
    return {"badge": w["badge"], "strain": body.level}


@router.post("/database-outage", dependencies=guard)
async def database_outage(body: ToggleRequest, svc: HeatGuardService = Depends(get_service)):
    svc.sim.db_outage = body.enabled
    svc._event("database_outage_simulated" if body.enabled else "database_restored_simulated", None,  # noqa: SLF001
               "Database sync paused; writes are queued" if body.enabled else f"Database sync resumed; {svc.repo.pending_writes} queued writes")
    return _status(svc)
