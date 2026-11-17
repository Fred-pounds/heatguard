from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

InterventionType = Literal[
    "hydration_break",
    "cooling_rest_break",
    "workload_reduction",
    "work_rotation",
    "shift_adjustment",
    "relocation_cooler_area",
    "other",
]

INTERVENTION_LABELS: dict[str, str] = {
    "hydration_break": "Hydration break",
    "cooling_rest_break": "Cooling / rest break",
    "workload_reduction": "Workload reduction",
    "work_rotation": "Work-rest rotation",
    "shift_adjustment": "Shift adjustment",
    "relocation_cooler_area": "Relocation to a cooler area",
    "other": "Other protective action",
}


class InterventionCreate(BaseModel):
    alert_id: str | None = None
    crew_id: str
    action: InterventionType
    notes: str = Field(default="", max_length=1000)
    supervisor_id: str = Field(default="supervisor-demo", max_length=60)
    # Optional context changes applied with the intervention (re-assessed immediately)
    new_workload: Literal["rest", "light", "moderate", "heavy", "very_heavy"] | None = None
    new_work_rest_regime: Literal["continuous", "45_15", "30_30", "15_45"] | None = None
    duration_minutes: int | None = Field(default=None, ge=1, le=600)


class InterventionComplete(BaseModel):
    notes: str = Field(default="", max_length=1000)
    supervisor_id: str = Field(default="supervisor-demo", max_length=60)


class FollowUp(BaseModel):
    timestamp: str
    assessment_id: str | None
    risk_category: str
    effective_wbgt: float | None
    note: str


class Intervention(BaseModel):
    intervention_id: str
    alert_id: str | None
    worksite_id: str
    crew_id: str
    crew_name: str = ""
    action: InterventionType
    action_label: str
    status: Literal["active", "completed"]
    start_time: str
    end_time: str | None = None
    planned_duration_minutes: int | None = None
    supervisor_id: str
    acknowledged: bool = True
    notes: str = ""
    completion_notes: str = ""
    context_changes: dict = Field(default_factory=dict)
    baseline_assessment: FollowUp | None = None
    follow_up_assessments: list[FollowUp] = Field(default_factory=list)
    outcome: str | None = None
