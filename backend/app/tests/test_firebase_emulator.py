"""Integration test against the Firebase Realtime Database emulator.

Skipped unless FIREBASE_DATABASE_EMULATOR_HOST is set, e.g.:
  java -jar ~/.cache/firebase/emulators/firebase-database-emulator-*.jar --host 127.0.0.1 --port 9000
  FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 python -m pytest app/tests/test_firebase_emulator.py
(or: cd firebase && firebase emulators:start --only database --project demo-heatguard)
"""
import os
import uuid

import pytest

pytestmark = pytest.mark.skipif(not os.getenv("FIREBASE_DATABASE_EMULATOR_HOST"), reason="Firebase emulator not running")


def test_repository_roundtrip_and_reload():
    from app.repositories.firebase_repository import FirebaseBackend
    from app.repositories.repository import HeatGuardRepository

    host = os.environ["FIREBASE_DATABASE_EMULATOR_HOST"]
    ns = f"heatguard-test-{uuid.uuid4().hex[:8]}"
    backend = FirebaseBackend(None, f"http://{host}?ns={ns}")
    repo = HeatGuardRepository(backend)
    repo.save_worksite({"worksite_id": "ws1", "name": "Site", "zones": ["A"]})
    repo.save_alert({"alert_id": "alr1", "worksite_id": "ws1", "crew_id": "c1", "history": [{"event": "created"}]})
    repo.add_reading({"reading_id": "r1", "worksite_id": "ws1", "received_at": "2026-01-01T00:00:00+00:00",
                      "ground_truth": {"x": 1}})
    assert repo.flush()
    assert repo.pending_writes == 0

    fresh = HeatGuardRepository(backend)
    fresh.load()
    assert fresh.worksites["ws1"]["name"] == "Site"
    assert fresh.alerts["alr1"]["history"][0]["event"] == "created"
    reading = fresh.readings["ws1"][0]
    assert "ground_truth" not in reading  # evaluation-only data never persisted
