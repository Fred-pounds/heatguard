from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Workload = Literal["rest", "light", "moderate", "heavy", "very_heavy", "unknown"]
Acclimatization = Literal["acclimatized", "not_acclimatized", "unknown"]
WorkRestRegime = Literal["continuous", "45_15", "30_30", "15_45"]


class Worksite(BaseModel):
    worksite_id: str
    name: str
    location: str
    environment: Literal["outdoor", "indoor"]
    industry: str = "construction"
    station_id: str
    zones: list[str] = Field(default_factory=list)
    created_at: str


class CrewBase(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    worksite_id: str
    zone: str = Field(min_length=1, max_length=60)
    worker_count: int = Field(ge=1, le=500)
    workload: Workload = "unknown"
    clothing: str = "unknown"
    acclimatization: Acclimatization = "unknown"
    work_rest_regime: WorkRestRegime = "continuous"
    shift_start: str = Field(default="07:00", pattern=r"^\d{2}:\d{2}$")
    shift_duration_hours: float = Field(default=8.0, gt=0, le=16)
    current_task: str = Field(default="", max_length=120)


class CrewCreate(CrewBase):
    pass


class CrewUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    worksite_id: str | None = None
    zone: str | None = None
    worker_count: int | None = Field(default=None, ge=1, le=500)
    workload: Workload | None = None
    clothing: str | None = None
    acclimatization: Acclimatization | None = None
    work_rest_regime: WorkRestRegime | None = None
    shift_start: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    shift_duration_hours: float | None = Field(default=None, gt=0, le=16)
    current_task: str | None = Field(default=None, max_length=120)
    active: bool | None = None


class Crew(CrewBase):
    crew_id: str
    active: bool = True
    created_at: str
    updated_at: str
