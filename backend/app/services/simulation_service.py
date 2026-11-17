"""Simulation controller: owns the simulated sensor sources and their run state.

Each worksite has its own virtual station. Run state (running/paused, speed)
is global so the whole demo moves together.
"""
from __future__ import annotations

from heatguard_sim import SCENARIOS

from ..sensors.simulated_station import SimulatedSensorSource

SPEEDS = (0.5, 1.0, 2.0, 5.0, 10.0)


class SimulationService:
    def __init__(self, tick_seconds: float, seed: int | None = None):
        self.base_tick_seconds = tick_seconds
        self.seed = seed
        self.sources: dict[str, SimulatedSensorSource] = {}
        self.state = "stopped"  # running | paused | stopped
        self.speed = 1.0
        self.db_outage = False  # simulated loss of database connectivity (sync queue demo)

    # ------------------------------------------------------------------ sources
    def add_station(self, worksite_id: str, scenario_id: str) -> SimulatedSensorSource:
        src = SimulatedSensorSource(worksite_id, scenario_id, self.seed)
        self.sources[worksite_id] = src
        return src

    def station(self, worksite_id: str):
        if worksite_id not in self.sources:
            raise KeyError(f"No simulated station for worksite {worksite_id}")
        return self.sources[worksite_id].station

    @property
    def tick_interval(self) -> float:
        return max(0.3, self.base_tick_seconds / self.speed)

    # ------------------------------------------------------------------ controls
    def start(self) -> None:
        self.state = "running"

    def pause(self) -> None:
        if self.state == "running":
            self.state = "paused"

    def resume(self) -> None:
        if self.state == "paused":
            self.state = "running"

    def stop(self) -> None:
        self.state = "stopped"

    def set_speed(self, speed: float) -> None:
        if not 0.25 <= speed <= 20:
            raise ValueError("Speed must be between 0.25x and 20x")
        self.speed = speed

    def reset(self, worksite_id: str | None = None) -> None:
        for ws, src in self.sources.items():
            if worksite_id is None or ws == worksite_id:
                src.station.reset()

    def set_scenario(self, worksite_id: str, scenario_id: str, environment: str) -> None:
        sc = SCENARIOS.get(scenario_id)
        if sc is None:
            raise ValueError(f"Unknown scenario '{scenario_id}'")
        if sc.indoor != (environment == "indoor"):
            raise ValueError(f"Scenario '{sc.name}' is {'indoor' if sc.indoor else 'outdoor'}; worksite is {environment}")
        self.station(worksite_id).set_scenario(scenario_id)

    def poll_all(self) -> list:
        out = []
        for src in self.sources.values():
            out.extend(src.poll())
        return out

    def status(self) -> dict:
        return {
            "state": self.state,
            "active": self.state == "running",
            "speed": self.speed,
            "tick_interval_seconds": round(self.tick_interval, 2),
            "simulated_minutes_per_tick": 1,
            "db_outage": self.db_outage,
            "stations": {ws: src.status() for ws, src in self.sources.items()},
            "data_origin": "SIMULATED",
        }


def scenario_catalog() -> list[dict]:
    return [
        {
            "id": s.id,
            "code": s.code,
            "name": s.name,
            "description": s.description,
            "indoor": s.indoor,
            "start_clock": s.start_clock,
            "duration_min": s.duration_min,
            "suggested_context": s.suggested_context,
            "scheduled_faults": [
                {"start_min": f.start_min, "end_min": f.end_min, "sensors": list(f.sensors), "mode": f.mode} for f in s.faults
            ],
        }
        for s in SCENARIOS.values()
    ]
