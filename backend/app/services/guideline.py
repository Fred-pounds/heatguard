"""Loads a documented assessment guideline configuration (JSON) and exposes its rules."""
from __future__ import annotations

import json
import math
from functools import lru_cache
from pathlib import Path

GUIDELINE_DIR = Path(__file__).resolve().parents[1] / "guidelines"

CATEGORY_LEVELS = {"routine": 0, "caution": 1, "elevated": 2, "high": 3, "critical": 4}
REGIME_CATEGORY = {"45_15": "elevated", "30_30": "high", "15_45": "high"}


class Guideline:
    def __init__(self, data: dict):
        self.data = data
        self.id: str = data["id"]
        self.reference = f'{data["name"]} ({data["edition"]}), {data["publication"]}'
        self.caution_margin: float = float(data["site_policy"]["caution_margin_c"])
        self.regimes: list[dict] = data["work_rest_regimes"]["regimes"]
        self.regime_ids = [r["id"] for r in self.regimes]
        self.categories = data["risk_categories"]["categories"]

    # -------------------------------------------------------------- limits
    def limit(self, limit_type: str, metabolic_w: float) -> float:
        eq = self.data["limits"][limit_type]
        return round(eq["a"] - eq["b"] * math.log10(metabolic_w), 2)

    def limit_type_for(self, acclimatization: str) -> str:
        return self.data["acclimatization"].get(acclimatization, {"limit": "RAL"})["limit"]

    # -------------------------------------------------------------- metabolic
    def metabolic_rate(self, workload: str) -> float | None:
        cls = self.data["metabolic_rates"]["classes"].get(workload)
        return float(cls["watts"]) if cls else None

    @property
    def rest_metabolic_rate(self) -> float:
        rest = self.data["metabolic_rates"]["rest_class_for_work_rest_twa"]
        return float(self.data["metabolic_rates"]["classes"][rest]["watts"])

    def regime(self, regime_id: str) -> dict:
        for r in self.regimes:
            if r["id"] == regime_id:
                return r
        raise KeyError(regime_id)

    def twa_metabolic_rate(self, work_w: float, regime_id: str) -> float:
        r = self.regime(regime_id)
        rest_w = min(self.rest_metabolic_rate, work_w)
        return (r["work_min"] * work_w + r["rest_min"] * rest_w) / 60.0

    # -------------------------------------------------------------- clothing
    def clothing(self, key: str) -> dict | None:
        return self.data["clothing_adjustment_factors"]["categories"].get(key)

    def clothing_options(self) -> dict:
        return self.data["clothing_adjustment_factors"]["categories"]

    def workload_options(self) -> dict:
        return self.data["metabolic_rates"]["classes"]

    def summary(self) -> dict:
        return self.data


@lru_cache
def load_guideline(guideline_id: str = "niosh_2016") -> Guideline:
    path = GUIDELINE_DIR / f"{guideline_id}.json"
    with path.open(encoding="utf-8") as fh:
        return Guideline(json.load(fh))
