# Five-minute demonstration

The easiest way to present is the built-in **Demo guide** (button in the top bar). It lists the 18 steps below,
shows a talk track for each one, and its button performs the step and opens the right screen. You can also click
through by hand; the steps work the same way.

**Before judges arrive**
1. Open the live demo (https://heatguard-tsl5.onrender.com; it keeps itself awake) or run `./scripts/run_demo.sh`, and open it in a desktop browser at 1440 px wide or more.
2. Open **Demo guide** and press **Prepare**. This resets the simulation, clears history and builds 30 minutes of readings.
3. Optional: open the worker app on a phone: `https://heatguard-tsl5.onrender.com/worker/` (or `http://<laptop-ip>:8000/worker/` on the same Wi-Fi), choose a language, *Concrete Crew A* and badge *CA-02* with code `150392` (codes are listed for the OHS role under Worker health).

| # | Step | Guide button | What it shows |
|---|---|---|---|
| 1 | Prepare a clean demo | Prepare | Clean state, a November morning (cool season) at the Saadiyat Island tower site |
| 2 | Introduce the site | Show overview | Plain status, crews needing attention, WBGT trend; everything labelled simulated |
| 3 | Show live conditions | Open live monitoring | Air, wet-bulb and globe readings; WBGT outdoor formula |
| 4 | Select a crew doing heavy work | Open Concrete Crew A | Assessment panel: status, gauge vs limit, plain explanation, numbered actions |
| 5 | Change acclimatization | Set "not acclimatized" | Limit switches from REL to the lower RAL; status goes to Elevated |
| 6 | Increase the heat | Raise heat | +4 °C and stronger sun; status rises to High; required work/rest schedule shown |
| 7 | A protective alert is raised | Open alerts | Explanation, recommended actions, duplicate suppression, no auto-clear |
| 8 | Acknowledge the alert | Acknowledge Crew A alert | Acknowledgement recorded in the alert history |
| 9 | Record an intervention | Record rotation | 15/45 rotation and lighter tasks; immediate reassessment (High to Routine) |
| 10 | Wearable strain, with consent | Simulate strain on CA-02 | Consented worker's sustained high heart rate: supervisor sees "check on badge CA-02", never the values |
| 11 | A worker reports symptoms | Report dizziness (Rebar B) | First-aid escalation raised from the worker app; emergency signs would trigger 998 |
| 12 | OHS view: who sees what | Switch to OHS role | Symptoms and signal values appear only for the OHS role, which records the outcome |
| 13 | Shamal dust storm | Start dust event | Fouled globe and wick detected: maintenance alert, "unavailable", never green |
| 14 | Clean the station | Clean station | Assessments resume; battery failure is handled the same way |
| 15 | Plan the shift | Open the shift plan | July morning: per crew, when heavy work fits, when rotation must start, when strenuous work must stop, midday break |
| 16 | UAE midday break | Jump to 12:35 in July | Compliance flag and "Midday break" alert: no outdoor work in direct sun 12:30-15:00, 15 Jun-15 Sep |
| 17 | Show the evaluation | Run evaluation | 13 synthetic cases (incl. dust, battery, worker strain, midday break), 35 checks, 0 "false safe" minutes |
| 18 | Worker app | Open worker app | The separate app workers carry: heat level, what to do, read aloud, My health (consent, badge code), Emergency (998 call) |

**Back-up:** if the network is slow, every step still works offline on a laptop: the dashboard and fonts are
bundled and no external APIs are used. In the **Simulation Lab**, **+1 min** advances time manually.

**Likely judge questions**
* *Where do the thresholds come from?* NIOSH 2016 REL/RAL equations, ISO 7243 metabolic classes and documented
  clothing adjustments, all in `backend/app/guidelines/niosh_2016.json`. The only site-policy number (the caution
  margin) is labelled as one.
* *Is it machine learning?* No, by design. The rules are transparent and every output explains itself.
* *What about real sensors?* `POST /api/sensors/ingest` takes readings from any station, such as an ESP32.
  `simulator/simulator.py` uses exactly that path.
* *Is it adapted to the UAE?* Yes: Abu Dhabi climate scenarios (including humid coastal mornings), the MoHRE
  midday break as a configurable compliance rule, Gulf Standard Time, the 998 ambulance number, and language
  slots for the UAE workforce. The OSHAD-SF heat code thresholds are a configuration slot, pending verification.
* *Is the data stored?* Yes: Firebase Realtime Database, verified against the official emulator, or a local JSON
  store in demo mode.
