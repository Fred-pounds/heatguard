from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Severity = Literal["routine", "caution", "elevated", "high", "critical", "data_unavailable"]


class AlertEvent(BaseModel):
    timestamp: str
    event: str
    detail: str = ""
    actor: str = "system"


class Alert(BaseModel):
    alert_id: str
    timestamp: str
    updated_at: str
    worksite_id: str
    worksite_name: str = ""
    crew_id: str
    crew_name: str = ""
    alert_type: Literal["heat_risk", "data_quality"]
    severity: Severity
    severity_level: int
    peak_severity: Severity
    explanation: str
    contributing_factors: list[dict] = Field(default_factory=list)
    recommendations: list[dict] = Field(default_factory=list)
    assessment_id: str | None = None
    acknowledgement_status: Literal["unacknowledged", "acknowledged"] = "unacknowledged"
    acknowledged_at: str | None = None
    acknowledged_by: str | None = None
    resolution_status: Literal["open", "conditions_improving", "resolved"] = "open"
    resolved_at: str | None = None
    resolved_by: str | None = None
    resolution_note: str | None = None
    escalation_level: int = 0
    escalated_at: str | None = None
    duplicate_count: int = 0
    improving_streak: int = 0
    latest_category: str | None = None
    intervention_ids: list[str] = Field(default_factory=list)
    history: list[AlertEvent] = Field(default_factory=list)
    data_origin: str = "SIMULATED"


class AcknowledgeRequest(BaseModel):
    supervisor_id: str = Field(default="supervisor-demo", max_length=60)
    note: str | None = Field(default=None, max_length=500)


class ResolveRequest(BaseModel):
    supervisor_id: str = Field(default="supervisor-demo", max_length=60)
    note: str = Field(min_length=3, max_length=500)
    override_active_conditions: bool = False
