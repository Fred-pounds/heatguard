"""Scenario-based evaluation of the HeatGuard pipeline (SYNTHETIC data only).

Each case runs a scenario headless through the *same* ingestion -> assessment
-> alert pipeline used live, with a virtual clock (3 s per simulated minute)
and an isolated in-memory repository. The simulator's noise-free ground truth
is assessed separately with the same rule set to obtain the *reference
outcome*; system outputs (from noisy, possibly faulty or delayed data) are
compared with it.

What this measures: whether the software behaves as specified by the
configured rules under noise, faults and outages. It does NOT measure clinical
or real-world predictive accuracy, and makes no claim about injury prevention.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from statistics import mean

from heatguard_sim import SCENARIOS

from ..core.config import Settings
from ..schemas.common import now_iso
from ..schemas.crew import Crew, Worksite
from ..schemas.sensor import SensorReading, SensorReadingIn
from .data_validation import validate_reading
from .heatguard_service import HeatGuardService, NullBackend
from .risk_engine import AssessmentContext
from .wbgt_calculator import compute_wbgt

LEVEL = {"routine": 0, "caution": 1, "elevated": 2, "high": 3, "critical": 4, "unavailable": -1}
NAMES = {v: k for k, v in LEVEL.items()}
SECONDS_PER_MIN = 3.0
FALSE_ALARM_HORIZON_MIN = 30  # an alert is "confirmed" if the reference reaches its severity within this horizon


@dataclass
class Case:
    id: str
    name: str
    scenario_id: str
    crew: dict
    purpose: str
    expect: dict
    network_outage: tuple[int, int] | None = None
    seed: int = 42
    minutes: int | None = None


CASES = [
    Case("normal_light", "Normal conditions - light work, acclimatized", "normal",
         {"workload": "light", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "No unnecessary alarms in moderate conditions.",
         {"max_category": "caution", "max_false_alarm_rate": 0.0}),
    Case("increasing_moderate", "Increasing heat - moderate work, acclimatized", "increasing_heat",
         {"workload": "moderate", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "Worsening conditions recognised before the limit is exceeded.",
         {"min_peak": "high", "min_lead_minutes": 1, "max_missed_rate": 0.05}),
    Case("heavy_construction", "Heavy workload - high-radiant construction site", "construction_radiant",
         {"workload": "heavy", "clothing": "long_sleeved_protective", "acclimatization": "acclimatized"},
         "Heavy work in radiant heat is classified at a high level immediately.",
         {"min_peak": "high", "max_missed_rate": 0.05}),
    Case("increasing_unacclimatized", "Increasing heat - unacclimatized crew", "increasing_heat",
         {"workload": "moderate", "clothing": "standard_work_clothing", "acclimatization": "not_acclimatized"},
         "Lower RAL applies, so alerts are raised earlier than for an acclimatized crew.",
         {"min_peak": "critical", "earlier_than": "increasing_moderate", "max_missed_rate": 0.05}),
    Case("missing_context", "Missing data - unknown workload", "normal",
         {"workload": "unknown", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "Missing work context yields incomplete assessments, never 'routine'.",
         {"all_incomplete": True}, minutes=60),
    Case("sensor_failure", "Sensor failure - scheduled probe faults", "sensor_failure",
         {"workload": "moderate", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "Faulty or missing measurements are detected and never classified as safe.",
         {"no_false_safe": True, "fault_minutes_unavailable": True, "data_alert": True}),
    Case("network_failure", "Network failure - 20 min uplink outage during rising heat", "increasing_heat",
         {"workload": "moderate", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "Outage detected as stale data (not safe); queued readings synchronised on recovery.",
         {"no_false_safe": True, "detect_stale": True, "backfill": 20}, network_outage=(60, 80)),
    Case("humid_coastal", "Humid coastal morning - moderate work", "humid_coastal",
         {"workload": "moderate", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "High humidity is recognised as high heat stress even though air temperature is only 33-37 degC.",
         {"min_peak": "high", "max_missed_rate": 0.05}),
    Case("uae_midday_break", "UAE midday break - outdoor work at 12:30", "increasing_heat",
         {"workload": "light", "clothing": "standard_work_clothing", "acclimatization": "acclimatized"},
         "The legal midday-break restriction is flagged from 12:30 in summer, and not before.",
         {"midday_break_from": "12:30"}),
    Case("indoor_heavy", "Industrial indoor - heavy work in coveralls", "industrial_indoor",
         {"workload": "heavy", "clothing": "cloth_coveralls", "acclimatization": "acclimatized"},
         "Indoor WBGT formula used; heavy work classified above routine.",
         {"min_peak": "elevated", "indoor_formula": True}, minutes=120),
]


@dataclass
class Trace:
    minute: list[int] = field(default_factory=list)
    truth: list[int] = field(default_factory=list)
    system: list[int] = field(default_factory=list)
    heat_alert_open: list[bool] = field(default_factory=list)
    data_alert_open: list[bool] = field(default_factory=list)
    fault: list[bool] = field(default_factory=list)
    link_down: list[bool] = field(default_factory=list)
    regulatory: list[bool] = field(default_factory=list)
    clock: list[str] = field(default_factory=list)
    formula: str | None = None


def _check(desc: str, expected, observed, passed: bool) -> dict:
    return {"description": desc, "expected": str(expected), "observed": str(observed), "passed": bool(passed)}


def run_case(case: Case, base: Settings) -> dict:
    vt = [datetime(2026, 1, 1, tzinfo=timezone.utc)]
    settings = base.model_copy(update={"storage_backend": "memory", "seed_demo_data": False, "simulation_autostart": False})
    svc = HeatGuardService(settings, backend=NullBackend(), clock=lambda: vt[0])
    sc = SCENARIOS[case.scenario_id]
    env = "indoor" if sc.indoor else "outdoor"
    ts = now_iso()
    svc.repo.save_worksite(Worksite(worksite_id="eval_site", name="Evaluation site", location="synthetic", environment=env,
                                    station_id="vstation-eval_site", zones=["Zone 1"], created_at=ts).model_dump())
    crew = Crew(crew_id="eval_crew", name="Evaluation crew", worksite_id="eval_site", zone="Zone 1", worker_count=5,
                created_at=ts, updated_at=ts, **case.crew).model_dump()
    svc.repo.save_crew(crew)
    src = svc.sim.add_station("eval_site", case.scenario_id)
    src.station.seed = case.seed
    src.station.reset()
    station = src.station
    ws = Worksite(**svc.repo.worksites["eval_site"])
    crew_model = Crew(**crew)

    minutes = case.minutes or sc.duration_min
    tr = Trace()
    truth_window: deque = deque(maxlen=60)
    alerts_created: list[tuple[int, int]] = []  # (trace index, severity level at creation)
    known_alerts: set[str] = set()
    backfilled = 0

    for _ in range(minutes):
        m = station.sim_minute
        vt[0] = vt[0] + timedelta(seconds=SECONDS_PER_MIN)
        down = case.network_outage is not None and case.network_outage[0] <= m < case.network_outage[1]
        station.network_up = not down
        # ---- reference outcome from noise-free ground truth
        st = station.true_state(m)
        truth_in = SensorReadingIn(station_id="truth", worksite_id="eval_site", dry_bulb=st.tdb, natural_wet_bulb=st.tnwb,
                                   globe_temperature=st.tg, relative_humidity=st.rh, direct_solar=st.direct_solar)
        val = validate_reading(truth_in)
        wb = compute_wbgt(st.tnwb, st.tg, st.tdb, env, st.direct_solar)
        truth_window.append(wb.value)
        truth_reading = SensorReading(**truth_in.model_dump(exclude={"reading_id", "timestamp"}), reading_id="truth",
                                      timestamp=vt[0].isoformat(), received_at=vt[0].isoformat(), wbgt=wb.value,
                                      wbgt_formula=wb.formula, validation=val)
        t_assess = svc.engine.assess(AssessmentContext(
            worksite=ws, crew=crew_model, reading=truth_reading, reading_age_seconds=0.0,
            stale_after_seconds=settings.stale_after_seconds,
            rolling_mean_wbgt=mean(truth_window) if len(truth_window) >= 2 else None))
        # ---- system pipeline on noisy / faulty / delayed data
        batch = svc.sim.poll_all()
        backfilled += sum(1 for r in batch if r.late_sync)
        svc.process_batch(batch)
        svc.check_staleness()
        a = svc.repo.latest_assessments.get("eval_crew")
        sys_level = LEVEL[a["risk_category"]] if a else -1
        latest = svc.latest_reading("eval_site")
        fault = (latest is None or latest["validation"]["measurement_validity"] != "valid"
                 or (svc.reading_age(latest) or 0) > settings.stale_after_seconds)
        heat_open = svc.alerts.open_alert("eval_site", "eval_crew", "heat_risk")
        data_open = (svc.alerts.open_alert("eval_site", "__site__", "data_quality")
                     or svc.alerts.open_alert("eval_site", "eval_crew", "data_quality"))
        for al in svc.repo.alerts.values():
            if al["alert_type"] == "heat_risk" and al["alert_id"] not in known_alerts:
                known_alerts.add(al["alert_id"])
                alerts_created.append((len(tr.minute), al["severity_level"]))
        if latest and latest.get("wbgt_formula"):
            tr.formula = latest["wbgt_formula"]
        tr.minute.append(m)
        tr.truth.append(LEVEL[t_assess.risk_category])
        tr.system.append(sys_level)
        tr.heat_alert_open.append(heat_open is not None)
        tr.data_alert_open.append(data_open is not None)
        tr.fault.append(fault)
        tr.link_down.append(down)
        tr.regulatory.append(bool(a and a.get("regulatory_flags")))
        tr.clock.append(station.sim_clock(m))

    n = len(tr.minute)
    exceed = [i for i in range(n) if tr.truth[i] >= 2]
    first_exceed = exceed[0] if exceed else None
    first_alert = next((i for i in range(n) if tr.heat_alert_open[i]), None)
    lead = (first_exceed - first_alert) if first_exceed is not None and first_alert is not None else None
    missed = sum(1 for i in exceed if not tr.heat_alert_open[i] and not tr.data_alert_open[i])
    missed_rate = missed / len(exceed) if exceed else 0.0
    false_alarms = sum(1 for i, lvl in alerts_created if max(tr.truth[i:i + FALSE_ALARM_HORIZON_MIN] or [-1]) < lvl)
    false_alarm_rate = false_alarms / len(alerts_created) if alerts_created else 0.0
    false_safe = sum(1 for i in range(n) if tr.fault[i] and tr.system[i] == 0)
    valid_minutes = sum(1 for s in tr.system if s >= 0)
    sensor_ok = sum(1 for f in tr.fault if not f)
    peak_sys = max(tr.system) if tr.system else -1
    peak_truth = max(tr.truth) if tr.truth else -1

    # stale detection / recovery around outage
    detect_s = recover_s = None
    if case.network_outage:
        s0, s1 = case.network_outage
        idx = [i for i in range(n) if tr.minute[i] >= s0]
        d = next((i for i in idx if tr.system[i] == -1), None)
        if d is not None:
            detect_s = (tr.minute[d] - s0 + 1) * SECONDS_PER_MIN
        r = next((i for i in range(n) if tr.minute[i] >= s1 and tr.system[i] >= 0), None)
        if r is not None:
            recover_s = (tr.minute[r] - s1 + 1) * SECONDS_PER_MIN

    metrics = {
        "minutes_simulated": n,
        "reference_peak_category": NAMES.get(peak_truth),
        "system_peak_category": NAMES.get(peak_sys),
        "first_reference_limit_exceedance_min": first_exceed,
        "first_alert_min": first_alert,
        "alert_lead_time_min": lead,
        "alerts_raised": len(alerts_created),
        "false_alarm_rate": round(false_alarm_rate, 3),
        "missed_alert_rate": round(missed_rate, 3),
        "false_safe_minutes": false_safe,
        "assessment_completeness": round(valid_minutes / n, 3) if n else None,
        "sensor_data_availability": round(sensor_ok / n, 3) if n else None,
        "stale_detection_seconds": detect_s,
        "connectivity_recovery_seconds": recover_s,
        "backfilled_readings": backfilled,
        "wbgt_formula": tr.formula,
        "unresolved_alerts": sum(1 for a in svc.repo.alerts.values() if a["resolution_status"] != "resolved"),
    }

    e = case.expect
    checks = []
    if "max_category" in e:
        checks.append(_check("System peak category does not exceed", e["max_category"], metrics["system_peak_category"],
                             peak_sys <= LEVEL[e["max_category"]]))
    if "max_false_alarm_rate" in e:
        checks.append(_check("False-alarm rate <=", e["max_false_alarm_rate"], metrics["false_alarm_rate"],
                             false_alarm_rate <= e["max_false_alarm_rate"]))
    if "min_peak" in e:
        checks.append(_check("System peak category reaches at least", e["min_peak"], metrics["system_peak_category"],
                             peak_sys >= LEVEL[e["min_peak"]]))
    if "min_lead_minutes" in e:
        checks.append(_check("Alert raised before reference limit exceedance (min lead, simulated minutes)",
                             f">= {e['min_lead_minutes']}", lead, lead is not None and lead >= e["min_lead_minutes"]))
    if "max_missed_rate" in e:
        checks.append(_check("Missed-alert rate <=", e["max_missed_rate"], metrics["missed_alert_rate"], missed_rate <= e["max_missed_rate"]))
    if e.get("all_incomplete"):
        checks.append(_check("All assessments incomplete (never routine)", "0 valid assessments",
                             f"{valid_minutes} valid", valid_minutes == 0))
    if e.get("no_false_safe") or e.get("all_incomplete") or e.get("fault_minutes_unavailable"):
        checks.append(_check("No 'routine' classification while data are missing, invalid or stale", 0, false_safe, false_safe == 0))
    if e.get("fault_minutes_unavailable"):
        bad = sum(1 for i in range(n) if tr.fault[i] and tr.system[i] != -1)
        checks.append(_check("Every faulty-data minute yields an unavailable/incomplete assessment", 0, bad, bad == 0))
        resumed = any(tr.system[i] >= 0 for i in range(n) if tr.minute[i] >= 85)
        checks.append(_check("Valid assessments resume after faults clear", True, resumed, resumed))
    if e.get("data_alert"):
        raised = any(tr.data_alert_open)
        checks.append(_check("Data-quality alert raised", True, raised, raised))
    if e.get("detect_stale"):
        limit = settings.stale_after_seconds + 2 * SECONDS_PER_MIN
        checks.append(_check("Outage detected as stale data within (s)", f"<= {limit:.0f}", detect_s, detect_s is not None and detect_s <= limit))
        checks.append(_check("Valid assessment restored after uplink recovery (s)", f"<= {2 * SECONDS_PER_MIN:.0f}", recover_s,
                             recover_s is not None and recover_s <= 2 * SECONDS_PER_MIN))
    if "backfill" in e:
        checks.append(_check("Queued readings synchronised after outage", e["backfill"], backfilled, backfilled == e["backfill"]))
    if e.get("midday_break_from"):
        first = next((tr.clock[i] for i in range(n) if tr.regulatory[i]), None)
        before = sum(1 for i in range(n) if tr.regulatory[i] and tr.clock[i] < e["midday_break_from"])
        checks.append(_check("Midday break first flagged at (site time)", e["midday_break_from"], first, first == e["midday_break_from"]))
        checks.append(_check("No midday-break flag before the window", 0, before, before == 0))
        reg_alert = any(al["alert_type"] == "regulatory" for al in svc.repo.alerts.values())
        checks.append(_check("Midday-break alert raised", True, reg_alert, reg_alert))
    if e.get("indoor_formula"):
        ok = bool(tr.formula and "0.3*Tg" in tr.formula)
        checks.append(_check("Indoor WBGT formula applied", "0.7*Tnwb + 0.3*Tg", tr.formula, ok))

    series = [{"minute": tr.minute[i], "reference": tr.truth[i], "system": tr.system[i]} for i in range(0, n, max(1, n // 120))]
    return {"id": case.id, "name": case.name, "scenario_id": case.scenario_id, "scenario_name": sc.name, "crew": case.crew,
            "purpose": case.purpose, "metrics": metrics, "checks": checks, "passed": all(c["passed"] for c in checks),
            "series": series}


def run_all(settings: Settings) -> dict:
    results = [run_case(c, settings) for c in CASES]
    by_id = {r["id"]: r for r in results}
    for case, res in zip(CASES, results):
        other = case.expect.get("earlier_than")
        if other:
            mine, theirs = res["metrics"]["first_alert_min"], by_id[other]["metrics"]["first_alert_min"]
            ok = mine is not None and theirs is not None and mine < theirs
            res["checks"].append(_check(f"First alert earlier than '{by_id[other]['name']}' (minute)", f"< {theirs}", mine, ok))
            res["passed"] = all(c["passed"] for c in res["checks"])
    total = sum(len(r["checks"]) for r in results)
    passed = sum(1 for r in results for c in r["checks"] if c["passed"])
    leads = [r["metrics"]["alert_lead_time_min"] for r in results if r["metrics"]["alert_lead_time_min"] is not None]
    agg = {
        "cases": len(results),
        "cases_passed": sum(1 for r in results if r["passed"]),
        "checks": total,
        "checks_passed": passed,
        "mean_alert_lead_time_min": round(mean(leads), 1) if leads else None,
        "mean_false_alarm_rate": round(mean(r["metrics"]["false_alarm_rate"] for r in results), 3),
        "mean_missed_alert_rate": round(mean(r["metrics"]["missed_alert_rate"] for r in results), 3),
        "total_false_safe_minutes": sum(r["metrics"]["false_safe_minutes"] for r in results),
    }
    return {
        "generated_at": now_iso(),
        "data_origin": "SIMULATED",
        "method": "Each case is run through the live ingestion/assessment/alert pipeline on noisy synthetic readings and compared with the "
                  "same rules applied to the simulator's noise-free ground truth. 1 simulated minute = 3 s virtual time. "
                  f"False alarm: an alert whose severity the reference does not reach within {FALSE_ALARM_HORIZON_MIN} simulated minutes. "
                  "Missed alert: a minute in which the reference exceeds the applicable limit but no heat or data alert is open. "
                  "Lead time: minutes between the first alert and the first reference limit exceedance.",
        "disclaimer": "Synthetic software verification only. These results are not clinical validation, not predictive accuracy for "
                      "heat illness, and not evidence of real-world prevention. Field validation with calibrated instruments is required.",
        "summary": agg,
        "cases": results,
    }
