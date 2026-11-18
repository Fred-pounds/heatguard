"""Simulated wearable for workers who have CONSENTED to share physiological signals (SYNTHETIC).

Produces heart rate, a device-estimated core temperature and battery level once per simulated minute.
The physiology is a simple, documented heuristic for demonstration only - not a validated model:

  HR   = 72 + workload_load * work_fraction + 2.5 * max(0, effective WBGT - continuous-work limit)
         + individual offset + strain (injected) + noise
  core = 36.9 + 0.011 * max(0, HR - 72) + strain_core (injected), approached gradually (thermal inertia)

No signals are generated for workers without active consent.
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field

WORKLOAD_LOAD = {"rest": 0, "light": 18, "moderate": 32, "heavy": 46, "very_heavy": 58, "unknown": 32}


@dataclass
class VirtualWearable:
    worker_id: str
    device_id: str
    offset: float = 0.0  # individual variation (bpm)
    battery_pct: float = 100.0
    strain: float = 0.0  # injected extra strain (0..1), e.g. a worker becoming unwell
    core: float = 36.9
    rng: random.Random = field(default_factory=random.Random)

    def reading(self, workload: str, work_fraction: float, effective_wbgt: float | None, limit_continuous: float | None) -> dict:
        heat = 0.0
        if effective_wbgt is not None and limit_continuous is not None:
            heat = 2.5 * max(0.0, effective_wbgt - limit_continuous)
        hr = 72 + WORKLOAD_LOAD.get(workload, 32) * work_fraction + heat + self.offset + 45 * self.strain + self.rng.gauss(0, 3)
        target_core = 36.9 + 0.011 * max(0.0, hr - 72) + 1.4 * self.strain
        self.core += (target_core - self.core) * 0.15  # thermal inertia
        self.battery_pct = max(0.0, self.battery_pct - 0.06)
        return {
            "worker_id": self.worker_id,
            "device_id": self.device_id,
            "heart_rate": round(hr),
            "core_temp_est": round(self.core + self.rng.gauss(0, 0.03), 2),
            "battery_pct": round(self.battery_pct, 1),
            "data_origin": "SIMULATED",
        }
