"""HeatGuard repository: in-memory working set + write-behind sync to a persistence backend.

All services go through this class; none talk to Firebase directly. Writes are
coalesced into a queue and flushed periodically. If the backend is unreachable
the queue is retained (and reported as "unsynchronised") until it recovers, so
alert and intervention history is never lost by a transient outage.
"""
from __future__ import annotations

import copy
import logging
import threading
from collections import deque
from typing import Any

from ..schemas.common import now_iso
from .base import PersistenceBackend

log = logging.getLogger("heatguard.repository")

MAX_PENDING = 20000


class HeatGuardRepository:
    def __init__(self, backend: PersistenceBackend, retain_readings: int = 2000, retain_assessments: int = 5000):
        self.backend = backend
        self.retain_readings = retain_readings
        self.retain_assessments = retain_assessments
        self._lock = threading.RLock()
        self.worksites: dict[str, dict] = {}
        self.crews: dict[str, dict] = {}
        self.readings: dict[str, deque] = {}
        self.assessments: deque = deque(maxlen=retain_assessments)
        self.latest_assessments: dict[str, dict] = {}
        self.alerts: dict[str, dict] = {}
        self.interventions: dict[str, dict] = {}
        self.events: deque = deque(maxlen=2000)  # connectivity / sensor / system events
        self.simulation: dict = {}
        self.system_health: dict = {}
        self.evaluation: dict | None = None
        self.meta: dict = {}
        self._pending: dict[str, Any] = {}
        self.last_sync: str | None = None
        self.sync_error: str | None = None
        self.synced_writes = 0

    # ------------------------------------------------------------------ load
    def load(self) -> None:
        try:
            tree = self.backend.load_all()
        except Exception as exc:  # pragma: no cover - depends on network
            log.warning("Could not load persisted state: %s", exc)
            self.sync_error = str(exc)
            return
        with self._lock:
            self.worksites = dict(tree.get("worksites") or {})
            self.crews = dict(tree.get("crews") or {})
            for ws, rows in (tree.get("sensor_readings") or {}).items():
                ordered = sorted((rows or {}).values(), key=lambda r: r.get("received_at", ""))
                self.readings[ws] = deque(ordered[-self.retain_readings:], maxlen=self.retain_readings)
            assessments = sorted((tree.get("assessments") or {}).values(), key=lambda a: a.get("timestamp", ""))
            self.assessments.extend(assessments[-self.retain_assessments:])
            self.latest_assessments = dict(tree.get("latest_assessments") or {})
            self.alerts = dict(tree.get("alerts") or {})
            self.interventions = dict(tree.get("interventions") or {})
            events = sorted((tree.get("events") or {}).values(), key=lambda e: e.get("timestamp", ""))
            self.events.extend(events[-2000:])
            for coll in (self.alerts.values(), self.interventions.values()):
                for item in coll:  # RTDB drops empty lists
                    for key in ("history", "intervention_ids", "contributing_factors", "recommendations", "follow_up_assessments"):
                        if key in item and item[key] is None:
                            item[key] = []
            self.evaluation = tree.get("evaluation")
            self.meta = dict(tree.get("meta") or {})

    # ------------------------------------------------------------------ queue
    def _queue(self, path: str, value: Any) -> None:
        with self._lock:
            if len(self._pending) >= MAX_PENDING:
                # Drop oldest queued sensor readings first; never drop alerts/interventions.
                for k in list(self._pending):
                    if k.startswith("sensor_readings/"):
                        self._pending.pop(k)
                        break
            self._pending[path] = copy.deepcopy(value)

    @property
    def pending_writes(self) -> int:
        return len(self._pending)

    def flush(self) -> bool:
        with self._lock:
            batch = dict(self._pending)
        if not batch:
            try:
                self.backend.flush()
            except Exception:  # pragma: no cover
                pass
            return True
        try:
            # chunk to keep RTDB requests reasonable
            items = list(batch.items())
            for i in range(0, len(items), 500):
                self.backend.apply(dict(items[i:i + 500]))
            self.backend.flush()
        except Exception as exc:
            self.sync_error = str(exc)[:300]
            log.warning("Sync to %s failed, %d writes queued: %s", self.backend.name, len(batch), exc)
            return False
        with self._lock:
            for k, v in batch.items():
                if self._pending.get(k, object()) is v:
                    self._pending.pop(k, None)
            self.synced_writes += len(batch)
        self.last_sync = now_iso()
        self.sync_error = None
        return True

    # ------------------------------------------------------------------ writes
    def save_worksite(self, ws: dict) -> None:
        self.worksites[ws["worksite_id"]] = ws
        self._queue(f"worksites/{ws['worksite_id']}", ws)

    def save_crew(self, crew: dict) -> None:
        self.crews[crew["crew_id"]] = crew
        self._queue(f"crews/{crew['crew_id']}", crew)

    def delete_crew(self, crew_id: str) -> None:
        self.crews.pop(crew_id, None)
        self.latest_assessments.pop(crew_id, None)
        self._queue(f"crews/{crew_id}", None)
        self._queue(f"latest_assessments/{crew_id}", None)

    def add_reading(self, reading: dict) -> None:
        ws = reading["worksite_id"]
        dq = self.readings.setdefault(ws, deque(maxlen=self.retain_readings))
        if len(dq) == dq.maxlen:
            old = dq[0]
            self._queue(f"sensor_readings/{ws}/{old['reading_id']}", None)
        dq.append(reading)
        persisted = {k: v for k, v in reading.items() if k != "ground_truth"}
        self._queue(f"sensor_readings/{ws}/{reading['reading_id']}", persisted)

    def add_assessment(self, a: dict, persist_history: bool) -> None:
        self.latest_assessments[a["crew_id"]] = a
        self._queue(f"latest_assessments/{a['crew_id']}", a)
        if persist_history:
            if len(self.assessments) == self.assessments.maxlen:
                old = self.assessments[0]
                self._queue(f"assessments/{old['assessment_id']}", None)
            self.assessments.append(a)
            self._queue(f"assessments/{a['assessment_id']}", a)

    def save_alert(self, alert: dict) -> None:
        self.alerts[alert["alert_id"]] = alert
        self._queue(f"alerts/{alert['alert_id']}", alert)

    def save_intervention(self, iv: dict) -> None:
        self.interventions[iv["intervention_id"]] = iv
        self._queue(f"interventions/{iv['intervention_id']}", iv)

    def add_event(self, event: dict) -> None:
        self.events.append(event)
        self._queue(f"events/{event['event_id']}", event)

    def set_simulation(self, sim: dict) -> None:
        self.simulation = sim
        self._queue("simulation", sim)

    def set_system_health(self, health: dict) -> None:
        self.system_health = health
        self._queue("system_health", health)

    def set_evaluation(self, ev: dict) -> None:
        self.evaluation = ev
        self._queue("evaluation", ev)

    def set_meta(self, meta: dict) -> None:
        self.meta = {**self.meta, **meta}
        self._queue("meta", self.meta)

    def reset_all(self) -> None:
        """Delete everything, including worksites and crews (used to replace outdated demo data)."""
        self.clear_operational_data()
        with self._lock:
            self.worksites.clear()
            self.crews.clear()
            self.simulation = {}
            self.meta = {}
            for p in ("worksites", "crews", "simulation", "system_health", "meta"):
                self._pending.pop(p, None)
                self._queue(p, None)

    def clear_operational_data(self) -> None:
        """Remove readings, assessments, alerts, interventions and events (keeps worksites/crews)."""
        roots = ("sensor_readings", "assessments", "latest_assessments", "alerts", "interventions", "events", "evaluation")
        with self._lock:
            # drop queued child writes superseded by the root deletes below
            for k in list(self._pending):
                if any(k == p or k.startswith(p + "/") for p in roots):
                    self._pending.pop(k)
            self.readings.clear()
            self.assessments.clear()
            self.latest_assessments.clear()
            self.alerts.clear()
            self.interventions.clear()
            self.events.clear()
            self.evaluation = None
            for p in roots:
                self._queue(p, None)
