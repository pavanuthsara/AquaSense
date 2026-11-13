"""Figures for the AI correction layer (matplotlib PNG)."""
from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

from ..plots import GRID, INK, INK2, SURFACE  # noqa: E402

PHYSICS, HYBRID, PURE = "#2a78d6", "#eb6834", "#1baf7a"  # categorical slots 1-3


def _style(ax, title, xlabel, ylabel):
    ax.set_title(title, loc="left", fontsize=11, color=INK, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=9, color=INK2)
    ax.set_ylabel(ylabel, fontsize=9, color=INK2)
    ax.grid(True, color=GRID, linewidth=0.7)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color("#b5b4ad")
    ax.tick_params(colors=INK2, labelsize=8.5)
    ax.set_facecolor(SURFACE)


def _stamp(fig, simulated: bool):
    if simulated:
        fig.text(0.99, 0.985, "SIMULATED DATA — proves the method, not real-world accuracy", ha="right",
                 va="top", fontsize=8.5, color="#c0392b", fontweight="bold")


def ml_figures(res: dict, test, hybrid_model, pure_model, out: Path) -> list[Path]:
    simulated = res["trained_on"] == "simulated"
    paths = []

    # 1. learning curve
    c = res["learning_curve"]
    n = [d["n"] for d in c]
    fig, ax = plt.subplots(figsize=(8, 4.6), facecolor=SURFACE)
    _style(ax, "Prediction error vs amount of training data", "Completed shipments used for training",
           "Mean error (percentage points of survival)")
    ax.plot(n, [d["physics_mae_pp"] for d in c], color=PHYSICS, lw=2, ls="--", label="Physics only")
    ax.plot(n, [d["hybrid_mae_pp"] for d in c], color=HYBRID, lw=2.5, marker="o", ms=6, label="Physics + AI correction")
    ax.plot(n, [d["pure_ml_mae_pp"] for d in c], color=PURE, lw=2, marker="s", ms=5, label="AI only (no physics)")
    ax.set_xscale("log")
    ax.set_xticks(n)
    ax.set_xticklabels([str(v) for v in n])
    ax.set_ylim(bottom=0)
    for series, color in (("hybrid_mae_pp", HYBRID), ("pure_ml_mae_pp", PURE)):
        ax.annotate(f"{c[-1][series]:.1f}", (n[-1], c[-1][series]), textcoords="offset points", xytext=(6, 0),
                    fontsize=8.5, color=INK2, va="center")
    ax.legend(frameon=False, fontsize=9)
    _stamp(fig, simulated)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    paths.append(out / "learning_curve.png")
    fig.savefig(paths[-1], dpi=150, facecolor=SURFACE)
    plt.close(fig)

    # 2. predicted vs observed
    fig, axes = plt.subplots(1, 2, figsize=(10, 4.8), facecolor=SURFACE, sharey=True)
    obs = 100 * test.obs
    for ax, pred, name, color in ((axes[0], 100 * test.phys, "Physics only", PHYSICS),
                                  (axes[1], 100 * hybrid_model.predict(test), "Physics + AI correction", HYBRID)):
        mae = np.mean(np.abs(pred - obs))
        _style(ax, f"{name}  (mean error {mae:.1f} pp)", "Predicted survival (%)", "Observed survival (%)")
        ax.plot([0, 100], [0, 100], color=INK2, lw=1, ls=":")
        ax.scatter(pred, obs, s=18, color=color, alpha=0.6, edgecolors=SURFACE, linewidths=0.6)
        ax.set_xlim(0, 101)
        ax.set_ylim(0, 101)
    _stamp(fig, simulated)
    fig.tight_layout(rect=(0, 0, 1, 0.95))
    paths.append(out / "predicted_vs_observed.png")
    fig.savefig(paths[-1], dpi=150, facecolor=SURFACE)
    plt.close(fig)

    # 3. feature importance
    imp = [d for d in res["importance"] if d["importance_pp"] > 0.005][:10][::-1]
    fig, ax = plt.subplots(figsize=(8, 0.45 * len(imp) + 1.4), facecolor=SURFACE)
    _style(ax, "What the AI correction pays attention to", "Error added when this information is scrambled (pp)", "")
    ax.barh([d["label"] for d in imp], [d["importance_pp"] for d in imp], color=HYBRID, height=0.6)
    for i, d in enumerate(imp):
        ax.text(d["importance_pp"], i, f" {d['importance_pp']:.2f}", va="center", fontsize=8.5, color=INK2)
    ax.set_xlim(0, max(d["importance_pp"] for d in imp) * 1.15 if imp else 1)
    _stamp(fig, simulated)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    paths.append(out / "feature_importance.png")
    fig.savefig(paths[-1], dpi=150, facecolor=SURFACE)
    plt.close(fig)
    return paths
