#!/usr/bin/env python3
"""Standalone virtual sensing station (SIMULATED data).

Runs a VirtualStation outside the backend and POSTs readings to the same
HTTP ingest endpoint a future ESP32 station would use:

    POST {api}/sensors/ingest

Usage (backend running with in-process simulation disabled):
    HEATGUARD_SIM_AUTOSTART=false uvicorn app.main:app --port 8000      # in backend/
    python simulator/simulator.py --worksite ws_kumasi_tower --scenario increasing_heat --interval 3

Readings that cannot be delivered (backend down / network failure) are kept
in the station's edge buffer and re-sent, flagged late_sync, on recovery.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from heatguard_sim import SCENARIOS, new_station  # noqa: E402


def post(url: str, payload: list[dict], key: str | None) -> None:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/json"})
    if key:
        req.add_header("X-HeatGuard-Key", key)
    with urllib.request.urlopen(req, timeout=5) as resp:
        resp.read()


def main() -> int:
    p = argparse.ArgumentParser(description="HeatGuard standalone virtual station (SIMULATED)")
    p.add_argument("--api", default="http://localhost:8000/api")
    p.add_argument("--worksite", default="ws_kumasi_tower")
    p.add_argument("--scenario", default="increasing_heat", choices=sorted(SCENARIOS))
    p.add_argument("--interval", type=float, default=3.0, help="seconds between readings (1 reading = 1 simulated minute)")
    p.add_argument("--minutes", type=int, default=0, help="stop after N simulated minutes (0 = run forever)")
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--key", default=None, help="sensor ingest key if HEATGUARD_INGEST_KEY is set on the backend")
    p.add_argument("--fail-globe-at", type=int, default=None, help="simulate globe sensor drop-out from this minute")
    args = p.parse_args()

    station = new_station(args.worksite, args.scenario, args.seed)
    url = f"{args.api.rstrip('/')}/sensors/ingest"
    print(f"[SIMULATED] station {station.station_id} -> {url} scenario={args.scenario}")
    pending: list[dict] = []
    while True:
        if args.fail_globe_at is not None and station.sim_minute >= args.fail_globe_at:
            station.manual_faults["globe"] = "missing"
        reading = station.tick()
        reading.pop("ground_truth", None)  # evaluation-only; never sent to the backend
        if pending:
            for r in pending:
                r["late_sync"] = True
        pending.append(reading)
        try:
            post(url, pending, args.key)
            print(f"{reading['sim_clock']} sent {len(pending)} reading(s); "
                  f"Tdb={reading['dry_bulb']} Tnwb={reading['natural_wet_bulb']} Tg={reading['globe_temperature']}")
            pending = []
        except (urllib.error.URLError, OSError) as exc:
            print(f"{reading['sim_clock']} delivery failed ({exc}); {len(pending)} reading(s) buffered at edge")
            pending = pending[-720:]
        if args.minutes and station.sim_minute >= args.minutes:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
