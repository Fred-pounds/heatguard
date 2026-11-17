import pytest

from app.services.wbgt_calculator import (
    MissingComponentError,
    compute_wbgt,
    uses_solar_formula,
    wbgt_no_solar,
    wbgt_outdoor_solar,
)


def test_outdoor_solar_formula():
    # 0.7*25 + 0.2*40 + 0.1*30 = 17.5 + 8 + 3 = 28.5
    assert wbgt_outdoor_solar(25, 40, 30) == pytest.approx(28.5)


def test_no_solar_formula():
    # 0.7*25 + 0.3*40 = 17.5 + 12 = 29.5
    assert wbgt_no_solar(25, 40) == pytest.approx(29.5)


def test_formula_selection():
    assert uses_solar_formula("outdoor", True)
    assert not uses_solar_formula("outdoor", False)
    assert not uses_solar_formula("indoor", True)
    # unknown solar status outdoors is not assumed to be shade
    assert uses_solar_formula("outdoor", None)


def test_compute_indoor_does_not_need_dry_bulb():
    r = compute_wbgt(24.0, 35.0, None, "indoor", None)
    assert r.value == pytest.approx(0.7 * 24 + 0.3 * 35)
    assert not r.with_solar_load


def test_compute_outdoor_requires_dry_bulb():
    with pytest.raises(MissingComponentError) as exc:
        compute_wbgt(24.0, 35.0, None, "outdoor", True)
    assert exc.value.missing == ["dry_bulb"]


def test_compute_missing_globe():
    with pytest.raises(MissingComponentError) as exc:
        compute_wbgt(24.0, None, 30.0, "outdoor", True)
    assert "globe_temperature" in exc.value.missing
