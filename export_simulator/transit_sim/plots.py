"""Static figures for reports and the thesis (matplotlib, PNG)."""
from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import matplotlib.ticker  # noqa: E402,F401

# Categorical slots 1-3 of the validated reference palette (light mode).
SERIES = {"control": "#2a78d6", "ms222": "#eb6834", "benzocaine": "#1baf7a"}
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e6e5e0", "#fcfcfb"
STATUS_CRIT = "#c0392b"


def _style(ax, title, ylabel):
    ax.set_title(title, loc="left", fontsize=10, color=INK, fontweight="bold")
    ax.set_ylabel(ylabel, fontsize=8.5, color=INK2)
    ax.grid(True, color=GRID, linewidth=0.7)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color("#b5b4ad")
    ax.tick_params(colors=INK2, labelsize=8)
    ax.set_facecolor(SURFACE)
    ax.set_xticks(range(0, 49, 12))


def calibration_figure(cal, path: Path) -> Path:
    from .calibration import LABELS, TREATMENTS

    panels = [("do", "Dissolved oxygen", "mg/L", lambda r: r.do),
              ("tan", "Total ammonia", "mg/L", lambda r: r.tan),
              ("co2", "Free CO2", "mg/L", lambda r: r.co2),
              ("ph", "pH (not fitted — check)", "pH", lambda r: r.ph),
              ("nh3", "Un-ionized NH3 (observed = paper's own calc.)", "mg/L", lambda r: r.nh3),
              ("mortality", "Cumulative mortality", "%", lambda r: 100 * (1 - r.survival))]
    fig, axes = plt.subplots(2, 3, figsize=(12, 6.8), facecolor=SURFACE)
    for ax, (key, title, unit, get) in zip(axes.flat, panels):
        _style(ax, title, unit)
        for trt in TREATMENTS:
            run = cal.runs[trt]
            ls = "-" if trt == "control" else "--" if trt == "ms222" else ":"
            ax.plot(run.t, get(run), color=SERIES[trt], lw=2, ls=ls, label=f"{LABELS[trt]} model")
            if key in cal.data[trt]:
                ax.plot(cal.data[trt]["t"], cal.data[trt][key], "o", ms=5.5, color=SERIES[trt],
                        mec=SURFACE, mew=1.2, label=f"{LABELS[trt]} observed")
        if key == "nh3":
            ax.axhline(0.02, color=INK2, lw=1, ls="-.")
            ax.text(47, 0.0195, "0.02 mg/L safe limit", fontsize=7.5, color=INK2, va="top", ha="right")
        if key == "mortality":
            ax.text(1, ax.get_ylim()[1] * 0.92,
                    "Anaesthetic curves are predictions\n(no mortality data used)", fontsize=7.5,
                    color=INK2, va="top")
        ax.set_xlabel("Hours in bag", fontsize=8.5, color=INK2)
    handles, labels = axes.flat[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=3, fontsize=8, frameon=False)
    fig.suptitle("Bag model vs Pramod et al. (2010) — Indian tiger barb, 72 g/L, 22 °C",
                 x=0.01, ha="left", fontsize=12, color=INK, fontweight="bold")
    fig.tight_layout(rect=(0, 0.07, 1, 0.96))
    fig.savefig(path, dpi=150, facecolor=SURFACE)
    plt.close(fig)
    return path


def scenario_figure(result, title: str, path: Path, do_crit: float = 3.0) -> Path:
    """Six small panels for one simulated shipment, including the unpacking phase."""
    panels = [("Dissolved oxygen", "mg/L", result.do, do_crit, "critical DO"),
              ("Total ammonia", "mg/L", result.tan, None, None),
              ("Free CO2", "mg/L", result.co2, None, None),
              ("pH", "pH", result.ph, None, None),
              ("Un-ionized ammonia (NH3)", "mg/L", result.nh3, 0.02, "0.02 safe limit"),
              ("Fish alive", "%", 100 * result.survival, None, None)]
    fig, axes = plt.subplots(2, 3, figsize=(12, 6.2), facecolor=SURFACE)
    opened = result.phase == 1
    t_open = float(result.t[opened][0]) if opened.any() else None
    for ax, (ttl, unit, y, ref, ref_lbl) in zip(axes.flat, panels):
        _style(ax, ttl, unit)
        ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(7, integer=True))
        ax.plot(result.t, y, color=SERIES["control"], lw=2)
        if unit == "%":
            ax.set_ylim(0, 102)
        if ref is not None:
            ax.axhline(ref, color=STATUS_CRIT, lw=1, ls="--")
            ax.text(result.t[0], ref, f" {ref_lbl}", color=STATUS_CRIT, fontsize=7.5, va="bottom")
        if t_open is not None:
            ax.axvspan(t_open, result.t[-1], color="#eda100", alpha=0.18, lw=0)
        ax.set_xlabel("Hours", fontsize=8.5, color=INK2)
    if t_open is not None:
        fig.text(0.99, 0.965, "shaded = bag opened (unpacking)", ha="right", fontsize=8, color=INK2)
    fig.suptitle(title, x=0.01, ha="left", fontsize=12, color=INK, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.95))
    fig.savefig(path, dpi=150, facecolor=SURFACE)
    plt.close(fig)
    return path


def range_figure(rr, title: str, path: Path, do_crit: float = 3.0) -> Path:
    """Band (min-max across all runs) + median line + worst case, for a temperature range."""
    import numpy as np

    t = rr.runs[0].t
    def stack(attr, scale=1.0):
        return np.vstack([scale * getattr(r, attr) for r in rr.runs])
    panels = [("Temperature", "°C", stack("temp"), None, None),
              ("Dissolved oxygen", "mg/L", stack("do"), do_crit, "critical DO"),
              ("Total ammonia", "mg/L", stack("tan"), None, None),
              ("Free CO2", "mg/L", stack("co2"), None, None),
              ("Un-ionized ammonia (NH3)", "mg/L", stack("nh3"), 0.02, "0.02 safe limit"),
              ("Fish alive", "%", stack("survival", 100.0), None, None)]
    i_worst = rr.labels.index(rr.worst_label)
    fig, axes = plt.subplots(2, 3, figsize=(12, 6.2), facecolor=SURFACE)
    opened = rr.runs[0].phase == 1
    for ax, (ttl, unit, Y, ref, ref_lbl) in zip(axes.flat, panels):
        _style(ax, ttl, unit)
        ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(7, integer=True))
        ax.fill_between(t, Y.min(0), Y.max(0), color=SERIES["control"], alpha=0.18, lw=0,
                        label=f"range of {len(rr.runs)} journeys")
        ax.plot(t, np.median(Y, 0), color=SERIES["control"], lw=2, label="median")
        ax.plot(t, Y[i_worst], color=SERIES["ms222"], lw=1.6, ls="--", label=f"worst: {rr.worst_label}")
        if unit == "%":
            ax.set_ylim(0, 102)
        if ref is not None:
            ax.axhline(ref, color=STATUS_CRIT, lw=1, ls=":")
            ax.text(t[0], ref, f" {ref_lbl}", color=STATUS_CRIT, fontsize=7.5, va="bottom")
        if opened.any():
            ax.axvspan(t[opened][0], t[-1], color="#eda100", alpha=0.18, lw=0)
        ax.set_xlabel("Hours", fontsize=8.5, color=INK2)
    h, l = axes.flat[0].get_legend_handles_labels()
    fig.legend(h, l, loc="lower center", ncol=3, fontsize=8, frameon=False)
    if opened.any():
        fig.text(0.99, 0.965, "shaded = bag opened (unpacking)", ha="right", fontsize=8, color=INK2)
    fig.suptitle(title, x=0.01, ha="left", fontsize=12, color=INK, fontweight="bold")
    fig.tight_layout(rect=(0, 0.05, 1, 0.95))
    fig.savefig(path, dpi=150, facecolor=SURFACE)
    plt.close(fig)
    return path
