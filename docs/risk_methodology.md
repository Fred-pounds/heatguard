# HeatGuard risk-assessment methodology

HeatGuard is a **decision-support prototype**. It does not diagnose heat illness, predict medical outcomes
or clear any worker to resume work. This document describes exactly how an assessment is produced, which
values come from documented guidance, and which are site-policy settings.

## 1. Guideline

| Item | Value |
|---|---|
| Guideline | NIOSH *Criteria for a Recommended Standard: Occupational Exposure to Heat and Hot Environments* |
| Edition | Revised Criteria 2016 |
| Publication | DHHS (NIOSH) Publication No. 2016-106 — https://www.cdc.gov/niosh/docs/2016-106/ |
| Licence | Work of the U.S. federal government; not subject to copyright in the U.S. |
| Configuration file | `backend/app/guidelines/niosh_2016.json` |

The engine (`backend/app/services/risk_engine.py`) reads every number from that JSON file. To use a different
guideline (e.g. a national standard or a licensed ACGIH TLV edition), add a new JSON file with the same
structure and set `HEATGUARD_GUIDELINE`. ACGIH TLVs were **not** bundled because they are licensed material.

## 2. WBGT

Implemented in `backend/app/services/wbgt_calculator.py` (unit-tested):

* Outdoors with direct solar load: `WBGT = 0.7·Tnwb + 0.2·Tg + 0.1·Tdb`
* Indoors, or outdoors without direct sun: `WBGT = 0.7·Tnwb + 0.3·Tg`

For an outdoor station that does not report solar status, the solar formula is used (missing information is
not assumed to mean shade). The simulator flags direct sun when irradiance is at least 120 W/m² (the WMO
sunshine-duration threshold).

## 3. Exposure limits

NIOSH 2016 limits, in °C-WBGT, as 1-hour time-weighted averages (M = metabolic rate, W):

* **REL** (acclimatized workers): `REL = 56.7 − 11.5·log10(M)`
* **RAL** (unacclimatized workers): `RAL = 59.9 − 14.1·log10(M)`

Selection:

| Acclimatization | Limit applied | Note |
|---|---|---|
| Acclimatized | REL | |
| Not acclimatized | RAL | |
| **Unknown** | **RAL** | Unknown is never treated as acclimatized. Confidence is marked *reduced*. |

### Metabolic rate (workload)

Representative values for the ISO 7243:2017 metabolic-rate classes (W/m² × 1.8 m² standard body surface):

| Workload | W/m² | M (W) |
|---|---|---|
| Rest | 65 | 117 |
| Light | 100 | 180 |
| Moderate | 165 | 297 |
| Heavy | 230 | 414 |
| Very heavy | 290 | 522 |

These are **category estimates**. Sites should replace them with task-specific estimates where available.
Workload `unknown` makes the assessment **incomplete**: no category is produced.

### Work/rest regimes

The 1-hour TWA metabolic rate for a regime is
`M_twa = (work_min · M_work + rest_min · M_rest) / 60`, with `M_rest` = the rest class (117 W) and rest assumed
to happen in the same thermal environment (the conservative case). The regimes are the ones NIOSH 2016 shows
alongside the RAL/REL curves: 60/0, 45/15, 30/30, 15/45.

### Clothing adjustment

The clothing adjustment value is added to the measured WBGT (°C-WBGT). The values are reproduced in NIOSH 2016
and the OSHA Technical Manual Sec. III Ch. 4, after Bernard and co-workers.

| Ensemble | Adjustment |
|---|---|
| Standard work clothing / long-sleeved woven / cloth coveralls | 0 |
| SMS polypropylene coveralls | +0.5 |
| Polyolefin coveralls | +1 |
| Double-layer woven clothing | +3 |
| Limited-use vapour-barrier coveralls | +11 (guidance cautions that WBGT assessment has limited validity) |
| **Specialized PPE (unspecified)** | **requires configuration**: the assessment is incomplete until an OHS professional sets a documented value |

Not all PPE has the same thermal effect, so HeatGuard never assigns an unverified value.

## 4. Screening WBGT

NIOSH limits apply to 1-hour TWAs. Readings arrive every simulated minute, so HeatGuard screens with

`screening WBGT = max(latest WBGT, rolling 60-minute mean WBGT)`
`effective WBGT = screening WBGT + clothing adjustment`

This means rising conditions are recognised immediately, and a single cooler reading cannot clear a concern.
It is more conservative than a strict TWA. That is a stated limitation, not a guideline value.

## 5. Risk categories (HeatGuard mapping)

Categories are defined by **which documented work/rest regime keeps the exposure within the applicable
limit**. They are not fixed WBGT thresholds.

| Category | Rule |
|---|---|
| Routine monitoring | Effective WBGT ≤ limit at the crew's current regime − caution margin |
| Caution | Within the caution margin of the limit at the current regime |
| Elevated | Limit exceeded at the current regime; a 45/15 regime would satisfy it |
| High | Only a 30/30 or 15/45 regime would satisfy it |
| Critical | Limit exceeded even at 15/45: work/rest scheduling alone cannot keep exposure within the guideline |
| Assessment unavailable | Required inputs missing, invalid or stale. **Never interpreted as low risk.** |

**Caution margin** (default 1.0 °C) is a **site-policy setting, not a NIOSH value**. It only controls how
early an "approaching the limit" caution appears.

Recording a work/rest rotation (intervention or crew edit) changes the crew's current regime. The next
assessment then uses the corresponding TWA metabolic rate, so the effect of the control is visible.

## 6. Explainability

Every assessment returns:

* `explanation`: a plain-language statement of conditions, crew context, limit and margin
* `contributing_factors`: each with direction (increases concern / reduces concern / uncertainty / neutral):
  environmental heat vs. limit, retained recent exposure, radiant heat (Tg − Tdb), humidity share of WBGT,
  workload, acclimatization, clothing, work/rest regime, extended shift, manual overrides
* `recommended_actions`: priority (routine / advised / required / urgent) and source
* `limit_details`: limit type and reason, M, TWA M, limits for every regime, clothing adjustment, measured,
  rolling and effective WBGT, margin
* `inputs_used`, `assessment_method`, `guideline_reference`, `limitations`
* `data_quality`: kept as three separate notions:
  * **measurement validity**: are the received values valid (range, plausibility, sensor status)?
  * **data completeness**: the fraction of required inputs present (WBGT components plus workload, clothing
    and acclimatization)
  * **assessment confidence**: a *qualitative* rating (`standard` / `reduced` / `not_assessable`) with reasons.
    It is **not** a probability.

## 7. Missing and invalid information

| Situation | Behaviour |
|---|---|
| Missing WBGT component | `incomplete` assessment, category `unavailable`, data-quality alert |
| Invalid value (out of range, sensor fault, −127 sentinel) | Same as missing |
| Implausible combination (Tnwb > Tdb + 1, Tg < Tdb − 5) | Component rejected → incomplete |
| No reading / stale reading (> `HEATGUARD_STALE_SECONDS`) | `unavailable`, last valid category shown as *historical* |
| Unknown workload or clothing | `incomplete` |
| Specialized PPE without a configured value | `incomplete` |
| Unknown acclimatization | Assessed with RAL; confidence reduced; completeness < 1 |

## 8. Recommendations

Recommendations follow NIOSH 2016 controls: water (about 1 cup every 15–20 min), shade or cool rest areas,
work/rest rotation at the regime the assessment requires, workload reduction, schedule changes, engineering
controls (shielding, ventilation) for indoor radiant heat, clothing review, the acclimatization schedule
(≤ 20 % exposure on day 1 for new workers, +20 %/day), and escalating symptoms to qualified personnel.
They come from the category plus the specific contributing factors, never from a single score.

## 9. UAE context (Abu Dhabi deployment)

**Midday break.** The UAE Ministry of Human Resources and Emiratisation (MoHRE) prohibits work under direct
sunlight and in open places from **12:30 to 15:00** during the summer period. In recent years that period has been
**15 June to 15 September**, set by an annual ministerial resolution. HeatGuard implements this as a separate,
configurable rule (`backend/app/guidelines/uae_midday_break.json`):

* It applies to **outdoor sites with direct solar load**. Indoor sites are not flagged.
* The site date and time come from the simulator, or, for real readings, from the timestamp converted to
  Gulf Standard Time (Asia/Dubai, UTC+4).
* When in force, the assessment gains a `regulatory_flags` entry, an **urgent** first action ("Stop outdoor work in
  direct sun") and a sentence in the explanation. One site-level "Midday break" alert is raised.
* It **does not change the NIOSH risk category**. It is a legal working-time rule, not a heat-stress limit, so the
  two are reported side by side.
* Exempt work (work that must technically continue, under MoHRE conditions) is described in the action text.
  Sites record their approved exemptions themselves.
* Verify the current year's resolution before relying on the dates. They are configuration, not code.

**Abu Dhabi OSH framework.** Sites regulated under the Abu Dhabi Occupational Safety and Health System
Framework (OSHAD-SF) should also apply its code of practice for working in the heat. Its thresholds are not
bundled here because they were not verified for this prototype. Add them as a guideline configuration file
(same structure as `niosh_2016.json`) once confirmed against the current edition.

**Climate.** Coastal humidity in Abu Dhabi often keeps the natural wet-bulb temperature high, which dominates
WBGT (70 % weight). The *Humid coastal morning* scenario shows high heat stress at air temperatures of only
33–37 °C.

## 10. Optional consented worker signals

* **Participation** is opt-in per worker from the worker app, with a plain-language notice covering purpose, who
  sees what, 2-hour retention, no disciplinary use, and withdrawal at any time. Withdrawal deletes held signals
  immediately and removes the age band.
* **Identity** is a pseudonymous badge (for example CA-02) linked to a device, with no names or employee numbers.
  The age band is collected only to apply the heart-rate threshold.
* **Criteria** come from NIOSH 2016's physiological monitoring guidance:
  * Heart rate sustained above **180 − age** (bpm) for 3 or more minutes. The upper bound of the age band is used,
    which is conservative.
  * Core temperature at or above **38.5 °C** for acclimatized crews, or **38.0 °C** otherwise. The wearable value is a
    device *estimate* and is labelled as such.
* **Output:** a "worker check" alert naming the badge for supervisors, with no values. Individual values are
  visible only to the **OHS role**. A missing or stale signal reverts that worker to the crew-level assessment.
* **Simulation:** the wearable physiology is a documented synthetic heuristic (`simulator/heatguard_sim/wearable.py`),
  not a validated model.

## 11. Symptom check-in and clinical escalation

Workers, co-workers or supervisors can report symptoms.

* **Emergency path:** confusion or slurred speech, fainting or collapse, hot dry skin or stopped sweating, or a
  seizure. These start the 998 emergency path with immediate cooling.
* **First-aid path:** other symptoms (dizziness, headache, nausea, cramps, heavy sweating, unusual tiredness)
  request a first-aid check.

Supervisors see the level and badge, without the symptoms, and can acknowledge or mark a responder as on the way.
Only the OHS role records the outcome: first aid given, clinic, ambulance, or observed. There is deliberately no
"cleared to work" outcome.

## 12. Trend outlook

A least-squares slope over the last 30 minutes of valid WBGT readings is projected forward, capped at 2 hours.
The projection is labelled and is not a weather forecast.

* **Early caution:** if a crew is still Routine but the projection reaches its limit within 30 minutes, the
  category becomes Caution, with the advice to move heavy tasks earlier or start rotation.
* **Midday-break countdown:** outdoor crews in the summer season get a countdown in the last hour before 12:30.

## 13. Field conditions

* **Wick plausibility:** natural wet-bulb must sit between the psychrometric wet-bulb (from temperature and RH,
  Stull 2011) minus 1.5 °C and plus 3.5 °C. Outside that range, the wick is treated as dry or fouled and the reading
  is rejected.
* **Dust:** a station dust index of 0.5 or more marks the globe and wick unreliable, because a dusty globe
  *under*-reads radiant heat (a hidden false-safe risk). A maintenance alert asks for cleaning.
* **Battery:** below 25% raises a maintenance alert. A dead station is detected as stale data. A wearable battery
  below 15% is flagged.

## 14. Limitations

* RAL/REL apply to healthy workers. Individual susceptibility is not assessed.
* Metabolic rates are category estimates.
* Screening is conservative and is not an exact 1-hour TWA.
* WBGT-based limits are of limited validity for vapour-barrier and encapsulating ensembles.
* All demo data are **SIMULATED**. Thresholds and outputs have not been field-validated.
