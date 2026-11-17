from fastapi.testclient import TestClient

import os

os.environ["HEATGUARD_STORAGE"] = "memory"
os.environ["HEATGUARD_SIM_AUTOSTART"] = "false"

from app.main import create_app  # noqa: E402


def test_api_smoke():
    with TestClient(create_app()) as c:
        assert c.get("/api/health").json()["backend_status"] == "ok"
        crews = c.get("/api/crews").json()
        assert len(crews) >= 4
        c.post("/api/simulation/step")
        assert c.get("/api/assessments/latest").json()
        r = c.put(f"/api/crews/{crews[0]['crew_id']}", json={"acclimatization": "not_acclimatized"})
        assert r.status_code == 200 and r.json()["assessment"]["inputs_used"]["acclimatization"] == "not_acclimatized"
        assert c.post("/api/simulation/override", json={"worksite_id": "ws_kumasi_tower", "natural_wet_bulb": 80}).status_code == 422
        assert c.put(f"/api/crews/{crews[0]['crew_id']}", json={"acclimatization": "x"}).status_code == 422
        # worker role cannot change crews
        assert c.put(f"/api/crews/{crews[0]['crew_id']}", json={"worker_count": 3},
                     headers={"X-HeatGuard-Role": "worker"}).status_code == 403
        csv = c.get("/api/reports/export?kind=readings")
        assert csv.status_code == 200 and "SIMULATED" in csv.text
        notice = c.get(f"/api/worker/{crews[0]['crew_id']}").json()
        assert notice["message"]
        ev = c.post("/api/evaluation/run").json()
        assert ev["summary"]["checks"] == ev["summary"]["checks_passed"]
