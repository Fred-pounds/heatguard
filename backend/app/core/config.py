"""Runtime configuration from environment variables (see .env.example)."""
from __future__ import annotations

import os
import sys
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, Field

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
    storage_backend: str = Field(default_factory=lambda: os.getenv("HEATGUARD_STORAGE", "local"))
    firebase_credentials: str | None = Field(default_factory=lambda: os.getenv("FIREBASE_CREDENTIALS"))  # path to service-account JSON
    firebase_database_url: str | None = Field(default_factory=lambda: os.getenv("FIREBASE_DATABASE_URL"))
    local_store_path: str = Field(default_factory=lambda: os.getenv("HEATGUARD_LOCAL_STORE", str(BACKEND_DIR / "data" / "local_store.json")))
    guideline_id: str = Field(default_factory=lambda: os.getenv("HEATGUARD_GUIDELINE", "niosh_2016"))
    # Country rules layered on top of the guideline (UAE summer midday break)
    uae_midday_break: bool = Field(default_factory=lambda: _bool("HEATGUARD_UAE_MIDDAY_BREAK", True))
    # Simulation
    simulation_autostart: bool = Field(default_factory=lambda: _bool("HEATGUARD_SIM_AUTOSTART", True))
    tick_seconds: float = Field(default_factory=lambda: float(os.getenv("HEATGUARD_TICK_SECONDS", "3")))
    simulation_seed: int | None = Field(default_factory=lambda: int(os.environ["HEATGUARD_SIM_SEED"]) if os.getenv("HEATGUARD_SIM_SEED") else None)
    seed_demo_data: bool = Field(default_factory=lambda: _bool("HEATGUARD_SEED_DEMO", True))
    # Data quality / alerting
    stale_after_seconds: float = Field(default_factory=lambda: float(os.getenv("HEATGUARD_STALE_SECONDS", "15")))
    escalate_after_seconds: float = Field(default_factory=lambda: float(os.getenv("HEATGUARD_ESCALATE_SECONDS", "120")))
    sustained_improvement_readings: int = Field(default_factory=lambda: int(os.getenv("HEATGUARD_SUSTAINED_READINGS", "10")))
    # Retention (configurable data-retention policy)
    retention_readings_per_site: int = Field(default_factory=lambda: int(os.getenv("HEATGUARD_RETAIN_READINGS", "2000")))
    retention_assessments: int = Field(default_factory=lambda: int(os.getenv("HEATGUARD_RETAIN_ASSESSMENTS", "5000")))
    retention_days: int = Field(default_factory=lambda: int(os.getenv("HEATGUARD_RETENTION_DAYS", "90")))
    # Security
    ingest_api_key: str | None = Field(default_factory=lambda: os.getenv("HEATGUARD_INGEST_KEY"))  # required for external sensor ingest if set
    cors_origins: list[str] = Field(default_factory=lambda: [o.strip() for o in os.getenv("HEATGUARD_CORS", "*").split(",")])


@lru_cache
def get_settings() -> Settings:
    return Settings()
