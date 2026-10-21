"""Step 2 — Forecasting models, simplest first.

Every model forecasts ALL horizon steps at once (t+1 .. t+H) for one target
parameter, from a lag dataset built by data_prep.make_lag_dataset:

    fit(sup, target, cfg)  ->  self
    predict(sup)           ->  array (n_rows, H) of forecast values

    Persistence     y(t+h) = y(t). No training. The bar to beat.
    LinearTrend     straight line through the last `window` readings, extended.
    Ridge           linear regression on the target's own lag window.
    GBoost          gradient-boosted trees on all four parameters' lag windows
                    plus time of day; one model per horizon step.

The trained models predict the CHANGE from the current value, then add it back
(y(t+h) = y(t) + delta). Pond levels differ a lot (one pond's DO sits at 3,
another's at 10), but how values move over two hours is much more alike, so
learning the change transfers across tanks.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.linear_model import Ridge
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from .settings import PLAUSIBLE, PrepConfig


def _relative(sup: pd.DataFrame, params: list[str], lags: int) -> pd.DataFrame:
    """lag0 kept as the level; lag1..lagN re-expressed as (lag_k - lag0)."""
    out = {}
    for p in params:
        now = sup[f"{p}_lag0"]
        out[f"{p}_now"] = now
        for k in range(1, lags):
            out[f"{p}_d{k}"] = sup[f"{p}_lag{k}"] - now
    out["tod_sin"], out["tod_cos"] = sup["tod_sin"], sup["tod_cos"]
    return pd.DataFrame(out, index=sup.index)


class Forecaster:
    name = "base"

    def __init__(self, cfg: PrepConfig):
        self.cfg = cfg
        self.target: str | None = None

    def fit(self, sup: pd.DataFrame, target: str) -> "Forecaster":
        self.target = target
        return self

    def predict(self, sup: pd.DataFrame) -> np.ndarray:
        raise NotImplementedError

    def _labels(self, sup: pd.DataFrame) -> np.ndarray:
        return sup[[f"y_h{h}" for h in range(1, self.cfg.horizon_steps + 1)]].to_numpy()

    def _clip(self, pred: np.ndarray) -> np.ndarray:
        lo, hi = PLAUSIBLE[self.target]
        return np.clip(pred, lo, hi)


class Persistence(Forecaster):
    name = "Persistence"

    def predict(self, sup):
        now = sup[f"{self.target}_lag0"].to_numpy()
        return np.repeat(now[:, None], self.cfg.horizon_steps, axis=1)


class LinearTrend(Forecaster):
    """Least-squares slope over the last `window` steps, extrapolated."""
    name = "LinearTrend"

    def __init__(self, cfg, window: int = 6):
        super().__init__(cfg)
        self.window = min(window, cfg.lag_steps)

    def predict(self, sup):
        # x = 0, -1, ..., -(w-1) for lag0 .. lag{w-1}
        x = -np.arange(self.window, dtype=float)
        y = sup[[f"{self.target}_lag{k}" for k in range(self.window)]].to_numpy()
        xc = x - x.mean()
        slope = ((y - y.mean(axis=1, keepdims=True)) * xc).sum(axis=1) / (xc ** 2).sum()
        level = y.mean(axis=1) - slope * x.mean()          # fitted value at t
        h = np.arange(1, self.cfg.horizon_steps + 1)
        return self._clip(level[:, None] + slope[:, None] * h[None, :])


class RidgeLags(Forecaster):
    """Linear regression on the target's own lag window (+ time of day)."""
    name = "Ridge"

    def fit(self, sup, target):
        super().fit(sup, target)
        X = _relative(sup, [target], self.cfg.lag_steps)
        dy = self._labels(sup) - sup[f"{target}_lag0"].to_numpy()[:, None]
        self.model = make_pipeline(StandardScaler(), Ridge(alpha=1.0)).fit(X, dy)
        return self

    def predict(self, sup):
        X = _relative(sup, [self.target], self.cfg.lag_steps)
        now = sup[f"{self.target}_lag0"].to_numpy()[:, None]
        # sklearn returns shape (n,) for a single-step horizon; keep (n, H)
        return self._clip(now + self.model.predict(X).reshape(len(X), -1))


class GBoost(Forecaster):
    """Gradient-boosted trees, one per horizon step, on every parameter's lags.
    Missing lags of the OTHER parameters are allowed (trees handle NaN).

    The other parameters enter only as recent CHANGES, not absolute levels:
    trees cannot extrapolate, and levels shift between tanks and when probes
    drift (IoTPond pH test levels sit below anything seen in training), which
    made the level-aware version clearly worse on pH and DO."""
    name = "GBoost"

    def __init__(self, cfg, max_iter: int = 300, seed: int = 42):
        super().__init__(cfg)
        self.max_iter, self.seed = max_iter, seed

    def _X(self, sup):
        X = _relative(sup, self.cfg.params, self.cfg.lag_steps)
        return X.drop(columns=[f"{p}_now" for p in self.cfg.params if p != self.target])

    def fit(self, sup, target):
        super().fit(sup, target)
        X = self._X(sup)
        dy = self._labels(sup) - sup[f"{target}_lag0"].to_numpy()[:, None]
        self.models = []
        for h in range(self.cfg.horizon_steps):
            m = HistGradientBoostingRegressor(
                max_iter=self.max_iter, learning_rate=0.05, max_leaf_nodes=31,
                min_samples_leaf=40, l2_regularization=1.0,
                early_stopping=True, validation_fraction=0.1, n_iter_no_change=20,
                random_state=self.seed)
            self.models.append(m.fit(X, dy[:, h]))
        return self

    def predict(self, sup):
        X = self._X(sup)
        now = sup[f"{self.target}_lag0"].to_numpy()
        return self._clip(np.column_stack([now + m.predict(X) for m in self.models]))


MODELS = {"persistence": Persistence, "trend": LinearTrend, "ridge": RidgeLags,
          "gboost": GBoost}
