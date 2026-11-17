"""SensorSource adapter around the synthetic VirtualStation (SIMULATED data only)."""
from __future__ import annotations

from heatguard_sim import VirtualStation, new_station

from ..schemas.sensor import SensorReadingIn
from .interface import SensorSource


class SimulatedSensorSource(SensorSource):
    source_type = "simulated"

    def __init__(self, worksite_id: str, scenario_id: str, seed: int | None = None):
        self.station: VirtualStation = new_station(worksite_id, scenario_id, seed)
        super().__init__(self.station.station_id, worksite_id)

    def poll(self) -> list[SensorReadingIn]:
        return [SensorReadingIn(**r) for r in self.station.produce()]

    def status(self) -> dict:
        return {"source_type": self.source_type, **self.station.status()}
