"""Consented worker signals, symptom check-ins and clinical escalation.

Governance built in:
* Only workers with active consent produce or keep signals; withdrawal deletes their signals immediately.
* Pseudonymous badges only (no names, no employee numbers); age band only, used for the HR threshold.
* Raw signals are held in memory for at most 2 hours; only status flags are persisted.
* Supervisors get crew-level counts and badges to check on - never values or symptoms.
* Physiological thresholds follow NIOSH 2016 (physiological monitoring criteria): sustained heart rate above
  180 - age (bpm); core temperature above 38.5 degC (acclimatized) or 38.0 degC (unacclimatized).
  Device core temperature is an estimate and is labelled as such.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
from collections import deque
from datetime import datetime, timedelta
from typing import Callable

from ..repositories.repository import HeatGuardRepository
from ..schemas.common import new_id, now_iso
from ..schemas.worker import (
    OUTCOMES,
    SYMPTOMS_FIRST_AID,
    SYMPTOMS_RED_FLAG,
    ConsentRequest,
    EscalationUpdate,
    SignalIn,
    SymptomReportIn,
    Worker,
)

SIGNAL_WINDOW = 120  # minutes of raw signal kept in memory
SUSTAINED_MINUTES = 3
SIGNAL_STALE_SECONDS = 30
LOW_DEVICE_BATTERY = 15.0
AGE_UPPER = {"18-29": 29, "30-39": 39, "40-49": 49, "50-59": 59, "60+": 70}
NIOSH_SOURCE = "NIOSH 2016, physiological monitoring criteria"
MAX_PAIR_ATTEMPTS = 5
PAIR_LOCK_MINUTES = 10


def demo_pairing_code(worker_id: str) -> str:
    """Stable 6-digit code for the SIMULATED demo badges, so a demo can be rehearsed. Real badges get random codes."""
    return f"{int(hashlib.sha256(f'heatguard-demo:{worker_id}'.encode()).hexdigest(), 16) % 1_000_000:06d}"


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class PairingError(Exception):
    def __init__(self, message: str, status: int):
        super().__init__(message)
        self.status = status


class WorkerService:
    def __init__(self, repo: HeatGuardRepository, clock: Callable[[], datetime]):
        self.repo = repo
        self.clock = clock
        self.signals: dict[str, deque] = {}
        self._failed_pairs: dict[str, list[datetime]] = {}

    # ------------------------------------------------------------------ device pairing
    def ensure_pairing_codes(self) -> None:
        for w in self.repo.workers.values():
            if not w.get("pairing_code"):
                w["pairing_code"] = demo_pairing_code(w["worker_id"])
                self.repo.save_worker(w)

    def pair(self, worker_id: str, code: str) -> str:
        """Link this device to a badge. Returns a device token; only its hash is stored."""
        w = self.repo.workers.get(worker_id)
        if not w:
            raise PairingError("Unknown badge", 404)
        now = self.clock()
        recent = [t for t in self._failed_pairs.get(worker_id, []) if now - t < timedelta(minutes=PAIR_LOCK_MINUTES)]
        self._failed_pairs[worker_id] = recent
        if len(recent) >= MAX_PAIR_ATTEMPTS:
            raise PairingError(f"Too many wrong codes. Try again in {PAIR_LOCK_MINUTES} minutes or ask the first aider.", 429)
        if not w.get("pairing_code") or not hmac.compare_digest(code.strip(), w["pairing_code"]):
            recent.append(now)
            raise PairingError("Wrong code", 403)
        self._failed_pairs.pop(worker_id, None)
        token = secrets.token_urlsafe(24)
        w["device_token_hash"] = _hash(token)  # one device per badge: pairing a new phone unpairs the old one
        w["paired_at"] = now_iso()
        self.repo.save_worker(w)
        self.repo.add_event({"event_id": new_id("evt"), "timestamp": now.isoformat(), "type": "badge_paired",
                             "worksite_id": None, "detail": f"Badge {w['badge']} paired with a phone", "data": {}})
        return token

    def check_device(self, worker_id: str, token: str | None) -> dict:
        w = self.repo.workers.get(worker_id)
        if not w:
            raise PairingError("Unknown badge", 404)
        if not token or not w.get("device_token_hash") or not hmac.compare_digest(_hash(token), w["device_token_hash"]):
            raise PairingError("This phone is not paired with this badge", 401)
        return w

    def reissue_code(self, worker_id: str) -> dict:
        """OHS: new random code; the currently paired phone is unpaired."""
        w = self.repo.workers[worker_id]
        w["pairing_code"] = f"{secrets.randbelow(1_000_000):06d}"
        w["device_token_hash"] = None
        w["paired_at"] = None
        self.repo.save_worker(w)
        return w

    @staticmethod
    def public(w: dict) -> dict:
        """Worker record without secrets (the token hash is never returned)."""
        return {k: v for k, v in w.items() if k != "device_token_hash"} | {"paired": bool(w.get("device_token_hash"))}

    # ------------------------------------------------------------------ registry & consent
    def workers_for_crew(self, crew_id: str) -> list[dict]:
        return sorted((w for w in self.repo.workers.values() if w["crew_id"] == crew_id), key=lambda w: w["badge"])

    def set_consent(self, worker_id: str, req: ConsentRequest) -> dict:
        w = self.repo.workers[worker_id]
        c = w["consent"]
        if req.granted:
            if "heart_rate" in req.scopes and not (req.age_band or w.get("age_band")):
                raise ValueError("An age band is needed to apply the heart-rate threshold (180 - age)")
            c.update(status="granted", scopes=list(req.scopes), granted_at=now_iso(), withdrawn_at=None)
            if req.age_band:
                w["age_band"] = req.age_band
        else:
            c.update(status="withdrawn", scopes=[], withdrawn_at=now_iso())
            w["age_band"] = None  # data minimisation: no longer needed
            self.signals.pop(worker_id, None)  # delete held signals immediately
            self.repo.save_worker_status(worker_id, None)
        self.repo.save_worker(w)
        self.repo.add_event({"event_id": new_id("evt"), "timestamp": self.clock().isoformat(), "type": "consent_changed",
                             "worksite_id": None, "detail": f"Badge {w['badge']}: consent {c['status']}", "data": {}})
        return w

    def consented(self, w: dict) -> bool:
        return w["consent"]["status"] == "granted"

    # ------------------------------------------------------------------ signals
    def ingest_signal(self, sig: SignalIn) -> dict | None:
        w = self.repo.workers.get(sig.worker_id)
        if not w or not self.consented(w) or w["device_id"] != sig.device_id:
            return None  # no consent, unknown worker or wrong device: discard, never store
        d = sig.model_dump()
        d["received_at"] = self.clock().isoformat()
        if "heart_rate" not in w["consent"]["scopes"]:
            d["heart_rate"] = None
        if "core_temp_est" not in w["consent"]["scopes"]:
            d["core_temp_est"] = None
        self.signals.setdefault(sig.worker_id, deque(maxlen=SIGNAL_WINDOW)).append(d)
        return d

    def status(self, w: dict, crew_acclimatization: str = "unknown") -> dict:
        if not self.consented(w):
            return {"status": "not_shared", "flags": [], "detail": "Not sharing signals (no consent)"}
        sig = self.signals.get(w["worker_id"])
        if not sig:
            return {"status": "unavailable", "flags": ["no_signal"], "detail": "No signal yet: crew-level assessment applies"}
        last = sig[-1]
        age = (self.clock() - datetime.fromisoformat(last["received_at"])).total_seconds()
        if age > SIGNAL_STALE_SECONDS:
            return {"status": "unavailable", "flags": ["stale_signal"], "detail": f"No signal for {age:.0f}s: crew-level assessment applies",
                    "battery_pct": last.get("battery_pct")}
        flags, reasons = [], []
        hr_limit = 180 - AGE_UPPER.get(w.get("age_band") or "", 70)
        recent = list(sig)[-SUSTAINED_MINUTES:]
        if len(recent) == SUSTAINED_MINUTES and all((x.get("heart_rate") or 0) > hr_limit for x in recent):
            flags.append("sustained_high_heart_rate")
            reasons.append(f"heart rate above {hr_limit} bpm (180 - age) for {SUSTAINED_MINUTES}+ min")
        core_limit = 38.5 if crew_acclimatization == "acclimatized" else 38.0
        if (last.get("core_temp_est") or 0) >= core_limit:
            flags.append("high_core_temp_est")
            reasons.append(f"estimated core temperature at or above {core_limit} degC")
        if (last.get("battery_pct") or 100) < LOW_DEVICE_BATTERY:
            flags.append("low_device_battery")
        status = "check" if any(f in flags for f in ("sustained_high_heart_rate", "high_core_temp_est")) else "ok"
        return {"status": status, "flags": flags, "detail": "; ".join(reasons) or "Within physiological criteria",
                "heart_rate": last.get("heart_rate"), "core_temp_est": last.get("core_temp_est"),
                "battery_pct": last.get("battery_pct"), "hr_limit": hr_limit, "core_limit": core_limit,
                "last_seen": last["received_at"]}

    def crew_summary(self, crew: dict) -> dict:
        workers = self.workers_for_crew(crew["crew_id"])
        statuses = [(w, self.status(w, crew.get("acclimatization", "unknown"))) for w in workers]
        return {
            "enrolled": len(workers),
            "consented": sum(1 for w in workers if self.consented(w)),
            "sharing": sum(1 for _, s in statuses if s["status"] in ("ok", "check")),
            "checks_needed": sum(1 for _, s in statuses if s["status"] == "check"),
            "check_badges": [w["badge"] for w, s in statuses if s["status"] == "check"],
            "unavailable": sum(1 for _, s in statuses if s["status"] == "unavailable"),
            "crew_size": crew.get("worker_count"),
        }

    # ------------------------------------------------------------------ symptoms & escalation
    def report_symptoms(self, req: SymptomReportIn) -> dict:
        crew = self.repo.crews.get(req.crew_id)
        if not crew:
            raise KeyError("Unknown crew")
        unknown = [x for x in req.symptoms if x not in SYMPTOMS_RED_FLAG and x not in SYMPTOMS_FIRST_AID]
        if unknown:
            raise ValueError(f"Unknown symptom code(s): {', '.join(unknown)}")
        red = [x for x in req.symptoms if x in SYMPTOMS_RED_FLAG]
        level = "emergency" if red else "first_aid"
        badge = None
        if req.worker_id and req.worker_id in self.repo.workers:
            badge = self.repo.workers[req.worker_id]["badge"]
        esc = {
            "escalation_id": new_id("esc"),
            "created_at": now_iso(),
            "crew_id": req.crew_id,
            "crew_name": crew["name"],
            "worksite_id": crew["worksite_id"],
            "worker_id": req.worker_id,
            "badge": badge,
            "reported_by": req.reported_by,
            "level": level,
            "symptoms": [{"code": x, "label": SYMPTOMS_RED_FLAG.get(x) or SYMPTOMS_FIRST_AID.get(x), "red_flag": x in SYMPTOMS_RED_FLAG}
                         for x in req.symptoms],
            "note": req.note,
            "status": "open",
            "acknowledged_at": None,
            "responding_at": None,
            "closed_at": None,
            "outcome": None,
            "timeline": [{"timestamp": now_iso(), "event": "reported", "detail": f"Reported by {req.reported_by}"}],
            "data_origin": "SIMULATED",
        }
        self.repo.save_escalation(esc)
        return esc

    def update_escalation(self, esc_id: str, req: EscalationUpdate) -> dict:
        esc = self.repo.escalations[esc_id]
        if esc["status"] == "closed":
            raise ValueError("Escalation already closed")
        ts = now_iso()
        if req.action == "acknowledge":
            esc["acknowledged_at"] = esc["acknowledged_at"] or ts
            esc["status"] = "acknowledged"
        elif req.action == "responding":
            esc["acknowledged_at"] = esc["acknowledged_at"] or ts
            esc["responding_at"] = esc["responding_at"] or ts
            esc["status"] = "responding"
        else:
            if not req.outcome:
                raise ValueError("An outcome is required to close an escalation")
            esc["acknowledged_at"] = esc["acknowledged_at"] or ts
            esc["closed_at"] = ts
            esc["status"] = "closed"
            esc["outcome"] = req.outcome
        esc["timeline"].append({"timestamp": ts, "event": req.action, "actor": req.responder_id,
                                "detail": (OUTCOMES.get(req.outcome or "", "") + (f" - {req.note}" if req.note else "")).strip(" -")})
        self.repo.save_escalation(esc)
        return esc

    @staticmethod
    def redact(esc: dict) -> dict:
        """Supervisor view: what is needed to act, without clinical detail."""
        return {k: esc[k] for k in ("escalation_id", "created_at", "crew_id", "crew_name", "worksite_id", "badge", "level",
                                     "status", "acknowledged_at", "responding_at", "closed_at", "data_origin")} | {
            "summary": "Emergency signs reported - call 998 and the first aider now" if esc["level"] == "emergency"
            else "Symptoms reported - first-aid check needed"}
