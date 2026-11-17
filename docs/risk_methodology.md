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

## 9. Limitations

* RAL/REL apply to healthy workers. Individual susceptibility is not assessed.
* Metabolic rates are category estimates.
* Screening is conservative and is not an exact 1-hour TWA.
* WBGT-based limits are of limited validity for vapour-barrier and encapsulating ensembles.
* All demo data are **SIMULATED**. Thresholds and outputs have not been field-validated.
