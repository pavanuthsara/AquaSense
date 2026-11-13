"""Guards against the YAML configs drifting away from what the calibration produces."""
import pytest

from transit_sim import load_species
from transit_sim.calibration import calibrate
from transit_sim.config import load_interventions
from transit_sim.model import bag_defaults


@pytest.mark.slow
def test_config_matches_fresh_calibration():
    cal = calibrate()
    sp = load_species("tiger_barb")
    for k in ("o2_rate", "tan_rate", "stress_amp"):
        assert getattr(sp, k) == pytest.approx(getattr(cal.species, k), rel=0.02), k
    assert bag_defaults()["sealed_bag_kla_per_h"]["value"] == pytest.approx(cal.kla, rel=0.02)
    iv = load_interventions()
    assert iv["ms222_40mgL"]["excretion_factor"] == pytest.approx(cal.anaesthetics["ms222"]["excretion_factor"], rel=0.02)
    # anaesthetic mortality is a prediction: it must at least go the right way
    m = cal.metrics
    assert m["ms222"]["mortality"]["end_model"] < m["control"]["mortality"]["end_model"]
    assert m["benzocaine"]["mortality"]["end_model"] < m["control"]["mortality"]["end_model"]
