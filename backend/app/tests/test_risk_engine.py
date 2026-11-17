import math

import pytest

from app.schemas.common import now_iso
from app.schemas.sensor import SensorReading, SensorReadingIn
from app.services.data_validation import validate_reading
from app.services.guideline import load_guideline
from app.services.risk_engine import AssessmentContext
from app.services.wbgt_calculator import compute_wbgt

from .conftest import make_crew

G = load_guideline("niosh_2016")


def reading(tdb=30.0, tnwb=24.0, tg=40.0, rh=55.0, solar=True, environment="outdoor", **kw):
    rin = SensorReadingIn(station_id="s", worksite_id="ws", dry_bulb=tdb, natural_wet_bulb=tnwb, globe_temperature=tg,
                          relative_humidity=rh, direct_solar=solar, **kw)
    v = validate_reading(rin)
    valid = set(v.valid_fields)
    try:
        w = compute_wbgt(tnwb if "natural_wet_bulb" in valid else None, tg if "globe_temperature" in valid else None,
                         tdb if "dry_bulb" in valid else None, environment, solar)
        wbgt, formula = w.value, w.formula
    except ValueError:
        wbgt = formula = None
    return SensorReading(**rin.model_dump(exclude={"reading_id", "timestamp"}), reading_id="r1", timestamp=now_iso(),
                         received_at=now_iso(), wbgt=wbgt, wbgt_formula=formula, validation=v)


def ctx(site, crew, r, age=1.0, rolling=None):
    return AssessmentContext(worksite=site, crew=crew, reading=r, reading_age_seconds=age, stale_after_seconds=15, rolling_mean_wbgt=rolling)


# ---------------------------------------------------------------- guideline equations
def test_niosh_equations():
    assert G.limit("REL", 300) == pytest.approx(56.7 - 11.5 * math.log10(300), abs=0.01)
    assert G.limit("RAL", 300) == pytest.approx(59.9 - 14.1 * math.log10(300), abs=0.01)
    # RAL is always below REL over the working range
    for m in (117, 180, 297, 414, 522):
        assert G.limit("RAL", m) < G.limit("REL", m)


def test_twa_metabolic_rate():
    assert G.twa_metabolic_rate(414, "continuous") == pytest.approx(414)
    assert G.twa_metabolic_rate(414, "30_30") == pytest.approx((30 * 414 + 30 * 117) / 60)


# ---------------------------------------------------------------- categories
def wbgt_for(effective):
    """Outdoor solar reading producing approximately the requested WBGT."""
    # choose tnwb so that 0.7*tnwb + 0.2*tg + 0.1*tdb == effective with tg = tdb + 10
    tdb = 32.0
    tg = 42.0
    tnwb = (effective - 0.2 * tg - 0.1 * tdb) / 0.7
    return reading(tdb=tdb, tnwb=tnwb, tg=tg)


def test_routine_below_limit(engine, outdoor_site):
    crew = make_crew(workload="light")
    a = engine.assess(ctx(outdoor_site, crew, wbgt_for(25.0)))
    assert a.assessment_status == "valid"
    assert a.risk_category == "routine"
    assert a.explanation
    assert a.limit_details.limit_type == "REL"


def test_caution_within_margin(engine, outdoor_site):
    crew = make_crew(workload="moderate")
    rel = G.limit("REL", 297)
    a = engine.assess(ctx(outdoor_site, crew, wbgt_for(rel - 0.5)))
    assert a.risk_category == "caution"


def test_elevated_requires_45_15(engine, outdoor_site):
    crew = make_crew(workload="moderate")
    rel = G.limit("REL", 297)
    rel_45 = G.limit("REL", G.twa_metabolic_rate(297, "45_15"))
    a = engine.assess(ctx(outdoor_site, crew, wbgt_for((rel + rel_45) / 2)))
    assert a.risk_category == "elevated"
    assert a.limit_details.required_regime == "45_15"


def test_critical_beyond_all_regimes(engine, outdoor_site):
    crew = make_crew(workload="heavy")
    lim = G.limit("REL", G.twa_metabolic_rate(414, "15_45"))
    a = engine.assess(ctx(outdoor_site, crew, wbgt_for(lim + 1)))
    assert a.risk_category == "critical"
    assert a.recommended_actions[0].priority == "urgent"


def test_work_rest_regime_reduces_category(engine, outdoor_site):
    r = wbgt_for(29.5)
    before = engine.assess(ctx(outdoor_site, make_crew(workload="heavy"), r))
    after = engine.assess(ctx(outdoor_site, make_crew(workload="heavy", work_rest_regime="15_45"), r))
    assert after.risk_level < before.risk_level


def test_unacclimatized_uses_ral_and_is_not_less_severe(engine, outdoor_site):
    r = wbgt_for(27.0)
    acc = engine.assess(ctx(outdoor_site, make_crew(acclimatization="acclimatized"), r))
    notacc = engine.assess(ctx(outdoor_site, make_crew(acclimatization="not_acclimatized"), r))
    assert notacc.limit_details.limit_type == "RAL"
    assert notacc.risk_level >= acc.risk_level


def test_unknown_acclimatization_is_not_treated_as_acclimatized(engine, outdoor_site):
    r = wbgt_for(27.0)
    unk = engine.assess(ctx(outdoor_site, make_crew(acclimatization="unknown"), r))
    assert unk.limit_details.limit_type == "RAL"
    assert unk.data_quality.assessment_confidence == "reduced"
    assert "acclimatization status" in unk.data_quality.unknown_inputs
    assert unk.data_completeness < 1.0


def test_clothing_adjustment_added(engine, outdoor_site):
    r = wbgt_for(26.0)
    a = engine.assess(ctx(outdoor_site, make_crew(clothing="double_layer_woven"), r))
    assert a.effective_wbgt == pytest.approx(a.wbgt + 3.0, abs=0.01)


def test_rolling_mean_retains_recent_exposure(engine, outdoor_site):
    r = wbgt_for(25.0)
    a = engine.assess(ctx(outdoor_site, make_crew(), r, rolling=30.0))
    assert a.limit_details.screening_wbgt == pytest.approx(30.0)
    assert a.risk_level >= 2


def test_indoor_formula_used(engine, indoor_site):
    r = reading(tdb=30, tnwb=24, tg=40, solar=None, environment="indoor")
    a = engine.assess(ctx(indoor_site, make_crew(), r))
    assert "0.3*Tg" in a.inputs_used["wbgt_formula"]


# ---------------------------------------------------------------- missing data
def test_missing_globe_gives_incomplete_never_routine(engine, outdoor_site):
    r = reading(tg=None)
    a = engine.assess(ctx(outdoor_site, make_crew(), r))
    assert a.assessment_status == "incomplete"
    assert a.risk_category == "unavailable"
    assert a.risk_level == -1
    assert "does NOT treat" in a.explanation


def test_invalid_sensor_value(engine, outdoor_site):
    r = reading(tnwb=-127.0)
    a = engine.assess(ctx(outdoor_site, make_crew(), r))
    assert a.risk_category == "unavailable"
    assert any("natural wet bulb" in m for m in a.data_quality.missing_inputs)


def test_implausible_wet_bulb_above_dry_bulb(engine, outdoor_site):
    r = reading(tdb=30.0, tnwb=34.0)
    assert any(i.issue == "implausible" for i in r.validation.issues)
    a = engine.assess(ctx(outdoor_site, make_crew(), r))
    assert a.risk_category == "unavailable"


def test_stale_reading_unavailable(engine, outdoor_site):
    a = engine.assess(ctx(outdoor_site, make_crew(), wbgt_for(20.0), age=60.0))
    assert a.assessment_status == "unavailable"
    assert a.data_quality.stale


def test_no_reading(engine, outdoor_site):
    a = engine.assess(ctx(outdoor_site, make_crew(), None, age=None))
    assert a.assessment_status == "unavailable"
    assert a.data_quality.measurement_validity == "no_data"


@pytest.mark.parametrize("field,value", [("workload", "unknown"), ("clothing", "unknown"), ("clothing", "specialized_ppe")])
def test_missing_context_incomplete(engine, outdoor_site, field, value):
    a = engine.assess(ctx(outdoor_site, make_crew(**{field: value}), wbgt_for(20.0)))
    assert a.assessment_status == "incomplete"
    assert a.risk_category == "unavailable"


def test_every_valid_assessment_has_explanation_and_reference(engine, outdoor_site):
    for w in (20, 26, 28, 30, 33):
        a = engine.assess(ctx(outdoor_site, make_crew(workload="heavy"), wbgt_for(w)))
        assert a.explanation and a.guideline_reference and a.limitations and a.contributing_factors and a.recommended_actions
