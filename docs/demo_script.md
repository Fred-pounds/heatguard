# Five-minute demonstration script

**Before judges arrive**
1. `./scripts/run_demo.sh` (or start the backend and frontend separately; see README).
2. Open http://localhost:8000. In **Simulation Lab** click **Reset**, tick *also delete history*, and confirm.
   The station restarts on Scenario A. Let it run for about 30 s so the charts have data.
3. Open the worker view in a second tab or on a phone: http://localhost:8000/#/worker → *Concrete Crew A*.

| Time | Step | Where | What to say / show |
|---|---|---|---|
| 0:00 | 1 | **Overview** | "Adum Tower is a simulated construction site in Kumasi with one virtual WBGT station. Everything here is labelled SIMULATED and comes from the backend, nothing is hard-coded." Show the KPI cards, WBGT trend and crew status. |
| 0:30 | 2 | **Live Monitoring** | The current Tdb / Tnwb / Tg / RH readings and the WBGT formula actually used (outdoor, direct sun). Sensor health, last update and the 60-min mean. |
| 1:00 | 3 | **Simulation Lab → Work context** | Pick **Concrete Crew A**: heavy work (~414 W), acclimatized → **REL** 26.6 °C. Point at the limit table: limits for every work/rest regime. |
| 1:20 | 4 | Work context | Change acclimatization to **Not acclimatized**. The assessment switches to the **RAL** (≈ 23 °C) and the explanation says why. *Unknown* is treated the same way: never as acclimatized. |
| 1:45 | 5 | **Environmental conditions** | Air temperature **+6 °C**, solar load **130 %**, **Apply** (or pick Scenario C). Set speed to 2×. |
| 2:05 | 6 | Resulting assessment | The category climbs. Read the explanation and contributing factors (radiant heat, workload, RAL). The recommendations include the *required* work/rest regime. |
| 2:30 | 7 | Alerts panel / **Alerts** | An alert has been generated (bell badge). Open it to see the explanation, recommendations and history. **Acknowledge**. |
| 2:50 | 8 | **Record intervention** | Action *Work-rest rotation*, regime **15 work / 45 rest**, workload **Moderate**, note "shaded rest at stair core". The crew is reassessed at once and the category drops. |
| 3:15 | 9 | **Interventions** | Timeline: Before → follow-ups. Explain that the alert is **not auto-cleared**: it needs sustained improvement and then a supervisor resolves it with a note. |
| 3:35 | 10 | **Simulation Lab → Failure injection** | Trigger a **Globe** sensor failure. Within one tick the assessment becomes **Assessment unavailable** (purple, never green), a site-level data-quality alert appears and the chart shows a gap, not a guess. |
| 4:05 | 11 | Network failure | **Trigger network failure**. After ~15 s the backend reports stale data and readings queue at the edge. **Restore** to back-fill the queued readings, labelled *late sync*. |
| 4:30 | 12 | **Reports** | **Run evaluation**: 8 synthetic cases, 22 checks, lead time, false/missed alerts, **0 false-safe minutes**. Point at the disclaimer. Export a CSV. |
| 4:50 | 13 | Worker view | Plain-language, crew-only notice with water and emergency guidance. No individual tracking. |

**Back-up:** if anything stalls, **Step +1 min** advances the simulation manually even while paused.
