import numpy as np
import pandas as pd

from prediction.data_prep import (_fill_short_gaps, _stuck_mask, clean_raw,
                                  make_lag_dataset, resample)
from prediction.settings import PARAMS, PrepConfig


def _raw(series="pond1", minutes=240, every_s=20, **overrides):
    t = pd.date_range("2021-07-01", periods=minutes * 60 // every_s, freq=f"{every_s}s")
    rng = np.random.default_rng(0)
    df = pd.DataFrame({"series": series, "time": t,
                       "do": 7 + rng.normal(0, 0.2, len(t)),
                       "ph": 7.2 + rng.normal(0, 0.01, len(t)),
                       "ammonia": 0.2 + rng.normal(0, 0.01, len(t)).clip(-0.1),
                       "temperature": 25 + rng.normal(0, 0.05, len(t))})
    for k, v in overrides.items():
        df[k] = v
    return df


def test_fill_short_gaps_leaves_long_outages_empty():
    x = pd.Series([1.0, np.nan, np.nan, 4.0, np.nan, np.nan, np.nan, np.nan, 9.0])
    out = _fill_short_gaps(x, max_steps=2)
    assert out[:4].tolist() == [1.0, 2.0, 3.0, 4.0]
    assert out[4:8].isna().all()            # 4-step gap: not even partly filled


def test_stuck_sensor_is_removed_but_short_flat_runs_kept():
    t = pd.Series(pd.date_range("2021-07-01", periods=500, freq="20s"))
    v = pd.Series([5.08] * 400 + list(np.linspace(5, 6, 100)))   # 400 x 20 s = 2.2 h flat
    assert _stuck_mask(t, v, max_hours=1.0)[:400].all()
    assert not _stuck_mask(t, v, max_hours=1.0)[400:].any()


def test_duplicate_pond_rows_dropped_from_later_series():
    a = _raw("pond1")
    b = a.assign(series="pond2")
    clean, report = clean_raw(pd.concat([a, b]), PrepConfig(min_pond_rows=10))
    assert report.loc["pond2", "duplicate_rows"] == len(b)
    assert set(clean["series"]) == {"pond1"}


def test_implausible_values_become_nan():
    raw = _raw(temperature=-127.0)
    clean, _ = clean_raw(raw, PrepConfig(min_pond_rows=10))
    assert clean["temperature"].isna().all()
    assert clean["do"].notna().all()


def test_every_model_returns_n_by_horizon_even_for_one_step():
    from prediction.models import MODELS

    for horizon in (1, 3):
        cfg = PrepConfig(min_pond_rows=10, lag_steps=3, horizon_steps=horizon)
        grid = resample(clean_raw(_raw(minutes=600), cfg)[0], cfg)
        sup = make_lag_dataset(grid, "temperature", cfg)
        for name, cls in MODELS.items():
            model = cls(cfg, max_iter=5) if name == "gboost" else cls(cfg)
            pred = model.fit(sup, "temperature").predict(sup)
            assert pred.shape == (len(sup), horizon), name


def test_lag_windows_never_bridge_a_long_gap():
    cfg = PrepConfig(min_pond_rows=10, lag_steps=3, horizon_steps=2)
    raw = pd.concat([_raw(minutes=120),
                     _raw(minutes=120).assign(time=lambda d: d["time"] + pd.Timedelta(hours=6))])
    grid = resample(clean_raw(raw, cfg)[0], cfg)
    sup = make_lag_dataset(grid, "temperature", cfg)
    step = pd.Timedelta(minutes=cfg.freq_min)
    for _, row in sup.iterrows():
        # every lag and label timestamp must hold a real grid value
        times = [row["time"] - k * step for k in range(cfg.lag_steps)] + \
                [row["time"] + h * step for h in range(1, cfg.horizon_steps + 1)]
        vals = grid.set_index("time").loc[times, "temperature"]
        assert vals.notna().all()
    assert set(PARAMS) <= {c.split("_lag")[0] for c in sup.columns if "_lag" in c}
