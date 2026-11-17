"""Virtual environmental sensing station (SIMULATED).

Produces one reading per tick (= one simulated minute). Each reading carries
both the noisy "measured" values that are sent to the backend and the
noise-free ground truth, which is used ONLY by the evaluation module to
compute false-alarm / missed-alert rates. Ground truth is never shown as a
measurement.
"""
from __future__ import annotations

import random
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone

from .physics import Drivers, ThermalState, derive_state
from .scenarios import DEFAULT_SCENARIO, SCENARIOS, Scenario

SENSOR_KEYS = ("dry_bulb", "wet_bulb", "globe", "humidity")
FIELD_FOR_SENSOR = {
    "dry_bulb": "dry_bulb",
    "wet_bulb": "natural_wet_bulb",
    "globe": "globe_temperature",
    "humidity": "relative_humidity",
}
INVALID_VALUE = -127.0  # typical "disconnected probe" sentinel of digital temperature sensors


@dataclass
class Adjustments:
    """Driver-level adjustments: physically consistent (components are re-derived)."""

    tdb_offset: float = 0.0
    rh_offset: float = 0.0
    solar_scale: float = 1.0
    wind_offset: float = 0.0


@dataclass
class Overrides:
    """Direct component overrides from the Simulation Lab (flagged on every reading)."""

    dry_bulb: float | None = None
    natural_wet_bulb: float | None = None
    globe_temperature: float | None = None

    def active(self) -> list[str]:
        return [k for k, v in self.__dict__.items() if v is not None]


@dataclass
class VirtualStation:
    station_id: str
    worksite_id: str
    scenario_id: str = DEFAULT_SCENARIO
    seed: int | None = None
    sim_minute: int = 0
    adjustments: Adjustments = field(default_factory=Adjustments)
    overrides: Overrides = field(default_factory=Overrides)
    manual_faults: dict[str, str] = field(default_factory=dict)  # sensor -> mode
    network_up: bool = True
    use_scheduled_events: bool = True
    buffer: deque = field(default_factory=lambda: deque(maxlen=720))
    sim_start: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def __post_init__(self) -> None:
        self.rng = random.Random(self.seed)
        self.run_id = uuid.uuid4().hex[:8]

    # ------------------------------------------------------------------ scenario
    @property
    def scenario(self) -> Scenario:
        return SCENARIOS[self.scenario_id]

    def set_scenario(self, scenario_id: str) -> None:
        if scenario_id not in SCENARIOS:
            raise ValueError(f"Unknown scenario '{scenario_id}'")
        self.scenario_id = scenario_id
        self.reset()

    def reset(self) -> None:
        self.sim_minute = 0
        self.adjustments = Adjustments()
        self.overrides = Overrides()
        self.manual_faults.clear()
        self.network_up = True
        self.buffer.clear()
        self.rng = random.Random(self.seed)
        self.run_id = uuid.uuid4().hex[:8]
        self.sim_start = datetime.now(timezone.utc)

    def sim_clock(self, minute: int | None = None) -> str:
        m = self.sim_minute if minute is None else minute
        hh, mm = (int(x) for x in self.scenario.start_clock.split(":"))
        total = hh * 60 + mm + m
        return f"{(total // 60) % 24:02d}:{total % 60:02d}"

    # ------------------------------------------------------------------ physics
    def drivers(self, minute: int) -> Drivers:
        base = self.scenario.profile(float(minute % max(1, self.scenario.duration_min)))
        a = self.adjustments
        return Drivers(
            tdb=base.tdb + a.tdb_offset,
            rh=max(5.0, min(100.0, base.rh + a.rh_offset)),
            solar=max(0.0, base.solar * a.solar_scale),
            wind=max(0.1, base.wind + a.wind_offset),
            radiant_excess=base.radiant_excess,
        )

    def true_state(self, minute: int) -> ThermalState:
        d = self.drivers(minute)
        if self.overrides.dry_bulb is not None:
            d = Drivers(self.overrides.dry_bulb, d.rh, d.solar, d.wind, d.radiant_excess)
        st = derive_state(d, self.scenario.indoor)
        tnwb = self.overrides.natural_wet_bulb if self.overrides.natural_wet_bulb is not None else st.tnwb
        tg = self.overrides.globe_temperature if self.overrides.globe_temperature is not None else st.tg
        return ThermalState(st.tdb, st.rh, tnwb, tg, st.solar, st.wind, st.direct_solar)

    def validate_override(self, field_name: str, value: float) -> None:
        """Reject physically implausible direct overrides (raises ValueError)."""
        st = self.true_state(self.sim_minute)
        limits = {"dry_bulb": (-10.0, 60.0), "natural_wet_bulb": (-10.0, 45.0), "globe_temperature": (-10.0, 90.0)}
        lo, hi = limits[field_name]
        if not lo <= value <= hi:
            raise ValueError(f"{field_name} must be between {lo} and {hi} degC")
        tdb = value if field_name == "dry_bulb" else st.tdb
        tnwb = value if field_name == "natural_wet_bulb" else st.tnwb
        tg = value if field_name == "globe_temperature" else st.tg
        if field_name == "natural_wet_bulb" and tnwb > tdb + 0.5:
            raise ValueError(f"Natural wet-bulb ({tnwb:.1f}) cannot exceed dry-bulb ({tdb:.1f}) degC")
        if field_name == "globe_temperature" and tg < tdb - 3.0:
            raise ValueError(f"Globe temperature ({tg:.1f}) implausibly below dry-bulb ({tdb:.1f}) degC")

    # ------------------------------------------------------------------ faults
    def active_faults(self, minute: int) -> dict[str, str]:
        faults = dict(self.manual_faults)
        if self.use_scheduled_events:
            m = minute % max(1, self.scenario.duration_min)
            for ev in self.scenario.faults:
                if ev.start_min <= m < ev.end_min:
                    for s in ev.sensors:
                        faults.setdefault(s, ev.mode)
        if "all" in faults:
            mode = faults.pop("all")
            for s in SENSOR_KEYS:
                faults.setdefault(s, mode)
        return faults

    def scheduled_network_down(self, minute: int) -> bool:
        if not self.use_scheduled_events:
            return False
        m = minute % max(1, self.scenario.duration_min)
        return any(a <= m < b for a, b in self.scenario.network_outages)

    # ------------------------------------------------------------------ tick
    def tick(self) -> dict:
        """Advance one simulated minute and produce a reading dict."""
        minute = self.sim_minute
        st = self.true_state(minute)
        faults = self.active_faults(minute)
        noise = self.scenario.noise_sd
        overridden = self.overrides.active()

        measured = {
            "dry_bulb": st.tdb if "dry_bulb" in overridden else st.tdb + self.rng.gauss(0, noise),
            "natural_wet_bulb": st.tnwb if "natural_wet_bulb" in overridden else st.tnwb + self.rng.gauss(0, noise),
            "globe_temperature": st.tg if "globe_temperature" in overridden else st.tg + self.rng.gauss(0, noise * 1.5),
            "relative_humidity": max(0.0, min(100.0, st.rh + self.rng.gauss(0, 1.0))),
        }
        # keep noisy values physically consistent
        if measured["natural_wet_bulb"] > measured["dry_bulb"]:
            measured["natural_wet_bulb"] = measured["dry_bulb"]

        sensor_status = {}
        for sensor in SENSOR_KEYS:
            key = FIELD_FOR_SENSOR[sensor]
            mode = faults.get(sensor)
            if mode == "missing":
                measured[key] = None
                sensor_status[sensor] = "no_signal"
            elif mode == "invalid":
                measured[key] = INVALID_VALUE
                sensor_status[sensor] = "fault"
            else:
                measured[key] = round(measured[key], 2)
                sensor_status[sensor] = "ok"

        ts = datetime.now(timezone.utc)
        reading = {
            "reading_id": uuid.uuid4().hex[:16],
            "station_id": self.station_id,
            "worksite_id": self.worksite_id,
            "timestamp": ts.isoformat(),
            "sim_minute": minute,
            "sim_clock": self.sim_clock(minute),
            "scenario_id": self.scenario_id,
            "run_id": self.run_id,
            **measured,
            "direct_solar": st.direct_solar,
            "solar_irradiance": round(st.solar, 1),
            "air_speed": round(st.wind, 2),
            "sensor_status": sensor_status,
            "manual_override": overridden,
            "data_origin": "SIMULATED",
            "ground_truth": {
                "dry_bulb": round(st.tdb, 3),
                "natural_wet_bulb": round(st.tnwb, 3),
                "globe_temperature": round(st.tg, 3),
                "relative_humidity": round(st.rh, 2),
            },
        }
        self.sim_minute += 1
        return reading

    def produce(self) -> list[dict]:
        """Tick once and return readings deliverable over the network now.

        While the (simulated) uplink is down, readings are queued on the
        station ("edge buffer"); when it comes back, queued readings are
        delivered first, flagged as late-synchronised.
        """
        reading = self.tick()
        link_up = self.network_up and not self.scheduled_network_down(reading["sim_minute"])
        if not link_up:
            reading["queued_at_edge"] = True
            self.buffer.append(reading)
            return []
        out: list[dict] = []
        while self.buffer:
            r = self.buffer.popleft()
            r["late_sync"] = True
            out.append(r)
        out.append(reading)
        return out

    def status(self) -> dict:
        faults = self.active_faults(self.sim_minute)
        return {
            "station_id": self.station_id,
            "worksite_id": self.worksite_id,
            "scenario_id": self.scenario_id,
            "sim_minute": self.sim_minute,
            "sim_clock": self.sim_clock(),
            "faults": faults,
            "manual_faults": dict(self.manual_faults),
            "network_up": self.network_up and not self.scheduled_network_down(self.sim_minute),
            "manual_network_down": not self.network_up,
            "buffered_readings": len(self.buffer),
            "overrides": {k: v for k, v in self.overrides.__dict__.items() if v is not None},
            "adjustments": dict(self.adjustments.__dict__),
            "data_origin": "SIMULATED",
        }


def new_station(worksite_id: str, scenario_id: str = DEFAULT_SCENARIO, seed: int | None = None) -> VirtualStation:
    return VirtualStation(station_id=f"vstation-{worksite_id}", worksite_id=worksite_id, scenario_id=scenario_id, seed=seed)

