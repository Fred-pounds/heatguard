import pytest

from app.core.config import Settings  # noqa: F401  (adds simulator to sys.path)
from app.schemas.common import now_iso
from app.schemas.crew import Crew, Worksite
from app.services.guideline import load_guideline
from app.services.risk_engine import RiskEngine


@pytest.fixture
def engine():
    return RiskEngine(load_guideline("niosh_2016"))


@pytest.fixture
def outdoor_site():
    return Worksite(worksite_id="ws", name="Site", location="x", environment="outdoor", station_id="s", zones=["Z"], created_at=now_iso())


@pytest.fixture
def indoor_site():
    return Worksite(worksite_id="ws", name="Hall", location="x", environment="indoor", station_id="s", zones=["Z"], created_at=now_iso())


def make_crew(**kw):
    base = dict(crew_id="c1", name="Crew", worksite_id="ws", zone="Z", worker_count=5, workload="moderate",
                clothing="standard_work_clothing", acclimatization="acclimatized", created_at=now_iso(), updated_at=now_iso())
    base.update(kw)
    return Crew(**base)
