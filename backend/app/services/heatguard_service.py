"""Application service: wires ingestion, validation, WBGT, assessment, alerts,
interventions, persistence and the simulator together.

Data flow per reading:
  SensorSource / HTTP ingest -> validate -> WBGT -> store reading
  -> assess every active crew at the worksite (risk engine)
  -> alert engine -> intervention follow-ups -> repository (write-behind sync)
"""
from __future__ import annotations

import asyncio
import logging
import os
import time
from datetime import datetime
from statistics import mean
from typing import Callable

from ..core.config import Settings
from ..repositories.base import PersistenceBackend
from ..repositories.local_repository import LocalJsonBackend
from ..repositories.repository import HeatGuardRepository
from ..schemas.common import new_id, now_iso, utcnow
from ..schemas.crew import Crew, Worksite
from ..schemas.sensor import SensorReading, SensorReadingIn
from ..schemas.worker import Consent, SignalIn, Worker
from .alert_engine import AlertEngine
from .data_validation import validate_reading
from .guideline import load_guideline
from .intervention_service import InterventionService
from .regulatory import load_midday_break
from .risk_engine import AssessmentContext, RiskEngine
from .simulation_service import SimulationService
from .worker_service import WorkerService
from .wbgt_calculator import MissingComponentError, compute_wbgt

log = logging.getLogger("heatguard.service")

HISTORY_EVERY_N = 5  # persist an assessment to history at least every N readings per crew
DEMO_SEED_VERSION = "abu-dhabi-3"  # bump when the demo worksites/crews change


class NullBackend(PersistenceBackend):
    """In-memory backend for tests and headless evaluation runs."""

    name = "memory"

    def load_all(self):
        return {}

    def apply(self, updates):
        return None

    def health(self):
        return {"backend": self.name, "status": "ok"}


def build_backend(settings: Settings) -> PersistenceBackend:
    if settings.storage_backend == "firebase":
        emulator = bool(os.getenv("FIREBASE_DATABASE_EMULATOR_HOST"))
        if not settings.firebase_database_url or not (settings.firebase_credentials or emulator):
            log.warning("HEATGUARD_STORAGE=firebase but FIREBASE_CREDENTIALS/FIREBASE_DATABASE_URL missing; using local demo store")
        else:
            try:
                from ..repositories.firebase_repository import FirebaseBackend

                return FirebaseBackend(settings.firebase_credentials, settings.firebase_database_url)
            except Exception as exc:  # pragma: no cover - depends on credentials
                log.error("Firebase initialisation failed (%s); using local demo store", exc)
    if settings.storage_backend == "memory":
        return NullBackend()
    return LocalJsonBackend(settings.local_store_path)


class HeatGuardService:
    def __init__(self, settings: Settings, backend: PersistenceBackend | None = None,
                 clock: Callable[[], datetime] | None = None):
        self.settings = settings
        self.backend = backend or build_backend(settings)
        self.repo = HeatGuardRepository(self.backend, settings.retention_readings_per_site, settings.retention_assessments)
        self.guideline = load_guideline(settings.guideline_id)
        self.engine = RiskEngine(self.guideline, load_midday_break() if settings.uae_midday_break else None)
        self.alerts = AlertEngine(self.repo, settings.sustained_improvement_readings, settings.escalate_after_seconds)
        self.interventions = InterventionService(self.repo)
        self.sim = SimulationService(settings.tick_seconds, settings.simulation_seed)
        self.clock = clock or utcnow
        self.workers = WorkerService(self.repo, self.clock)
        self.started_at = now_iso()
        self._crew_counter: dict[str, int] = {}
        self._site_state: dict[str, dict] = {}  # per-site data-flow tracking (fault / stale episodes)
        self._last_valid: dict[str, dict] = {}  # last valid assessment per crew (shown when data become unavailable)
        self._task: asyncio.Task | None = None
        self.ticks = 0

    # ================================================================== setup
    def initialise(self) -> None:
        self.repo.load()
        if self.settings.seed_demo_data and self.repo.worksites and self.repo.meta.get("seed_version") != DEMO_SEED_VERSION:
            log.warning("Stored demo data is from an older demo version; replacing it with the current demo seed")
            self.repo.reset_all()
        if not self.repo.worksites and self.settings.seed_demo_data:
            self.seed_demo()
            self.seed_workers()
            self.repo.set_meta({"seed_version": DEMO_SEED_VERSION})
        self.workers.ensure_pairing_codes()
        for ws in self.repo.worksites.values():
            scenario = (self.repo.simulation.get("stations", {}).get(ws["worksite_id"], {}) or {}).get("scenario_id")
            default = "industrial_indoor" if ws["environment"] == "indoor" else "normal"
            try:
                self.sim.add_station(ws["worksite_id"], scenario or default)
            except Exception:
                self.sim.add_station(ws["worksite_id"], default)
        if self.settings.simulation_autostart:
            self.sim.start()
            if not any(self.repo.readings.values()):
                self.warm_up(30)
        self._publish_simulation()

    def seed_demo(self) -> None:
        """Create the demo worksites and crews (SIMULATED operational context, no personal data)."""
        ts = now_iso()
        sites = [
            Worksite(worksite_id="ws_saadiyat_tower", name="Saadiyat Island Tower Site", location="Saadiyat Island, Abu Dhabi (demo)",
                     environment="outdoor", industry="construction", station_id="vstation-ws_saadiyat_tower",
                     zones=["Level 4 deck", "Ground works", "Scaffolding east", "Materials yard"], created_at=ts),
            Worksite(worksite_id="ws_kezad_plant", name="KEZAD Metal Processing Hall", location="Khalifa Economic Zones (KEZAD), Abu Dhabi (demo)",
                     environment="indoor", industry="manufacturing", station_id="vstation-ws_kezad_plant",
                     zones=["Furnace bay", "Casting line"], created_at=ts),
        ]
        for s in sites:
            self.repo.save_worksite(s.model_dump())
        crews = [
            ("crew_concrete_a", "Concrete Crew A", "ws_saadiyat_tower", "Level 4 deck", 8, "heavy", "long_sleeved_protective", "acclimatized", "Pouring and finishing level-4 slab"),
            ("crew_rebar_b", "Rebar Crew B", "ws_saadiyat_tower", "Ground works", 6, "moderate", "standard_work_clothing", "not_acclimatized", "Tying rebar for pile caps"),
            ("crew_scaffold_c", "Scaffolding Crew C", "ws_saadiyat_tower", "Scaffolding east", 5, "moderate", "standard_work_clothing", "unknown", "Erecting east-face scaffolding"),
            ("crew_logistics", "Site Logistics", "ws_saadiyat_tower", "Materials yard", 4, "light", "standard_work_clothing", "acclimatized", "Receiving and checking deliveries"),
            ("crew_furnace", "Furnace Team", "ws_kezad_plant", "Furnace bay", 6, "heavy", "cloth_coveralls", "acclimatized", "Charging and tapping furnace"),
            ("crew_casting", "Casting Line Crew", "ws_kezad_plant", "Casting line", 7, "moderate", "sms_polypropylene_coveralls", "acclimatized", "Mould handling and fettling"),
        ]
        for cid, name, ws, zone, n, wl, cl, ac, task in crews:
            self.repo.save_crew(Crew(crew_id=cid, name=name, worksite_id=ws, zone=zone, worker_count=n, workload=wl, clothing=cl,
                                     acclimatization=ac, current_task=task, shift_start="07:00", shift_duration_hours=8,
                                     created_at=ts, updated_at=ts).model_dump())

    def seed_workers(self) -> None:
        """Pseudonymous wearable-programme participants (SIMULATED). Some consented, one declined."""
        ts = now_iso()
        plan = [("crew_concrete_a", "CA", ["30-39", "18-29", "40-49", "30-39"], 1),
                ("crew_rebar_b", "RB", ["18-29", "30-39"], 1),
                ("crew_furnace", "FT", ["30-39", "50-59", "40-49"], 0)]
        for crew_id, prefix, bands, declined in plan:
            if crew_id not in self.repo.crews:
                continue
            for i, band in enumerate(bands + [None] * declined, start=1):
                consent = Consent(status="granted", scopes=["heart_rate", "core_temp_est"], granted_at=ts) if band else Consent()
                w = Worker(worker_id=f"wk_{prefix.lower()}{i:02d}", badge=f"{prefix}-{i:02d}", crew_id=crew_id,
                           device_id=f"dev-{prefix.lower()}{i:02d}", age_band=band, consent=consent, created_at=ts)
                self.repo.save_worker(w.model_dump())
        self.workers.ensure_pairing_codes()

    def warm_up(self, ticks: int) -> None:
        """Pre-populate history with simulated minutes so charts are not empty at demo start."""
        for _ in range(ticks):
            self.process_batch(self.sim.poll_all(), from_sim=True)

    # ================================================================== ingestion
    def worksite(self, worksite_id: str) -> Worksite:
        ws = self.repo.worksites.get(worksite_id)
        if not ws:
            raise KeyError(f"Unknown worksite '{worksite_id}'")
        return Worksite(**ws)

    def ingest(self, r: SensorReadingIn) -> dict:
        ws = self.worksite(r.worksite_id)
        validation = validate_reading(r)
        valid = set(validation.valid_fields)
        wbgt = formula = None
        try:
            res = compute_wbgt(r.natural_wet_bulb if "natural_wet_bulb" in valid else None,
                               r.globe_temperature if "globe_temperature" in valid else None,
                               r.dry_bulb if "dry_bulb" in valid else None, ws.environment, r.direct_solar)
            wbgt, formula = res.value, res.formula
        except MissingComponentError:
            pass
        reading = SensorReading(
            **{**r.model_dump(), "reading_id": r.reading_id or new_id("rdg"), "timestamp": r.timestamp or self.clock().isoformat()},
            received_at=self.clock().isoformat(), wbgt=wbgt, wbgt_formula=formula, validation=validation,
        ).model_dump()
        self.repo.add_reading(reading)
        self._track_validity(ws.worksite_id, reading)
        return reading

    def process_batch(self, readings: list[SensorReadingIn], from_sim: bool = False) -> list[dict]:
        if from_sim:
            self._simulate_wearables()
        if not readings:
            return []
        stored = [self.ingest(r) for r in readings]
        late = [r for r in stored if r.get("late_sync")]
        if late:
            first = datetime.fromisoformat(late[0]["timestamp"])
            self._event("connectivity_restored", late[0]["worksite_id"],
                        f"{len(late)} queued readings synchronised after {(self.clock() - first).total_seconds():.0f}s outage",
                        {"backfilled": len(late), "outage_seconds": round((self.clock() - first).total_seconds(), 1)})
        assessments = []
        for ws_id in dict.fromkeys(r["worksite_id"] for r in stored):
            assessments += self.assess_worksite(ws_id)
            self._maintenance_check(ws_id)
            self._worker_checks(ws_id)
            if from_sim:
                self._count_lost_time(ws_id)
        self.ticks += 1
        return assessments

    # ================================================================== field operation
    def _maintenance_check(self, ws_id: str) -> None:
        r = self.latest_reading(ws_id)
        if r is None:
            return
        reasons, actions = [], []
        batt = r.get("battery_pct")
        if batt is not None and batt < 25:
            reasons.append(f"station battery at {batt:.0f}%")
            actions.append({"action": "Charge or replace the station battery", "priority": "required", "source": "HeatGuard",
                            "detail": "At 0% the station stops reporting and every assessment becomes unavailable."})
        wick = any(i["issue"] == "implausible" and "wick" in i["detail"] for i in r["validation"]["issues"])
        dust = r.get("dust_index") or 0
        if wick or dust >= 0.3:
            reasons.append("dust fouling of the globe and wet-bulb wick" + (" (wet-bulb reading implausible)" if wick else ""))
            actions.append({"action": "Clean the globe and re-wet or replace the wick", "priority": "required", "source": "ISO 7243 maintenance",
                            "detail": "Readings from a fouled station are not trusted; assessments stay unavailable until it is serviced."})
        ws = self.repo.worksites[ws_id]
        if reasons:
            self.alerts.raise_simple(worksite_id=ws_id, worksite_name=ws["name"], crew_id="__site__", crew_name="Sensing station",
                                     alert_type="maintenance", severity="maintenance", level=1,
                                     explanation="Station maintenance needed: " + "; ".join(reasons) + ".", recommendations=actions)
        else:
            self.alerts.clear_simple(ws_id, "__site__", "maintenance", "station healthy again")

    def _worker_checks(self, ws_id: str) -> None:
        ws = self.repo.worksites[ws_id]
        for crew in [c for c in self.repo.crews.values() if c["worksite_id"] == ws_id]:
            summary = self.workers.crew_summary(crew)
            for w in self.workers.workers_for_crew(crew["crew_id"]):
                st = self.workers.status(w, crew.get("acclimatization", "unknown"))
                prev = self.repo.worker_status.get(w["worker_id"])
                if prev is None or prev.get("status") != st["status"] or prev.get("flags") != st["flags"]:
                    self.repo.save_worker_status(w["worker_id"], {"status": st["status"], "flags": st["flags"], "updated_at": now_iso()})
            if summary["checks_needed"]:
                n = summary["checks_needed"]
                self.alerts.raise_simple(
                    worksite_id=ws_id, worksite_name=ws["name"], crew_id=crew["crew_id"], crew_name=crew["name"],
                    alert_type="worker_check", severity="high", level=3,
                    explanation=(f"{n} consented worker{'s' if n > 1 else ''} in {crew['name']} "
                                 f"(badge {', '.join(summary['check_badges'])}) show signs of physiological heat strain. Check on them now."),
                    recommendations=[
                        {"action": "Check on the worker now", "priority": "urgent", "source": "NIOSH 2016",
                         "detail": "Stop their work, move them to shade or a cooled area, give cool water."},
                        {"action": "Call the first aider", "priority": "required", "source": "HeatGuard",
                         "detail": "First aider assesses symptoms; if confused or collapsed, call 998."},
                        {"action": "Do not return them to work on the strength of this system", "priority": "required", "source": "HeatGuard",
                         "detail": "Return to work is decided by qualified personnel, not by HeatGuard."}])
            else:
                self.alerts.clear_simple(ws_id, crew["crew_id"], "worker_check", "no worker strain flags")

    def _simulate_wearables(self) -> None:
        """Generate signals only for consented workers (devices of others are treated as off)."""
        for w in self.repo.workers.values():
            if not self.workers.consented(w):
                self.sim.wearables.pop(w["worker_id"], None)
                continue
            crew = self.repo.crews.get(w["crew_id"])
            if not crew or crew["worksite_id"] not in self.sim.sources:
                continue
            wear = self.sim.wearable(w)
            a = self.repo.latest_assessments.get(crew["crew_id"]) or {}
            ld = a.get("limit_details") or {}
            regime = self.guideline.regime(crew.get("work_rest_regime", "continuous"))
            sig = wear.reading(crew.get("workload", "unknown"), regime["work_min"] / 60, a.get("effective_wbgt"),
                               (ld.get("regime_limits") or {}).get("continuous"))
            self.workers.ingest_signal(SignalIn(**sig))

    def _count_lost_time(self, ws_id: str) -> None:
        ops = self.repo.meta.setdefault("ops", {"rest_worker_minutes": 0.0, "midday_break_worker_minutes": 0.0, "crew_minutes": 0})
        for crew in [c for c in self.repo.crews.values() if c["worksite_id"] == ws_id and c.get("active", True)]:
            ops["crew_minutes"] += 1
            regime = self.guideline.regime(crew.get("work_rest_regime", "continuous"))
            ops["rest_worker_minutes"] += regime["rest_min"] / 60 * crew["worker_count"]
            if (self.repo.latest_assessments.get(crew["crew_id"]) or {}).get("regulatory_flags"):
                ops["midday_break_worker_minutes"] += crew["worker_count"]
        self.repo.set_meta({"ops": ops})

    # ================================================================== assessment
    def latest_reading(self, worksite_id: str) -> dict | None:
        dq = self.repo.readings.get(worksite_id)
        return dq[-1] if dq else None

    def reading_age(self, reading: dict | None) -> float | None:
        if not reading:
            return None
        return max(0.0, (self.clock() - datetime.fromisoformat(reading["received_at"])).total_seconds())

    def rolling_mean_wbgt(self, worksite_id: str) -> float | None:
        dq = self.repo.readings.get(worksite_id)
        if not dq:
            return None
        latest = dq[-1]
        vals = []
        if latest.get("sim_minute") is not None:
            for r in reversed(dq):
                if r.get("run_id") != latest.get("run_id") or r.get("sim_minute") is None:
                    break
                if r["sim_minute"] < latest["sim_minute"] - 59:
                    break
                if r.get("wbgt") is not None:
                    vals.append(r["wbgt"])
        else:
            t_last = datetime.fromisoformat(latest["timestamp"])
            for r in reversed(dq):
                if (t_last - datetime.fromisoformat(r["timestamp"])).total_seconds() > 3600:
                    break
                if r.get("wbgt") is not None:
                    vals.append(r["wbgt"])
        return mean(vals) if len(vals) >= 2 else None

    def trend_c_per_min(self, worksite_id: str) -> float | None:
        """Least-squares WBGT slope over the last 30 simulated minutes of valid readings (same run)."""
        dq = self.repo.readings.get(worksite_id)
        if not dq:
            return None
        latest = dq[-1]
        pts = []
        for r in reversed(dq):
            if r.get("run_id") != latest.get("run_id") or r.get("sim_minute") is None:
                break
            if r["sim_minute"] < (latest.get("sim_minute") or 0) - 29:
                break
            if r.get("wbgt") is not None:
                pts.append((r["sim_minute"], r["wbgt"]))
        if len(pts) < 10:
            return None
        n = len(pts)
        mx = sum(p[0] for p in pts) / n
        my = sum(p[1] for p in pts) / n
        den = sum((p[0] - mx) ** 2 for p in pts)
        return None if den == 0 else sum((p[0] - mx) * (p[1] - my) for p in pts) / den

    def assess_crew(self, crew: dict, reading: dict | None = None, persist: bool = True) -> dict:
        ws = self.worksite(crew["worksite_id"])
        reading = reading if reading is not None else self.latest_reading(ws.worksite_id)
        prev = self.repo.latest_assessments.get(crew["crew_id"])
        last_valid = self._last_valid.get(crew["crew_id"])
        ctx = AssessmentContext(
            worksite=ws, crew=Crew(**crew), reading=SensorReading(**reading) if reading else None,
            reading_age_seconds=self.reading_age(reading), stale_after_seconds=self.settings.stale_after_seconds,
            rolling_mean_wbgt=self.rolling_mean_wbgt(ws.worksite_id) if reading else None,
            last_valid_category=(last_valid or {}).get("risk_category"), last_valid_time=(last_valid or {}).get("sim_clock"),
            trend_c_per_min=self.trend_c_per_min(ws.worksite_id) if reading else None,
        )
        a = self.engine.assess(ctx)
        summary = self.workers.crew_summary(crew)
        if summary["enrolled"]:
            a.worker_signals = summary
            if summary["checks_needed"]:
                from ..schemas.assessment import ContributingFactor, RecommendedAction

                a.contributing_factors.insert(0, ContributingFactor(
                    factor="Worker strain signals",
                    detail=f"{summary['checks_needed']} of {summary['sharing']} consented workers sharing signals meet NIOSH physiological strain criteria.",
                    direction="increases_concern"))
                a.recommended_actions.insert(0, RecommendedAction(
                    action=f"Check on badge {', '.join(summary['check_badges'])} now", priority="urgent", source="NIOSH 2016",
                    detail="Stop their work, move them to shade or a cooled area, give cool water and call the first aider."))
        ad = a.model_dump()
        if a.assessment_status == "valid":
            self._last_valid[crew["crew_id"]] = ad
        n = self._crew_counter.get(crew["crew_id"], 0) + 1
        self._crew_counter[crew["crew_id"]] = n
        changed = prev is None or prev.get("risk_category") != a.risk_category
        if persist:
            self.repo.add_assessment(ad, persist_history=changed or n % HISTORY_EVERY_N == 0)
            self.alerts.process(a, ws.name)
            self.interventions.record_follow_up(ad)
        return ad

    def assess_worksite(self, worksite_id: str) -> list[dict]:
        reading = self.latest_reading(worksite_id)
        return [self.assess_crew(c, reading) for c in self.repo.crews.values()
                if c["worksite_id"] == worksite_id and c.get("active", True)]

    # ================================================================== monitoring
    def _event(self, kind: str, worksite_id: str | None, detail: str, data: dict | None = None) -> None:
        self.repo.add_event({"event_id": new_id("evt"), "timestamp": self.clock().isoformat(), "type": kind,
                             "worksite_id": worksite_id, "detail": detail, "data": data or {}})

    def _track_validity(self, ws_id: str, reading: dict) -> None:
        st = self._site_state.setdefault(ws_id, {"fault": False, "stale": False})
        bad = reading["validation"]["measurement_validity"] != "valid"
        if bad and not st["fault"]:
            fields = ", ".join(f"{i['field']} ({i['issue']})" for i in reading["validation"]["issues"])
            self._event("sensor_fault_detected", ws_id, f"Invalid or missing measurements: {fields}")
        elif not bad and st["fault"]:
            self._event("sensor_restored", ws_id, "All measurements valid again")
        st["fault"] = bad
        if st["stale"]:
            gap = st.get("stale_since")
            secs = (self.clock() - datetime.fromisoformat(gap)).total_seconds() if gap else None
            self._event("data_flow_restored", ws_id, "Readings received again" + (f" after {secs:.0f}s without fresh data" if secs else ""),
                        {"recovery_seconds": round(secs, 1) if secs else None})
            st["stale"] = False

    def check_staleness(self) -> list[dict]:
        """Reassess worksites whose data stopped arriving (never shows stale data as live)."""
        out = []
        for ws_id in self.repo.worksites:
            reading = self.latest_reading(ws_id)
            age = self.reading_age(reading)
            st = self._site_state.setdefault(ws_id, {"fault": False, "stale": False})
            if reading is None or (age is not None and age > self.settings.stale_after_seconds):
                if not st["stale"]:
                    st["stale"] = True
                    st["stale_since"] = reading["received_at"] if reading else self.clock().isoformat()
                    self._event("data_stale_detected", ws_id, f"No fresh readings for {age or 0:.0f}s (threshold {self.settings.stale_after_seconds:.0f}s)")
                out += self.assess_worksite(ws_id)
        return out

    def site_status(self, ws_id: str) -> dict:
        reading = self.latest_reading(ws_id)
        age = self.reading_age(reading)
        if reading is None:
            status = "offline"
        elif age is not None and age > self.settings.stale_after_seconds:
            status = "stale"
        else:
            status = {"valid": "ok", "partially_valid": "degraded", "invalid": "fault"}[reading["validation"]["measurement_validity"]]
        return {"worksite_id": ws_id, "sensor_status": status, "last_reading_at": reading["received_at"] if reading else None,
                "reading_age_seconds": round(age, 1) if age is not None else None,
                "sensors": reading.get("sensor_status") if reading else {}}

    def health(self) -> dict:
        db = self.backend.health()
        db_status = "simulated_outage" if self.sim.db_outage else ("degraded" if self.repo.sync_error else db.get("status", "ok"))
        sites = {ws: self.site_status(ws) for ws in self.repo.worksites}
        return {
            "last_update": self.clock().isoformat(),
            "backend_status": "ok",
            "database_status": db_status,
            "database_backend": self.backend.name,
            "pending_sync_writes": self.repo.pending_writes,
            "last_sync": self.repo.last_sync,
            "sync_error": self.repo.sync_error,
            "sensor_status": sites,
            "simulation_state": self.sim.state,
            "started_at": self.started_at,
            "data_origin": "SIMULATED",
        }

    def _publish_simulation(self) -> None:
        st = self.sim.status()
        self.repo.set_simulation({k: v for k, v in st.items()})

    # ================================================================== runtime loop
    async def run_forever(self) -> None:
        next_tick = time.monotonic()
        last_maint = last_flush = 0.0
        while True:
            try:
                now = time.monotonic()
                if self.sim.state == "running" and now >= next_tick:
                    self.process_batch(self.sim.poll_all(), from_sim=True)
                    self._publish_simulation()
                    next_tick = now + self.sim.tick_interval
                elif self.sim.state != "running":
                    next_tick = now
                if now - last_maint >= 1.0:
                    self.check_staleness()
                    self.alerts.check_escalations()
                    self.repo.set_system_health(self.health())
                    last_maint = now
                if now - last_flush >= 2.0 and not self.sim.db_outage:
                    await asyncio.to_thread(self.repo.flush)
                    last_flush = now
            except Exception:  # keep the loop alive; surface via logs
                log.exception("HeatGuard loop iteration failed")
            await asyncio.sleep(0.1)

    def start_background(self) -> None:
        self._task = asyncio.create_task(self.run_forever())

    async def shutdown(self) -> None:
        if self._task:
            self._task.cancel()
        await asyncio.to_thread(self.repo.flush)
