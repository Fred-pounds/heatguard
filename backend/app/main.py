"""HeatGuard FastAPI application entry point.

Run:  uvicorn app.main:app --reload --port 8000   (from the backend/ directory)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .api.routes import alerts, assessments, crews, interventions, reports, sensors, simulation, system
from .core.config import REPO_DIR, get_settings
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

    @app.middleware("http")
    async def no_stale_dashboard(request, call_next):
        """Make browsers revalidate dashboard files so an updated build is picked up on a normal refresh."""
        response = await call_next(request)
        if not request.url.path.startswith("/api"):
            response.headers["Cache-Control"] = "no-cache"
        return response
    for module in (system, crews, sensors, assessments, alerts, interventions, simulation, reports):
        app.include_router(module.router, prefix="/api")
    # Single-port demo: serve the Flutter Web build if it has been built
    # Serve whichever dashboard is newest: a local Flutter build (frontend/build/web) or the prebuilt
    # copy committed in frontend/dist. A stale local build must never hide an updated dist after `git pull`.
    candidates = [d for d in (REPO_DIR / "frontend" / "build" / "web", REPO_DIR / "frontend" / "dist")
                  if (d / "main.dart.js").exists()]
    web = max(candidates, key=lambda d: (d / "main.dart.js").stat().st_mtime, default=None)
    app.state.dashboard_dir = str(web) if web else None
    if web is not None:
        logging.getLogger("heatguard").info("Serving dashboard from %s", web)
        app.mount("/", StaticFiles(directory=web, html=True), name="dashboard")
    return app


app = create_app()
