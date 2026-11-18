# HeatGuard backend (FastAPI)

```bash
pip install -r requirements.txt
cp .env.example .env        # local demo mode by default; see comments for Firebase
uvicorn app.main:app --reload --port 8000
python -m pytest app/tests -q
```

* Interactive API docs: http://localhost:8000/docs
* The in-process simulator starts automatically (`HEATGUARD_SIM_AUTOSTART`), seeds two demo worksites and
  six crews, and warms up 30 simulated minutes of history.
* Write endpoints require the `supervisor` or `admin` role (`X-HeatGuard-Role` demo header; defaults to
  supervisor). `worker` callers get read-only, crew-scoped endpoints under `/api/worker`.

Key endpoints:

| Area | Endpoints |
|---|---|
| System | `GET /api/health`, `GET /api/meta`, `GET /api/overview` |
| Crews | `GET/POST /api/crews`, `PUT/DELETE /api/crews/{id}`, `GET /api/worksites` |
| Sensors | `GET /api/sensors/readings?worksite_id=`, `GET /api/sensors/latest`, `POST /api/sensors/ingest` |
| Assessments | `GET /api/assessments/latest`, `GET /api/assessments/history`, `GET /api/assessments/{crew_id}` |
| Alerts | `GET /api/alerts?status=active`, `POST /api/alerts/{id}/acknowledge`, `POST /api/alerts/{id}/resolve` |
| Interventions | `GET/POST /api/interventions`, `POST /api/interventions/{id}/complete` |
| Simulation | `POST /api/simulation/{start,pause,resume,stop,step,jump,reset,scenario,speed,adjust,override,sensor-failure,sensor-restore,network-failure,network-restore,database-outage}` |
| Reports | `GET /api/reports/summary`, `GET /api/reports/export?kind=summary|readings|assessments|alerts|interventions|evaluation`, `POST /api/evaluation/run` |
| Worker | `GET /api/worker/crews`, `GET /api/worker/{crew_id}` |

See `../docs/` for the methodology and architecture.
