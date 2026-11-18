"""HeatGuard FastAPI application entry point.

Run:  uvicorn app.main:app --reload --port 8000   (from the backend/ directory)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .api.routes import alerts, assessments, crews, interventions, planner, reports, sensors, simulation, system, workers
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


def _newest_build(project):
    candidates = [d for d in (project / "build" / "web", project / "dist") if (d / "main.dart.js").exists()]
    return max(candidates, key=lambda d: (d / "main.dart.js").stat().st_mtime, default=None)


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
    for module in (system, crews, sensors, assessments, alerts, interventions, planner, simulation, reports, workers):
        app.include_router(module.router, prefix="/api")
    # Single-port demo. Two separate Flutter apps are served from the same server:
    #   /worker/  the worker app that workers carry (worker_app/), also buildable for Android and iOS
    #   /         the supervisor / OHS dashboard (frontend/)
    # For each, serve whichever build is newest: a local build (build/web) or the prebuilt copy committed in
    # dist/. A stale local build must never hide an updated dist after `git pull`.
    worker = _newest_build(REPO_DIR / "worker_app")
    app.state.worker_app_dir = str(worker) if worker else None
    if worker is not None:
        @app.get("/worker", include_in_schema=False)
        async def worker_slash():
            return RedirectResponse("/worker/")

        app.mount("/worker", StaticFiles(directory=worker, html=True), name="worker_app")
    web = _newest_build(REPO_DIR / "frontend")
    app.state.dashboard_dir = str(web) if web else None
    if web is not None:
        logging.getLogger("heatguard").info("Serving dashboard from %s and worker app from %s", web, worker)
        app.mount("/", StaticFiles(directory=web, html=True), name="dashboard")
    return app


app = create_app()
