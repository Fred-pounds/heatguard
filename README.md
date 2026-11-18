# HeatGuard

**Explainable occupational heat-risk early warning and intervention system** (hackathon prototype)

> *From environmental monitoring to proactive worker protection.*

HeatGuard combines environmental heat measurements (WBGT), workload, clothing and acclimatization to produce
**explainable, guideline-based heat-risk assessments**. It raises alerts with recommended protective actions,
tracks the interventions supervisors take, and reassesses afterwards. It is decision support only: it does not
diagnose heat illness or clear workers to resume work.

> ⚠️ **All sensor data in this prototype are SIMULATED** by a built-in synthetic sensing station and labelled as
> such throughout the UI, API and CSV exports. No physical hardware is required.

## What's inside

| | |
|---|---|
| **Simulator** | Physically consistent synthetic Tdb / Tnwb / Tg / RH, 5 scenarios (normal, increasing heat, high-radiant construction, indoor industrial, sensor failure), noise, sensor faults, network outages with edge buffering |
| **WBGT** | Indoor/outdoor ISO 7243 / NIOSH formulas, unit-tested |
| **Risk engine** | NIOSH 2016 REL/RAL equations, metabolic classes, clothing adjustment factors, work/rest regimes. Categories are defined by *which work/rest regime keeps exposure within the limit*, not by invented WBGT cut-offs. Every assessment includes an explanation, contributing factors, recommendations, data quality, method, guideline reference and limitations |
| **Missing data** | Missing, invalid, implausible or stale data and unknown context → *incomplete/unavailable*, **never "safe"** |
| **Alerts** | Duplicate suppression, severity escalation with re-acknowledgement, escalation of unacknowledged alerts, no auto-clear (sustained improvement → supervisor review) |
| **Interventions** | Hydration / cooling break / workload reduction / rotation / shift change / relocation, with optional context changes, immediate reassessment, follow-up timeline and outcome |
| **Dashboard** | Flutter Web (Material 3, Provider, fl_chart): Overview, Live Monitoring, Crew Management, Alerts, Interventions, **Simulation Lab**, Reports (with evaluation and CSV), Settings (methodology and governance) |
| **Worker view** | Mobile-friendly, crew-only, plain language, ready for translations |
| **Persistence** | Firebase Realtime Database via a repository layer, or a local JSON store when no credentials are present; write-behind queue survives outages |
| **Evaluation** | 8 repeatable synthetic cases compared with ground truth: lead time, false/missed alerts, false-safe minutes, completeness, stale detection, recovery |

## Quick start

### Fastest: Python only (prebuilt dashboard included)

```bash
git clone https://github.com/Fred-pounds/heatguard.git
cd heatguard/backend
pip install -r requirements.txt
python -m uvicorn app.main:app --port 8000
```

Open **http://localhost:8000** (worker view: **http://localhost:8000/#/worker**). A prebuilt dashboard ships in
`frontend/dist`, so Flutter is only needed if you change the frontend.

### Requirements for development
* Python 3.11+
* Flutter 3.24+ with web support (developed on Flutter 3.50 / Dart 3.11)

### One command (API + dashboard on one port)

```bash
./scripts/run_demo.sh
```

This builds the dashboard if needed, installs the Python requirements and serves everything at
**http://localhost:8000**. The worker view is at **http://localhost:8000/#/worker**.

### Or run the parts separately

Backend (in local demo mode, no Firebase credentials needed):

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8000
```

API docs are at http://localhost:8000/docs.

Frontend (development):

```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api
```

Frontend (release build served by the backend):

```bash
cd frontend
flutter build web --release --no-web-resources-cdn
```

The backend serves `frontend/build/web` when it exists, otherwise the committed `frontend/dist`. After changing the frontend, refresh `frontend/dist` with the new build. `--no-web-resources-cdn` bundles CanvasKit,
and the Roboto font is bundled too, so the demo works without internet.

### Tests

```bash
cd backend && python -m pytest app/tests -q    # 33 tests
cd frontend && flutter analyze                  # static analysis
```

## Firebase Realtime Database (optional)

1. Create a Firebase project with a Realtime Database.
2. Download a service-account key (Project settings → Service accounts). **Do not commit it.**
3. In `backend/.env` set:
   ```
   HEATGUARD_STORAGE=firebase
   FIREBASE_CREDENTIALS=/absolute/path/to/service-account.json
   FIREBASE_DATABASE_URL=https://<project>-default-rtdb.<region>.firebasedatabase.app
   ```
4. Deploy the rules: `cd firebase && firebase deploy --only database`. To use the emulator instead, run
   `firebase emulators:start --only database` and set `FIREBASE_DATABASE_URL` to the emulator URL.

Without credentials HeatGuard falls back to `backend/data/local_store.json`, which mirrors the same tree.
If Firebase is unreachable, writes queue up. The sidebar shows the queue as "unsynced", and the Simulation Lab
can simulate a database outage.

> Firebase **Authentication** is not wired up in this MVP. Roles are passed as an `X-HeatGuard-Role` demo
> header. The RTDB rules already expect `role` / `crew_id` custom claims. See `docs/data_governance.md`.

## External / ESP32 stations

`POST /api/sensors/ingest` accepts readings from any station, with an optional `X-HeatGuard-Key` if
`HEATGUARD_INGEST_KEY` is set. `simulator/simulator.py` is a standalone client that uses this path:

```bash
cd backend && HEATGUARD_SIM_AUTOSTART=false uvicorn app.main:app --port 8000
```

```bash
python simulator/simulator.py --worksite ws_kumasi_tower --scenario increasing_heat --interval 3
```

## Project structure

```
heatguard/
├── backend/app/
│   ├── main.py                    FastAPI app (+ serves the dashboard build)
│   ├── api/routes/                simulation, sensors, assessments, alerts, crews, interventions, reports, system
│   ├── core/                      config (env vars), security (demo roles, ingest key)
│   ├── guidelines/niosh_2016.json documented assessment configuration
│   ├── schemas/                   Pydantic models
│   ├── sensors/                   SensorSource interface + simulated adapter
│   ├── services/                  wbgt_calculator, data_validation, guideline, risk_engine, alert_engine,
│   │                              intervention_service, simulation_service, heatguard_service,
│   │                              reports_service, evaluation_service
│   ├── repositories/              repository + Firebase / local JSON backends
│   └── tests/
├── simulator/                     heatguard_sim (physics, scenarios, station) + standalone simulator.py
├── frontend/lib/                  app shell, core (theme, severity, l10n), models, services, providers,
│                                  widgets, features/{overview,monitoring,crews,alerts,interventions,
│                                  simulation,reports,settings,worker}
├── firebase/                      database.rules.json, firebase.json
├── docs/                          architecture, risk_methodology, data_governance, evaluation, demo_script
└── scripts/run_demo.sh
```

## Documentation

* [Architecture](docs/architecture.md)
* [Risk methodology](docs/risk_methodology.md): guideline, equations, categories, missing data
* [Data governance](docs/data_governance.md)
* [Evaluation](docs/evaluation.md): method, metric definitions, results
* [5-minute demo script](docs/demo_script.md)

## Limitations

* All data are synthetic. Nothing has been validated in the field.
* NIOSH RAL/REL apply to healthy workers. Metabolic rates are category estimates, and screening is a
  conservative approximation of a 1-hour TWA.
* The simulator's physics is a consistency heuristic, not a validated thermal model.
* The demo role header is not authentication. Translations (e.g. Twi) need qualified native-speaker review
  before use.
* Not a medical device. It does not diagnose, predict illness or clear workers to resume work.

## Acceptance checklist

- [x] Backend starts; Flutter Web app builds and runs against it
- [x] Firebase integration (Admin SDK repository, rules), with local demo store fallback
- [x] Simulator generates readings; 5 scenarios selectable; WBGT formulas unit-tested
- [x] Workload / acclimatization / clothing / work-rest changes reassess immediately
- [x] Structured, explained assessments; missing data → incomplete; sensor and network failure handled safely
- [x] Alerts generated, acknowledged, escalated, resolved with notes; interventions recorded with follow-up
- [x] Live dashboard, trends, interactive Simulation Lab, reports, CSV export, SIMULATED labelling
- [x] Methodology documentation; 33 unit/API tests; evaluation suite (8 cases / 22 checks passing)
