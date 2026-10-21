"""Build AquaSense_Prediction_Colab.ipynb: a self-contained Colab notebook that
embeds the current prediction code (written out with %%writefile), so it runs
without cloning the repo. Re-run after changing the code:

    python -m prediction.make_colab
"""
from __future__ import annotations

import json
import os

import sklearn

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "AquaSense_Prediction_Colab.ipynb")

EMBED = ["prediction/__init__.py", "prediction/settings.py", "prediction/data_prep.py",
         "prediction/models.py", "prediction/alerts.py", "prediction/evaluate.py",
         "prediction/train.py", "controller/config.yaml"]


def md(text: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": text.strip("\n")}


def code(text: str) -> dict:
    return {"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
            "source": text.strip("\n")}


def build() -> dict:
    cells = [
        md("""
# AquaSense — Water-quality forecasting + early alerts (Colab)

Runs the AquaSense prediction layer end to end on the Udanor IoTPond data:

1. **Data preparation**: clean the 20-s sensor logs into a 10-min grid with lag features
2. **Model comparison**: Persistence, Linear trend, Ridge, Gradient boosting
3. **Evaluation**: RMSE, MAE, MAPE, R², skill vs persistence, per horizon step
4. **Early-alert scores**: precision, recall, **F1**, breaches warned, lead time
5. **Train + download** the final models for the dashboard's forecasting service

Run the cells top to bottom (**Runtime → Run all**). A CPU runtime is enough. At the
default 10-min horizon the whole notebook takes about 2–3 min; with a 3-h horizon
(`HORIZON_STEPS = 18`) gradient boosting fits 18 models per parameter (~15 min).
"""),
        md("## 0. Setup"),
        code(f"""
# Same scikit-learn version as the local project, so the downloaded models load there.
!pip install -q "scikit-learn=={sklearn.__version__}" pyyaml joblib

import os, sys
ROOT = "/content/aquasense"
for d in ["prediction", "controller", "data"]:
    os.makedirs(os.path.join(ROOT, d), exist_ok=True)
os.chdir(ROOT)
sys.path.insert(0, ROOT)
print("working in", os.getcwd())
"""),
        md("""
## 0b. Get the data

**Option A (default):** run the cell and pick the `IoTPond*.csv` files, or one `.zip` of them.

**Option B:** keep them in Google Drive: set `DRIVE_PATH` to the folder (or `.zip`) and the upload is skipped.
"""),
        code("""
import glob, shutil, zipfile

DRIVE_PATH = None   # e.g. "/content/drive/MyDrive/AquaSense/data"  or  ".../IoTPond.zip"

def _collect(path):
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            for m in z.namelist():
                if m.lower().endswith(".csv") and "pond" in m.lower() and not m.startswith("__MACOSX"):
                    with z.open(m) as src, open(os.path.join("data", os.path.basename(m)), "wb") as dst:
                        shutil.copyfileobj(src, dst)
    elif os.path.isdir(path):
        for f in glob.glob(os.path.join(path, "*[Pp]ond*.csv")):
            shutil.copy(f, "data")
    elif path.lower().endswith(".csv"):
        shutil.move(path, os.path.join("data", os.path.basename(path)))

if DRIVE_PATH:
    from google.colab import drive
    drive.mount("/content/drive")
    _collect(DRIVE_PATH)
elif not glob.glob("data/*[Pp]ond*.csv"):
    from google.colab import files
    for name in files.upload():
        _collect(name)

print(sorted(os.listdir("data")))
"""),
        md("""
## 1. Prediction code

The same modules as `water_quality/prediction/` in the project, plus the controller's
`config.yaml` (the safe limits come from there). Just run these cells.
"""),
    ]
    for rel in EMBED:
        with open(os.path.join(ROOT, rel)) as f:
            cells.append(code(f"%%writefile {rel}\n" + f.read()))

    cells += [
        md("""
## 2. Settings

Change these and re-run from here. One step = `FREQ_MIN` minutes:
`HORIZON_STEPS = 1` → 10 min, `6` → 1 h, `18` → 3 h.
"""),
        code("""
import importlib, time
import numpy as np, pandas as pd
import matplotlib.pyplot as plt
from IPython.display import Image, display

import prediction.settings, prediction.data_prep, prediction.models, prediction.alerts, prediction.evaluate
for m in [prediction.settings, prediction.data_prep, prediction.models, prediction.alerts, prediction.evaluate]:
    importlib.reload(m)   # pick up edits if the code cells were re-run
from prediction.settings import PrepConfig, PRETTY
from prediction.data_prep import load_csv_dir, prepare, grid_report, make_lag_dataset, plot_before_after, OUT_DIR
from prediction.evaluate import evaluate_target, useful_lead_time, plot_rmse, plot_example
from prediction.alerts import load_safe_ranges

FREQ_MIN      = 10    # resample interval (minutes)
LAG_STEPS     = 12    # past readings used as input (12 x 10 min = 2 h)
HORIZON_STEPS = 1     # steps forecast ahead (1 x 10 min = 10 min)
MIN_R2        = 0.7   # R² a horizon step needs to count as "reliable"
MODEL_NAMES   = ["persistence", "trend", "ridge", "gboost"]

cfg = PrepConfig(freq_min=FREQ_MIN, lag_steps=LAG_STEPS, horizon_steps=HORIZON_STEPS)
limits = load_safe_ranges()
os.makedirs(OUT_DIR, exist_ok=True)
pd.set_option("display.width", 200); pd.set_option("display.max_columns", 40)
print(cfg)
print("safe ranges:", {p: limits[p] for p in cfg.params})
"""),
        md("""
## 3. Step 1 — Data preparation

Implausible values and stuck sensors → missing; copied rows between ponds dropped;
10-min median bins; spike filter; gaps ≤ 30 min filled; light trailing smoothing.
"""),
        code("""
raw = load_csv_dir("data")
print(f"{len(raw):,} raw rows from {raw['series'].nunique()} ponds")
grid, report = prepare(raw, cfg)

print("\\nRemoved per pond (% of that pond's raw rows):")
display(report)
print("Clean 10-min grid — coverage % per parameter:")
display(grid_report(grid, cfg).round(1))

rows = {PRETTY[p]: len(make_lag_dataset(grid, p, cfg)) for p in cfg.params}
print("Usable training rows per parameter:", rows)
display(grid.dropna(subset=cfg.params).head(8))
"""),
        code("""
best = grid.dropna(subset=cfg.params).groupby("series").size().idxmax()
display(Image(plot_before_after(raw, grid, cfg, best)))
"""),
        md("""
## 4. Steps 2 + 4 — Train on the older 80 %, test on the latest 20 %

One date cutoff for all ponds; training labels never reach into the test period.
"""),
        code("""
all_res, all_alerts, lead, tests = [], [], [], {}
for target in cfg.params:
    t0 = time.time()
    res, info, test, preds, y, al = evaluate_target(grid, target, cfg, MODEL_NAMES, limits[target])
    all_res.append(res); all_alerts.append(al); tests[target] = (test, preds, y)
    best_model, hours = useful_lead_time(res, cfg, MIN_R2)
    lead.append({"parameter": PRETTY[target], "best_model": best_model, "reliable_up_to_h": round(hours, 2)})
    print(f"{PRETTY[target]:<17} train={info['n_train']:>6,}  test={info['n_test']:>6,}  "
          f"cutoff={info['cutoff']:%Y-%m-%d}  ({time.time() - t0:.0f} s)")
all_res = pd.concat(all_res, ignore_index=True)
all_alerts = pd.concat(all_alerts, ignore_index=True)
all_res.to_csv(os.path.join(OUT_DIR, "metrics_by_horizon.csv"), index=False)
all_alerts.to_csv(os.path.join(OUT_DIR, "alert_metrics.csv"), index=False)
"""),
        md("""
### Forecast accuracy per parameter and model

**Skill** = 1 − RMSE / RMSE(persistence): above 0 means better than assuming "nothing changes".
"""),
        code("""
show = sorted({1, 60 // cfg.freq_min, 120 // cfg.freq_min, cfg.horizon_steps} & set(range(1, cfg.horizon_steps + 1)))
label = lambda h: f"+{h * cfg.freq_min} min" if h * cfg.freq_min < 60 else f"+{h * cfg.freq_min / 60:g} h"
for metric in ["rmse", "mae", "mape_%", "r2", "skill"]:
    tbl = all_res[all_res["h"].isin(show)].pivot_table(index=["target", "model"], columns="h",
                                                        values=metric, sort=False)
    tbl.columns = [label(h) for h in tbl.columns]
    print(f"\\n=== {metric.upper()}")
    display(tbl.round(3))

print("Useful lead time (every step up to it has R² >= MIN_R2 and beats persistence):")
display(pd.DataFrame(lead))
"""),
        md("""
## 5. Early-alert scores (with F1)

Counted only while the water is still safe (otherwise there is nothing to warn about early).

* **precision**: share of alerts followed by a real breach
* **recall**: share of real coming breaches that got an alert
* **f1** = 2·P·R / (P + R): high only when both are high
* **warned_%**: share of distinct breaches warned at least once; **lead_med_h**: median earliest warning
* **(perfect forecast)**: the best any model could do on this data
* **margin**: the alert line is moved this far inside the safe limit (negative = outside),
  chosen for the best F1 on a validation slice (latest 20 % of training data, never the test set).
  **f1_untuned** is the same model alerting exactly at the limit.
"""),
        code("""
cols = ["target", "model", "margin", "alerts", "precision", "recall", "f1", "f1_untuned",
        "events", "warned_%", "lead_med_h", "warned_1h_%"]
display(all_alerts[cols].round(2))

f1 = all_alerts[~all_alerts["model"].isin(["Persistence", "(perfect forecast)"])].pivot(
    index="target", columns="model", values="f1")
ax = f1.rename(index=PRETTY).plot.bar(figsize=(9, 3.6), rot=0, width=0.75)
ax.set_ylabel("F1 (early alerts)"); ax.set_ylim(0, 1); ax.set_xlabel("")
ax.set_title(f"Early-alert F1 per model — horizon {label(cfg.horizon_steps)}")
ax.grid(axis="y", alpha=0.3); plt.tight_layout(); plt.show()
"""),
        md("## 6. Plots — forecast vs actual on the test set"),
        code("""
if cfg.horizon_steps > 1:
    display(Image(plot_rmse(all_res, cfg, OUT_DIR)))
for target, (test, preds, y) in tests.items():
    display(Image(plot_example(target, test, preds, y, cfg, OUT_DIR)))
"""),
        md("""
## 7. Train the final models on all data and download

Put the downloaded files into the project:

* `forecaster.joblib` → `water_quality/outputs/prediction/models/forecaster.joblib`
* `alert_metrics.csv` → `water_quality/outputs/prediction/alert_metrics.csv` (the dashboard's reliability notes)

Then restart the forecasting service (`python -m prediction.service`).
"""),
        code("""
import datetime as dt, joblib
from prediction.train import DEPLOYED, train_all

DEPLOYED = dict(DEPLOYED)   # e.g. DEPLOYED["do"] = "trend" to deploy another model for DO
models, margins = train_all(grid, cfg, DEPLOYED, limits)
path = os.path.join(OUT_DIR, "forecaster.joblib")
joblib.dump({"cfg": cfg, "models": models, "margins": margins,
             "trained_at": dt.datetime.now().isoformat(timespec="seconds"),
             "trained_on": "IoTPond CSVs (Colab)"}, path, compress=3)
print("saved", path, f"({os.path.getsize(path) / 1e6:.1f} MB)")

from google.colab import files
files.download(path)
files.download(os.path.join(OUT_DIR, "alert_metrics.csv"))
"""),
    ]
    return {"cells": cells,
            "metadata": {"colab": {"provenance": [], "name": os.path.basename(OUT)},
                         "kernelspec": {"display_name": "Python 3", "name": "python3"},
                         "language_info": {"name": "python"}},
            "nbformat": 4, "nbformat_minor": 0}


def main() -> None:
    nb = build()
    for c in nb["cells"]:                      # nbformat stores source as a list of lines
        c["source"] = c["source"].splitlines(keepends=True)
    with open(OUT, "w") as f:
        json.dump(nb, f, indent=1)
    print(f"wrote {OUT} ({len(nb['cells'])} cells)")


if __name__ == "__main__":
    main()
