# Evaluation (synthetic software verification)

> **Scope.** These results verify that the software behaves as specified on **synthetic** data. They are
> **not** clinical validation, not predictive accuracy for heat illness, and not evidence of real-world
> prevention. Field validation with calibrated instruments and OHS professionals is required.

## Method

`backend/app/services/evaluation_service.py`. You can run it from **Reports → Run evaluation** or `POST /api/evaluation/run`.

* Each case runs a scenario through the **same** ingestion → validation → WBGT → assessment → alert pipeline
  used live, with an isolated in-memory repository and a virtual clock (1 simulated minute = 3 s).
* **Reference outcome:** the same configured rules applied to the simulator's noise-free ground truth
  (no noise, faults or outages).
* **System outcome:** what HeatGuard produced from noisy, faulty or delayed readings.

### Metric definitions

| Metric | Definition |
|---|---|
| Alert lead time | Minutes between the first heat alert (Caution or above) and the first minute the reference exceeds the applicable limit (≥ Elevated). Positive means early. |
| False-alarm rate | Share of alerts whose severity the reference does not reach within 30 simulated minutes. |
| Missed-alert rate | Share of reference limit-exceedance minutes with no open heat or data alert. |
| False-safe minutes | Minutes in which data were missing, invalid or stale but the system showed Routine. **Must be 0.** |
| Assessment completeness | Share of minutes with a valid assessment. |
| Sensor data availability | Share of minutes with a fresh, fully valid reading. |
| Stale detection / recovery | Seconds from outage start to "unavailable", and from restore to a valid assessment again. |

Operational metrics (acknowledgement time, intervention completion rate, sensor availability, missing-data
frequency, connectivity recovery time, unresolved alerts) are computed live in **Reports** from stored data.

## Results (seeded run, 8 cases, 22 checks, all passed)

| Case | Scenario | Ref. peak | System peak | Lead (min) | False alarm | Missed | False-safe min | Completeness | Checks |
|---|---|---|---|---|---|---|---|---|---|
| Normal conditions - light work, acclimatized | normal | routine | routine | – | 0% | 0% | 0 | 100% | 2/2 |
| Increasing heat - moderate work, acclimatized | increasing_heat | critical | critical | 24 | 0% | 0% | 0 | 100% | 3/3 |
| Heavy workload - high-radiant construction site | construction_radiant | critical | critical | 0 | 0% | 0% | 0 | 100% | 2/2 |
| Increasing heat - unacclimatized crew | increasing_heat | critical | critical | 10 | 0% | 0% | 0 | 100% | 3/3 |
| Missing data - unknown workload | normal | unavailable | unavailable | – | 0% | 0% | 0 | 0% | 2/2 |
| Sensor failure - scheduled probe faults | sensor_failure | high | high | 47 | 0% | 0% | 0 | 62% | 4/4 |
| Network failure - 20 min uplink outage during rising heat | increasing_heat | critical | critical | 24 | 0% | 0% | 0 | 92% | 4/4 |
| Industrial indoor - heavy work in coveralls | industrial_indoor | high | high | 0 | 0% | 0% | 0 | 100% | 2/2 |

Network-failure case: the outage was detected as stale data after 18 s, a valid assessment returned 3 s after
the uplink was restored, and all 20 queued readings were back-filled. In the same rising-heat scenario the unacclimatized crew was alerted
at minute 0 (conditions were already within the caution margin of the lower RAL), while the acclimatized crew
was alerted at minute 57, 24 minutes before its REL was exceeded at minute 81. This difference comes from RAL < REL.

### Interpreting these numbers honestly

* The synthetic sensor noise is small (σ ≈ 0.15 °C), so 0 % false/missed alarms mainly shows that the rules,
  the caution margin and the duplicate suppression are consistent. It does **not** show real-world accuracy.
  Real instruments have larger errors, lag (globe response time ~15–20 min) and siting effects.
* A lead time of 0 means conditions already exceeded the limit when the scenario started.
* The "reference" uses the same rules as the system, so this checks *implementation correctness and
  robustness to data problems*, not whether the NIOSH limits are the right limits for a given workforce.

## Unit tests

`cd backend && python -m pytest app/tests -q` runs 33 tests (plus a Firebase-emulator integration test when the emulator is running) covering WBGT formulas and formula selection,
the NIOSH equations, category boundaries, work/rest effects, RAL for unknown acclimatization, clothing
adjustment, rolling-mean retention, missing, invalid, implausible and stale data, incomplete context, duplicate
suppression, no auto-clear, resolution rules, site-level data alerts, intervention reassessment, edge
buffering/back-fill, and an API smoke test that includes role checks and CSV export.
