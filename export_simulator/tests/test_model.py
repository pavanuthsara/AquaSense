import numpy as np
import pytest

from transit_sim import Interventions, Shipment, Unpacking, load_species, simulate
from transit_sim import chemistry as chem
from transit_sim.calibration import load_pramod, pramod_shipment


def guppy_bag(count=20, hours=24.0, **kw):
    return Shipment(fish_count=count, fish_mass_g=0.3, water_l=0.4, gas_l=1.2, duration_h=hours,
                    temperature_c=25.0, **kw)


def test_species_inheritance():
    barb, guppy = load_species("tiger_barb"), load_species("guppy")
    assert guppy.o2_rate == barb.o2_rate
    assert guppy.nh3_lc50 == pytest.approx(1.17)
    assert "inherited" in guppy.sources["o2_rate"]


def test_no_fish_is_stable():
    sh = Shipment(fish_count=0, fish_mass_g=1.0, water_l=1.0, gas_l=1.0, duration_h=24, temperature_c=22)
    r = simulate(load_species("guppy"), sh, unpacking=None)
    assert r.survival[-1] == pytest.approx(1.0)
    assert np.allclose(r.tan, r.tan[0])
    assert r.do[-1] == pytest.approx(chem.o2_henry_mgL_per_atm(22.0), rel=0.02)


def test_oxygen_is_conserved_without_fish():
    sh = Shipment(fish_count=0, fish_mass_g=1.0, water_l=1.0, gas_l=0.5, duration_h=24, temperature_c=22,
                  initial_do_mgL=8.0)
    r = simulate(load_species("guppy"), sh, unpacking=None)
    tk = chem.kelvin(22.0)
    total = r.do * 1.0 / 32.0 + r.gas_o2_atm * 0.5 / (chem.R_GAS * tk) * 1000.0  # mmol
    assert total[-1] == pytest.approx(total[0], rel=1e-3)


def test_more_fish_means_lower_survival():
    sp = load_species("guppy")
    s = [simulate(sp, guppy_bag(n, 48), unpacking=None).summary["survival_at_arrival"] for n in (20, 60, 120)]
    assert s[0] >= s[1] >= s[2]
    assert s[2] < s[0]


def test_longer_transit_means_lower_survival():
    sp = load_species("guppy")
    s = [simulate(sp, guppy_bag(60, h), unpacking=None).summary["survival_at_arrival"] for h in (12, 36, 72)]
    assert s[0] > s[1] > s[2]


def test_warmer_means_faster_depletion():
    sp = load_species("guppy")
    cold = simulate(sp, Shipment(60, 0.3, 0.4, 1.2, 24, temperature_c=22.0), unpacking=None)
    warm = simulate(sp, Shipment(60, 0.3, 0.4, 1.2, 24, temperature_c=30.0), unpacking=None)
    assert warm.tan[-1] > cold.tan[-1]


def test_unpacking_ph_rebound_raises_nh3():
    r = simulate(load_species("guppy"), guppy_bag(60, 48), unpacking=Unpacking(duration_h=1.0))
    s = r.summary
    assert s["peak_ph_unpacking"] > s["final_ph"] + 0.5
    assert s["peak_nh3_unpacking_mgL"] > 3 * s["max_nh3_transit_mgL"]


def test_anaesthetic_and_zeolite_reduce_ammonia():
    sp = load_species("guppy")
    base = simulate(sp, guppy_bag(60, 48), unpacking=None)
    sed = simulate(sp, guppy_bag(60, 48), Interventions(metabolic_factor=0.88, excretion_factor=0.46),
                   unpacking=None)
    zeo = simulate(sp, guppy_bag(60, 48), Interventions(zeolite_g_per_l=20), unpacking=None)
    assert sed.tan[-1] < base.tan[-1]
    assert zeo.tan[-1] < base.tan[-1]


def test_feeding_before_packing_is_worse():
    sp = load_species("guppy")
    fed = simulate(sp, guppy_bag(60, 48), Interventions(starvation_h=0), unpacking=None)
    fasted = simulate(sp, guppy_bag(60, 48), Interventions(starvation_h=48), unpacking=None)
    assert fed.tan[-1] > fasted.tan[-1]


def test_temperature_profile_interpolation():
    sh = Shipment(1, 1, 1, 1, 24, temperature_c=[(0, 20.0), (12, 30.0), (24, 20.0)])
    assert sh.temperature_at(6) == pytest.approx(25.0)
    assert sh.temperature_at(30) == pytest.approx(20.0)


def test_calibrated_config_reproduces_pramod_control():
    sp = load_species("tiger_barb")
    r = simulate(sp, pramod_shipment(), unpacking=None, dt_out=6.0)
    obs = load_pramod()["control"]
    assert np.sqrt(np.mean((r.do - obs["do"]) ** 2)) < 1.5
    assert np.sqrt(np.mean((r.tan - obs["tan"]) ** 2)) < 1.5
    assert np.sqrt(np.mean((r.co2 - obs["co2"]) ** 2)) < 10
    assert 100 * (1 - r.survival[-1]) == pytest.approx(15.3, abs=2.0)
