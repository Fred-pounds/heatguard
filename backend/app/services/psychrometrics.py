"""Psychrometric helpers used for sensor plausibility checks."""
from __future__ import annotations

import math


def stull_wet_bulb(tdb_c: float, rh_pct: float) -> float:
    """Psychrometric wet-bulb temperature (degC), Stull (2011), J. Appl. Meteor. Climatol. 50:2267-2269."""
    rh = max(1.0, min(100.0, rh_pct))
    t = tdb_c
    return (t * math.atan(0.151977 * math.sqrt(rh + 8.313659)) + math.atan(t + rh) - math.atan(rh - 1.676331)
            + 0.00391838 * rh ** 1.5 * math.atan(0.023101 * rh) - 4.686035)
