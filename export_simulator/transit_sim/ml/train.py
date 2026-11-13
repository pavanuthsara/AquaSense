"""Train and evaluate the AI correction layer.

    python -m transit_sim ml generate            # simulated shipments -> data/shipments/simulated_shipments.csv
    python -m transit_sim ml train               # learning curve, final model, charts, summary
    python -m transit_sim ml train --data data/shipments/real_shipments.csv   # later: real records

Evaluation compares three ways of predicting survival on shipments the models never saw:
    physics only | physics + AI correction (hybrid) | AI alone (no physics)
for growing amounts of training data (learning curve).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .correction import (CorrectionModel, Dataset, PureMLModel, build_dataset, importances, metrics,
                         model_meta)
from .synthetic import generate, read_csv, write_csv

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data" / "shipments"
SIM_TRAIN = DATA_DIR / "simulated_shipments.csv"
SIM_TEST = DATA_DIR / "simulated_test_shipments.csv"
REPORT_DIR = ROOT / "reports" / "ml"
SIZES = (10, 20, 40, 80, 160, 320, 600)


def ensure_simulated(n_train: int = 600, n_test: int = 300, seed: int = 0) -> tuple[Path, Path]:
    if not SIM_TRAIN.exists():
        write_csv(generate(n_train, seed=seed), SIM_TRAIN)
    if not SIM_TEST.exists():
        write_csv(generate(n_test, seed=seed + 1000), SIM_TEST)  # different seed: unseen shipments
    return SIM_TRAIN, SIM_TEST


def learning_curve(pool: Dataset, test: Dataset, sizes=SIZES, repeats: int = 5) -> list[dict]:
    rng = np.random.default_rng(0)
    phys = metrics(test.phys, test.obs)
    out = []
    for n in sizes:
        if n > len(pool.rows):
            continue
        hyb, pure = [], []
        for r in range(repeats):
            idx = rng.choice(len(pool.rows), size=n, replace=False)
            sub = pool.subset(idx)
            hyb.append(metrics(CorrectionModel(seed=r).fit(sub).predict(test), test.obs))
            pure.append(metrics(PureMLModel(seed=r).fit(sub).predict(test), test.obs))
        avg = lambda ms, k: float(np.mean([m[k] for m in ms]))  # noqa: E731
        out.append({"n": n,
                    "physics_mae_pp": phys["mae_pp"], "hybrid_mae_pp": avg(hyb, "mae_pp"),
                    "pure_ml_mae_pp": avg(pure, "mae_pp"),
                    "physics_safe_acc": phys["safe_call_accuracy"],
                    "hybrid_safe_acc": avg(hyb, "safe_call_accuracy"),
                    "pure_ml_safe_acc": avg(pure, "safe_call_accuracy")})
    return out


def train(data_path: Path | None = None, test_path: Path | None = None, report_dir: Path = REPORT_DIR,
          save: bool = True) -> dict:
    simulated = data_path is None
    if simulated:
        data_path, test_path = ensure_simulated()
    rows = read_csv(data_path)
    trained_on = "simulated" if all(r.get("source", "real") == "simulated" for r in rows) else "real"

    pool = build_dataset(rows)
    if test_path is not None:
        test = build_dataset(read_csv(test_path))
    else:  # real data without a separate test file: hold out 25 %
        rng = np.random.default_rng(0)
        idx = rng.permutation(len(rows))
        cut = max(1, len(rows) // 4)
        test, pool = pool.subset(idx[:cut]), pool.subset(idx[cut:])

    curve = learning_curve(pool, test)
    final = CorrectionModel().fit(pool)
    pure = PureMLModel().fit(pool)
    result = {
        "trained_on": trained_on,
        "n_train": len(pool.rows),
        "n_test": len(test.rows),
        "test": {
            "physics_only": metrics(test.phys, test.obs),
            "physics_plus_ai": metrics(final.predict(test), test.obs),
            "ai_only": metrics(pure.predict(test), test.obs),
        },
        "learning_curve": curve,
        "importance": importances(final, test),
    }
    if save:
        final.save(model_meta(trained_on, len(pool.rows), result["test"]["physics_plus_ai"],
                              {"physics_only_test_metrics": result["test"]["physics_only"],
                               "data_file": str(Path(data_path).name)}))
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "ml_result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    from .plots import ml_figures
    ml_figures(result, test, final, pure, report_dir)
    write_summary(result, report_dir / "ml_summary.md")
    return result


def write_summary(res: dict, path: Path) -> None:
    t = res["test"]
    label = "SIMULATED shipments (pretend reality)" if res["trained_on"] == "simulated" else "real shipment records"
    lines = [
        "# AI correction layer — training summary", "",
        f"Trained on **{res['n_train']} {label}**, tested on **{res['n_test']} unseen shipments**.", "",
    ]
    if res["trained_on"] == "simulated":
        lines += ["> These results show the method works and how much data it needs. They are **not** real-world "
                  "accuracy. Real shipment records will replace the simulated ones.", ""]
    lines += ["| Method | Mean error (percentage points) | Bias | Safe / not-safe call correct |",
              "|---|---|---|---|"]
    for name, key in (("Physics only", "physics_only"), ("Physics + AI correction", "physics_plus_ai"),
                      ("AI only (no physics)", "ai_only")):
        m = t[key]
        lines.append(f"| {name} | {m['mae_pp']:.2f} | {m['bias_pp']:+.2f} | {100 * m['safe_call_accuracy']:.0f}% |")
    lines += ["", "## Learning curve (mean error, percentage points)", "",
              "| Training shipments | Physics only | Physics + AI | AI only |", "|---|---|---|---|"]
    for c in res["learning_curve"]:
        lines.append(f"| {c['n']} | {c['physics_mae_pp']:.2f} | {c['hybrid_mae_pp']:.2f} | {c['pure_ml_mae_pp']:.2f} |")
    lines += ["", "## What the AI pays most attention to", ""]
    for d in res["importance"][:6]:
        lines.append(f"- {d['label']} ({d['importance_pp']:.2f} pp)")
    lines += ["", "Figures: `learning_curve.png`, `predicted_vs_observed.png`, `feature_importance.png`."]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
