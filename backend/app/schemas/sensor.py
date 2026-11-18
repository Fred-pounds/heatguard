from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class SensorReadingIn(BaseModel):
    """Reading as delivered by any station (simulated or a future ESP32)."""

    reading_id: str | None = None
    station_id: str
    worksite_id: str
    timestamp: str | None = Field(default=None, description="ISO-8601 measurement time (UTC)")
    dry_bulb: float | None = None
    natural_wet_bulb: float | None = None
    globe_temperature: float | None = None
    relative_humidity: float | None = None
    direct_solar: bool | None = Field(default=None, description="Direct solar load at the measurement point")
    solar_irradiance: float | None = None
    air_speed: float | None = None
    sensor_status: dict[str, str] = Field(default_factory=dict)
    manual_override: list[str] = Field(default_factory=list)
    data_origin: Literal["SIMULATED", "MEASURED"] = "SIMULATED"
    sim_minute: int | None = None
    sim_clock: str | None = None
    sim_date: str | None = Field(default=None, description="Site-local calendar date (YYYY-MM-DD)")
    scenario_id: str | None = None
    run_id: str | None = None
    late_sync: bool = False
    queued_at_edge: bool = False
    ground_truth: dict | None = Field(default=None, description="Simulator-only noise-free values used for evaluation")


class ValidationIssue(BaseModel):
    field: str
    issue: Literal["missing", "invalid", "implausible", "sensor_fault", "stale"]
    detail: str


class ValidationResult(BaseModel):
    measurement_validity: Literal["valid", "partially_valid", "invalid"]
    valid_fields: list[str]
    issues: list[ValidationIssue]


class SensorReading(SensorReadingIn):
    reading_id: str
    timestamp: str
    received_at: str
    wbgt: float | None = None
    wbgt_formula: str | None = None
    validation: ValidationResult
