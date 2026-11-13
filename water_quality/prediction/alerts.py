"""Step 3 — Lead-time (early) alerts from a forecast.

The baseline rule engine alerts when a value IS out of range. This module
alerts when the FORECAST leaves the range while the current value is still
safe, and says how long until it does:

    "Ammonia unsafe in ~2 h (forecast 0.62 mg/L > 0.5)"

A breach must hold for `confirm_steps` consecutive forecast steps, so one
noisy step does not raise an alert.

Alert margin: the forecast is compared with the limit moved inward by
`margin` (in the parameter's units). margin > 0 alerts when the forecast gets
CLOSE to the limit (catches more breaches); margin < 0 needs the forecast to be
clearly PAST it (fewer false alarms). `tune_margin` picks the value with the
best F1 on validation data; it never touches the safe limits themselves.

Safe limits are read from the controller's config.yaml: one source of truth
for the reactive engine and the predictive layer.
"""
from __future__ import annotations

import os
from dataclasses import asdict, dataclass

import numpy as np
import pandas as pd

from .settings import PRETTY, UNITS, PrepConfig

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTROLLER_CONFIG = os.path.join(ROOT, "controller", "config.yaml")

CONFIRM_STEPS = 2


def load_safe_ranges(path: str = CONTROLLER_CONFIG) -> dict[str, tuple[float | None, float | None]]:
    import yaml

    with open(path) as f:
        params = yaml.safe_load(f)["parameters"]
    return {name: (p.get("min"), p.get("max")) for name, p in params.items()}


def shift_limits(limits: tuple, margin: float) -> tuple:
    """Move both limits inward by `margin` (outward when negative)."""
    lo, hi = limits
    return (None if lo is None else lo + margin, None if hi is None else hi - margin)


def _outside(values: np.ndarray, lo, hi) -> np.ndarray:
    out = np.zeros(values.shape, dtype=bool)
    if lo is not None:
        out |= values < lo
    if hi is not None:
        out |= values > hi
    return out


def first_breach_step(paths: np.ndarray, lo, hi, confirm: int = CONFIRM_STEPS) -> np.ndarray:
    """For each row of a (n, H) array of future values: the first step (1-based)
    that starts a run of `confirm` out-of-range steps, or 0 if none. A run that
    starts in the last steps of the horizon counts if it lasts to the end."""
    out = _outside(paths, lo, hi)
    n, H = out.shape
    run = np.zeros_like(out)
    for c in range(confirm):                 # run[:, h] = out[h] & ... & out[h+c]
        shifted = np.ones_like(out)
        shifted[:, :H - c] = out[:, c:]
        run = out & shifted if c == 0 else run & shifted
    hit = run.argmax(axis=1) + 1
    return np.where(run.any(axis=1), hit, 0)


@dataclass
class EarlyAlert:
    parameter: str
    side: str                 # low | high
    limit: float
    eta_min: int              # minutes until the forecast crosses the limit
    breach_at: str            # ISO time
    forecast_value: float     # forecast value at the breach step
    current_value: float
    message: str

    def to_dict(self) -> dict:
        return asdict(self)


def _eta_text(minutes: int) -> str:
    if minutes < 60:
        return f"~{minutes} min"
    hours = minutes / 60
    return f"~{hours:.0f} h" if abs(hours - round(hours)) < 0.25 else f"~{hours:.1f} h"


def early_alert(parameter: str, now: pd.Timestamp, current: float, forecast: np.ndarray,
                limits: tuple, cfg: PrepConfig, margin: float = 0.0) -> EarlyAlert | None:
    """Alert if `forecast` (H future values) breaches while `current` is safe."""
    lo, hi = limits
    if current is None or np.isnan(current) or _outside(np.array([current]), lo, hi)[0]:
        return None               # already out of range: the rule engine handles it
    a_lo, a_hi = shift_limits(limits, margin)
    step = int(first_breach_step(forecast[None, :], a_lo, a_hi)[0])
    if step == 0:
        return None
    value = float(forecast[step - 1])
    side, limit = ("low", lo) if a_lo is not None and value < a_lo else ("high", hi)
    eta = step * cfg.freq_min
    unit = UNITS[parameter]
    msg = (f"{PRETTY[parameter]} unsafe in {_eta_text(eta)} "
           f"(forecast {value:.2f}{' ' + unit if unit else ''}, "
           f"safe {'min' if side == 'low' else 'max'} {limit:g})")
    return EarlyAlert(parameter, side, float(limit), eta,
                      (now + pd.Timedelta(minutes=eta)).isoformat(), round(value, 3),
                      round(float(current), 3), msg)


# ---------------------------------------------------------------------------
# Evaluation of the alerts themselves (used by evaluate.py)
# ---------------------------------------------------------------------------
def alert_metrics(test: pd.DataFrame, y: np.ndarray, pred: np.ndarray, target: str,
                  limits: tuple, cfg: PrepConfig, margin: float = 0.0) -> dict:
    """How useful are the early alerts on held-out data?

    Only moments when the water is currently SAFE count (otherwise there is
    nothing to warn about early).

    precision   of the early alerts raised, the share followed by a real breach
                within the horizon
    recall      of the moments followed by a real breach within the horizon,
                the share that got an alert
    f1          2·P·R / (P + R): one score, high only if both are high
    events      distinct real breaches (series + breach time) in the test set
    warned_%    share of events that got at least one correct early warning
    lead_med_h  median, over warned events, of the EARLIEST correct warning
    warned_1h_% share of events warned at least 1 h ahead
    eta_mae_min how far off the predicted time-to-breach was, minutes
    """
    lo, hi = limits
    safe = ~_outside(test[f"{target}_lag0"].to_numpy(), lo, hi)
    actual = first_breach_step(y, lo, hi)[safe]
    alarm = first_breach_step(pred, *shift_limits(limits, margin))[safe]
    times = test["time"].to_numpy()[safe]
    series = test["series"].to_numpy()[safe]

    tp = (actual > 0) & (alarm > 0)
    step = pd.Timedelta(minutes=cfg.freq_min)
    ev = pd.DataFrame({"series": series[actual > 0],
                       "breach": times[actual > 0] + actual[actual > 0] * step,
                       "lead_steps": np.where(tp, actual, 0)[actual > 0]})
    per_event = ev.groupby(["series", "breach"])["lead_steps"].max()
    warned = per_event[per_event > 0]
    precision = tp.sum() / max((alarm > 0).sum(), 1)
    recall = tp.sum() / max((actual > 0).sum(), 1)
    return {
        "safe_rows": int(safe.sum()),
        "alerts": int((alarm > 0).sum()),
        "precision": precision,
        "recall": recall,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
        "events": len(per_event),
        "warned_%": 100 * len(warned) / max(len(per_event), 1),
        "lead_med_h": float(warned.median() * cfg.freq_min / 60) if len(warned) else 0.0,
        "warned_1h_%": 100 * float((per_event * cfg.freq_min >= 60).mean()) if len(per_event) else 0.0,
        "eta_mae_min": float(np.abs(alarm[tp] - actual[tp]).mean() * cfg.freq_min) if tp.any() else np.nan,
    }


def tune_margin(val: pd.DataFrame, y: np.ndarray, pred: np.ndarray, target: str,
                limits: tuple, cfg: PrepConfig, n: int = 61) -> tuple[float, float]:
    """Alert margin with the best F1 on VALIDATION data (never the test set).

    Candidates span +/- the 95th percentile of the forecast error, so the search
    scales with each parameter's units. Ties go to the margin closest to 0;
    with no breaches in `val` (pH) the margin stays 0.
    Returns (margin, validation F1).
    """
    span = float(np.nanquantile(np.abs(pred - y), 0.95)) if len(y) else 0.0
    best, best_f1 = 0.0, alert_metrics(val, y, pred, target, limits, cfg)["f1"]
    for m in np.linspace(-span, span, n):
        f1 = alert_metrics(val, y, pred, target, limits, cfg, margin=m)["f1"]
        if f1 > best_f1 + 1e-9 or (abs(f1 - best_f1) <= 1e-9 and abs(m) < abs(best)):
            best, best_f1 = float(m), f1
    return best, best_f1
