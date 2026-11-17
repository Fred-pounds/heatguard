"""HeatGuard FastAPI application entry point.

Run:  uvicorn app.main:app --reload --port 8000   (from the backend/ directory)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.routes import alerts, assessments, crews, interventions, reports, sensors, simulation, system
from .core.config import get_settings
from .services.heatguard_service import HeatGuardService

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    service = HeatGuardService(get_settings())
    service.initialise()
    app.state.service = service
    service.start_background()
    yield
    await service.shutdown()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="HeatGuard API",
        version="0.1.0",
        description="Explainable occupational heat-risk early warning (hackathon prototype). "
                    "All sensor data produced by the built-in simulator are SIMULATED.",
        lifespan=lifespan,
    )
    app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_methods=["*"], allow_headers=["*"])
    for module in (system, crews, sensors, assessments, alerts, interventions, simulation, reports):
        app.include_router(module.router, prefix="/api")
    return app


app = create_app()
