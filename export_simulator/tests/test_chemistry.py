import pytest

from transit_sim import chemistry as chem


def test_emerson_matches_pramod_48h_control():
    # Pramod 2010 Fig. 3 reports 0.016 mg/L NH3 at 48 h (TAN 18.17 mg/L, pH 6.28, 22 C)
    assert 18.17 * chem.unionized_fraction(6.28, 22.0) == pytest.approx(0.016, abs=0.001)


def test_emerson_pka_at_25c():
    assert chem.ammonia_pka(25.0) == pytest.approx(9.24, abs=0.01)


def test_o2_solubility():
    assert chem.o2_saturation_air_mgL(20.0) == pytest.approx(9.09, abs=0.05)
    assert 41.0 < chem.o2_henry_mgL_per_atm(22.0) < 45.0  # pure O2 at 1 atm


def test_carbonate_constants_25c():
    k1, k2, kw = chem.carbonate_constants(25.0)
    assert -__import__("math").log10(k1) == pytest.approx(6.35, abs=0.02)
    assert -__import__("math").log10(k2) == pytest.approx(10.33, abs=0.02)


@pytest.mark.parametrize("ph", [6.0, 6.8, 7.4, 8.2])
def test_ph_roundtrip(ph):
    alk = chem.alkalinity_from_caco3(65)
    dic = chem.dic_from_ph_alk(ph, alk, 5.0, 22.0)
    assert chem.solve_ph(dic, alk, 5.0, 22.0) == pytest.approx(ph, abs=1e-6)


def test_adding_co2_lowers_ph():
    alk = chem.alkalinity_from_caco3(65)
    dic = chem.dic_from_ph_alk(7.4, alk, 0.5, 22.0)
    assert chem.solve_ph(dic + 1.0, alk, 0.5, 22.0) < 7.0
