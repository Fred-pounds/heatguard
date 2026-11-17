"""Wet Bulb Globe Temperature (WBGT) calculation.

Standard formulas (ISO 7243; NIOSH 2016), all temperatures in °C:

* Outdoors with direct solar load:   WBGT = 0.7*Tnwb + 0.2*Tg + 0.1*Tdb
* Indoors / outdoors without sun:    WBGT = 0.7*Tnwb + 0.3*Tg
"""
from __future__ import annotations

from dataclasses import dataclass

OUTDOOR_SOLAR_FORMULA = "WBGT = 0.7*Tnwb + 0.2*Tg + 0.1*Tdb (outdoor, direct solar load)"
NO_SOLAR_FORMULA = "WBGT = 0.7*Tnwb + 0.3*Tg (indoor or no direct solar load)"


class MissingComponentError(ValueError):
    def __init__(self, missing: list[str]):
        self.missing = missing
        super().__init__(f"Missing WBGT component(s): {', '.join(missing)}")


@dataclass(frozen=True)
class WBGTResult:
    value: float
    formula: str
    with_solar_load: bool


def wbgt_outdoor_solar(tnwb: float, tg: float, tdb: float) -> float:
    return 0.7 * tnwb + 0.2 * tg + 0.1 * tdb


def wbgt_no_solar(tnwb: float, tg: float) -> float:
    return 0.7 * tnwb + 0.3 * tg


def uses_solar_formula(environment: str, direct_solar: bool | None) -> bool:
    """Outdoor sites use the solar formula unless the station reports no direct sun.

    If an outdoor station does not report solar status, the solar formula is used:
    it requires the dry-bulb reading and is the formula specified for outdoor
    conditions with sun, so the absence of information is not assumed to mean shade.
    """
    if environment == "indoor":
        return False
    return direct_solar is not False


def compute_wbgt(
    tnwb: float | None, tg: float | None, tdb: float | None, environment: str, direct_solar: bool | None
) -> WBGTResult:
    solar = uses_solar_formula(environment, direct_solar)
    required = {"natural_wet_bulb": tnwb, "globe_temperature": tg}
    if solar:
        required["dry_bulb"] = tdb
    missing = [k for k, v in required.items() if v is None]
    if missing:
        raise MissingComponentError(missing)
    if solar:
        return WBGTResult(round(wbgt_outdoor_solar(tnwb, tg, tdb), 2), OUTDOOR_SOLAR_FORMULA, True)  # type: ignore[arg-type]
    return WBGTResult(round(wbgt_no_solar(tnwb, tg), 2), NO_SOLAR_FORMULA, False)  # type: ignore[arg-type]
