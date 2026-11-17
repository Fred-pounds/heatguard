from __future__ import annotations

from fastapi import Request

from ..services.heatguard_service import HeatGuardService


def get_service(request: Request) -> HeatGuardService:
    return request.app.state.service


def public_reading(r: dict) -> dict:
    """Strip simulator-internal ground truth from API output."""
    return {k: v for k, v in r.items() if k != "ground_truth"}
