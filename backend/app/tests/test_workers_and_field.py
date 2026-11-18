import os

from fastapi.testclient import TestClient

os.environ["HEATGUARD_STORAGE"] = "memory"
os.environ["HEATGUARD_SIM_AUTOSTART"] = "false"

from app.core.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402
from app.schemas.worker import ConsentRequest, SignalIn  # noqa: E402
from app.services.heatguard_service import HeatGuardService, NullBackend  # noqa: E402
from app.services.worker_service import demo_pairing_code  # noqa: E402

SUP = {"X-HeatGuard-Role": "supervisor"}
OHS = {"X-HeatGuard-Role": "ohs"}


def service():
    s = HeatGuardService(Settings(storage_backend="memory", simulation_autostart=False), backend=NullBackend())
    s.initialise()
    return s


def tick(s, n=1):
    for _ in range(n):
        s.process_batch(s.sim.poll_all(), from_sim=True)


def test_signals_require_consent_and_withdrawal_deletes_them():
    s = service()
    tick(s, 3)
    assert s.workers.signals.get("wk_ca01")
    # the declined worker never produces or keeps signals
    assert not s.workers.signals.get("wk_ca05")
    assert s.workers.ingest_signal(SignalIn(worker_id="wk_ca05", device_id="dev-ca05", heart_rate=120)) is None
    s.workers.set_consent("wk_ca01", ConsentRequest(granted=False))
    assert "wk_ca01" not in s.workers.signals
    assert s.repo.workers["wk_ca01"]["age_band"] is None


def test_strain_raises_worker_check_with_badge_but_no_values_for_supervisor():
    s = service()
    tick(s, 2)
    s.sim.wearable(s.repo.workers["wk_ca02"]).strain = 1.0
    tick(s, 5)
    summary = s.repo.latest_assessments["crew_concrete_a"]["worker_signals"]
    assert summary["check_badges"] == ["CA-02"]
    assert "heart_rate" not in str(summary)
    alert = s.alerts.open_alert("ws_saadiyat_tower", "crew_concrete_a", "worker_check")
    assert alert and "CA-02" in alert["explanation"] and "bpm" not in alert["explanation"]


def test_heavy_dust_makes_assessment_unavailable_and_requests_maintenance():
    s = service()
    st = s.sim.station("ws_saadiyat_tower")
    st.dust_boost = 0.1
    tick(s, 7)
    assert s.repo.latest_assessments["crew_concrete_a"]["risk_category"] == "unavailable"
    assert s.alerts.open_alert("ws_saadiyat_tower", "__site__", "maintenance")


def test_low_battery_warns_then_station_goes_silent():
    s = service()
    st = s.sim.station("ws_saadiyat_tower")
    st.battery_fault = True
    tick(s, 25)  # about 17% left: warned while still reporting
    m = s.alerts.open_alert("ws_saadiyat_tower", "__site__", "maintenance")
    assert m and "battery" in m["explanation"]
    tick(s, 15)
    assert s.sim.sources["ws_saadiyat_tower"].poll() == []  # dead station transmits nothing


def test_escalation_access_rules_via_api():
    with TestClient(create_app()) as c:
        r = c.post("/api/symptoms", json={"crew_id": "crew_rebar_b", "symptoms": ["confusion"], "reported_by": "coworker"})
        assert r.status_code == 201
        esc_id = r.json()["escalation_id"]
        sup = c.get("/api/escalations", headers=SUP).json()[0]
        assert sup["level"] == "emergency" and "symptoms" not in sup
        assert "symptoms" in c.get("/api/escalations", headers=OHS).json()[0]
        assert c.get("/api/workers", headers=SUP).status_code == 403
        assert c.get("/api/workers", headers=OHS).status_code == 200
        # supervisor may acknowledge but not record the clinical outcome
        assert c.post(f"/api/escalations/{esc_id}", json={"action": "acknowledge"}, headers=SUP).status_code == 200
        assert c.post(f"/api/escalations/{esc_id}", json={"action": "close", "outcome": "ambulance_called"}, headers=SUP).status_code == 403
        assert c.post(f"/api/escalations/{esc_id}", json={"action": "close", "outcome": "ambulance_called"}, headers=OHS).status_code == 200
        alerts = [a for a in c.get("/api/alerts").json() if a.get("escalation_id") == esc_id]
        assert alerts and alerts[0]["resolution_status"] == "resolved"
        # consent needs an age band for the heart-rate threshold (from the paired phone)
        dev = {"X-HeatGuard-Device": c.post("/api/worker/pair", json={"worker_id": "wk_ca05", "code": demo_pairing_code("wk_ca05")}).json()["device_token"]}
        assert c.post("/api/worker/me/wk_ca05/consent", json={"granted": True}, headers=dev).status_code == 422
        assert c.post("/api/worker/me/wk_ca05/consent", json={"granted": True, "age_band": "30-39"}, headers=dev).status_code == 200
        safety = c.get("/api/reports/summary").json()["safety"]
        assert safety["escalations"]["emergency_calls"] == 1


def test_rising_trend_gives_early_caution():
    s = service()
    st = s.sim.station("ws_saadiyat_tower")
    st.set_scenario("increasing_heat")
    st.sim_minute = 60
    tick(s, 40)
    a = s.repo.latest_assessments["crew_logistics"]
    assert a["outlook"]["trend_c_per_hour"] > 0


def test_badge_data_only_for_the_paired_phone():
    W = {"X-HeatGuard-Role": "worker"}
    with TestClient(create_app()) as c:
        # without pairing, nobody can read a badge's signals or change its consent
        assert c.get("/api/worker/me/wk_ca03", headers=W).status_code == 401
        assert c.post("/api/worker/me/wk_ca03/consent", json={"granted": False}, headers=W).status_code == 401
        assert c.get("/api/worker/me/wk_ca03", headers={**W, "X-HeatGuard-Device": "guess"}).status_code == 401
        # the worker app's badge list does not reveal who is sharing
        assert all("sharing" not in b for b in c.get("/api/worker/badges/crew_concrete_a", headers=W).json())
        assert all("sharing" in b for b in c.get("/api/worker/badges/crew_concrete_a", headers=SUP).json())
        # wrong codes are limited
        for _ in range(5):
            assert c.post("/api/worker/pair", json={"worker_id": "wk_ca03", "code": "000000x"}).status_code == 403
        assert c.post("/api/worker/pair", json={"worker_id": "wk_ca03", "code": demo_pairing_code("wk_ca03")}).status_code == 429
        # correct code pairs; the token hash and code are never exposed to the phone
        r = c.post("/api/worker/pair", json={"worker_id": "wk_ca04", "code": demo_pairing_code("wk_ca04")})
        assert r.status_code == 200 and "pairing_code" not in r.json()
        dev = {**W, "X-HeatGuard-Device": r.json()["device_token"]}
        me = c.get("/api/worker/me/wk_ca04", headers=dev)
        assert me.status_code == 200 and me.json()["badge"] == "CA-04"
        assert c.get("/api/worker/me/wk_ca01", headers=dev).status_code == 401  # token works for its own badge only
        # a symptom report naming a badge must come from its paired phone
        rep = {"crew_id": "crew_concrete_a", "worker_id": "wk_ca04", "symptoms": ["dizziness"], "reported_by": "self"}
        assert c.post("/api/symptoms", json=rep, headers=W).status_code == 401
        assert c.post("/api/symptoms", json=rep, headers=dev).status_code == 201
        # OHS sees codes (not token hashes); a new code unpairs the old phone
        rows = {w["worker_id"]: w for w in c.get("/api/workers", headers=OHS).json()}
        assert rows["wk_ca04"]["paired"] and "device_token_hash" not in rows["wk_ca04"] and rows["wk_ca04"]["pairing_code"]
        assert c.post("/api/workers/wk_ca04/pairing-code", headers=SUP).status_code == 403
        assert c.post("/api/workers/wk_ca04/pairing-code", headers=OHS).status_code == 200
        assert c.get("/api/worker/me/wk_ca04", headers=dev).status_code == 401


def test_shift_planner_gives_crew_level_timing_advice():
    with TestClient(create_app()) as c:
        c.post("/api/simulation/scenario", json={"worksite_id": "ws_saadiyat_tower", "scenario_id": "increasing_heat"})
        assert c.get("/api/planner/ws_saadiyat_tower", headers={"X-HeatGuard-Role": "worker"}).status_code == 403
        d = c.get("/api/planner/ws_saadiyat_tower", headers=SUP).json()
        assert d["forecast_source"] == "simulated" and d["slots"][0] == "07:00" and len(d["slots"]) == 13
        crews = {cr["crew_name"]: cr for cr in d["crews"]}
        light = crews["Site Logistics"]
        cats = [x["category"] for x in light["cells"]]
        assert cats[0] == "routine" and cats[-1] == "critical"  # rising heat across the morning
        texts = " ".join(a["text"] for a in light["advice"])
        assert "before 10:00" in texts and "should stop" in texts and "midday break" in texts
        assert any(x["midday_break"] for x in light["cells"]) and not light["cells"][0]["midday_break"]
        # crew-level only: no worker identifiers in the plan
        assert "badge" not in str(d) and "worker_id" not in str(d)
