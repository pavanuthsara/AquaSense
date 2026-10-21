"""Step 4 — Evaluate the step-2 models on held-out data.

Split: ONE chronological cutoff for all ponds. Test = the latest TEST_FRAC of
the timeline; train = rows whose last label (t + horizon) is still before the
cutoff, so no training label peeks into the test period. Nothing is shuffled.
One global cutoff (not one per pond) matters: ponds share a site and weather,
so training on pond A's September while testing pond B's September would leak.

Metrics per parameter x model x horizon step: RMSE, MAE, MAPE, R², and skill
(1 - RMSE / RMSE_persistence: > 0 means better than "nothing changes").

Early alerts: each model's alert margin (see alerts.py) is tuned for F1 on a
validation slice (latest 20% of train), then scored once on test. f1_untuned
is the same model alerting at the plain limit, for comparison.

Useful lead time: the longest horizon at which the best model still has
R² >= --min-r2 AND beats persistence (skill > 0).

Run:
    python -m prediction.evaluate
    python -m prediction.evaluate --freq 5 --lags 24 --horizon 36 --models persistence,ridge
"""
from __future__ import annotations

import argparse
import os
import time

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from .alerts import CONFIRM_STEPS, alert_metrics, load_safe_ranges, tune_margin
from .data_prep import (DATA_DIR, OUT_DIR, label_matrix, load_controller_db, load_csv_dir,
                        make_lag_dataset, prepare)
from .models import MODELS
from .settings import PRETTY, PrepConfig

TEST_FRAC = 0.2

# MAPE divides by the true value, so it explodes near zero (ammonia often reads
# 0.001). It is computed only where |true| >= this floor.
MAPE_FLOOR = {"do": 0.5, "ph": 1.0, "ammonia": 0.05, "temperature": 1.0}


def time_split(sup: pd.DataFrame, cfg: PrepConfig, test_frac: float = TEST_FRAC):
    cutoff = sup["time"].quantile(1 - test_frac)
    horizon = pd.Timedelta(minutes=cfg.horizon_steps * cfg.freq_min)
    return sup[sup["time"] + horizon < cutoff], sup[sup["time"] >= cutoff], cutoff


def horizon_metrics(y: np.ndarray, pred: np.ndarray, target: str) -> pd.DataFrame:
    rows = []
    for h in range(y.shape[1]):
        yt, yp = y[:, h], pred[:, h]
        m = np.abs(yt) >= MAPE_FLOOR[target]
        rows.append({"h": h + 1,
                     "rmse": float(np.sqrt(mean_squared_error(yt, yp))),
                     "mae": mean_absolute_error(yt, yp),
                     "mape_%": 100 * float(np.mean(np.abs((yt[m] - yp[m]) / yt[m]))) if m.any() else np.nan,
                     "r2": r2_score(yt, yp)})
    return pd.DataFrame(rows)


def evaluate_target(grid, target, cfg, model_names, limits):
    sup = make_lag_dataset(grid, target, cfg)
    train, test, cutoff = time_split(sup, cfg)
    # alert margins are chosen on the latest 20% of TRAIN, never on test
    inner, val, _ = time_split(train, cfg)
    y, y_val = label_matrix(test, cfg), label_matrix(val, cfg)
    frames, preds, alerts = [], {}, []
    for name in model_names:
        t0 = time.time()
        model = MODELS[name](cfg).fit(train, target)
        preds[name] = model.predict(test)
        m = horizon_metrics(y, preds[name], target)
        m.insert(0, "model", model.name)
        m["fit_s"] = round(time.time() - t0, 1)
        frames.append(m)
        tuner = MODELS[name](cfg).fit(inner, target)
        margin, _ = tune_margin(val, y_val, tuner.predict(val), target, limits, cfg)
        untuned = alert_metrics(test, y, preds[name], target, limits, cfg)["f1"]
        alerts.append({"target": target, "model": model.name, "margin": margin,
                       **alert_metrics(test, y, preds[name], target, limits, cfg, margin=margin),
                       "f1_untuned": untuned})
    # Oracle: alerts from the TRUE future. Its scores are the ceiling the data
    # allows (e.g. a breach after a sensor outage cannot be warned about).
    alerts.append({"target": target, "model": "(perfect forecast)", "margin": 0.0,
                   **alert_metrics(test, y, y, target, limits, cfg)})
    res = pd.concat(frames, ignore_index=True)
    base = res[res["model"] == "Persistence"].set_index("h")["rmse"]
    res["skill"] = 1 - res["rmse"] / res["h"].map(base)
    res.insert(0, "target", target)
    info = {"target": target, "n_train": len(train), "n_test": len(test),
            "cutoff": cutoff, "test_ponds": test["series"].nunique()}
    return res, info, test, preds, y, pd.DataFrame(alerts)


def useful_lead_time(res: pd.DataFrame, cfg: PrepConfig, min_r2: float):
    """Best model = lowest mean RMSE over all horizons. Its lead time is the
    longest h for which every step up to h has R² >= min_r2 and skill > 0."""
    trained = res[res["model"] != "Persistence"]
    best = trained.groupby("model")["rmse"].mean().idxmin()
    b = trained[trained["model"] == best].sort_values("h")
    ok = (b["r2"] >= min_r2) & (b["skill"] > 0)
    steps = int(ok.cumprod().sum())
    return best, steps * cfg.freq_min / 60


def plot_rmse(all_res: pd.DataFrame, cfg: PrepConfig, out_dir: str) -> str:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    targets = all_res["target"].unique()
    fig, axes = plt.subplots(1, len(targets), figsize=(4.2 * len(targets), 3.6))
    for ax, t in zip(np.atleast_1d(axes), targets):
        for model, g in all_res[all_res["target"] == t].groupby("model", sort=False):
            ax.plot(g["h"] * cfg.freq_min / 60, g["rmse"], marker=".", label=model)
        ax.set_title(PRETTY[t])
        ax.set_xlabel("hours ahead")
        ax.grid(alpha=0.3)
    np.atleast_1d(axes)[0].set_ylabel("RMSE (test)")
    np.atleast_1d(axes)[0].legend(fontsize=8)
    fig.tight_layout()
    path = os.path.join(out_dir, "rmse_vs_horizon.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


def plot_example(target, test, preds, y, cfg, out_dir, h_hours=(1, 2, 3)) -> str:
    """Actual vs forecast made h hours earlier, for the test pond with most rows."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    pond = test["series"].value_counts().idxmax()
    sel = (test["series"] == pond).to_numpy()
    t = test.loc[sel, "time"]
    # one panel per distinct step that fits in the horizon (10-min horizon -> 1 panel)
    steps = sorted({min(max(int(hh * 60 / cfg.freq_min), 1), cfg.horizon_steps) for hh in h_hours})
    fig, axes = plt.subplots(len(steps), 1, figsize=(12, 2.6 * len(steps)), sharex=True)
    axes = np.atleast_1d(axes)
    for ax, h in zip(axes, steps):
        when = (t + pd.Timedelta(minutes=h * cfg.freq_min)).to_numpy()
        order = np.argsort(when)[:6 * 24 * 60 // cfg.freq_min // 6 * 3]      # ~3 days of rows
        ax.plot(when[order], y[sel, h - 1][order], ".", ms=2, color="#222", label="actual")
        for name, p in preds.items():
            if name != "persistence":
                ax.plot(when[order], p[sel, h - 1][order], ".", ms=2, label=name)
        ax.set_ylabel(f"+{h * cfg.freq_min} min" if h * cfg.freq_min < 60
                      else f"+{h * cfg.freq_min / 60:g} h")
        ax.grid(alpha=0.3)
    axes[0].set_title(f"{PRETTY[target]} — forecast vs actual, test set, {pond}")
    axes[0].legend(fontsize=8, markerscale=4)
    fig.tight_layout()
    path = os.path.join(out_dir, f"forecast_example_{target}.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


def main() -> None:
    ap = argparse.ArgumentParser(description="AquaSense forecasting: model comparison")
    ap.add_argument("--data", default=DATA_DIR)
    ap.add_argument("--db")
    ap.add_argument("--tank")
    ap.add_argument("--freq", type=int, default=PrepConfig.freq_min)
    ap.add_argument("--lags", type=int, default=PrepConfig.lag_steps)
    ap.add_argument("--horizon", type=int, default=PrepConfig.horizon_steps)
    ap.add_argument("--models", default=",".join(MODELS))
    ap.add_argument("--targets", default=",".join(PrepConfig().params))
    ap.add_argument("--min-r2", type=float, default=0.7,
                    help="R² a horizon step needs to count as reliable")
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    cfg = PrepConfig(freq_min=args.freq, lag_steps=args.lags, horizon_steps=args.horizon)
    model_names = args.models.split(",")
    if "persistence" not in model_names:
        model_names.insert(0, "persistence")       # needed for the skill score
    os.makedirs(args.out, exist_ok=True)
    pd.set_option("display.width", 200)

    raw = load_controller_db(args.db, args.tank) if args.db else load_csv_dir(args.data)
    grid, _ = prepare(raw, cfg)

    limits = load_safe_ranges()
    all_res, infos, lead, all_alerts = [], [], [], []
    for target in args.targets.split(","):
        res, info, test, preds, y, al = evaluate_target(grid, target, cfg, model_names,
                                                        limits[target])
        all_res.append(res)
        all_alerts.append(al)
        infos.append(info)
        best, hours = useful_lead_time(res, cfg, args.min_r2)
        lead.append({"target": target, "best_model": best, "useful_lead_h": hours})
        plot_example(target, test, preds, y, cfg, args.out)
        print(f"[{PRETTY[target]}] train={info['n_train']:,} test={info['n_test']:,} "
              f"({info['test_ponds']} ponds) cutoff={info['cutoff']:%Y-%m-%d}")
    all_res = pd.concat(all_res, ignore_index=True)
    all_res.to_csv(os.path.join(args.out, "metrics_by_horizon.csv"), index=False)

    show = sorted({1, 60 // cfg.freq_min, 120 // cfg.freq_min, cfg.horizon_steps}
                  & set(range(1, cfg.horizon_steps + 1)))
    for metric in ["rmse", "mae", "mape_%", "r2", "skill"]:
        tbl = all_res[all_res["h"].isin(show)].pivot_table(
            index=["target", "model"], columns="h", values=metric, sort=False)
        tbl.columns = [f"+{h * cfg.freq_min / 60:g}h" for h in tbl.columns]
        print(f"\n=== {metric.upper()} on held-out test data")
        print(tbl.round(3).to_string())

    fit = all_res.groupby(["target", "model"], sort=False)["fit_s"].first().unstack()
    print("\n=== fit time (s)\n" + fit.to_string())
    lead = pd.DataFrame(lead)
    print(f"\n=== useful lead time (best model; every step up to it has R² >= {args.min_r2} "
          f"and beats persistence)\n" + lead.to_string(index=False))
    lead.to_csv(os.path.join(args.out, "lead_time.csv"), index=False)

    all_alerts = pd.concat(all_alerts, ignore_index=True)
    all_alerts.to_csv(os.path.join(args.out, "alert_metrics.csv"), index=False)
    print(f"\n=== early alerts on held-out data (limits from controller/config.yaml, "
          f"breach = {CONFIRM_STEPS} consecutive steps, horizon "
          f"{cfg.horizon_steps * cfg.freq_min / 60:g} h)")
    print(all_alerts.round(2).to_string(index=False))
    print(f"\nwrote {plot_rmse(all_res, cfg, args.out)} and metrics_by_horizon.csv")


if __name__ == "__main__":
    main()
