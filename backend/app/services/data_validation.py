"""Measurement validation: missing, out-of-range, implausible and faulted values."""
from __future__ import annotations

from ..schemas.sensor import SensorReadingIn, ValidationIssue, ValidationResult
from .psychrometrics import stull_wet_bulb

# Natural wet-bulb normally sits between the psychrometric wet-bulb and a few degrees above it (radiant load).
# A reading far above that band means a dry or dust-fouled wick; far below means a faulty probe.
WICK_MAX_ABOVE = 3.5
WICK_MAX_BELOW = 1.5
DUST_UNRELIABLE = 0.5  # station-reported fouling at which globe and wick readings are no longer trusted

# Plausible operating ranges for occupational heat monitoring instruments (degC / %RH).
RANGES = {
    "dry_bulb": (-20.0, 60.0),
    "natural_wet_bulb": (-20.0, 45.0),
    "globe_temperature": (-20.0, 90.0),
    "relative_humidity": (0.0, 100.0),
}
SENSOR_OF_FIELD = {
    "dry_bulb": "dry_bulb",
    "natural_wet_bulb": "wet_bulb",
    "globe_temperature": "globe",
    "relative_humidity": "humidity",
}
WBGT_FIELDS = ("dry_bulb", "natural_wet_bulb", "globe_temperature")


def validate_reading(r: SensorReadingIn) -> ValidationResult:
    issues: list[ValidationIssue] = []
    valid: list[str] = []
    for field, (lo, hi) in RANGES.items():
        value = getattr(r, field)
        status = r.sensor_status.get(SENSOR_OF_FIELD[field], "ok")
        if value is None:
            issues.append(ValidationIssue(field=field, issue="missing", detail=f"No value received (sensor status: {status})"))
            continue
        if status not in ("ok", "unknown"):
            issues.append(ValidationIssue(field=field, issue="sensor_fault", detail=f"Station reports sensor status '{status}'"))
            continue
        if not lo <= value <= hi:
            issues.append(ValidationIssue(field=field, issue="invalid", detail=f"{value} outside plausible range {lo}..{hi}"))
            continue
        valid.append(field)

    # Heavy dust fouling: a coated globe under-reads radiant heat (a hidden false-safe risk), so do not trust it
    if r.dust_index is not None and r.dust_index >= DUST_UNRELIABLE:
        for field in ("globe_temperature", "natural_wet_bulb"):
            if field in valid:
                valid.remove(field)
                issues.append(ValidationIssue(field=field, issue="sensor_fault",
                                              detail=f"Dust fouling {r.dust_index:.2f}: reading unreliable until the station is cleaned"))

    # Cross-field physical plausibility (tolerance for measurement noise)
    if "natural_wet_bulb" in valid and "dry_bulb" in valid and r.natural_wet_bulb > r.dry_bulb + 1.0:  # type: ignore[operator]
        issues.append(ValidationIssue(field="natural_wet_bulb", issue="implausible",
                                      detail=f"Natural wet-bulb {r.natural_wet_bulb} exceeds dry-bulb {r.dry_bulb}"))
        valid.remove("natural_wet_bulb")
    if ("natural_wet_bulb" in valid and "dry_bulb" in valid and "relative_humidity" in valid
            and "natural_wet_bulb" not in (r.manual_override or [])):
        expected = stull_wet_bulb(r.dry_bulb, r.relative_humidity)  # type: ignore[arg-type]
        diff = r.natural_wet_bulb - expected  # type: ignore[operator]
        if diff > WICK_MAX_ABOVE or diff < -WICK_MAX_BELOW:
            issues.append(ValidationIssue(
                field="natural_wet_bulb", issue="implausible",
                detail=f"Wet-bulb {r.natural_wet_bulb:.1f} degC inconsistent with air {r.dry_bulb:.1f} degC and RH "
                       f"{r.relative_humidity:.0f}% (expected about {expected:.1f} degC): wick may be dry or dust-fouled"))
            valid.remove("natural_wet_bulb")
    if "globe_temperature" in valid and "dry_bulb" in valid and r.globe_temperature < r.dry_bulb - 5.0:  # type: ignore[operator]
        issues.append(ValidationIssue(field="globe_temperature", issue="implausible",
                                      detail=f"Globe {r.globe_temperature} far below dry-bulb {r.dry_bulb}"))
        valid.remove("globe_temperature")

    if not issues:
        validity = "valid"
    elif any(f in valid for f in WBGT_FIELDS):
        validity = "partially_valid"
    else:
        validity = "invalid"
    return ValidationResult(measurement_validity=validity, valid_fields=valid, issues=issues)
