"""Runtime configuration from environment variables (see .env.example)."""
from __future__ import annotations

import os
import sys
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel

BACKEND_DIR = Path(__file__).resolve().parents[2]
REPO_DIR = BACKEND_DIR.parent

# Make the simulator package importable without installation.
_sim_path = str(REPO_DIR / "simulator")
if _sim_path not in sys.path:
    sys.path.insert(0, _sim_path)

try:  # optional .env support
    from dotenv import load_dotenv

    load_dotenv(BACKEND_DIR / ".env")
except ImportError:  # pragma: no cover
    pass


def _bool(name: str, default: bool) -> bool:
    v = os.getenv(name)
    return default if v is None else v.strip().lower() in {"1", "true", "yes", "on"}


class Settings(BaseModel):
    app_name: str = "HeatGuard"
    # Persistence: "firebase" requires credentials, "local" uses a JSON file store (demo mode)
    storage_backend: str = os.getenv("HEATGUARD_STORAGE", "local")
    firebase_credentials: str | None = os.getenv("FIREBASE_CREDENTIALS")  # path to service-account JSON
    firebase_database_url: str | None = os.getenv("FIREBASE_DATABASE_URL")
    local_store_path: str = os.getenv("HEATGUARD_LOCAL_STORE", str(BACKEND_DIR / "data" / "local_store.json"))
    guideline_id: str = os.getenv("HEATGUARD_GUIDELINE", "niosh_2016")
    # Simulation
    simulation_autostart: bool = _bool("HEATGUARD_SIM_AUTOSTART", True)
    tick_seconds: float = float(os.getenv("HEATGUARD_TICK_SECONDS", "3"))
    simulation_seed: int | None = int(os.environ["HEATGUARD_SIM_SEED"]) if os.getenv("HEATGUARD_SIM_SEED") else None
    seed_demo_data: bool = _bool("HEATGUARD_SEED_DEMO", True)
    # Data quality / alerting
    stale_after_seconds: float = float(os.getenv("HEATGUARD_STALE_SECONDS", "15"))
    escalate_after_seconds: float = float(os.getenv("HEATGUARD_ESCALATE_SECONDS", "120"))
    sustained_improvement_readings: int = int(os.getenv("HEATGUARD_SUSTAINED_READINGS", "10"))
    # Retention (configurable data-retention policy)
    retention_readings_per_site: int = int(os.getenv("HEATGUARD_RETAIN_READINGS", "2000"))
    retention_assessments: int = int(os.getenv("HEATGUARD_RETAIN_ASSESSMENTS", "5000"))
    retention_days: int = int(os.getenv("HEATGUARD_RETENTION_DAYS", "90"))
    # Security
    ingest_api_key: str | None = os.getenv("HEATGUARD_INGEST_KEY")  # required for external sensor ingest if set
    cors_origins: list[str] = [o.strip() for o in os.getenv("HEATGUARD_CORS", "*").split(",")]


@lru_cache
def get_settings() -> Settings:
    return Settings()
