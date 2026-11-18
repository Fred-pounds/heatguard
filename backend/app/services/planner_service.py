"""Shift planner: when heavy work fits, when rotation must start, and when strenuous work must stop.

For each crew the next hours are assessed in steps with the same rules as the live assessment (NIOSH limits for
the crew's workload, clothing and acclimatization, plus the UAE midday break). The planning baseline is normal
continuous work; each step reports the work/rest schedule that keeps exposure within the limit.

Conditions ahead come from a forecast. In this prototype the forecast is the simulated scenario profile for the
site (labelled as such). In a pilot it would be an hourly weather forecast for the site converted to WBGT.
A forecast is a planning aid only: live measurements and alerts always take precedence.
"""
from __future__ import annotations

from ..schemas.crew import Crew
from ..schemas.sensor import SensorReading, SensorReadingIn
from ..schemas.common import now_iso
from .data_validation import validate_reading
from .risk_engine import AssessmentContext
from .wbgt_calculator import compute_wbgt

LIGHT_ENOUGH = ("routine", "caution")
FORECAST_NOTE = ("Planning forecast from the simulated scenario for this site (SIMULATED). In a pilot this uses the site's "
                 "hourly weather forecast converted to WBGT. Live measurements and alerts always take precedence.")


def _minutes(clock: str) -> int:
    h, m = (int(x) for x in clock.split(":"))
    return h * 60 + m


def _in_shift(clock: str, start: str, hours: float) -> bool:
    t, s = _minutes(clock), _minutes(start)
    return (t - s) % 1440 < hours * 60


class PlannerService:
    def __init__(self, svc):
        self.svc = svc

    def plan(self, worksite_id: str, hours: int = 6, step: int = 30) -> dict:
        svc = self.svc
        ws = svc.worksite(worksite_id)
        try:
            station = svc.sim.station(worksite_id)
        except Exception:
            station = None
        crews = [c for c in svc.repo.crews.values() if c["worksite_id"] == worksite_id and c.get("active", True)]
        base = {"worksite_id": worksite_id, "worksite_name": ws.name, "generated_at": now_iso(), "hours": hours,
                "step_minutes": step, "forecast_source": "simulated", "note": FORECAST_NOTE, "data_origin": "SIMULATED"}
        if station is None:
            return base | {"forecast_source": "none", "slots": [], "crews": [],
                           "note": "No forecast is connected for this site. Connect a weather forecast feed to plan ahead."}

        # First column is "now"; after that, round clock times (e.g. 08:00, 08:30) so the plan is easy to read.
        now_min = _minutes(station.sim_clock())
        first = step - now_min % step
        steps = [0] + list(range(first if first != step else step, hours * 60 + 1, step))
        readings = []
        for k in steps:
            m = station.sim_minute + k
            st = station.true_state(m)
            rin = SensorReadingIn(station_id="forecast", worksite_id=worksite_id, dry_bulb=st.tdb, natural_wet_bulb=st.tnwb,
                                  globe_temperature=st.tg, relative_humidity=st.rh, direct_solar=st.direct_solar,
                                  sim_clock=station.sim_clock(m), sim_date=station.scenario.sim_date)
            wb = compute_wbgt(st.tnwb, st.tg, st.tdb, ws.environment, st.direct_solar)
            ts = now_iso()
            readings.append(SensorReading(**rin.model_dump(exclude={"reading_id", "timestamp"}), reading_id=f"forecast-{k}",
                                          timestamp=ts, received_at=ts, wbgt=wb.value, wbgt_formula=wb.formula,
                                          validation=validate_reading(rin)))

        out_crews = []
        for c in crews:
            plan_crew = Crew(**{**c, "work_rest_regime": "continuous"})  # planning baseline: normal continuous work
            cells = []
            for r in readings:
                a = svc.engine.assess(AssessmentContext(worksite=ws, crew=plan_crew, reading=r, reading_age_seconds=0.0,
                                                        stale_after_seconds=svc.settings.stale_after_seconds))
                d = a.limit_details
                cells.append({
                    "clock": r.sim_clock,
                    "category": a.risk_category,
                    "regime": d.required_regime if d else None,
                    "effective_wbgt": d.effective_wbgt if d else None,
                    "limit": d.limit_at_current_regime if d else None,
                    "midday_break": bool(a.regulatory_flags),
                    "in_shift": _in_shift(r.sim_clock, c.get("shift_start", "07:00"), c.get("shift_duration_hours", 8)),
                })
            out_crews.append({"crew_id": c["crew_id"], "crew_name": c["name"], "workload": c["workload"],
                              "zone": c.get("zone", ""), "cells": cells, "advice": self._advice(cells)})
        return base | {"slots": [r.sim_clock for r in readings], "crews": out_crews}

    def _advice(self, cells: list[dict]) -> list[dict]:
        """Plain planning statements, in time order. Each has a kind for styling and a sentence."""
        g = self.svc.guideline
        work = [c for c in cells if c["in_shift"]]
        if not work:
            return [{"kind": "info", "text": "No shift in the planning window."}]
        out: list[dict] = []
        first_bad = next((c for c in work if c["category"] not in LIGHT_ENOUGH), None)
        if first_bad is None:
            out.append({"kind": "ok", "text": "Normal continuous work fits the whole planning window. Keep water breaks."})
        else:
            rot = first_bad["regime"]
            if first_bad is work[0]:
                out.append({"kind": "warn", "text": (f"Continuous work is already above the limit: use {g.regime(rot)['label'].lower()} now."
                                                     if rot else "Continuous work is already above the limit.")})
            else:
                out.append({"kind": "ok", "text": f"Schedule the heaviest tasks before {first_bad['clock']}."})
                if rot:
                    out.append({"kind": "warn", "text": f"Start {g.regime(rot)['label'].lower()} by {first_bad['clock']}."})
        stop = next((c for c in work if c["category"] == "critical" and not c["regime"]), None)
        if stop is not None:
            out.append({"kind": "stop", "text": f"Strenuous work should stop from {stop['clock']}: no work/rest schedule is enough."})
        mid = [c for c in work if c["midday_break"]]
        if mid:
            out.append({"kind": "info", "text": f"UAE midday break: no outdoor work in direct sun {mid[0]['clock']}-15:00. Plan shaded or indoor tasks."})
        later = next((c for c in work if c is not first_bad and first_bad is not None and work.index(c) > work.index(first_bad)
                      and c["category"] in LIGHT_ENOUGH), None)
        if later is not None:
            out.append({"kind": "ok", "text": f"Conditions ease again from about {later['clock']}."})
        return out
