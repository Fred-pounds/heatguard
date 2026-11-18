# Five-minute demonstration

The easiest way to present is the built-in **Demo guide** (button in the top bar). It lists the 13 steps below,
shows a talk track for each one, and its button performs the step and opens the right screen. You can also click
through by hand; the steps work the same way.

**Before judges arrive**
1. Start HeatGuard (`./scripts/run_demo.sh`, or the deployed link) and open it in a desktop browser at 1440 px wide or more.
2. Open **Demo guide** and press **Prepare**. This resets the simulation, clears history and builds 30 minutes of readings.
3. Optional: open the worker view on a phone: `<url>/#/worker`, then choose *Concrete Crew A*.

| # | Step | Guide button | What it shows |
|---|---|---|---|
| 1 | Prepare a clean demo | Prepare | Clean state, normal conditions at the Adum Tower construction site |
| 2 | Introduce the site | Show overview | Plain status, crews needing attention, WBGT trend; everything labelled simulated |
| 3 | Show live conditions | Open live monitoring | Air, wet-bulb and globe readings; WBGT outdoor formula |
| 4 | Select a crew doing heavy work | Open Concrete Crew A | Assessment panel: status, gauge vs limit, plain explanation, numbered actions |
| 5 | Change acclimatization | Set "not acclimatized" | Limit switches from REL to the lower RAL; status goes to Elevated |
| 6 | Increase the heat | Raise heat | +4 °C and stronger sun; status rises to High; required work/rest schedule shown |
| 7 | A protective alert is raised | Open alerts | Explanation, recommended actions, duplicate suppression, no auto-clear |
| 8 | Acknowledge the alert | Acknowledge Crew A alert | Acknowledgement recorded in the alert history |
| 9 | Record an intervention | Record rotation | 15/45 rotation and lighter tasks; immediate reassessment (High to Routine) |
| 10 | Trigger a sensor failure | Break the globe sensor | "Assessment unavailable" (purple, never green), gap in the chart, data alert |
| 11 | Restore the sensor | Restore | Assessments resume; the alert stays open for supervisor review |
| 12 | Show the evaluation | Run evaluation | 8 synthetic cases, 22 checks, 0 "false safe" minutes, with the disclaimer |
| 13 | Worker view | Open worker view | Crew-only, plain-language notice with water, rest and emergency guidance |

**Back-up:** if the network is slow, every step still works offline on a laptop: the dashboard and fonts are
bundled and no external APIs are used. In the **Simulation Lab**, **+1 min** advances time manually.

**Likely judge questions**
* *Where do the thresholds come from?* NIOSH 2016 REL/RAL equations, ISO 7243 metabolic classes and documented
  clothing adjustments, all in `backend/app/guidelines/niosh_2016.json`. The only site-policy number (the caution
  margin) is labelled as one.
* *Is it machine learning?* No, by design. The rules are transparent and every output explains itself.
* *What about real sensors?* `POST /api/sensors/ingest` takes readings from any station, such as an ESP32.
  `simulator/simulator.py` uses exactly that path.
* *Is the data stored?* Yes: Firebase Realtime Database, verified against the official emulator, or a local JSON
  store in demo mode.
