"""Predefined SYNTHETIC environmental scenarios.

Each scenario returns environmental *drivers* (air temperature, humidity,
solar irradiance, air speed, indoor radiant excess) for a simulated minute.
The station converts drivers to WBGT components with the consistent model in
physics.py, then adds measurement noise and any configured faults.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable

from .physics import Drivers


def _lerp(a: float, b: float, frac: float) -> float:
    frac = max(0.0, min(1.0, frac))
    return a + (b - a) * frac


@dataclass(frozen=True)
class FaultEvent:
    """Scheduled fault: at `start_min` the listed sensors fail until `end_min`."""

    start_min: int
    end_min: int
    sensors: tuple[str, ...]  # subset of: dry_bulb, wet_bulb, globe, humidity, all
    mode: str = "missing"  # missing | invalid


@dataclass(frozen=True)
class Scenario:
    id: str
    code: str
    name: str
    description: str
    indoor: bool
    start_clock: str  # simulated local time-of-day at minute 0, HH:MM
    duration_min: int
    profile: Callable[[float], Drivers]
    suggested_context: dict = field(default_factory=dict)
    faults: tuple[FaultEvent, ...] = ()
    network_outages: tuple[tuple[int, int], ...] = ()  # (start_min, end_min)
    noise_sd: float = 0.15  # degC sensor noise (synthetic)


def _normal(t: float) -> Drivers:
    # Early-morning, partly cloudy, moderate heat; gentle drift.
    frac = t / 240.0
    return Drivers(
        tdb=_lerp(25.5, 28.0, frac) + 0.3 * math.sin(t / 17.0),
        rh=_lerp(72.0, 62.0, frac),
        solar=_lerp(180.0, 330.0, frac) + 60.0 * math.sin(t / 9.0),
        wind=2.2 + 0.4 * math.sin(t / 11.0),
    )


def _increasing(t: float) -> Drivers:
    # Morning-to-midday build-up: temperature and solar load rise, wind drops.
    frac = t / 180.0
    return Drivers(
        tdb=_lerp(27.0, 36.5, frac) + 0.2 * math.sin(t / 13.0),
        rh=_lerp(68.0, 46.0, frac),
        solar=_lerp(250.0, 920.0, frac),
        wind=_lerp(2.0, 0.8, frac),
    )


def _construction(t: float) -> Drivers:
    # Exposed concrete deck around solar noon: high radiant load, low air movement.
    return Drivers(
        tdb=32.3 + 0.7 * math.sin(t / 30.0),
        rh=49.0 + 3.0 * math.sin(t / 23.0),
        solar=910.0 + 40.0 * math.sin(t / 7.0),
        wind=0.85 + 0.2 * math.sin(t / 5.0),
    )


def _industrial(t: float) -> Drivers:
    # Indoor foundry / processing hall: radiant sources, poor ventilation.
    return Drivers(
        tdb=30.6 + 0.6 * math.sin(t / 25.0),
        rh=50.0 + 2.0 * math.sin(t / 19.0),
        solar=0.0,
        wind=0.4,
        radiant_excess=9.0 + 1.5 * math.sin(t / 15.0),
    )


def _sensor_failure(t: float) -> Drivers:
    # Warm late-morning conditions; faults are scheduled separately.
    frac = t / 120.0
    return Drivers(
        tdb=_lerp(29.0, 32.0, frac),
        rh=_lerp(62.0, 55.0, frac),
        solar=_lerp(500.0, 750.0, frac),
        wind=1.4,
    )


SCENARIOS: dict[str, Scenario] = {
    s.id: s
    for s in [
        Scenario(
            id="normal",
            code="A",
            name="Normal working conditions",
            description="Moderate environmental heat in the early morning, light cloud and steady breeze. "
            "Light-to-moderate work by acclimatized crews.",
            indoor=False,
            start_clock="07:00",
            duration_min=240,
            profile=_normal,
            suggested_context={"workload": "light", "acclimatization": "acclimatized", "clothing": "standard_work_clothing"},
        ),
        Scenario(
            id="increasing_heat",
            code="B",
            name="Increasing environmental heat",
            description="Air temperature, solar load and radiant heat rise steadily toward midday while air movement falls. "
            "The system should recognise worsening conditions early.",
            indoor=False,
            start_clock="09:00",
            duration_min=180,
            profile=_increasing,
            suggested_context={"workload": "moderate", "acclimatization": "acclimatized", "clothing": "standard_work_clothing"},
        ),
        Scenario(
            id="construction_radiant",
            code="C",
            name="High-radiant-heat construction site",
            description="Outdoor concrete deck with direct sun, elevated globe temperature and low wind. Moderate to heavy work.",
            indoor=False,
            start_clock="12:00",
            duration_min=180,
            profile=_construction,
            suggested_context={"workload": "heavy", "acclimatization": "acclimatized", "clothing": "long_sleeved_protective"},
        ),
        Scenario(
            id="industrial_indoor",
            code="D",
            name="Industrial work environment",
            description="Indoor processing hall with furnace radiant heat, limited ventilation and heavy work.",
            indoor=True,
            start_clock="10:00",
            duration_min=240,
            profile=_industrial,
            suggested_context={"workload": "heavy", "acclimatization": "acclimatized", "clothing": "cloth_coveralls"},
        ),
        Scenario(
            id="sensor_failure",
            code="E",
            name="Sensor failure",
            description="Warm conditions with scheduled faults: globe sensor drop-out, invalid wet-bulb values, "
            "full station outage, then recovery. Missing data must never be classified as safe.",
            indoor=False,
            start_clock="10:30",
            duration_min=120,
            profile=_sensor_failure,
            suggested_context={"workload": "moderate", "acclimatization": "acclimatized", "clothing": "standard_work_clothing"},
            faults=(
                FaultEvent(15, 30, ("globe",), "missing"),
                FaultEvent(40, 55, ("wet_bulb",), "invalid"),
                FaultEvent(70, 85, ("all",), "missing"),
            ),
        ),
    ]
}

DEFAULT_SCENARIO = "normal"
