# HeatGuard architecture

```
 ENVIRONMENTAL SIMULATOR (simulator/heatguard_sim)          future: ESP32 station
   scenarios.py -> physics.py -> station.py (VirtualStation)      |
            |  SensorSource interface (backend/app/sensors)       |  POST /api/sensors/ingest
            v                                                      v
 ┌──────────────────────────── FASTAPI BACKEND (backend/app) ─────────────────────────────┐
 │ HeatGuardService.process_batch()                                                       │
 │   data_validation.validate_reading()  ──►  wbgt_calculator.compute_wbgt()              │
 │                       │                                                                │
 │                       ▼                                                                │
 │   risk_engine.RiskEngine.assess()   (guideline.py + guidelines/niosh_2016.json)        │
 │          │                                   │                                         │
 │          ▼                                   ▼                                         │
 │   alert_engine.AlertEngine          intervention_service.InterventionService           │
 │          └──────────────┬────────────────────┘                                         │
 │                         ▼                                                              │
 │   repositories/HeatGuardRepository (in-memory working set + write-behind sync queue)   │
 │          ├── FirebaseBackend (firebase-admin, Realtime Database)                       │
 │          └── LocalJsonBackend (demo mode, no credentials)                              │
 │   reports_service / evaluation_service                                                 │
 └───────────────────────────────▲────────────────────────────────────────────────────────┘
                                 │ REST (polled every 2 s)
        DASHBOARD (frontend/, served at /)        WORKER APP (worker_app/, served at /worker/)
        Supervisor / OHS roles, Flutter Web       Flutter: web + Android + iOS, EN/AR/UR/HI
```

## Components

| Layer | Path | Responsibility |
|---|---|---|
| Simulator | `simulator/heatguard_sim` | Consistent synthetic drivers → Tdb, Tnwb, Tg, RH; noise; faults; edge buffer during uplink outage; ground truth for evaluation only |
| Sensor interface | `backend/app/sensors/interface.py` | `SensorSource.poll()`; the backend never imports the simulator directly except through `SimulatedSensorSource` |
| HTTP ingest | `POST /api/sensors/ingest` | Same pipeline for any external station; optional `X-HeatGuard-Key`; strips ground truth |
| Validation | `services/data_validation.py` | Missing, out-of-range, faulted, implausible values |
| WBGT | `services/wbgt_calculator.py` | ISO 7243 / NIOSH formulas |
| Risk engine | `services/risk_engine.py`, `services/guideline.py` | Pure function of reading + context + guideline → explained assessment |
| UAE rules | `services/regulatory.py`, `guidelines/uae_midday_break.json` | Midday-break compliance flag, urgent action and site-level alert; independent of the NIOSH category |
| Worker signals & escalation | `services/worker_service.py`, `api/routes/workers.py`, `simulator/heatguard_sim/wearable.py` | Consent, pseudonymous badges, NIOSH physiological criteria, symptom escalation, OHS-only access |
| Alerts | `services/alert_engine.py` | Raise, suppress duplicates, escalate severity, re-acknowledgement, escalation of unacknowledged alerts, sustained-improvement review; never auto-resolves |
| Interventions | `services/intervention_service.py` | Records actions, applies optional context changes, baseline + follow-up assessments, outcome |
| Orchestration | `services/heatguard_service.py` | Ingestion pipeline, staleness detection, events, health, async loop |
| Persistence | `repositories/` | Repository layer; Firebase or local JSON; queued writes survive outages |
| Reports & evaluation | `services/reports_service.py`, `services/evaluation_service.py` | Metrics, CSV export, headless scenario tests |
| Dashboard | `frontend/lib` | Supervisor / OHS app. Provider state (`providers/app_state.dart`) polling the REST API; feature pages under `features/` |
| Worker app | `worker_app/lib` | Separate app carried by workers (web, Android, iOS). `core/state.dart` polls the worker endpoints every 3 s with the `worker` role and remembers language, crew and badge on the device; `ui/` has onboarding and the Today, My health and Emergency tabs |

## Timing model

One simulator tick is one **simulated minute**. At 1× speed a tick happens every `HEATGUARD_TICK_SECONDS`
(default 3 s); the Simulation Lab can run at 0.5×–10×. Staleness is measured in wall-clock seconds since a
reading was received (default 15 s), so a stopped or disconnected station is detected within about 5 ticks.

## Resilience

| Failure | Detection | Behaviour |
|---|---|---|
| Sensor probe missing/invalid | Validation | Assessment `incomplete`; site-level data-quality alert; gap in charts (no interpolation) |
| Station uplink down | No readings → staleness | Assessment `unavailable`; readings queued at the edge; on recovery delivered with `late_sync=true`; `connectivity_restored` / `data_flow_restored` events with durations |
| Database unreachable | Backend write fails (or simulated outage) | Writes stay in the coalescing queue (`pending_sync_writes`); alerts and interventions are never dropped from the queue |
| Backend down | Frontend poll fails | Red banner, content dimmed, sidebar status "Backend unavailable"; last data labelled as not live |

## Replacing the simulator with an ESP32

1. Wire a natural wet-bulb sensor, a black-globe probe (e.g. DS18B20 inside a 150 mm matte-black globe) and a
   shielded dry-bulb/RH sensor.
2. POST JSON matching `SensorReadingIn` (`backend/app/schemas/sensor.py`) to `/api/sensors/ingest` with
   `data_origin: "MEASURED"` and the `X-HeatGuard-Key` header, or implement a `SensorSource` (e.g. MQTT).
3. Run the backend with `HEATGUARD_SIM_AUTOSTART=false`. `simulator/simulator.py` shows the client protocol,
   including edge buffering.

## Firebase Realtime Database layout

```
/worksites/{worksite_id}
/crews/{crew_id}
/sensor_readings/{worksite_id}/{reading_id}
/assessments/{assessment_id}          (history: on category change and every 5th reading)
/latest_assessments/{crew_id}
/alerts/{alert_id}
/interventions/{intervention_id}
/events/{event_id}                    (sensor / connectivity / simulation events)
/workers/{worker_id}                  (pseudonymous badge, consent, age band; OHS only)
/worker_status/{worker_id}            (latest strain flags, no raw signals; OHS only)
/escalations/{escalation_id}          (symptom reports and outcomes; OHS only)
/simulation
/system_health
/evaluation
```

Writes use the Admin SDK through the repository's multi-path `update()`. Client access is governed by
`firebase/database.rules.json`, which is role-based with no client writes and per-crew read access for workers.
