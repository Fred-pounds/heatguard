from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

AGE_BANDS = ("18-29", "30-39", "40-49", "50-59", "60+")
SIGNAL_SCOPES = ("heart_rate", "core_temp_est")
SYMPTOMS_RED_FLAG = {
    "confusion": "Confusion or slurred speech",
    "collapse": "Fainting or collapse",
    "hot_dry_skin": "Hot, dry skin or stopped sweating",
    "seizure": "Seizure",
}
SYMPTOMS_FIRST_AID = {
    "dizziness": "Dizziness or light-headedness",
    "headache": "Headache",
    "nausea": "Nausea or vomiting",
    "cramps": "Muscle cramps",
    "heavy_sweating": "Heavy sweating",
    "fatigue": "Unusual tiredness or weakness",
}
OUTCOMES = {
    "first_aid_given": "First aid given; resting in a cool area",
    "transferred_to_clinic": "Transferred to site clinic",
    "ambulance_called": "Ambulance called (998)",
    "monitored_no_symptoms": "Checked by first aider; symptoms resolved, kept under observation",
}


class Consent(BaseModel):
    status: Literal["granted", "withdrawn", "not_asked"] = "not_asked"
    scopes: list[str] = Field(default_factory=list)
    granted_at: str | None = None
    withdrawn_at: str | None = None
    notice_version: str = "2026-11"


class Worker(BaseModel):
    """Pseudonymous wearable-programme participant. No name, no employee number."""

    worker_id: str
    badge: str
    crew_id: str
    device_id: str
    age_band: str | None = None  # only used for the NIOSH heart-rate threshold, with consent
    consent: Consent = Field(default_factory=Consent)
    created_at: str


class ConsentRequest(BaseModel):
    granted: bool
    age_band: Literal["18-29", "30-39", "40-49", "50-59", "60+"] | None = None
    scopes: list[Literal["heart_rate", "core_temp_est"]] = Field(default_factory=lambda: ["heart_rate", "core_temp_est"])


class SignalIn(BaseModel):
    worker_id: str
    device_id: str
    heart_rate: float | None = Field(default=None, ge=30, le=230)
    core_temp_est: float | None = Field(default=None, ge=34, le=43)
    battery_pct: float | None = Field(default=None, ge=0, le=100)
    timestamp: str | None = None
    data_origin: Literal["SIMULATED", "MEASURED"] = "SIMULATED"


class SymptomReportIn(BaseModel):
    crew_id: str
    worker_id: str | None = None
    reported_by: Literal["self", "coworker", "supervisor"] = "self"
    symptoms: list[str] = Field(min_length=1)
    note: str = Field(default="", max_length=300)


class EscalationUpdate(BaseModel):
    action: Literal["acknowledge", "responding", "close"]
    outcome: Literal["first_aid_given", "transferred_to_clinic", "ambulance_called", "monitored_no_symptoms"] | None = None
    note: str = Field(default="", max_length=500)
    responder_id: str = Field(default="first-aider-demo", max_length=60)
