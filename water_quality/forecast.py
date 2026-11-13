"""
AquaSense — Water-quality forecasting module
============================================

Forecasts each water-quality parameter 30 minutes ahead from the last 1 hour of
history, using the Udanor "Sensor Based Aquaponics Fish Pond Datasets"
(IoTPond*.csv). One XGBoost regressor is trained per target and compared
against two naive baselines (persistence and seasonal-naive).

Pipeline:
    load -> clean -> resample (5-min grid) -> make_supervised(target)
         -> baselines + XGBoost (time-series split) -> metrics table + plots

Run:
    python forecast.py                    # uses ./data
    python forecast.py --data /path/to/csvs
"""

import argparse
import glob
import os
import re

import matplotlib

matplotlib.use("Agg")  # headless: write plots to files, never open windows
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import mean_absolute_error, mean_squared_error

# ---------------------------------------------------------------------------
# Configuration constants
# ---------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "data")        # folder with the IoTPond*.csv files
OUTPUT_DIR = os.path.join(HERE, "outputs")   # plots + summary table go here

# Forecast targets — one model each. DO first: it is the fish-safety headline.
TARGETS = ["do", "temperature", "turbidity", "ph", "ammonia", "nitrate"]

# Slow-moving fish measurements: used ONLY as input context, never forecast.
CONTEXT_FEATURES = ["population", "length", "weight"]

ALL_VARS = TARGETS + CONTEXT_FEATURES

FREQ = "5min"        # fixed sampling grid
STEP_MINUTES = 5
N_LAGS = 12          # 12 x 5 min = last 1 hour of history as features
HORIZON = 6          # 6 x 5 min = forecast 30 minutes ahead
SEASON = 12          # seasonal-naive period: 12 steps = 1 hour
INTERP_LIMIT = 6     # interpolate gaps of up to 6 steps (= 30 min) only
TEST_FRAC = 0.20     # last 20% of the timeline is the held-out test set
VAL_FRAC = 0.10      # last 10% of the TRAIN slice is used for early stopping
RANDOM_STATE = 42

PRETTY = {
    "do": "Dissolved Oxygen", "temperature": "Temperature", "turbidity": "Turbidity",
    "ph": "pH", "ammonia": "Ammonia", "nitrate": "Nitrate",
    "population": "Population", "length": "Fish length", "weight": "Fish weight",
}

# Physically plausible ranges. Readings outside -> NaN (sensor faults).
# The first three come from the project spec. The others were added after
# inspecting the raw files:
#   * temperature = -127 is the DS18B20 probe's "disconnected" error code (caught by <0)
#   * pH = 15.45 / negative values are recurring probe-fault values (caught by 0..14)
#   * turbidity < 0 is impossible (negative NTU appears in ponds 7-12)
#   * ammonia contains inf and values up to ~1e12 — corrupted readings; a cap of
#     100 mg/L is far above anything compatible with live fish
#   * nitrate is a 12-bit ADC reading that saturates at 4095; >= 4000 treated as clipped
VALID_RANGES = {
    "do": (0, 25),
    "ph": (0, 14),
    "temperature": (0, 45),
    "turbidity": (0, np.inf),
    "ammonia": (0, 100),
    "nitrate": (0, 4000),
}


# ---------------------------------------------------------------------------
# Step 1 — Load
# ---------------------------------------------------------------------------
def _canonical_name(col):
    """Map a messy raw column header to a canonical variable name by keyword.

    Headers differ between files, e.g. 'Dissolved Oxygen(g/ml)', 'DISOLVED OXYGEN',
    'Fish_Length (cm)', 'Lenght', 'Total_length (cm)', 'PH', 'pH'. The unit in
    brackets is stripped, then keywords are matched.
    """
    base = str(col).split("(")[0].strip().lower()
    letters = re.sub(r"[^a-z]", "", base)
    if letters == "createdat" or base == "unnamed: 0":  # pond 8: headerless col 0
        return "time"
    if "temp" in letters:
        return "temperature"
    if "turbid" in letters:
        return "turbidity"
    if "oxygen" in letters or "disolved" in letters or "dissolved" in letters:
        return "do"
    if letters == "ph":
        return "ph"
    if "ammonia" in letters:
        return "ammonia"
    if "nitrate" in letters:
        return "nitrate"
    if "population" in letters:
        return "population"
    if "length" in letters or "lenght" in letters:
        return "length"
    if "weight" in letters:
        return "weight"
    return None  # entry_id, extra 'Date' column, empty trailing columns, ...


def load_data(data_dir=DATA_DIR):
    """Read every IoTPond*.csv, normalise column names, tag each row with its
    pond id, and concatenate into one long DataFrame."""
    files = sorted(glob.glob(os.path.join(data_dir, "*[Pp]ond*.csv")))
    if not files:
        raise FileNotFoundError(f"No IoTPond*.csv files found in {data_dir}")

    frames = []
    for path in files:
        raw = pd.read_csv(path, low_memory=False, dtype=str)
        # Pond 8 has no header on its timestamp column -> treat column 0 as time
        # whenever no 'created_at' column exists.
        mapping = {}
        for col in raw.columns:
            name = _canonical_name(col)
            if name and name not in mapping.values():
                mapping[col] = name
        if "time" not in mapping.values():
            mapping[raw.columns[0]] = "time"

        df = raw[list(mapping)].rename(columns=mapping)
        for var in ALL_VARS:  # ponds 7-9 have no Population column -> NaN
            if var not in df.columns:
                df[var] = np.nan

        pond_id = int(re.search(r"(\d+)", os.path.basename(path)).group(1))
        df["pond"] = pond_id
        frames.append(df[["pond", "time"] + ALL_VARS])
        print(f"  loaded {os.path.basename(path):<16} pond={pond_id:<3} rows={len(df):>7}")

    return pd.concat(frames, ignore_index=True)


# ---------------------------------------------------------------------------
# Step 2 — Clean
# ---------------------------------------------------------------------------
_TS_PATTERN = re.compile(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})")


def _parse_time(series):
    """Extract 'YYYY-MM-DD HH:MM:SS' from strings like
    '2021-06-19 00:00:05 CET' or '2021-12-30T20:37:56+01:00'.

    The timezone suffix is dropped: labels are inconsistent (CET/UTC/+01:00)
    but each pond is internally consistent, which is all lag features need.
    Rows holding only a date (e.g. '5/12/2021', common in ponds 10-12) have no
    time-of-day, cannot be placed on a 5-minute grid, and become NaT.
    """
    parts = series.astype(str).str.extract(_TS_PATTERN)
    return pd.to_datetime(parts[0] + " " + parts[1], format="%Y-%m-%d %H:%M:%S",
                          errors="coerce")


def clean_data(df):
    """Coerce types, parse timestamps, sort, null out impossible readings,
    and forward-fill the rarely-measured fish features."""
    df = df.copy()

    # 2a. Timestamps -> datetime; drop rows without a usable timestamp.
    df["time"] = _parse_time(df["time"])
    n_before = len(df)
    df = df.dropna(subset=["time"])
    print(f"  dropped {n_before - len(df)} rows with no parseable date+time")

    # 2b. Everything else -> numeric (bad strings such as 'Jan-00' -> NaN; inf -> NaN).
    for var in ALL_VARS:
        df[var] = pd.to_numeric(df[var], errors="coerce").replace([np.inf, -np.inf], np.nan)

    # 2c. Sort by pond then time.
    df = df.sort_values(["pond", "time"]).reset_index(drop=True)

    # 2d. Impossible readings -> NaN (the row is kept; other sensors may be fine).
    for var, (lo, hi) in VALID_RANGES.items():
        bad = (df[var] < lo) | (df[var] > hi)
        if var == "nitrate":
            bad = (df[var] < lo) | (df[var] >= hi)
        print(f"  {PRETTY[var]:<17} {bad.sum():>7} out-of-range readings -> NaN "
              f"({100 * bad.mean():.1f}%)")
        df.loc[bad, var] = np.nan

    # 2e. Fish features change slowly / are measured rarely: forward-fill per pond.
    df[CONTEXT_FEATURES] = df.groupby("pond")[CONTEXT_FEATURES].ffill()
    return df


# ---------------------------------------------------------------------------
# Step 3 — Resample onto a fixed 5-minute grid
# ---------------------------------------------------------------------------
def resample_data(df):
    """Per pond: average raw readings into 5-minute bins, then linearly
    interpolate (in time) only short gaps of <= 30 min. Longer outages stay
    NaN so we never fabricate long stretches of data."""
    out = []
    for pond, g in df.groupby("pond"):
        g = g.set_index("time")[ALL_VARS].resample(FREQ).mean()
        g[TARGETS] = g[TARGETS].interpolate(method="time", limit=INTERP_LIMIT,
                                            limit_area="inside")
        g[CONTEXT_FEATURES] = g[CONTEXT_FEATURES].ffill()
        g["pond"] = pond
        out.append(g.reset_index())
    res = pd.concat(out, ignore_index=True)
    print(f"  {len(res)} rows on the {FREQ} grid across {res['pond'].nunique()} ponds")
    return res


# ---------------------------------------------------------------------------
# Step 4 — Supervised windows
# ---------------------------------------------------------------------------
def make_supervised(df, target):
    """Build (X, y) for one target.

    Features at time t: the last N_LAGS values (t, t-5min, ..., t-55min) of all
    9 variables. Label: target at t + HORIZON (30 min ahead).
    Lags/shifts are computed inside each pond so a window never spans two ponds.

    Rows are dropped if the label or any water-quality lag is NaN. NaN fish
    context is allowed (ponds 7-9 never recorded Population); XGBoost handles
    missing values natively.
    """
    frames = []
    for pond, g in df.groupby("pond"):
        g = g.sort_values("time")
        feats = {}
        for var in ALL_VARS:
            for k in range(N_LAGS):
                feats[f"{var}_lag{k}"] = g[var].shift(k)
        sup = pd.DataFrame(feats, index=g.index)
        sup["y"] = g[target].shift(-HORIZON)
        sup["time"] = g["time"]
        sup["pond"] = pond
        frames.append(sup)
    sup = pd.concat(frames, ignore_index=True)

    required = ["y"] + [f"{v}_lag{k}" for v in TARGETS for k in range(N_LAGS)]
    sup = sup.dropna(subset=required)
    # Chronological order across the whole dataset (needed for the time split).
    sup = sup.sort_values(["time", "pond"]).reset_index(drop=True)
    return sup


def feature_columns(sup):
    return [c for c in sup.columns if "_lag" in c]


def relative_features(X):
    """Re-express the same 1-hour window relative to 'now'.

    For each water-quality variable: keep the current level (lag0) and replace
    lag1..lag11 with (lag_k - lag0), i.e. how far the value has moved. This is
    a lossless transform of the same lag window (no new information), but it
    makes the trees depend on recent *dynamics* rather than absolute levels, so
    they still work when the test period contains levels never seen in
    training (e.g. pH probes drifting to ~3.5 in ponds 2 and 6 after August).
    """
    X = X.copy()
    for var in TARGETS:
        now = X[f"{var}_lag0"]
        for k in range(1, N_LAGS):
            X[f"{var}_lag{k}"] = X[f"{var}_lag{k}"] - now
    return X


# ---------------------------------------------------------------------------
# Step 5-7 — Time-series split, baselines, XGBoost, metrics
# ---------------------------------------------------------------------------
def time_split(sup):
    """Chronological split with ONE global cutoff for all ponds.

    test  = rows with t >= cutoff (the latest 20% of the timeline)
    train = rows whose LABEL time t + 30 min is still < cutoff

    The 30-minute purge stops a training label from 'peeking' into the test
    period. Nothing is shuffled.
    """
    cutoff = sup["time"].quantile(1 - TEST_FRAC)
    horizon = pd.Timedelta(minutes=HORIZON * STEP_MINUTES)
    train = sup[sup["time"] + horizon < cutoff]
    test = sup[sup["time"] >= cutoff]
    return train, test, cutoff


def _metrics(y_true, y_pred):
    return (mean_absolute_error(y_true, y_pred),
            float(np.sqrt(mean_squared_error(y_true, y_pred))))


def train_eval(sup, target):
    """Fit baselines + XGBoost for one target, return metrics and artefacts."""
    feats = feature_columns(sup)
    train, test, cutoff = time_split(sup)
    y_test = test["y"].values

    # Baseline 1 — persistence: the value 30 min from now = the value now.
    pers_pred = test[f"{target}_lag0"].values
    # Baseline 2 — seasonal-naive (1-hour season): the value at (target time - 1 h)
    # = t + 30min - 60min = t - 30min = lag (SEASON - HORIZON) = lag6.
    seas_pred = test[f"{target}_lag{SEASON - HORIZON}"].values

    # Early stopping uses the LAST 10% of the training slice (still strictly
    # before the test period), so the test set is never looked at.
    n_val = int(len(train) * VAL_FRAC)
    tr, va = train.iloc[:-n_val], train.iloc[-n_val:]

    def fit(X_tr, y_tr, X_va, y_va):
        model = xgb.XGBRegressor(
            n_estimators=1000, learning_rate=0.05, max_depth=6,
            subsample=0.8, colsample_bytree=0.8, min_child_weight=5,
            objective="reg:squarederror", tree_method="hist",
            early_stopping_rounds=50, random_state=RANDOM_STATE, n_jobs=-1,
        )
        model.fit(X_tr, y_tr, eval_set=[(X_va, y_va)], verbose=False)
        return model

    # XGBoost (level): predicts the raw value y(t+30min) from the raw lags.
    level_model = fit(tr[feats], tr["y"], va[feats], va["y"])
    level_pred = level_model.predict(test[feats])

    # XGBoost (delta): predicts the CHANGE y(t+30min) - y(t) from the
    # relative lag window, then adds it back to the current value:
    #   y_hat(t+30) = y(t) + delta_hat
    now = f"{target}_lag0"
    delta_model = fit(relative_features(tr[feats]), tr["y"] - tr[now],
                      relative_features(va[feats]), va["y"] - va[now])
    delta_pred = test[now].values + delta_model.predict(relative_features(test[feats]))

    results = {
        "target": target,
        "n_train": len(train), "n_test": len(test), "cutoff": cutoff,
        "best_iter_level": level_model.best_iteration,
        "best_iter_delta": delta_model.best_iteration,
    }
    for name, pred in [("persistence", pers_pred), ("seasonal", seas_pred),
                       ("xgb_level", level_pred), ("xgb_delta", delta_pred)]:
        mae, rmse = _metrics(y_test, pred)
        results[f"{name}_mae"], results[f"{name}_rmse"] = mae, rmse

    artefacts = {"test": test, "xgb_pred": delta_pred, "level_pred": level_pred,
                 "pers_pred": pers_pred, "model": delta_model, "features": feats}
    return results, artefacts


# ---------------------------------------------------------------------------
# Step 8 — Plots
# ---------------------------------------------------------------------------
def plot_results(target, art, out_dir=OUTPUT_DIR, days=3):
    """(a) Predicted vs actual on the test slice for the pond with the most
    test data (first `days` days, so the series stays readable).
    (b) Top-20 feature importances (gain)."""
    os.makedirs(out_dir, exist_ok=True)
    test = art["test"].assign(xgb=art["xgb_pred"], lvl=art["level_pred"],
                              pers=art["pers_pred"])
    pond = test["pond"].value_counts().idxmax()
    t = test[test["pond"] == pond].sort_values("time")
    t = t[t["time"] < t["time"].iloc[0] + pd.Timedelta(days=days)]
    # Index by the label timestamp and reindex onto the full grid so that
    # missing periods show as breaks instead of straight connecting lines.
    t = t.set_index(t["time"] + pd.Timedelta(minutes=HORIZON * STEP_MINUTES))
    t = t.reindex(pd.date_range(t.index.min(), t.index.max(), freq=FREQ))
    when = t.index

    fig, ax = plt.subplots(figsize=(12, 4))
    ax.plot(when, t["y"], label="Actual", color="#222222", linewidth=1.2)
    ax.plot(when, t["xgb"], label="XGBoost-delta (+30 min)", color="#1f77b4", linewidth=1.0)
    ax.plot(when, t["lvl"], label="XGBoost-level", color="#2ca02c", linewidth=0.8, alpha=0.7)
    ax.plot(when, t["pers"], label="Persistence", color="#ff7f0e", linewidth=0.8,
            alpha=0.7, linestyle="--")
    ax.set_title(f"{PRETTY[target]} — 30-min-ahead forecast vs actual "
                 f"(test slice, pond {pond}, first {days} days)")
    ax.set_xlabel("Time")
    ax.set_ylabel(PRETTY[target])
    ax.legend(loc="upper right")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, f"pred_vs_actual_{target}.png"), dpi=130)
    plt.close(fig)

    gain = art["model"].get_booster().get_score(importance_type="gain")
    imp = pd.Series(gain).sort_values(ascending=True).tail(20)
    fig, ax = plt.subplots(figsize=(7, 6))
    ax.barh(imp.index, imp.values, color="#1f77b4")
    ax.set_title(f"{PRETTY[target]} — XGBoost-delta top-20 features (gain)\n"
                 f"(lagK of water-quality vars = value K steps ago minus now)", fontsize=10)
    ax.set_xlabel("Average gain")
    ax.grid(axis="x", alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, f"feature_importance_{target}.png"), dpi=130)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="AquaSense water-quality forecasting")
    parser.add_argument("--data", default=DATA_DIR, help="folder containing IoTPond*.csv")
    parser.add_argument("--out", default=OUTPUT_DIR, help="folder for plots/tables")
    args = parser.parse_args()

    print("[1] Loading");    raw = load_data(args.data)
    print("[2] Cleaning");   clean = clean_data(raw)
    print("[3] Resampling"); grid = resample_data(clean)

    rows = []
    for target in TARGETS:  # DO first
        print(f"[4-8] {PRETTY[target]}")
        sup = make_supervised(grid, target)
        res, art = train_eval(sup, target)
        plot_results(target, art, args.out)
        rows.append(res)
        print(f"      train={res['n_train']} test={res['n_test']} "
              f"cutoff={res['cutoff']:%Y-%m-%d %H:%M} "
              f"best_iter level/delta={res['best_iter_level']}/{res['best_iter_delta']}")

    summary = pd.DataFrame(rows)
    os.makedirs(args.out, exist_ok=True)
    summary.to_csv(os.path.join(args.out, "summary.csv"), index=False)

    # Summary table
    models = [("persistence", "Persist"), ("seasonal", "Seasonal"),
              ("xgb_level", "XGB-lvl"), ("xgb_delta", "XGB-Δ")]
    print("\n" + "=" * 118)
    print(f"30-minute-ahead forecast | test = last {int(TEST_FRAC * 100)}% of timeline")
    print("=" * 118)
    header = (f"{'Target':<17}" + "".join(f"{lbl + ' MAE':>13}" for _, lbl in models)
              + "".join(f"{lbl + ' RMSE':>14}" for _, lbl in models) + f"{'n_test':>8}")
    print(header)
    print("-" * len(header))
    for r in rows:
        print(f"{PRETTY[r['target']]:<17}"
              + "".join(f"{r[m + '_mae']:>13.4f}" for m, _ in models)
              + "".join(f"{r[m + '_rmse']:>14.4f}" for m, _ in models)
              + f"{r['n_test']:>8}")

    # Plain-language verdict per target (headline model = XGBoost-delta)
    print("\nVerdict (XGBoost-delta vs the BEST baseline on each metric; + = better):")
    for r in rows:
        best_mae = min(r["persistence_mae"], r["seasonal_mae"])
        best_rmse = min(r["persistence_rmse"], r["seasonal_rmse"])
        d_mae = 100 * (best_mae - r["xgb_delta_mae"]) / best_mae
        d_rmse = 100 * (best_rmse - r["xgb_delta_rmse"]) / best_rmse
        if d_mae > 0 and d_rmse > 0:
            verdict = "BEAT both baselines"
        elif d_mae <= 0 and d_rmse <= 0:
            verdict = "did NOT beat the baselines"
        else:
            verdict = "MIXED (better on one metric only)"
        print(f"  {PRETTY[r['target']]:<17} {verdict:<34} "
              f"MAE {d_mae:+.1f}%  RMSE {d_rmse:+.1f}%")
    print(f"\nPlots + summary.csv written to {args.out}")


if __name__ == "__main__":
    main()
