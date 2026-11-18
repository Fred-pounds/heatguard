"""Minimal access control for the prototype.

Roles are passed in the `X-HeatGuard-Role` header (supervisor | ohs | worker | admin).
`ohs` (occupational health and safety officer / first aider) is the only role that sees individual
physiological signals and symptom details.
This is a demo stand-in for Firebase Authentication custom claims; it is NOT a
secure authentication mechanism and must be replaced before field use.
Sensor ingestion can additionally be protected with an API key.
"""
from __future__ import annotations

from fastapi import Header, HTTPException

from .config import get_settings

ROLES = {"supervisor", "ohs", "worker", "admin"}


def current_role(x_heatguard_role: str | None = Header(default=None)) -> str:
    role = (x_heatguard_role or "supervisor").lower()
    if role not in ROLES:
        raise HTTPException(status_code=403, detail=f"Unknown role '{role}'")
    return role


def require_supervisor(x_heatguard_role: str | None = Header(default=None)) -> str:
    role = current_role(x_heatguard_role)
    if role not in {"supervisor", "ohs", "admin"}:
        raise HTTPException(status_code=403, detail="Supervisor, OHS or admin role required")
    return role


def require_ohs(x_heatguard_role: str | None = Header(default=None)) -> str:
    role = current_role(x_heatguard_role)
    if role not in {"ohs", "admin"}:
        raise HTTPException(status_code=403, detail="Individual health data is restricted to the OHS role")
    return role


def require_ingest_key(x_heatguard_key: str | None = Header(default=None)) -> None:
    key = get_settings().ingest_api_key
    if key and x_heatguard_key != key:
        raise HTTPException(status_code=401, detail="Invalid sensor ingest key")
