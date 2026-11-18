# Responsible data governance

Worker protection takes priority over productivity optimisation.

## Principles as implemented

| Principle | Implementation in this prototype |
|---|---|
| **Data minimisation** | Crew-level context (crew name, zone, worker *count*, workload, clothing, acclimatization, shift). Wearable participants are pseudonymous badges with an age band; no names, employee numbers or locations. |
| **Consent** | Wearable sharing is opt-in per worker in the worker app, with a plain-language notice (purpose, who sees what, retention, no disciplinary use). Withdrawal is one tap and deletes held signals and the age band immediately. No signals are generated or stored without consent. |
| **Role separation** | Supervisors see crew-level counts and the badge to check on. Individual signal values and symptoms are visible only to the **OHS role** (occupational health officer or first aider), which also records clinical outcomes. Enforced in the API and in the RTDB rules (`workers`, `worker_status`, `escalations` are OHS-only). |
| **Retention of health data** | Raw signals are kept in memory for at most 2 hours and never persisted. Only status flags and escalation records (the safety record) are stored. |
| **Access control** | Supervisor/admin roles see crew-level data; the OHS role also sees individual signals and symptoms. The worker app (a separate application) uses only the worker endpoints: `/api/worker/{crew_id}` returns that crew's notice in plain language, and `/api/worker/me/{id}` returns a badge's own consent and signals. The RTDB rules (`firebase/database.rules.json`) enforce role claims and per-crew worker reads, and give clients no writes. The demo uses an `X-HeatGuard-Role` header in place of Firebase Authentication; replace it before field use. |
| **Non-punitive use** | There is no individual scoring, ranking or productivity metric. Reports are about conditions, response times and data quality. |
| **Transparency** | Each assessment exposes the data used, method, guideline, missing information, contributing factors, recommendations and limitations (see `risk_methodology.md`). |
| **Data retention** | Configurable: `HEATGUARD_RETAIN_READINGS` (per site), `HEATGUARD_RETAIN_ASSESSMENTS` (rolling windows enforced by the repository, oldest deleted from the database as well) and `HEATGUARD_RETENTION_DAYS` (documented policy for archival jobs). Alerts and interventions are kept as the safety record. |
| **No medical diagnosis** | No heat-illness prediction. Symptom guidance is to escalate to qualified personnel. The system never clears anyone to resume work. |
| **Simulated data labelling** | Every reading has `data_origin`. The UI shows SIMULATED badges throughout, and CSV exports carry a SIMULATED header and column. |

## Before any field deployment

1. Replace demo roles with Firebase Authentication custom claims (`role`, `crew_id`) and deploy the rules.
2. Run a data-protection impact assessment. In the UAE, personal data are governed by Federal Decree-Law No. 45 of 2021 on
   the Protection of Personal Data (PDPL), or by the applicable free-zone regime (for example ADGM in Abu Dhabi).
3. Have the draft Arabic, Urdu and Hindi worker messages reviewed by qualified native speakers, and add the other
   languages of the workforce (for example Malayalam, Bengali and Tagalog). The app marks the drafts as such.
4. Agree in writing with worker representatives that the data cannot be used for discipline.
5. Validate instruments, thresholds and workflows in the field with OHS professionals.
