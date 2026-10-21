import numpy as np
import pandas as pd

from prediction.alerts import (alert_metrics, early_alert, first_breach_step, load_safe_ranges,
                               tune_margin)
from prediction.settings import PrepConfig

CFG = PrepConfig(horizon_steps=6)
NOW = pd.Timestamp("2021-07-01 12:00")


def test_first_breach_needs_consecutive_steps():
    paths = np.array([
        [0.1, 0.6, 0.1, 0.1, 0.1, 0.1],   # single-step spike: ignored
        [0.1, 0.2, 0.6, 0.7, 0.1, 0.1],   # breach starts at step 3
        [0.1, 0.1, 0.1, 0.1, 0.1, 0.6],   # last step only: counts (runs to the end)
    ])
    assert first_breach_step(paths, None, 0.5).tolist() == [0, 3, 6]


def test_early_alert_message_and_eta():
    a = early_alert("ammonia", NOW, 0.40, np.array([0.42, 0.45, 0.48, 0.52, 0.55, 0.6]),
                    (None, 0.5), CFG)
    assert a.eta_min == 40 and a.side == "high"
    assert a.message.startswith("Ammonia unsafe in ~40 min")
    assert pd.Timestamp(a.breach_at) == NOW + pd.Timedelta(minutes=40)


def test_low_side_and_hours_text():
    path = np.array([5.5] * 5 + [4.8])
    a = early_alert("do", NOW, 6.0, path, (5.0, None), PrepConfig(horizon_steps=6, freq_min=20))
    assert a.side == "low" and a.eta_min == 120
    assert "unsafe in ~2 h" in a.message


def test_no_early_alert_when_already_out_of_range_or_safe_forecast():
    assert early_alert("ph", NOW, 8.4, np.full(6, 8.6), (6.5, 8.0), CFG) is None
    assert early_alert("ph", NOW, 7.2, np.full(6, 7.3), (6.5, 8.0), CFG) is None


def test_margin_moves_the_alert_line_but_not_the_reported_limit():
    path = np.array([0.46, 0.47, 0.48, 0.48, 0.49, 0.49])   # never above 0.5
    assert early_alert("ammonia", NOW, 0.40, path, (None, 0.5), CFG) is None
    a = early_alert("ammonia", NOW, 0.40, path, (None, 0.5), CFG, margin=0.05)
    assert a.eta_min == 10 and a.limit == 0.5 and "safe max 0.5" in a.message
    # negative margin: needs to be clearly past the limit
    over = np.array([0.52] * 6)
    assert early_alert("ammonia", NOW, 0.40, over, (None, 0.5), CFG, margin=-0.05) is None


def test_tune_margin_finds_the_better_alert_line():
    t = pd.date_range(NOW, periods=6, freq="10min")
    val = pd.DataFrame({"series": "p", "time": t, "ammonia_lag0": [0.3] * 6})
    up, calm = [0.6] * 6, [0.3] * 6
    y = np.array([up, up, up, calm, calm, calm])
    # model under-forecasts real breaches (0.48) and says 0.40 when calm
    pred = np.array([[0.48] * 6] * 3 + [[0.40] * 6] * 3)
    margin, f1 = tune_margin(val, y, pred, "ammonia", (None, 0.5), CFG)
    assert 0.02 < margin < 0.10 and f1 == 1.0


def test_alert_metrics_perfect_forecast_scores_one():
    t = pd.date_range(NOW, periods=4, freq="10min")
    test = pd.DataFrame({"series": "p", "time": t, "ammonia_lag0": [0.3, 0.3, 0.3, 0.3]})
    y = np.array([[0.3, 0.3, 0.6, 0.6, 0.6, 0.6]] * 4)
    m = alert_metrics(test, y, y, "ammonia", (None, 0.5), CFG)
    assert m["precision"] == 1 and m["recall"] == 1 and m["f1"] == 1 and m["warned_%"] == 100


def test_f1_combines_precision_and_recall():
    t = pd.date_range(NOW, periods=4, freq="10min")
    test = pd.DataFrame({"series": "p", "time": t, "ammonia_lag0": [0.3] * 4})
    breach, calm = [0.3, 0.3, 0.6, 0.6, 0.6, 0.6], [0.3] * 6
    y = np.array([breach, breach, calm, calm])
    pred = np.array([breach, calm, breach, calm])      # 1 hit, 1 miss, 1 false alarm
    m = alert_metrics(test, y, pred, "ammonia", (None, 0.5), CFG)
    assert m["precision"] == 0.5 and m["recall"] == 0.5 and m["f1"] == 0.5


def test_safe_ranges_come_from_controller_config():
    limits = load_safe_ranges()
    assert limits["do"] == (5.0, None) and limits["ammonia"] == (None, 0.5)
