"""Train the deployed forecasters on ALL available data and save them.

evaluate.py decides which model to trust (held-out test); this script refits
that choice on everything, so the live service uses every row we have.

Run:
    python -m prediction.train                                  # IoTPond CSVs
    python -m prediction.train --db controller/controller.db    # your own logs
"""
from __future__ import annotations

import argparse
import datetime as dt
import os

import joblib

from .alerts import load_safe_ranges, tune_margin
from .data_prep import (DATA_DIR, OUT_DIR, label_matrix, load_controller_db, load_csv_dir,
                        make_lag_dataset, prepare)
from .evaluate import time_split
from .models import MODELS
from .settings import PRETTY, PrepConfig

MODEL_PATH = os.path.join(OUT_DIR, "models", "forecaster.joblib")

# Chosen from the held-out comparison (see evaluate.py / README): gradient
# boosting gave the best mix of alert precision and warned breaches for every
# parameter. Change one name here to deploy another model for a parameter.
DEPLOYED = {"temperature": "gboost", "ammonia": "gboost", "do": "gboost", "ph": "gboost"}


def train_all(grid, cfg: PrepConfig, choice: dict[str, str],
              limits: dict | None = None) -> tuple[dict, dict]:
    """Returns (models, alert margins). Each margin is tuned for F1 on the
    latest 20% of the data with a model fitted on the rest; the deployed model
    is then refitted on everything."""
    limits = limits or load_safe_ranges()
    models, margins = {}, {}
    for target, name in choice.items():
        sup = make_lag_dataset(grid, target, cfg)
        inner, val, _ = time_split(sup, cfg)
        tuner = MODELS[name](cfg).fit(inner, target)
        margins[target], f1 = tune_margin(val, label_matrix(val, cfg), tuner.predict(val),
                                          target, limits[target], cfg)
        models[target] = MODELS[name](cfg).fit(sup, target)
        print(f"  {PRETTY[target]:<17} {models[target].name:<12} trained on {len(sup):,} rows  "
              f"alert margin {margins[target]:+.3f} (validation F1 {f1:.2f})")
    return models, margins


def main() -> None:
    ap = argparse.ArgumentParser(description="AquaSense forecasting: train + save")
    ap.add_argument("--data", default=DATA_DIR)
    ap.add_argument("--db")
    ap.add_argument("--tank")
    ap.add_argument("--freq", type=int, default=PrepConfig.freq_min)
    ap.add_argument("--lags", type=int, default=PrepConfig.lag_steps)
    ap.add_argument("--horizon", type=int, default=PrepConfig.horizon_steps)
    ap.add_argument("--out", default=MODEL_PATH)
    args = ap.parse_args()
    cfg = PrepConfig(freq_min=args.freq, lag_steps=args.lags, horizon_steps=args.horizon)

    raw = load_controller_db(args.db, args.tank) if args.db else load_csv_dir(args.data)
    grid, _ = prepare(raw, cfg)
    models, margins = train_all(grid, cfg, DEPLOYED)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    joblib.dump({"cfg": cfg, "models": models, "margins": margins,
                 "trained_at": dt.datetime.now().isoformat(timespec="seconds"),
                 "trained_on": args.db or args.data}, args.out, compress=3)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
