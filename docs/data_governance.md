# Responsible data governance

Worker protection takes priority over productivity optimisation.

## Principles as implemented

| Principle | Implementation in this prototype |
|---|---|
| **Data minimisation** | Only crew-level context is stored (crew name, zone, worker *count*, workload, clothing, acclimatization, shift). No worker names, IDs, locations or health data. |
| **Consent** | No personal or physiological signals are collected. `/individual_health` is reserved and locked in the RTDB rules. Any future signal must be optional, with informed consent that can be withdrawn. |
| **Access control** | Supervisor/admin roles see crew-level data. The worker view (`/api/worker/{crew_id}`) returns only that crew's notice, in plain language. The RTDB rules (`firebase/database.rules.json`) enforce role claims and per-crew worker reads, and give clients no writes. The demo uses an `X-HeatGuard-Role` header in place of Firebase Authentication; replace it before field use. |
| **Non-punitive use** | There is no individual scoring, ranking or productivity metric. Reports are about conditions, response times and data quality. |
| **Transparency** | Each assessment exposes the data used, method, guideline, missing information, contributing factors, recommendations and limitations (see `risk_methodology.md`). |
| **Data retention** | Configurable: `HEATGUARD_RETAIN_READINGS` (per site), `HEATGUARD_RETAIN_ASSESSMENTS` (rolling windows enforced by the repository, oldest deleted from the database as well) and `HEATGUARD_RETENTION_DAYS` (documented policy for archival jobs). Alerts and interventions are kept as the safety record. |
| **No medical diagnosis** | No heat-illness prediction. Symptom guidance is to escalate to qualified personnel. The system never clears anyone to resume work. |
| **Simulated data labelling** | Every reading has `data_origin`. The UI shows SIMULATED badges throughout, and CSV exports carry a SIMULATED header and column. |

## Before any field deployment

1. Replace demo roles with Firebase Authentication custom claims (`role`, `crew_id`) and deploy the rules.
2. Run a data-protection impact assessment. In the UAE, personal data are governed by Federal Decree-Law No. 45 of 2021 on
   the Protection of Personal Data (PDPL), or by the applicable free-zone regime (for example ADGM in Abu Dhabi).
3. Have the worker messages translated into the languages of the workforce (for example Arabic, Urdu, Hindi,
   Malayalam, Bengali and Tagalog) and reviewed by qualified native speakers. The translation slots are
   deliberately empty.
4. Agree in writing with worker representatives that the data cannot be used for discipline.
5. Validate instruments, thresholds and workflows in the field with OHS professionals.
