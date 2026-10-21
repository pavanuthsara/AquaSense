from transit_sim import Shipment, load_species
from transit_sim.cli import main
from transit_sim.uncertainty import random_profile, run_temperature_range

import numpy as np


def bag():
    return Shipment(fish_count=60, fish_mass_g=0.3, water_l=0.4, gas_l=1.2, duration_h=48)


def test_random_profile_stays_in_range():
    prof = random_profile(np.random.default_rng(1), 24, 30, 48)
    assert prof[0][0] == 0 and prof[-1][0] >= 48
    assert all(24 <= v <= 30 for _, v in prof)


def test_range_band_is_ordered_and_reproducible():
    sp = load_species("guppy")
    rr = run_temperature_range(sp, bag(), 24, 30, samples=5, seed=3)
    s = rr.stats["survival_after_unpacking"]
    assert s["min"] <= s["p10"] <= s["median"] <= s["max"]
    assert rr.stats["n_runs"] == 8
    again = run_temperature_range(sp, bag(), 24, 30, samples=5, seed=3)
    assert again.stats == rr.stats


def test_hotter_range_is_worse():
    sp = load_species("guppy")
    cool = run_temperature_range(sp, bag(), 22, 24, samples=3)
    hot = run_temperature_range(sp, bag(), 28, 32, samples=3)
    assert hot.stats["survival_at_arrival"]["median"] < cool.stats["survival_at_arrival"]["median"]


def test_cli_temp_range(capsys, tmp_path):
    out = tmp_path / "runs.csv"
    assert main(["simulate", "--count", "60", "--mass", "0.3", "--water", "0.4", "--gas", "1.2",
                 "--hours", "24", "--temp-range", "24", "30", "--samples", "3", "--csv", str(out)]) == 0
    assert "worst" in capsys.readouterr().out
    assert len(out.read_text().strip().splitlines()) == 1 + 6
