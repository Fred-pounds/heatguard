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
    start_clock: str  # simulated local time-of-day at minute 0, HH:MM (Gulf Standard Time)
    duration_min: int
    profile: Callable[[float], Drivers]
    suggested_context: dict = field(default_factory=dict)
    faults: tuple[FaultEvent, ...] = ()
    network_outages: tuple[tuple[int, int], ...] = ()  # (start_min, end_min)
    noise_sd: float = 0.15  # degC sensor noise (synthetic)
    sim_date: str = "2026-07-15"  # simulated calendar date (ISO), used for seasonal rules such as the UAE midday break


def _normal(t: float) -> Drivers:
    # Abu Dhabi cool season (November), coastal morning: humid, mild sun, sea breeze.
    frac = t / 240.0
    return Drivers(
        tdb=_lerp(25.5, 28.0, frac) + 0.3 * math.sin(t / 17.0),
        rh=_lerp(72.0, 62.0, frac),
        solar=_lerp(180.0, 330.0, frac) + 60.0 * math.sin(t / 9.0),
        wind=2.2 + 0.4 * math.sin(t / 11.0),
    )


def _increasing(t: float) -> Drivers:
    # Abu Dhabi summer (July) day building from early morning towards midday: temperature and sun rise,
    # humidity falls as the land heats, the morning breeze drops.
    frac = t / 360.0
    return Drivers(
        tdb=_lerp(30.0, 43.0, frac) + 0.2 * math.sin(t / 13.0),
        rh=_lerp(55.0, 30.0, frac),
        solar=_lerp(250.0, 980.0, frac),
        wind=_lerp(3.5, 1.4, frac),
    )


def _construction(t: float) -> Drivers:
    # Summer afternoon on an exposed deck after the midday break: very hot, dry air, strong sun easing.
    frac = t / 180.0
    return Drivers(
        tdb=_lerp(42.0, 39.0, frac) + 0.5 * math.sin(t / 30.0),
        rh=_lerp(25.0, 35.0, frac) + 2.0 * math.sin(t / 23.0),
        solar=_lerp(800.0, 450.0, frac) + 30.0 * math.sin(t / 7.0),
        wind=1.6 + 0.3 * math.sin(t / 5.0),
    )


def _industrial(t: float) -> Drivers:
    # Indoor metal-processing hall in August: partial cooling only, furnace radiant heat.
    return Drivers(
        tdb=33.5 + 0.6 * math.sin(t / 25.0),
        rh=42.0 + 2.0 * math.sin(t / 19.0),
        solar=0.0,
        wind=0.5,
        radiant_excess=6.5 + 1.0 * math.sin(t / 15.0),
    )


def _sensor_failure(t: float) -> Drivers:
    # Late-September morning; faults are scheduled separately.
    frac = t / 120.0
    return Drivers(
        tdb=_lerp(31.0, 34.0, frac),
        rh=_lerp(60.0, 50.0, frac),
        solar=_lerp(450.0, 750.0, frac),
        wind=1.6,
    )


def _humid_coastal(t: float) -> Drivers:
    # Gulf-coast summer morning (August): very high humidity limits sweat evaporation,
    # so heat stress is high even before peak air temperature.
    frac = t / 180.0
    return Drivers(
        tdb=_lerp(33.0, 37.0, frac) + 0.2 * math.sin(t / 11.0),
        rh=_lerp(82.0, 62.0, frac),
        solar=_lerp(300.0, 750.0, frac),
        wind=_lerp(1.2, 1.6, frac),
    )


SCENARIOS: dict[str, Scenario] = {
    s.id: s
    for s in [
        Scenario(
            id="normal",
            code="A",
            name="Cool-season morning",
            description="Abu Dhabi in November: mild, humid coastal morning with a sea breeze. "
            "Light-to-moderate work by acclimatized crews.",
            indoor=False,
            start_clock="07:00",
            sim_date="2026-11-12",
            duration_min=240,
            profile=_normal,
            suggested_context={"workload": "light", "acclimatization": "acclimatized", "clothing": "standard_work_clothing"},
        ),
        Scenario(
            id="increasing_heat",
            code="B",
            name="Summer day heating up",
            description="A July day from 07:00 towards midday: air temperature climbs to 43 °C and the sun strengthens. "
            "Crosses into the UAE midday break at 12:30.",
            indoor=False,
            start_clock="07:00",
            sim_date="2026-07-15",
            duration_min=360,
            profile=_increasing,
            suggested_context={"workload": "moderate", "acclimatization": "acclimatized", "clothing": "standard_work_clothing"},
        ),
        Scenario(
            id="construction_radiant",
            code="C",
            name="Summer afternoon on site",
            description="Exposed concrete deck after the midday break (15:00, July): 40+ °C, dry air, strong sun. "
            "Moderate to heavy work.",
            indoor=False,
            start_clock="15:00",
            sim_date="2026-07-15",
            duration_min=180,
            profile=_construction,
            suggested_context={"workload": "heavy", "acclimatization": "acclimatized", "clothing": "long_sleeved_protective"},
        ),
        Scenario(
            id="humid_coastal",
            code="F",
            name="Humid coastal morning",
            description="August morning on the Gulf coast: humidity above 80 % stops sweat from cooling the body, "
            "so heat stress is high even before the hottest hours.",
            indoor=False,
            start_clock="07:00",
            sim_date="2026-08-10",
            duration_min=180,
            profile=_humid_coastal,
            suggested_context={"workload": "moderate", "acclimatization": "acclimatized", "clothing": "standard_work_clothing"},
        ),
        Scenario(
            id="industrial_indoor",
            code="D",
            name="Industrial work environment",
            description="Indoor metal-processing hall in August with partial cooling, furnace radiant heat and heavy work.",
            indoor=True,
            start_clock="10:00",
            sim_date="2026-08-10",
            duration_min=240,
            profile=_industrial,
            suggested_context={"workload": "heavy", "acclimatization": "acclimatized", "clothing": "cloth_coveralls"},
        ),
        Scenario(
            id="sensor_failure",
            code="E",
            name="Sensor failure",
            description="Warm September morning with scheduled faults: globe sensor drop-out, invalid wet-bulb values, "
            "full station outage, then recovery. Missing data must never be classified as safe.",
            indoor=False,
            start_clock="08:30",
            sim_date="2026-09-25",
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
