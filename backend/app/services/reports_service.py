"""Operational metrics and CSV exports. All figures derive from stored data (SIMULATED in this prototype)."""
from __future__ import annotations

import csv
import io
from collections import Counter
from datetime import datetime
from statistics import mean, median

from .heatguard_service import HeatGuardService

SEVERITIES = ["caution", "elevated", "high", "critical", "data_unavailable"]


def _secs(a: str | None, b: str | None) -> float | None:
    if not a or not b:
        return None
    return (datetime.fromisoformat(b) - datetime.fromisoformat(a)).total_seconds()


def _stats(values: list[float]) -> dict:
    if not values:
        return {"count": 0, "mean": None, "median": None, "max": None}
    return {"count": len(values), "mean": round(mean(values), 1), "median": round(median(values), 1), "max": round(max(values), 1)}


def summary(svc: HeatGuardService) -> dict:
    repo = svc.repo
    alerts = list(repo.alerts.values())
    ivs = list(repo.interventions.values())

    # ---- environmental trends per worksite
    env = {}
    for ws_id, ws in repo.worksites.items():
        rows = list(repo.readings.get(ws_id, []))
        vals = [r["wbgt"] for r in rows if r.get("wbgt") is not None]
        total = len(rows)
        complete = sum(1 for r in rows if r["validation"]["measurement_validity"] == "valid")
        field_issues = Counter(i["field"] for r in rows for i in r["validation"]["issues"])
        late = sum(1 for r in rows if r.get("late_sync"))
        # expected readings (one per simulated minute) within each simulation run
        expected = 0
        runs: dict[str, list[int]] = {}
        for r in rows:
            if r.get("sim_minute") is not None:
                runs.setdefault(r.get("run_id") or "-", []).append(r["sim_minute"])
        for mins in runs.values():
            expected += max(mins) - min(mins) + 1
        env[ws_id] = {
            "worksite_name": ws["name"],
            "readings": total,
            "wbgt": {"min": round(min(vals), 2) if vals else None, "mean": round(mean(vals), 2) if vals else None,
                     "max": round(max(vals), 2) if vals else None},
            "sensor_availability": round(complete / total, 3) if total else None,
            "delivery_ratio": round(total / expected, 3) if expected else None,
            "missing_data_frequency": round((total - complete) / total, 3) if total else None,
            "field_issue_counts": dict(field_issues),
            "late_synchronised_readings": late,
        }

    # ---- alerts
    by_sev = Counter(a["peak_severity"] for a in alerts)
    ack_times = [s for a in alerts if (s := _secs(a["timestamp"], a.get("acknowledged_at"))) is not None]
    res_times = [s for a in alerts if (s := _secs(a["timestamp"], a.get("resolved_at"))) is not None]
    unresolved = [a for a in alerts if a["resolution_status"] != "resolved"]

    # ---- interventions
    completed = [i for i in ivs if i["status"] == "completed"]
    outcomes = Counter((i.get("outcome") or "pending").split(":")[0] for i in completed)
    by_type = Counter(i["action_label"] for i in ivs)
    heat_alerts = [a for a in alerts if a["alert_type"] == "heat_risk"]
    with_iv = sum(1 for a in heat_alerts if a.get("intervention_ids"))

    # ---- assessments
    assessments = list(repo.assessments)
    valid = sum(1 for a in assessments if a["assessment_status"] == "valid")
    cat_counts = Counter(a["risk_category"] for a in assessments)

    # ---- connectivity
    events = list(repo.events)
    recoveries = [e["data"].get("recovery_seconds") for e in events if e["type"] == "data_flow_restored" and e["data"].get("recovery_seconds")]
    outages = [e["data"].get("outage_seconds") for e in events if e["type"] == "connectivity_restored"]

    return {
        "data_origin": "SIMULATED",
        "disclaimer": "All figures are computed from SIMULATED sensor data and demo operations. They are not field measurements "
                      "and do not demonstrate real-world prevention outcomes.",
        "environment": env,
        "alerts": {
            "total": len(alerts),
            "by_peak_severity": {s: by_sev.get(s, 0) for s in SEVERITIES},
            "by_type": dict(Counter(a["alert_type"] for a in alerts)),
            "unresolved": len(unresolved),
            "unacknowledged": sum(1 for a in unresolved if a["acknowledgement_status"] == "unacknowledged"),
            "escalated": sum(1 for a in alerts if a.get("escalation_level", 0) > 0),
            "acknowledgement_time_seconds": _stats(ack_times),
            "resolution_time_seconds": _stats(res_times),
            "duplicates_suppressed": sum(a.get("duplicate_count", 0) for a in alerts),
        },
        "interventions": {
            "total": len(ivs),
            "active": len(ivs) - len(completed),
            "completed": len(completed),
            "completion_rate": round(len(completed) / len(ivs), 3) if ivs else None,
            "by_type": dict(by_type),
            "outcomes": dict(outcomes),
            "heat_alerts_with_intervention": with_iv,
            "heat_alert_intervention_coverage": round(with_iv / len(heat_alerts), 3) if heat_alerts else None,
        },
        "assessments": {
            "stored": len(assessments),
            "completeness": round(valid / len(assessments), 3) if assessments else None,
            "by_category": dict(cat_counts),
        },
        "connectivity": {
            "data_flow_recoveries": len(recoveries),
            "recovery_time_seconds": _stats([float(x) for x in recoveries]),
            "edge_outages_synchronised": len(outages),
            "outage_seconds": _stats([float(x) for x in outages if x is not None]),
            "pending_database_writes": repo.pending_writes,
        },
        "evaluation": repo.evaluation,
    }


def to_csv(rows: list[dict], columns: list[str]) -> str:
    buf = io.StringIO()
    buf.write("# HeatGuard export - SIMULATED DATA - not real-world measurements\n")
    w = csv.DictWriter(buf, fieldnames=columns, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow({c: r.get(c) for c in columns})
    return buf.getvalue()


def export(svc: HeatGuardService, kind: str, worksite_id: str | None = None) -> tuple[str, str]:
    repo = svc.repo
    if kind == "readings":
        rows = []
        for ws_id, dq in repo.readings.items():
            if worksite_id in (None, ws_id):
                for r in dq:
                    rows.append({**r, "measurement_validity": r["validation"]["measurement_validity"],
                                 "manual_override": ";".join(r.get("manual_override") or [])})
        cols = ["data_origin", "reading_id", "worksite_id", "timestamp", "received_at", "sim_clock", "scenario_id", "dry_bulb",
                "natural_wet_bulb", "globe_temperature", "relative_humidity", "direct_solar", "wbgt", "wbgt_formula",
                "measurement_validity", "late_sync", "manual_override"]
        return to_csv(rows, cols), "heatguard_readings.csv"
    if kind == "assessments":
        rows = [{**a, "limit_type": (a.get("limit_details") or {}).get("limit_type"),
                 "limit": (a.get("limit_details") or {}).get("limit_at_current_regime"),
                 "required_regime": (a.get("limit_details") or {}).get("required_regime"),
                 "missing_inputs": ";".join(a["data_quality"]["missing_inputs"]),
                 "confidence": a["data_quality"]["assessment_confidence"]}
                for a in repo.assessments if worksite_id in (None, a["worksite_id"])]
        cols = ["data_origin", "assessment_id", "timestamp", "sim_clock", "worksite_id", "crew_name", "assessment_status", "risk_category",
                "wbgt", "effective_wbgt", "limit_type", "limit", "required_regime", "data_completeness", "confidence",
                "missing_inputs", "explanation"]
        return to_csv(rows, cols), "heatguard_assessments.csv"
    if kind == "alerts":
        rows = [{**a, "ack_seconds": _secs(a["timestamp"], a.get("acknowledged_at")),
                 "interventions": len(a.get("intervention_ids") or [])}
                for a in repo.alerts.values() if worksite_id in (None, a["worksite_id"])]
        cols = ["data_origin", "alert_id", "timestamp", "worksite_name", "crew_name", "alert_type", "severity", "peak_severity",
                "acknowledgement_status", "acknowledged_at", "ack_seconds", "resolution_status", "resolved_at", "escalation_level",
                "duplicate_count", "interventions", "explanation"]
        return to_csv(sorted(rows, key=lambda r: r["timestamp"]), cols), "heatguard_alerts.csv"
    if kind == "interventions":
        rows = [{**i, "baseline_category": (i.get("baseline_assessment") or {}).get("risk_category"),
                 "data_origin": "SIMULATED"} for i in repo.interventions.values() if worksite_id in (None, i["worksite_id"])]
        cols = ["data_origin", "intervention_id", "alert_id", "crew_name", "action_label", "status", "start_time", "end_time",
                "supervisor_id", "baseline_category", "outcome", "notes", "completion_notes"]
        return to_csv(sorted(rows, key=lambda r: r["start_time"]), cols), "heatguard_interventions.csv"
    if kind == "summary":
        s = summary(svc)
        rows = []

        def flat(prefix: str, obj) -> None:
            if isinstance(obj, dict):
                for k, v in obj.items():
                    flat(f"{prefix}.{k}" if prefix else k, v)
            elif not isinstance(obj, list):
                rows.append({"metric": prefix, "value": obj})

        flat("", {k: v for k, v in s.items() if k not in ("evaluation", "disclaimer")})
        return to_csv(rows, ["metric", "value"]), "heatguard_summary.csv"
    if kind == "evaluation":
        ev = repo.evaluation or {"cases": []}
        rows = []
        for c in ev.get("cases", []):
            for chk in c["checks"]:
                rows.append({"case": c["name"], "scenario": c["scenario_id"], "check": chk["description"],
                             "expected": chk["expected"], "observed": chk["observed"], "passed": chk["passed"]})
        return to_csv(rows, ["case", "scenario", "check", "expected", "observed", "passed"]), "heatguard_evaluation.csv"
    raise ValueError(f"Unknown export kind '{kind}'")
