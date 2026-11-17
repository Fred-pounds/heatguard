"""Synthetic thermal-environment model used ONLY to generate SIMULATED readings.

The goal is internal consistency (e.g. wet-bulb never above dry-bulb, globe
temperature rising with solar load and falling with wind), not a validated
physical model. Real deployments must measure Tnwb, Tg and Tdb directly with
instruments that conform to ISO 7243 / NIOSH measurement guidance.

Generation assumptions (documented in simulator/README.md):

1. Psychrometric wet-bulb (Twb) from dry-bulb and RH using Stull (2011),
   "Wet-Bulb Temperature from Relative Humidity and Air Temperature",
   J. Appl. Meteor. Climatol. 50:2267-2269. Valid roughly RH 5-99 %, T -20..50 C.
2. Globe temperature excess over air temperature grows with solar irradiance
   (outdoors) or a configured radiant-source excess (indoors) and shrinks with
   air speed. Simplified heuristic: dTg = k_s * S / (1 + 0.3 * v) + R / (1 + 0.3 * v).
3. Natural wet-bulb exceeds psychrometric wet-bulb modestly under radiant load
   and low air movement: Tnwb = Twb + 0.1 * (Tg - Tdb) / (1 + 0.2 * v),
   then constrained to Tnwb <= Tdb.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

SOLAR_GLOBE_COEFF = 0.016  # degC per W/m2 at still air (heuristic)
DIRECT_SUN_THRESHOLD_WM2 = 120.0  # WMO sunshine threshold (direct irradiance) used as "direct solar load" flag


def stull_wet_bulb(tdb_c: float, rh_pct: float) -> float:
    """Psychrometric wet-bulb temperature (degC), Stull (2011)."""
    rh = max(1.0, min(100.0, rh_pct))
    t = tdb_c
    return (
        t * math.atan(0.151977 * math.sqrt(rh + 8.313659))
        + math.atan(t + rh)
        - math.atan(rh - 1.676331)
        + 0.00391838 * rh ** 1.5 * math.atan(0.023101 * rh)
        - 4.686035
    )


def globe_temperature(tdb_c: float, solar_wm2: float, wind_ms: float, radiant_excess_c: float = 0.0) -> float:
    damp = 1.0 + 0.3 * max(0.0, wind_ms)
    return tdb_c + (SOLAR_GLOBE_COEFF * max(0.0, solar_wm2) + max(0.0, radiant_excess_c)) / damp


def natural_wet_bulb(twb_c: float, tdb_c: float, tg_c: float, wind_ms: float) -> float:
    tnwb = twb_c + 0.1 * max(0.0, tg_c - tdb_c) / (1.0 + 0.2 * max(0.0, wind_ms))
    return min(tnwb, tdb_c)


@dataclass(frozen=True)
class Drivers:
    """Underlying (unobservable) environmental drivers for a time step."""

    tdb: float
    rh: float
    solar: float  # W/m2 (0 indoors)
    wind: float  # m/s
    radiant_excess: float = 0.0  # degC, indoor radiant sources (furnaces, hot surfaces)


@dataclass(frozen=True)
class ThermalState:
    tdb: float
    rh: float
    tnwb: float
    tg: float
    solar: float
    wind: float
    direct_solar: bool


def derive_state(d: Drivers, indoor: bool) -> ThermalState:
    solar = 0.0 if indoor else d.solar
    twb = stull_wet_bulb(d.tdb, d.rh)
    tg = globe_temperature(d.tdb, solar, d.wind, d.radiant_excess)
    tnwb = natural_wet_bulb(twb, d.tdb, tg, d.wind)
    return ThermalState(
        tdb=d.tdb,
        rh=d.rh,
        tnwb=tnwb,
        tg=tg,
        solar=solar,
        wind=d.wind,
        direct_solar=(not indoor) and solar >= DIRECT_SUN_THRESHOLD_WM2,
    )
