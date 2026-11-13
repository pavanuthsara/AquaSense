"""Live forecast for one tank: latest readings -> same cleaning as training ->
saved models -> forecast path + early alerts.

Kept free of web code so a later cause-analysis layer (or a test) can call
`forecast_tank` directly.
"""
from __future__ import annotations

import os
import sqlite3
from dataclasses import replace

import joblib
import numpy as np
import pandas as pd

from .alerts import early_alert
from .data_prep import OUT_DIR, load_controller_db, make_lag_dataset, prepare
from .settings import PRETTY, UNITS

EPOCH = pd.Timestamp("1970-01-01")


def _epoch(t: pd.Timestamp) -> float:
    return (t - EPOCH) / pd.Timedelta(seconds=1)


def load_bundle(path: str) -> dict:
    return joblib.load(path)


def load_reliability(out_dir: str = OUT_DIR) -> dict[tuple[str, str], dict]:
    """Held-out alert scores per (parameter, model) from evaluate.py, so the
    dashboard can say how far to trust a warning."""
    path = os.path.join(out_dir, "alert_metrics.csv")
    if not os.path.exists(path):
        return {}
    df = pd.read_csv(path)
    return {(r["target"], r["model"]): r for r in df.to_dict("records")}


def latest_ts(db_path: str, tank: str) -> float | None:
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
        row = conn.execute("SELECT MAX(ts) FROM readings WHERE tank_id = ?", (tank,)).fetchone()
    return row[0]


def forecast_tank(db_path: str, tank: str, bundle: dict, limits: dict,
                  reliability: dict | None = None,
                  sources: tuple[str, ...] = ("payload", "simulated")) -> dict:
    """Forecast every parameter of `tank` from its latest readings.

    "Now" is the tank's newest reading, not the wall clock, so CSV replays of
    2021 data forecast correctly. A parameter gets no forecast (with a reason)
    when its last `lag_steps` cleaned values are not all present and recent.
    """
    cfg = replace(bundle["cfg"], min_pond_rows=0)
    end = latest_ts(db_path, tank)
    out = {"tank_id": tank, "now": end, "freq_min": cfg.freq_min,
           "horizon_steps": cfg.horizon_steps, "parameters": {}, "early_alerts": []}
    if end is None:
        return out

    # lag window + room for the trailing spike filter and denoise to warm up
    warmup = cfg.lag_steps + cfg.hampel_window + cfg.smooth_steps + 1
    raw = load_controller_db(db_path, tank, sources=sources,
                             since=end - warmup * cfg.freq_min * 60)
    grid = prepare(raw, cfg)[0] if len(raw) else None
    newest_bin = pd.Timestamp(end, unit="s").floor(cfg.freq)
    step = pd.Timedelta(minutes=cfg.freq_min)

    for p, model in bundle["models"].items():
        entry = {"label": PRETTY[p], "unit": UNITS[p], "model": model.name,
                 "limits": {"min": limits.get(p, (None, None))[0],
                            "max": limits.get(p, (None, None))[1]},
                 "reliability": _reliability_view((reliability or {}).get((p, model.name))),
                 "current": None, "as_of": None, "forecast": [], "early_alert": None,
                 "reason": None}
        out["parameters"][p] = entry
        sup = make_lag_dataset(grid, p, cfg, require_labels=False) if grid is not None else None
        if sup is None or sup.empty:
            entry["reason"] = f"needs {cfg.lag_steps * cfg.freq_min} min of continuous readings"
            continue
        row = sup.iloc[[-1]]
        t0 = row["time"].iloc[0]
        if newest_bin - t0 > 2 * step:
            entry["reason"] = "no recent readings"
            continue
        path = model.predict(row)[0]
        current = float(row[f"{p}_lag0"].iloc[0])
        entry.update(current=round(current, 3), as_of=_epoch(t0),
                     forecast=[{"ts": _epoch(t0 + (h + 1) * step), "value": round(float(v), 3)}
                               for h, v in enumerate(path)])
        if p in limits:
            # bundles trained before margins existed alert at the plain limit
            margin = bundle.get("margins", {}).get(p, 0.0)
            entry["alert_margin"] = margin
            alert = early_alert(p, t0, current, path, limits[p], cfg, margin=margin)
            if alert:
                a = alert.to_dict()
                a["breach_ts"] = _epoch(pd.Timestamp(a.pop("breach_at")))
                entry["early_alert"] = a
                out["early_alerts"].append(a)
    out["early_alerts"].sort(key=lambda a: a["eta_min"])
    return out


def _reliability_view(r: dict | None) -> dict | None:
    if not r:
        return None
    clean = lambda v: None if v is None or (isinstance(v, float) and np.isnan(v)) else v
    return {"precision": clean(r.get("precision")), "warned_pct": clean(r.get("warned_%")),
            "lead_median_h": clean(r.get("lead_med_h")), "events": clean(r.get("events"))}
