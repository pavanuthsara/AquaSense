import numpy as np
import pytest

from transit_sim.ml.correction import CorrectionModel, PureMLModel, build_dataset, correct_one, metrics
from transit_sim.ml.physics import RAW_COLUMNS
from transit_sim.ml.synthetic import CSV_COLUMNS, generate, read_csv, write_csv


@pytest.fixture(scope="module")
def data():
    train = build_dataset(generate(150, seed=11))
    test = build_dataset(generate(80, seed=12))
    return train, test


def test_simulated_records_use_the_real_data_format(tmp_path):
    rows = generate(5, seed=3)
    path = write_csv(rows, tmp_path / "s.csv")
    back = read_csv(path)
    assert list(back[0]) == CSV_COLUMNS
    assert set(RAW_COLUMNS) <= set(back[0])
    assert all(r["source"] == "simulated" for r in back)
    assert all(0 <= float(r["observed_survival"]) <= 1 for r in back)


def test_pretend_reality_differs_from_physics(data):
    train, _ = data
    assert abs(np.mean(train.obs - train.phys)) > 0.005  # there is something to learn


def test_correction_beats_physics_and_pure_ml_on_unseen_shipments(data):
    train, test = data
    phys = metrics(test.phys, test.obs)["mae_pp"]
    hybrid = metrics(CorrectionModel().fit(train).predict(test), test.obs)["mae_pp"]
    pure = metrics(PureMLModel().fit(train).predict(test), test.obs)["mae_pp"]
    assert hybrid < phys
    assert hybrid < pure


def test_predictions_stay_between_0_and_1(data):
    train, test = data
    pred = CorrectionModel().fit(train).predict(test)
    assert np.all((pred >= 0) & (pred <= 1))


def test_no_model_means_no_correction(tmp_path):
    assert CorrectionModel.load(tmp_path / "none.joblib", tmp_path / "none.json") is None


def test_saved_model_round_trip(data, tmp_path):
    train, _ = data
    m = CorrectionModel().fit(train)
    m.save({"trained_on": "simulated", "n_shipments": 150}, tmp_path / "m.joblib", tmp_path / "m.json")
    loaded = CorrectionModel.load(tmp_path / "m.joblib", tmp_path / "m.json")
    row = {"species": "guppy", "fish_mass_g": 0.3, "fish_per_bag": 60, "water_l": 0.4, "gas_l": 1.2,
           "duration_h": 36, "temp_low_c": 24, "temp_high_c": 28, "fasting_h": 24, "zeolite_g_per_l": 0,
           "anaesthetic": "none"}
    out = correct_one(row, loaded)
    assert out["trained_on"] == "simulated"
    assert 0 <= out["corrected_survival_pct"] <= 100
