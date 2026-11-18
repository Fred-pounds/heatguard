"""Explainable occupational heat-risk assessment engine.

Independent of storage, transport and the simulator: give it an environmental
reading, the work context and the guideline, and it returns a structured,
explained assessment. Missing information is never interpreted as low risk.
"""
from __future__ import annotations

from dataclasses import dataclass

from ..schemas.assessment import (
    Assessment,
    ContributingFactor,
    DataQuality,
    LimitDetails,
    RecommendedAction,
)
from ..schemas.common import new_id, now_iso
from ..schemas.crew import Crew, Worksite
from ..schemas.sensor import SensorReading
from .guideline import CATEGORY_LEVELS, REGIME_CATEGORY, Guideline
from .regulatory import MiddayBreak
from .wbgt_calculator import MissingComponentError, compute_wbgt, uses_solar_formula

CATEGORY_LABELS = {
    "routine": "Routine monitoring",
    "caution": "Caution",
    "elevated": "Elevated",
    "high": "High",
    "critical": "Critical",
    "unavailable": "Assessment unavailable",
}
WORKLOAD_LABELS = {"rest": "rest", "light": "light", "moderate": "moderate", "heavy": "heavy", "very_heavy": "very heavy"}
NIOSH = "NIOSH 2016"
SYMPTOM_ESCALATION = RecommendedAction(
    action="Escalate symptoms to qualified personnel",
    detail="Any worker reporting or showing symptoms such as dizziness, confusion, nausea, headache, cramps or fainting "
    "must stop work and be referred to trained first-aid or medical personnel; follow the site emergency procedure. "
    "HeatGuard does not diagnose heat illness and never clears a worker to resume work.",
    priority="required",
    source=NIOSH,
)


@dataclass
class AssessmentContext:
    worksite: Worksite
    crew: Crew
    reading: SensorReading | None
    reading_age_seconds: float | None
    stale_after_seconds: float
    rolling_mean_wbgt: float | None = None
    last_valid_category: str | None = None
    last_valid_time: str | None = None


class RiskEngine:
    def __init__(self, guideline: Guideline, midday_break: MiddayBreak | None = None):
        self.g = guideline
        self.midday = midday_break

    # ------------------------------------------------------------------ regulation
    def _regulatory_flags(self, site: Worksite, r: SensorReading | None, solar: bool) -> list[dict]:
        """UAE midday break: outdoor work in direct sun is not permitted in the restricted window."""
        if self.midday is None or r is None or site.environment != "outdoor" or not solar:
            return []
        date, clock = self.midday.site_date_time(r.sim_date, r.sim_clock, r.timestamp)
        return [self.midday.flag()] if self.midday.in_force(date, clock) else []

    def _apply_regulation(self, a: Assessment, flags: list[dict]) -> Assessment:
        if not flags:
            return a
        f = flags[0]
        end = self.midday.data["window_end"] if self.midday else "15:00"
        a.regulatory_flags = flags
        a.contributing_factors.insert(0, ContributingFactor(factor=f["title"], detail=f["detail"], direction="increases_concern"))
        a.recommended_actions.insert(0, RecommendedAction(
            action="Stop outdoor work in direct sun (midday break)",
            detail=f"Move the crew to shade or indoor work until {end}. {f['exemptions']}",
            priority="urgent", source=f["authority"]))
        a.explanation += f" The UAE midday break is in force: outdoor work in direct sun is not permitted until {end}."
        return a

    # ================================================================== public
    def assess(self, ctx: AssessmentContext) -> Assessment:
        crew, site, r = ctx.crew, ctx.worksite, ctx.reading
        factors: list[ContributingFactor] = []
        missing: list[str] = []
        unknown: list[str] = []
        confidence_reasons: list[str] = []

        # ------------------------------------------------ environmental data
        stale = ctx.reading_age_seconds is not None and ctx.reading_age_seconds > ctx.stale_after_seconds
        validity = r.validation.measurement_validity if r else "no_data"
        solar = uses_solar_formula(site.environment, r.direct_solar if r else None)
        required_env = ["natural_wet_bulb", "globe_temperature"] + (["dry_bulb"] if solar else [])
        env_values: dict[str, float | None] = {}
        if r is None:
            missing.append("environmental reading (no data received)")
        else:
            invalid = {i.field: i for i in r.validation.issues}
            for f in required_env:
                if f in r.validation.valid_fields:
                    env_values[f] = getattr(r, f)
                else:
                    env_values[f] = None
                    issue = invalid.get(f)
                    missing.append(f"{f.replace('_', ' ')} ({issue.issue if issue else 'missing'})")
            if stale:
                missing.append(f"current environmental data (last reading {ctx.reading_age_seconds:.0f}s old)")

        # ------------------------------------------------ work context
        metabolic = self.g.metabolic_rate(crew.workload) if crew.workload != "unknown" else None
        if metabolic is None:
            missing.append("workload category")
        clothing = self.g.clothing(crew.clothing) if crew.clothing != "unknown" else None
        caf: float | None = None
        if clothing is None:
            missing.append("clothing category")
        elif clothing.get("caf") is None:
            missing.append(f"clothing adjustment for '{clothing['label']}' (requires configuration by OHS professional)")
        else:
            caf = float(clothing["caf"])
        if crew.acclimatization == "unknown":
            unknown.append("acclimatization status")
            confidence_reasons.append("Acclimatization status unknown: more protective RAL applied.")

        total_inputs = len(required_env) + 3
        present = sum(1 for f in required_env if env_values.get(f) is not None) + (metabolic is not None) + (caf is not None) + (
            crew.acclimatization != "unknown"
        )
        if stale or r is None:
            present -= sum(1 for f in required_env if env_values.get(f) is not None)
        completeness = round(max(0, present) / total_inputs, 2)

        if r is not None and r.manual_override:
            confidence_reasons.append(f"Manually overridden inputs: {', '.join(r.manual_override)}.")
        if r is not None and r.late_sync:
            confidence_reasons.append("Reading was delivered late after a connectivity outage.")
        if r is not None and r.validation.issues and not missing:
            confidence_reasons.append("Some non-WBGT sensor values were invalid or missing.")

        inputs_used = self._inputs_used(site, crew, r, metabolic, caf, solar)

        # ------------------------------------------------ cannot assess
        if missing:
            env_missing = r is None or stale or any(env_values.get(f) is None for f in required_env)
            status = "unavailable" if (r is None or stale) else "incomplete"
            dq = DataQuality(
                measurement_validity="no_data" if r is None else validity,
                data_completeness=completeness,
                missing_inputs=missing,
                unknown_inputs=unknown,
                stale=stale,
                environmental_data_available=not env_missing,
                reading_age_seconds=ctx.reading_age_seconds,
                assessment_confidence="not_assessable",
                confidence_reasons=confidence_reasons + ["Required inputs are missing; no risk category can be assigned."],
            )
            wbgt_val = None
            if r is not None and not stale and r.wbgt is not None and not env_missing:
                wbgt_val = r.wbgt
            return self._apply_regulation(self._incomplete(ctx, status, dq, missing, env_missing, inputs_used, wbgt_val),
                                          self._regulatory_flags(site, r, solar))

        # ------------------------------------------------ compute
        assert r is not None and metabolic is not None and caf is not None
        wb = compute_wbgt(env_values.get("natural_wet_bulb"), env_values.get("globe_temperature"),
                          env_values.get("dry_bulb"), site.environment, r.direct_solar)
        measured = wb.value
        screening = max(measured, ctx.rolling_mean_wbgt) if ctx.rolling_mean_wbgt is not None else measured
        effective = round(screening + caf, 2)
        limit_type = self.g.limit_type_for(crew.acclimatization)
        regime_limits = {
            rid: self.g.limit(limit_type, self.g.twa_metabolic_rate(metabolic, rid)) for rid in self.g.regime_ids
        }
        current = crew.work_rest_regime
        l_cur = regime_limits[current]
        margin = round(l_cur - effective, 2)

        required_regime: str | None = None
        if effective <= l_cur:
            category = "routine" if margin >= self.g.caution_margin else "caution"
        else:
            idx = self.g.regime_ids.index(current)
            for rid in self.g.regime_ids[idx + 1:]:
                if effective <= regime_limits[rid]:
                    required_regime = rid
                    break
            category = REGIME_CATEGORY[required_regime] if required_regime else "critical"

        limit_reason = {
            "acclimatized": "Crew recorded as acclimatized: Recommended Exposure Limit (REL) applies.",
            "not_acclimatized": "Crew not acclimatized: Recommended Alert Limit (RAL) applies.",
            "unknown": "Acclimatization unknown: RAL applied as the protective default (unknown is not treated as acclimatized).",
        }[crew.acclimatization]

        details = LimitDetails(
            limit_type=limit_type,  # type: ignore[arg-type]
            limit_reason=limit_reason,
            metabolic_rate_w=metabolic,
            twa_metabolic_rate_w=round(self.g.twa_metabolic_rate(metabolic, current), 1),
            current_regime=current,
            limit_at_current_regime=l_cur,
            required_regime=required_regime,
            regime_limits=regime_limits,
            clothing_adjustment=caf,
            measured_wbgt=measured,
            rolling_mean_wbgt=round(ctx.rolling_mean_wbgt, 2) if ctx.rolling_mean_wbgt is not None else None,
            screening_wbgt=round(screening, 2),
            effective_wbgt=effective,
            margin_to_limit=margin,
            caution_margin=self.g.caution_margin,
        )

        factors = self._factors(site, crew, r, details, metabolic, clothing, solar)
        confidence = "reduced" if confidence_reasons else "standard"
        dq = DataQuality(
            measurement_validity=validity,
            data_completeness=completeness,
            missing_inputs=[],
            unknown_inputs=unknown,
            stale=False,
            reading_age_seconds=ctx.reading_age_seconds,
            assessment_confidence=confidence,  # type: ignore[arg-type]
            confidence_reasons=confidence_reasons,
        )
        explanation = self._explain(category, crew, details, solar, site)
        actions = self._recommend(category, crew, details, clothing, solar, site)
        inputs_used["wbgt_formula"] = wb.formula
        return self._apply_regulation(Assessment(
            assessment_id=new_id("asm"),
            timestamp=now_iso(),
            worksite_id=site.worksite_id,
            crew_id=crew.crew_id,
            crew_name=crew.name,
            reading_id=r.reading_id,
            sim_clock=r.sim_clock,
            assessment_status="valid",
            risk_category=category,  # type: ignore[arg-type]
            risk_level=CATEGORY_LEVELS[category],
            wbgt=measured,
            effective_wbgt=effective,
            contributing_factors=factors,
            explanation=explanation,
            recommended_actions=actions,
            data_quality=dq,
            data_completeness=completeness,
            inputs_used=inputs_used,
            limit_details=details,
            assessment_method=(
                f"{limit_type} for {WORKLOAD_LABELS[crew.workload]} work (~{metabolic:.0f} W) compared with effective WBGT "
                f"(screening WBGT + clothing adjustment); category set by the work/rest regime required to stay within the limit."
            ),
            guideline_reference=self.g.reference,
            limitations=self.g.data["limitations"],
            data_origin=r.data_origin,
        ), self._regulatory_flags(site, r, solar))

    # ================================================================== helpers
    def _inputs_used(self, site, crew, r, metabolic, caf, solar) -> dict:
        return {
            "environment": site.environment,
            "direct_solar_load": solar,
            "dry_bulb": r.dry_bulb if r else None,
            "natural_wet_bulb": r.natural_wet_bulb if r else None,
            "globe_temperature": r.globe_temperature if r else None,
            "relative_humidity": r.relative_humidity if r else None,
            "workload": crew.workload,
            "metabolic_rate_w": metabolic,
            "clothing": crew.clothing,
            "clothing_adjustment": caf,
            "acclimatization": crew.acclimatization,
            "work_rest_regime": crew.work_rest_regime,
            "shift_start": crew.shift_start,
            "shift_duration_hours": crew.shift_duration_hours,
            "reading_timestamp": r.timestamp if r else None,
            "sim_clock": r.sim_clock if r else None,
            "manual_override": r.manual_override if r else [],
            "data_origin": r.data_origin if r else None,
        }

    def _factors(self, site, crew, r, d: LimitDetails, metabolic, clothing, solar) -> list[ContributingFactor]:
        f: list[ContributingFactor] = []
        over = d.effective_wbgt - d.limit_at_current_regime
        f.append(ContributingFactor(
            factor="Environmental heat (WBGT)",
            detail=(f"Effective WBGT {d.effective_wbgt:.1f} °C vs {d.limit_type} {d.limit_at_current_regime:.1f} °C "
                    f"at current regime ({'exceeds by' if over > 0 else 'below by'} {abs(over):.1f} °C)."),
            direction="increases_concern" if over > -d.caution_margin else "neutral",
        ))
        if d.rolling_mean_wbgt is not None and d.rolling_mean_wbgt > d.measured_wbgt + 0.2:
            f.append(ContributingFactor(
                factor="Recent exposure retained",
                detail=f"Rolling 60-min mean WBGT {d.rolling_mean_wbgt:.1f} °C exceeds the latest reading {d.measured_wbgt:.1f} °C; "
                       "the higher value is used so a single cooler reading does not clear the concern.",
                direction="increases_concern"))
        if r.globe_temperature is not None and r.dry_bulb is not None:
            excess = r.globe_temperature - r.dry_bulb
            if excess >= 5:
                src = "direct sun" if solar else "radiant sources"
                f.append(ContributingFactor(
                    factor="Radiant heat",
                    detail=f"Globe temperature exceeds air temperature by {excess:.1f} °C ({src}).",
                    direction="increases_concern"))
        if r.natural_wet_bulb is not None:
            share = 0.7 * r.natural_wet_bulb / max(d.measured_wbgt, 1e-6)
            f.append(ContributingFactor(
                factor="Humidity / evaporative cooling",
                detail=f"Natural wet-bulb {r.natural_wet_bulb:.1f} °C contributes {share:.0%} of WBGT"
                       + (f" (RH {r.relative_humidity:.0f}%)" if r.relative_humidity is not None else "") + ".",
                direction="neutral"))
        if crew.workload in ("heavy", "very_heavy", "moderate"):
            f.append(ContributingFactor(
                factor="Workload",
                detail=f"{WORKLOAD_LABELS[crew.workload].capitalize()} work (~{metabolic:.0f} W) lowers the applicable limit "
                       f"to {self.g.limit(d.limit_type, metabolic):.1f} °C for continuous work.",
                direction="increases_concern"))
        if crew.acclimatization == "not_acclimatized":
            f.append(ContributingFactor(factor="Not acclimatized",
                                        detail="Lower RAL applies; unacclimatized workers have less physiological heat tolerance.",
                                        direction="increases_concern"))
        elif crew.acclimatization == "unknown":
            f.append(ContributingFactor(factor="Acclimatization unknown",
                                        detail="Status not recorded; the protective RAL is applied instead of the REL.",
                                        direction="uncertainty"))
        else:
            ral = self.g.limit("RAL", d.twa_metabolic_rate_w)
            if d.effective_wbgt > ral:
                f.append(ContributingFactor(
                    factor="New or returning workers",
                    detail=f"Conditions exceed the RAL ({ral:.1f} °C); any new or returning (unacclimatized) worker in this crew would need extra protection.",
                    direction="increases_concern"))
        if d.clothing_adjustment > 0:
            f.append(ContributingFactor(factor="Protective clothing",
                                        detail=f"{clothing['label']} adds {d.clothing_adjustment:.1f} °C to effective WBGT.",
                                        direction="increases_concern"))
        if d.current_regime != "continuous":
            f.append(ContributingFactor(factor="Work/rest regime in place",
                                        detail=f"{self.g.regime(d.current_regime)['label']} lowers the 1-h TWA metabolic rate to "
                                               f"{d.twa_metabolic_rate_w:.0f} W.",
                                        direction="reduces_concern"))
        if crew.shift_duration_hours > 8:
            f.append(ContributingFactor(factor="Extended shift",
                                        detail=f"{crew.shift_duration_hours:g}-hour shift increases cumulative exposure time; plan hydration and recovery.",
                                        direction="increases_concern"))
        if r.manual_override:
            f.append(ContributingFactor(factor="Manual override", detail=f"Inputs set manually: {', '.join(r.manual_override)}.",
                                        direction="uncertainty"))
        return f

    def _explain(self, category: str, crew: Crew, d: LimitDetails, solar: bool, site: Worksite) -> str:
        work = WORKLOAD_LABELS[crew.workload]
        who = {
            "acclimatized": "an acclimatized crew",
            "not_acclimatized": "an unacclimatized crew",
            "unknown": "a crew whose acclimatization is unknown",
        }[crew.acclimatization]
        where = "in direct sun" if solar else ("indoors" if site.environment == "indoor" else "in shade")
        limit_name = "exposure limit (REL)" if d.limit_type == "REL" else "alert limit (RAL)"
        schedule = "" if d.current_regime == "continuous" else f" with the current {self.g.regime(d.current_regime)['label'].lower()} schedule"
        base = (f"Effective WBGT is {d.effective_wbgt:.1f} °C {where}. For {work} work by {who}, the {limit_name} is "
                f"{d.limit_at_current_regime:.1f} °C{schedule}.")
        over = -d.margin_to_limit
        if category == "routine":
            return base + f" Conditions are {d.margin_to_limit:.1f} °C below the limit. Continue routine monitoring."
        if category == "caution":
            return base + f" Conditions are within {self.g.caution_margin:.1f} °C of the limit and approaching it."
        if category == "critical":
            return base + (f" The limit is exceeded by {over:.1f} °C. Even a 15 min work / 45 min rest schedule would not be enough, "
                           "so strenuous work should stop or be postponed and other controls added.")
        req = self.g.regime(d.required_regime)["label"].lower() if d.required_regime else ""
        return base + f" The limit is exceeded by {over:.1f} °C. Use at least a {req} schedule, or reduce the workload."

    def _recommend(self, category: str, crew: Crew, d: LimitDetails, clothing: dict, solar: bool, site: Worksite) -> list[RecommendedAction]:
        a: list[RecommendedAction] = []
        water = RecommendedAction(action="Provide drinking water",
                                  detail="Cool potable water close to the work area; encourage about 1 cup (~240 mL) every 15-20 minutes.",
                                  priority="advised", source=NIOSH)
        if category == "routine":
            a.append(RecommendedAction(action="Continue routine monitoring", detail="Conditions are within the applicable limit.",
                                       priority="routine", source="HeatGuard"))
            water.priority = "routine"
            a.append(water)
        elif category == "caution":
            water.priority = "advised"
            a += [water,
                  RecommendedAction(action="Prepare shaded or cooled rest area", detail="Ensure shade/cool area is available near the crew.",
                                    priority="advised", source=NIOSH),
                  RecommendedAction(action="Increase observation", detail="Use a buddy system and supervisor check-ins; consider moving heavy tasks to cooler hours.",
                                    priority="advised", source=NIOSH)]
        else:
            water.priority = "required"
            if category in ("elevated", "high") and d.required_regime:
                lbl = self.g.regime(d.required_regime)["label"]
                a.append(RecommendedAction(action="Introduce work-rest rotation",
                                           detail=f"Adopt at least: {lbl}, with rest in shade or a cooled area.",
                                           priority="required", source=f"{NIOSH} work/rest regimes"))
            a.append(water)
            a.append(RecommendedAction(action="Schedule recovery breaks in shade/cool area",
                                       detail="Rest breaks should be taken out of direct sun and away from radiant sources.",
                                       priority="required", source=NIOSH))
            a.append(RecommendedAction(action="Reduce physical workload",
                                       detail="Use mechanical aids, share tasks across more workers, or slow the pace.",
                                       priority="required" if category != "elevated" else "advised", source=NIOSH))
            if category in ("high", "critical"):
                a.append(RecommendedAction(action="Modify work schedule",
                                           detail="Move strenuous tasks to cooler parts of the day or shorten exposure duration.",
                                           priority="required", source=NIOSH))
            if category == "critical":
                a.insert(0, RecommendedAction(action="Stop or postpone strenuous work",
                                              detail="Work/rest scheduling alone cannot keep exposure within the guideline. Pause strenuous "
                                                     "work until conditions improve or engineering controls reduce exposure.",
                                              priority="urgent", source=NIOSH))
            a.append(SYMPTOM_ESCALATION)
        # factor-specific actions
        if solar and category not in ("routine",):
            a.append(RecommendedAction(action="Provide shade", detail="Erect temporary shade over work and rest areas.",
                                       priority="advised", source=NIOSH))
        if site.environment == "indoor" and category not in ("routine",):
            a.append(RecommendedAction(action="Engineering controls for radiant heat",
                                       detail="Use shielding, insulation of hot surfaces, and increased ventilation / spot cooling.",
                                       priority="advised", source=NIOSH))
        if d.clothing_adjustment > 0 and category not in ("routine",):
            a.append(RecommendedAction(action="Review protective clothing",
                                       detail=f"{clothing['label']} adds {d.clothing_adjustment:.1f} °C. Consider lighter compliant ensembles or cooling garments.",
                                       priority="advised", source=NIOSH))
        if crew.acclimatization == "not_acclimatized":
            a.append(RecommendedAction(action="Follow an acclimatization schedule",
                                       detail=self.g.data["acclimatization"]["schedule_new_workers"],
                                       priority="required" if category != "routine" else "advised", source=NIOSH))
        elif crew.acclimatization == "unknown":
            a.append(RecommendedAction(action="Confirm acclimatization status",
                                       detail="Record whether crew members are acclimatized; until then the RAL is applied.",
                                       priority="advised", source="HeatGuard"))
        return a

    def _incomplete(self, ctx: AssessmentContext, status: str, dq: DataQuality, missing: list[str], env_missing: bool,
                    inputs_used: dict, wbgt_val: float | None) -> Assessment:
        crew = ctx.crew
        last = ""
        if ctx.last_valid_category:
            last = (f" Last valid assessment: {CATEGORY_LABELS[ctx.last_valid_category]}"
                    + (f" at {ctx.last_valid_time}" if ctx.last_valid_time else "") + " (may no longer reflect current conditions).")
        what = "Environmental data are unavailable or stale" if status == "unavailable" else "Required information is missing"
        explanation = (f"{what}: {', '.join(missing)}. HeatGuard cannot determine the heat-risk category and does NOT treat "
                       f"this as safe.{last}")
        actions = []
        if env_missing:
            actions += [
                RecommendedAction(action="Restore environmental monitoring",
                                  detail="Inspect the sensing station (power, probes, wick water, connectivity).",
                                  priority="required", source="HeatGuard"),
                RecommendedAction(action="Verify conditions manually",
                                  detail="Take a spot measurement with a calibrated handheld WBGT instrument and reassess.",
                                  priority="required", source="HeatGuard"),
                RecommendedAction(action="Apply precautionary measures",
                                  detail="Until reassessed, maintain water, shade and rest breaks at least at the level of the last valid assessment.",
                                  priority="required", source="HeatGuard"),
            ]
        if any("workload" in m or "clothing" in m for m in missing):
            actions.append(RecommendedAction(action="Complete crew work context",
                                             detail="Record workload and clothing category in Crew Management so the assessment can run.",
                                             priority="required", source="HeatGuard"))
        actions.append(SYMPTOM_ESCALATION)
        factors = [ContributingFactor(factor="Missing information", detail=m, direction="uncertainty") for m in missing]
        return Assessment(
            assessment_id=new_id("asm"),
            timestamp=now_iso(),
            worksite_id=ctx.worksite.worksite_id,
            crew_id=crew.crew_id,
            crew_name=crew.name,
            reading_id=ctx.reading.reading_id if ctx.reading else None,
            sim_clock=ctx.reading.sim_clock if ctx.reading else None,
            assessment_status=status,  # type: ignore[arg-type]
            risk_category="unavailable",
            risk_level=-1,
            wbgt=wbgt_val,
            effective_wbgt=None,
            contributing_factors=factors,
            explanation=explanation,
            recommended_actions=actions,
            data_quality=dq,
            data_completeness=dq.data_completeness,
            inputs_used=inputs_used,
            limit_details=None,
            assessment_method="Not performed: required inputs missing (missing data is never classified as low risk).",
            guideline_reference=self.g.reference,
            limitations=self.g.data["limitations"],
            data_origin=ctx.reading.data_origin if ctx.reading else "SIMULATED",
        )


__all__ = ["RiskEngine", "AssessmentContext", "MissingComponentError", "CATEGORY_LABELS"]
