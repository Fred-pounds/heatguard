from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

RiskCategory = Literal["routine", "caution", "elevated", "high", "critical", "unavailable"]


class ContributingFactor(BaseModel):
    factor: str
    detail: str
    direction: Literal["increases_concern", "reduces_concern", "uncertainty", "neutral"] = "increases_concern"


class RecommendedAction(BaseModel):
    action: str
    detail: str
    priority: Literal["routine", "advised", "required", "urgent"] = "advised"
    source: str = ""


class DataQuality(BaseModel):
    measurement_validity: Literal["valid", "partially_valid", "invalid", "no_data"]
    data_completeness: float = Field(ge=0, le=1)
    missing_inputs: list[str] = Field(default_factory=list)
    unknown_inputs: list[str] = Field(default_factory=list)
    stale: bool = False
    environmental_data_available: bool = True
    reading_age_seconds: float | None = None
    assessment_confidence: Literal["standard", "reduced", "not_assessable"]
    confidence_reasons: list[str] = Field(default_factory=list)


class LimitDetails(BaseModel):
    limit_type: Literal["REL", "RAL"]
    limit_reason: str
    metabolic_rate_w: float
    twa_metabolic_rate_w: float
    current_regime: str
    limit_at_current_regime: float
    required_regime: str | None
    regime_limits: dict[str, float]
    clothing_adjustment: float
    measured_wbgt: float
    rolling_mean_wbgt: float | None
    screening_wbgt: float
    effective_wbgt: float
    margin_to_limit: float
    caution_margin: float


class Assessment(BaseModel):
    assessment_id: str
    timestamp: str
    worksite_id: str
    crew_id: str
    crew_name: str = ""
    reading_id: str | None = None
    sim_clock: str | None = None
    assessment_status: Literal["valid", "incomplete", "unavailable"]
    risk_category: RiskCategory
    risk_level: int = Field(description="0-4 for routine..critical, -1 when unavailable")
    wbgt: float | None = None
    effective_wbgt: float | None = None
    contributing_factors: list[ContributingFactor]
    explanation: str
    recommended_actions: list[RecommendedAction]
    data_quality: DataQuality
    data_completeness: float
    inputs_used: dict
    limit_details: LimitDetails | None = None
    assessment_method: str
    guideline_reference: str
    limitations: list[str]
    outlook: dict = Field(default_factory=dict, description="Trend projection: minutes to limit, midday-break countdown")
    worker_signals: dict | None = Field(default=None, description="Crew-level summary of consented wearable signals (no individual values)")
    regulatory_flags: list[dict] = Field(default_factory=list, description="Country-specific legal restrictions in force (e.g. UAE midday break)")
    data_origin: Literal["SIMULATED", "MEASURED"] = "SIMULATED"
