from app.core.config import Settings
from app.schemas.intervention import InterventionComplete, InterventionCreate
from app.services.heatguard_service import HeatGuardService, NullBackend


def service():
    s = HeatGuardService(Settings(storage_backend="memory", simulation_autostart=False, sustained_improvement_readings=3),
                         backend=NullBackend())
    s.initialise()
    return s


def heat_alerts(s, crew_id):
    return [a for a in s.repo.alerts.values() if a["crew_id"] == crew_id and a["alert_type"] == "heat_risk"]


def test_duplicate_suppression_and_no_auto_clear():
    s = service()
    st = s.sim.station("ws_kumasi_tower")
    st.set_scenario("construction_radiant")
    for _ in range(5):
        s.process_batch(s.sim.poll_all())
    alerts = heat_alerts(s, "crew_concrete_a")
    assert len(alerts) == 1
    assert alerts[0]["duplicate_count"] >= 3
    # conditions drop sharply: alert must not be resolved automatically
    st.set_scenario("normal")
    s.repo.readings["ws_kumasi_tower"].clear()
    for _ in range(6):
        s.process_batch(s.sim.poll_all())
    a = heat_alerts(s, "crew_concrete_a")[0]
    assert a["resolution_status"] == "conditions_improving"
    assert a["resolved_at"] is None


def test_resolve_requires_ack_and_improvement():
    s = service()
    s.sim.station("ws_kumasi_tower").set_scenario("construction_radiant")
    s.process_batch(s.sim.poll_all())
    alert = heat_alerts(s, "crew_concrete_a")[0]
    import pytest
    with pytest.raises(ValueError):
        s.alerts.resolve(alert["alert_id"], "sup", "done", False)
    s.alerts.acknowledge(alert["alert_id"], "sup", None)
    with pytest.raises(PermissionError):
        s.alerts.resolve(alert["alert_id"], "sup", "done", False)
    resolved = s.alerts.resolve(alert["alert_id"], "sup", "Work stopped, crew relocated", True)
    assert resolved["resolution_status"] == "resolved"


def test_sensor_failure_creates_site_data_alert_and_no_false_safe():
    s = service()
    st = s.sim.station("ws_kumasi_tower")
    st.manual_faults["all"] = "missing"
    s.process_batch(s.sim.poll_all())
    for c in s.repo.crews.values():
        if c["worksite_id"] == "ws_kumasi_tower":
            assert s.repo.latest_assessments[c["crew_id"]]["risk_category"] == "unavailable"
    data_alerts = [a for a in s.repo.alerts.values() if a["alert_type"] == "data_quality"]
    assert len(data_alerts) == 1 and data_alerts[0]["crew_id"] == "__site__"


def test_intervention_regime_change_reassesses():
    s = service()
    s.sim.station("ws_kumasi_tower").set_scenario("construction_radiant")
    s.process_batch(s.sim.poll_all())
    before = s.repo.latest_assessments["crew_concrete_a"]["risk_level"]
    alert = heat_alerts(s, "crew_concrete_a")[0]
    iv = s.interventions.create(InterventionCreate(alert_id=alert["alert_id"], crew_id="crew_concrete_a", action="work_rotation",
                                                   new_work_rest_regime="15_45", new_workload="moderate"))
    s.assess_crew(s.repo.crews["crew_concrete_a"])
    after = s.repo.latest_assessments["crew_concrete_a"]["risk_level"]
    assert after < before
    assert s.repo.alerts[alert["alert_id"]]["acknowledgement_status"] == "acknowledged"
    done = s.interventions.complete(iv["intervention_id"], InterventionComplete(notes="ok"))
    assert done["status"] == "completed" and done["outcome"].startswith("improved")


def test_network_outage_buffers_and_backfills():
    s = service()
    st = s.sim.station("ws_kumasi_tower")
    st.network_up = False
    for _ in range(4):
        s.process_batch(s.sim.poll_all())
    assert len(st.buffer) == 4
    st.network_up = True
    s.process_batch(s.sim.poll_all())
    late = [r for r in s.repo.readings["ws_kumasi_tower"] if r.get("late_sync")]
    assert len(late) == 4
