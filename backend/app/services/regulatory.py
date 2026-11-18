"""Country-specific regulatory checks layered on top of the guideline-based assessment.

The UAE summer midday break is a legal working-time restriction, not a heat-stress
limit, so it is reported separately: it never changes the NIOSH-based risk category,
but adds a compliance flag, a required action and a dedicated alert.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

GUIDELINE_DIR = Path(__file__).resolve().parents[1] / "guidelines"


@dataclass(frozen=True)
class MiddayBreak:
    data: dict

    @property
    def enabled(self) -> bool:
        return bool(self.data.get("enabled", True))

    def in_force(self, sim_date: str | None, sim_clock: str | None) -> bool:
        """True when the given site date (YYYY-MM-DD) and time (HH:MM) fall in the restricted period and window."""
        if not (self.enabled and sim_date and sim_clock):
            return False
        md = sim_date[5:10]
        in_period = self.data["period_start"] <= md <= self.data["period_end"]
        in_window = self.data["window_start"] <= sim_clock < self.data["window_end"]
        return in_period and in_window

    def site_date_time(self, sim_date: str | None, sim_clock: str | None, timestamp: str | None) -> tuple[str | None, str | None]:
        """Simulated readings carry site date/time; real readings are converted to the site time zone."""
        if sim_date and sim_clock:
            return sim_date, sim_clock
        if not timestamp:
            return None, None
        from datetime import datetime
        from zoneinfo import ZoneInfo

        local = datetime.fromisoformat(timestamp).astimezone(ZoneInfo(self.data.get("timezone", "Asia/Dubai")))
        return local.strftime("%Y-%m-%d"), local.strftime("%H:%M")

    def season_active(self, sim_date: str | None) -> bool:
        if not (self.enabled and sim_date):
            return False
        return self.data["period_start"] <= sim_date[5:10] <= self.data["period_end"]

    def flag(self) -> dict:
        d = self.data
        return {
            "rule_id": d["id"],
            "title": "UAE midday break in force",
            "detail": f"{d['rule']} Applies {self._period_label()} each year.",
            "authority": d["authority"],
            "exemptions": d["exemptions"],
            "verification_note": d["verification_note"],
        }

    def _period_label(self) -> str:
        months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

        def fmt(md: str) -> str:
            m, day = md.split("-")
            return f"{int(day)} {months[int(m) - 1]}"

        return f"{fmt(self.data['period_start'])} to {fmt(self.data['period_end'])}"


@lru_cache
def load_midday_break(rule_id: str = "uae_midday_break") -> MiddayBreak | None:
    path = GUIDELINE_DIR / f"{rule_id}.json"
    if not path.exists():
        return None
    return MiddayBreak(json.loads(path.read_text(encoding="utf-8")))
