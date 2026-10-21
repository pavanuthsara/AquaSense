"""Step 1 — Data preparation for forecasting.

    raw logs (IoTPond CSVs or the controller's SQLite `readings` table)
      -> clean_raw:  plausibility filter, stuck-sensor removal, duplicate ponds
      -> resample:   fixed-interval median bins, spike filter, short-gap fill,
                     optional denoise
      -> make_lag_dataset: one row per time t with the past `lag_steps` values
                     of every parameter (features) and the next `horizon_steps`
                     values of the target (labels)

Every filter on the grid is TRAILING (looks only at the past), so the exact
same cleaning can run live on the backend without peeking into the future.

Run:
    python -m prediction.data_prep                      # IoTPond CSVs in ./data
    python -m prediction.data_prep --db controller/controller.db --tank pond1
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sqlite3

import numpy as np
import pandas as pd

from .settings import MIN_SAMPLES_PER_BIN, PARAMS, PLAUSIBLE, PRETTY, STUCK_HOURS, PrepConfig

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # water_quality/
DATA_DIR = os.path.join(ROOT, "data")
OUT_DIR = os.path.join(ROOT, "outputs", "prediction")

# Smallest MAD the spike filter trusts, roughly one sensor resolution step.
# Without a floor, a flat stretch (MAD = 0) would flag any change as a spike.
HAMPEL_MIN_MAD = {"temperature": 0.1, "do": 0.1, "ph": 0.02, "ammonia": 0.01}


# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------
def _canonical_name(col: str) -> str | None:
    """'Dissolved Oxygen(g/ml)', 'DISOLVED OXYGEN', 'PH', ... -> canonical name."""
    base = str(col).split("(")[0].strip().lower()
    letters = re.sub(r"[^a-z]", "", base)
    if letters == "createdat" or base == "unnamed: 0":   # pond 8: headerless col 0
        return "time"
    if "temp" in letters:
        return "temperature"
    if "oxygen" in letters or "disolved" in letters or "dissolved" in letters:
        return "do"
    if letters == "ph":
        return "ph"
    if "ammonia" in letters:
        return "ammonia"
    return None


_TS = re.compile(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})")


def _series_key(name: str) -> int:
    """Numeric id in a series name, so pond2 sorts before pond10."""
    m = re.search(r"(\d+)", str(name))
    return int(m.group(1)) if m else 0


def load_csv_dir(data_dir: str = DATA_DIR) -> pd.DataFrame:
    """Read every IoTPond*.csv into one long frame: series, time, <params>.

    Timezone suffixes (CET/UTC/+01:00) are dropped; each pond is internally
    consistent, which is all lag features need. Date-only rows ('5/12/2021')
    cannot be placed on a grid and are dropped.
    """
    files = sorted(glob.glob(os.path.join(data_dir, "*[Pp]ond*.csv")),
                   key=lambda p: _series_key(os.path.basename(p)))
    if not files:
        raise FileNotFoundError(f"No IoTPond*.csv files in {data_dir}")
    frames = []
    for path in files:
        raw = pd.read_csv(path, dtype=str, low_memory=False)
        mapping = {}
        for col in raw.columns:
            name = _canonical_name(col)
            if name and name not in mapping.values():
                mapping[col] = name
        if "time" not in mapping.values():
            mapping[raw.columns[0]] = "time"
        df = raw[list(mapping)].rename(columns=mapping)
        parts = df["time"].str.extract(_TS)
        df["time"] = pd.to_datetime(parts[0] + " " + parts[1],
                                    format="%Y-%m-%d %H:%M:%S", errors="coerce")
        for p in PARAMS:
            df[p] = (pd.to_numeric(df[p], errors="coerce").replace([np.inf, -np.inf], np.nan)
                     if p in df else np.nan)
        df["series"] = f"pond{_series_key(os.path.basename(path))}"
        frames.append(df.dropna(subset=["time"])[["series", "time"] + PARAMS])
    return pd.concat(frames, ignore_index=True)


def load_controller_db(db_path: str, tank: str | None = None,
                       sources: tuple[str, ...] = ("payload",),
                       since: float | None = None) -> pd.DataFrame:
    """Read the controller's long-format `readings` table into the same shape.

    Only real sensor values are used by default (`source='payload'`): training
    on the server's simulated values would teach the model the simulator.
    FAULT readings are skipped; clean_raw applies its own plausibility filter.
    `since` (epoch seconds) limits the read to recent rows for live forecasts.
    """
    q = (f"SELECT tank_id, ts, parameter, value FROM readings "
         f"WHERE status != 'FAULT' AND value IS NOT NULL "
         f"AND parameter IN ({','.join('?' * len(PARAMS))}) "
         f"AND source IN ({','.join('?' * len(sources))})")
    args: list = [*PARAMS, *sources]
    if tank:
        q += " AND tank_id = ?"
        args.append(tank)
    if since is not None:
        q += " AND ts >= ?"
        args.append(since)
    # read-only: the controller owns this database
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
        long = pd.read_sql_query(q, conn, params=args)
    if long.empty:
        return pd.DataFrame(columns=["series", "time"] + PARAMS)
    wide = long.pivot_table(index=["tank_id", "ts"], columns="parameter",
                            values="value", aggfunc="mean").reset_index()
    wide = wide.rename(columns={"tank_id": "series"})
    wide["time"] = pd.to_datetime(wide["ts"], unit="s")
    for p in PARAMS:
        if p not in wide:
            wide[p] = np.nan
    return wide[["series", "time"] + PARAMS]


# ---------------------------------------------------------------------------
# Clean raw readings
# ---------------------------------------------------------------------------
def _stuck_mask(times: pd.Series, values: pd.Series, max_hours: float) -> pd.Series:
    """True where a value belongs to a run of identical readings lasting longer
    than `max_hours` (a frozen sensor, not stable water)."""
    run = (values != values.shift()).cumsum()
    by_run = times.groupby(run)
    span = by_run.transform("max") - by_run.transform("min")
    return values.notna() & (span > pd.Timedelta(hours=max_hours))


def clean_raw(raw: pd.DataFrame, cfg: PrepConfig) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Drop thin series and duplicated rows, then null out implausible and
    stuck readings. Returns (clean, per-series report of what was removed)."""
    df = raw.sort_values(["series", "time"], key=lambda s: s.map(_series_key)
                         if s.name == "series" else s).reset_index(drop=True)

    counts = df.groupby("series").size()
    thin = counts[counts < cfg.min_pond_rows].index
    df = df[~df["series"].isin(thin)]

    # A row identical (time + every value) to one already seen in an earlier
    # series is a copy: IoTPond2 repeats IoTpond1 from July onward.
    dup = df.duplicated(subset=["time"] + PARAMS, keep="first") & df[PARAMS].notna().any(axis=1)
    report = pd.DataFrame({"raw_rows": df.groupby("series").size(),
                           "duplicate_rows": dup.groupby(df["series"]).sum()})
    df = df[~dup].reset_index(drop=True)

    for p in cfg.params:
        lo, hi = PLAUSIBLE[p]
        bad = (df[p] < lo) | (df[p] > hi)
        report[f"{p}_implausible_%"] = 100 * bad.groupby(df["series"]).mean()
        df.loc[bad, p] = np.nan

        stuck = pd.Series(False, index=df.index)
        for _, g in df.groupby("series"):
            stuck.loc[g.index] = _stuck_mask(g["time"], g[p], STUCK_HOURS[p])
        report[f"{p}_stuck_%"] = 100 * stuck.groupby(df["series"]).mean()
        df.loc[stuck, p] = np.nan

    for s in thin:
        report.loc[s, "raw_rows"] = counts[s]
    report["kept"] = ~report.index.isin(thin)
    return df, report.round(1)


# ---------------------------------------------------------------------------
# Resample onto a fixed grid
# ---------------------------------------------------------------------------
def _hampel_trailing(x: pd.Series, window: int, sigmas: float, min_mad: float) -> pd.Series:
    """Null out spikes: points further than `sigmas` robust std-devs from the
    median of the trailing window."""
    med = x.rolling(window, min_periods=3).median()
    mad = (x - med).abs().rolling(window, min_periods=3).median().clip(lower=min_mad)
    spike = (x - med).abs() > sigmas * 1.4826 * mad
    return x.mask(spike)


def _fill_short_gaps(x: pd.Series, max_steps: int) -> pd.Series:
    """Linearly interpolate NaN runs of at most `max_steps`; longer outages are
    left untouched (pandas' `limit` would half-fill them instead)."""
    if max_steps <= 0:
        return x
    isna = x.isna()
    run = (isna != isna.shift()).cumsum()
    run_len = isna.groupby(run).transform("sum")
    filled = x.interpolate(method="linear", limit_area="inside")
    return x.where(~(isna & (run_len <= max_steps)), filled)


def resample(clean: pd.DataFrame, cfg: PrepConfig) -> pd.DataFrame:
    """Per series: median of raw readings per `freq` bin (robust to the 20-s
    sensor noise), drop bins with too few raw samples, remove spikes, fill
    short gaps, then denoise with a trailing rolling median.

    Output: series, time, <params>, n_raw, <param>_filled
    """
    out = []
    for series, g in clean.groupby("series", sort=False):
        g = g.set_index("time")[cfg.params]
        binned = g.resample(cfg.freq)
        grid = binned.median()
        n = binned.count()
        for p in cfg.params:
            grid[p] = grid[p].mask(n[p] < MIN_SAMPLES_PER_BIN[p])

        for p in cfg.params:
            x = _hampel_trailing(grid[p], cfg.hampel_window, cfg.hampel_sigmas,
                                 HAMPEL_MIN_MAD[p])
            observed = x.notna()
            x = _fill_short_gaps(x, cfg.gap_fill_steps)
            if cfg.smooth_steps > 1:
                present = x.notna()
                x = x.rolling(cfg.smooth_steps, min_periods=1).median().where(present)
            grid[p] = x
            grid[f"{p}_filled"] = x.notna() & ~observed

        grid["n_raw"] = n.max(axis=1)
        grid["series"] = series
        out.append(grid.reset_index())
    cols = ["series", "time"] + cfg.params + ["n_raw"] + [f"{p}_filled" for p in cfg.params]
    return pd.concat(out, ignore_index=True)[cols]


# ---------------------------------------------------------------------------
# Supervised lag dataset
# ---------------------------------------------------------------------------
def make_lag_dataset(grid: pd.DataFrame, target: str, cfg: PrepConfig,
                     require_labels: bool = True) -> pd.DataFrame:
    """One row per (series, t).

    Features: <p>_lag0 .. <p>_lag{L-1} for every parameter (lag0 = value at t),
              plus time-of-day as sin/cos (DO and temperature follow a daily cycle).
    Labels:   y_h1 .. y_hH = target at t+1 .. t+H steps.

    A row needs its full target lag window (and, for training, every label).
    Other parameters' lags may be NaN: gradient boosting handles that, and the
    linear models only use the target's own lags.
    Shifts happen inside each series on a gap-preserving grid, so a window
    never spans two ponds or bridges a long outage.
    """
    frames = []
    for series, g in grid.groupby("series", sort=False):
        g = g.sort_values("time")
        cols = {}
        for p in cfg.params:
            for k in range(cfg.lag_steps):
                cols[f"{p}_lag{k}"] = g[p].shift(k)
        for h in range(1, cfg.horizon_steps + 1):
            cols[f"y_h{h}"] = g[target].shift(-h)
        sup = pd.DataFrame(cols, index=g.index)
        hour = g["time"].dt.hour + g["time"].dt.minute / 60
        sup["tod_sin"] = np.sin(2 * np.pi * hour / 24)
        sup["tod_cos"] = np.cos(2 * np.pi * hour / 24)
        sup.insert(0, "time", g["time"])
        sup.insert(0, "series", series)
        frames.append(sup)
    sup = pd.concat(frames, ignore_index=True)

    required = [f"{target}_lag{k}" for k in range(cfg.lag_steps)]
    if require_labels:
        required += [f"y_h{h}" for h in range(1, cfg.horizon_steps + 1)]
    return sup.dropna(subset=required).sort_values(["time", "series"]).reset_index(drop=True)


def label_matrix(sup: pd.DataFrame, cfg: PrepConfig) -> np.ndarray:
    """(n, H) array of the true future values y_h1 .. y_hH."""
    return sup[[f"y_h{h}" for h in range(1, cfg.horizon_steps + 1)]].to_numpy()


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
def grid_report(grid: pd.DataFrame, cfg: PrepConfig) -> pd.DataFrame:
    rows = {}
    for series, g in grid.groupby("series", sort=False):
        r = {"start": g["time"].min().strftime("%Y-%m-%d"),
             "end": g["time"].max().strftime("%Y-%m-%d"),
             "grid_rows": len(g)}
        for p in cfg.params:
            r[f"{p}_cov_%"] = 100 * g[p].notna().mean()
        rows[series] = r
    return pd.DataFrame(rows).T


def plot_before_after(raw: pd.DataFrame, grid: pd.DataFrame, cfg: PrepConfig,
                      series: str, days: int = 3, out_dir: str = OUT_DIR) -> str:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    g = grid[grid["series"] == series].set_index("time")
    start = g[cfg.params].dropna().index.min()
    end = start + pd.Timedelta(days=days)
    r = raw[(raw["series"] == series) & raw["time"].between(start, end)].set_index("time")
    g = g.loc[start:end]

    fig, axes = plt.subplots(len(cfg.params), 1, figsize=(12, 2.4 * len(cfg.params)), sharex=True)
    for ax, p in zip(axes, cfg.params):
        lo, hi = PLAUSIBLE[p]
        ax.plot(r.index, r[p].where(r[p].between(lo, hi)), color="#bbbbbb", lw=0.5,
                label="raw (20 s, plausible only)")
        ax.plot(g.index, g[p], color="#1f77b4", lw=1.3, label=f"clean ({cfg.freq})")
        ax.set_ylabel(PRETTY[p])
        ax.grid(alpha=0.3)
    axes[0].legend(loc="upper right", fontsize=8)
    axes[0].set_title(f"{series}: raw vs cleaned, first {days} days")
    fig.tight_layout()
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"prep_{series}.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


def prepare(source_df: pd.DataFrame, cfg: PrepConfig) -> tuple[pd.DataFrame, pd.DataFrame]:
    """raw -> clean grid. Returns (grid, cleaning report)."""
    clean, report = clean_raw(source_df, cfg)
    return resample(clean, cfg), report


def main() -> None:
    ap = argparse.ArgumentParser(description="AquaSense forecasting: data preparation")
    ap.add_argument("--data", default=DATA_DIR, help="folder with IoTPond*.csv")
    ap.add_argument("--db", help="controller SQLite DB instead of CSVs")
    ap.add_argument("--tank", help="tank id when reading --db")
    ap.add_argument("--freq", type=int, default=PrepConfig.freq_min, help="interval, minutes")
    ap.add_argument("--lags", type=int, default=PrepConfig.lag_steps)
    ap.add_argument("--horizon", type=int, default=PrepConfig.horizon_steps)
    ap.add_argument("--smooth", type=int, default=PrepConfig.smooth_steps)
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    cfg = PrepConfig(freq_min=args.freq, lag_steps=args.lags,
                     horizon_steps=args.horizon, smooth_steps=args.smooth)

    pd.set_option("display.width", 200)
    pd.set_option("display.max_columns", 40)

    raw = load_controller_db(args.db, args.tank) if args.db else load_csv_dir(args.data)
    print(f"[load] {len(raw):,} raw rows from {raw['series'].nunique()} series")

    grid, report = prepare(raw, cfg)
    print("\n[clean] what was removed per series (% of that series' raw rows)")
    print(report.to_string())

    print(f"\n[grid] {cfg.freq} grid, gaps <= {cfg.gap_fill_min} min filled, "
          f"trailing median denoise = {cfg.smooth_steps} steps")
    print(grid_report(grid, cfg).round(1).to_string())

    print(f"\n[lags] usable supervised rows per target "
          f"(window {cfg.lag_steps} x {cfg.freq} = {cfg.lag_steps * cfg.freq_min / 60:g} h, "
          f"horizon {cfg.horizon_steps} x {cfg.freq} = {cfg.horizon_steps * cfg.freq_min / 60:g} h)")
    for p in cfg.params:
        sup = make_lag_dataset(grid, p, cfg)
        days = len(sup) * cfg.freq_min / 1440
        per = sup.groupby("series").size().to_dict()
        print(f"  {PRETTY[p]:<17} {len(sup):>7,} rows (~{days:,.0f} pond-days)  {per}")

    print("\n[sample] cleaned grid, pond with most data, first complete rows")
    best = grid.dropna(subset=cfg.params).groupby("series").size().idxmax()
    print(grid[grid["series"] == best].dropna(subset=cfg.params).head(8)
          .round({p: 3 for p in cfg.params}).to_string(index=False))
    print("\n[describe] cleaned values (all series)")
    print(grid[cfg.params].describe().round(3).to_string())

    os.makedirs(args.out, exist_ok=True)
    grid_path = os.path.join(args.out, "clean_grid.csv.gz")
    grid.to_csv(grid_path, index=False)
    report.to_csv(os.path.join(args.out, "cleaning_report.csv"))
    plot = plot_before_after(raw, grid, cfg, best, out_dir=args.out)
    print(f"\nwrote {grid_path}\nwrote {plot}")


if __name__ == "__main__":
    main()
