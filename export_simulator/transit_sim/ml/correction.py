"""AI correction layer: learns the physics simulator's error from completed shipments.

Hybrid ("residual") learning:

    corrected = expit( logit(physics_survival) + AI_correction(features) )

The AI predicts only the *difference* between what the physics said and what really happened
(on the logit scale, so corrected survival always stays between 0 and 100 %). Because the physics
already gets most of the answer right, the AI needs far less data than a model that has to learn
survival from scratch, and when it has seen nothing it simply leaves the physics unchanged.

Model: scikit-learn GradientBoostingRegressor (shallow trees, strong shrinkage, subsampling) —
works on small tabular data, captures interactions (e.g. sedation x temperature), and gives
feature importances so every correction can be explained.
"""
from __future__ import annotations

import json
import warnings
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import sklearn
from sklearn.ensemble import GradientBoostingRegressor

from .physics import expit, logit, physics_prediction

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "models"
MODEL_PATH = MODEL_DIR / "correction_model.joblib"
META_PATH = MODEL_DIR / "correction_model.json"

# Plain names for the explanation chart / API.
FEATURE_LABELS = {
    "fish_mass_g": "Fish weight",
    "fish_per_bag": "Fish per bag",
    "density_g_per_l": "Packing density",
    "water_l": "Water per bag",
    "gas_ratio": "Oxygen : water ratio",
    "duration_h": "Trip length",
    "temp_low_c": "Coolest temperature",
    "temp_high_c": "Warmest temperature",
    "fasting_h": "Fasting",
    "zeolite": "Zeolite",
    "is_guppy": "Species (guppy)",
    "sed_ms222": "MS-222",
    "sed_benzocaine": "Benzocaine",
    "phys_logit": "Physics survival estimate",
    "phys_min_do": "Physics: lowest oxygen",
    "phys_max_co2": "Physics: highest CO2",
    "phys_peak_nh3_unpack": "Physics: ammonia at unpacking",
}
RAW_FEATURES = ["fish_mass_g", "fish_per_bag", "density_g_per_l", "water_l", "gas_ratio", "duration_h",
                "temp_low_c", "temp_high_c", "fasting_h", "zeolite", "is_guppy", "sed_ms222", "sed_benzocaine"]
PHYSICS_FEATURES = ["phys_logit", "phys_min_do", "phys_max_co2", "phys_peak_nh3_unpack"]
HYBRID_FEATURES = RAW_FEATURES + PHYSICS_FEATURES


def _gbr(seed: int = 0) -> GradientBoostingRegressor:
    return GradientBoostingRegressor(n_estimators=300, learning_rate=0.03, max_depth=2, subsample=0.8,
                                     min_samples_leaf=5, random_state=seed)


@dataclass
class Dataset:
    rows: list[dict]
    raw: np.ndarray            # raw shipment features
    hybrid: np.ndarray         # raw + physics features
    phys: np.ndarray           # physics survival (0-1)
    obs: np.ndarray            # observed survival (0-1); NaN when unknown
    weight: np.ndarray = field(default_factory=lambda: np.array([]))

    def subset(self, idx) -> "Dataset":
        idx = np.asarray(idx)
        return Dataset([self.rows[i] for i in idx], self.raw[idx], self.hybrid[idx], self.phys[idx],
                       self.obs[idx], self.weight[idx] if len(self.weight) else self.weight)


def feature_row(row: dict, phys: dict) -> dict:
    mass, fish, water = float(row["fish_mass_g"]), float(row["fish_per_bag"]), float(row["water_l"])
    sed = row.get("anaesthetic") or "none"
    return {
        "fish_mass_g": mass,
        "fish_per_bag": fish,
        "density_g_per_l": fish * mass / water,
        "water_l": water,
        "gas_ratio": float(row["gas_l"]) / water,
        "duration_h": float(row["duration_h"]),
        "temp_low_c": float(row["temp_low_c"]),
        "temp_high_c": float(row["temp_high_c"]),
        "fasting_h": float(row["fasting_h"]),
        "zeolite": 1.0 if float(row["zeolite_g_per_l"]) > 0 else 0.0,
        "is_guppy": 1.0 if row["species"] == "guppy" else 0.0,
        "sed_ms222": 1.0 if sed == "ms222_40mgL" else 0.0,
        "sed_benzocaine": 1.0 if sed == "benzocaine_20mgL" else 0.0,
        "phys_logit": float(logit(phys["phys_survival"])),
        "phys_min_do": phys["phys_min_do"],
        "phys_max_co2": phys["phys_max_co2"],
        "phys_peak_nh3_unpack": phys["phys_peak_nh3_unpack"],
    }


def build_dataset(rows: list[dict]) -> Dataset:
    feats, phys, obs, weight = [], [], [], []
    for row in rows:
        p = physics_prediction(row)
        feats.append(feature_row(row, p))
        phys.append(p["phys_survival"])
        o = row.get("observed_survival")
        obs.append(float(o) if o not in (None, "") else np.nan)
        counted = row.get("fish_counted")
        weight.append(np.sqrt(float(counted)) if counted not in (None, "") else 1.0)
    raw = np.array([[f[k] for k in RAW_FEATURES] for f in feats])
    hybrid = np.array([[f[k] for k in HYBRID_FEATURES] for f in feats])
    return Dataset(rows, raw, hybrid, np.array(phys), np.array(obs), np.array(weight))


class CorrectionModel:
    """Physics + learned correction. With no training data it returns the physics unchanged."""

    def __init__(self, seed: int = 0):
        self.model = _gbr(seed)
        self.meta: dict = {}

    def fit(self, data: Dataset) -> "CorrectionModel":
        residual = logit(data.obs) - logit(data.phys)
        self.model.fit(data.hybrid, residual, sample_weight=data.weight)
        return self

    def correction(self, hybrid: np.ndarray) -> np.ndarray:
        return self.model.predict(hybrid)

    def predict(self, data: Dataset) -> np.ndarray:
        return expit(logit(data.phys) + self.correction(data.hybrid))

    def save(self, meta: dict, path: Path = MODEL_PATH, meta_path: Path = META_PATH) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump(self.model, path)
        self.meta = meta
        meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    @classmethod
    def load(cls, path: Path = MODEL_PATH, meta_path: Path = META_PATH) -> "CorrectionModel | None":
        if not path.exists():
            return None
        m = cls()
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", category=UserWarning)  # e.g. saved with another sklearn version
                m.model = joblib.load(path)
        except Exception:  # noqa: BLE001 - an unreadable model must never break the advisory
            return None
        m.meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
        return m


class PureMLModel:
    """Baseline without physics: learns survival from the shipment details alone."""

    def __init__(self, seed: int = 0):
        self.model = _gbr(seed)

    def fit(self, data: Dataset) -> "PureMLModel":
        self.model.fit(data.raw, logit(data.obs), sample_weight=data.weight)
        return self

    def predict(self, data: Dataset) -> np.ndarray:
        return expit(self.model.predict(data.raw))


def metrics(pred: np.ndarray, obs: np.ndarray, target: float = 0.95) -> dict:
    err = pred - obs
    return {
        "mae_pp": float(100 * np.mean(np.abs(err))),
        "rmse_pp": float(100 * np.sqrt(np.mean(err**2))),
        "bias_pp": float(100 * np.mean(err)),
        # Would the exporter make the right call ("safe" = at least the target alive)?
        "safe_call_accuracy": float(np.mean((pred >= target) == (obs >= target))),
    }


def importances(model: CorrectionModel, test: Dataset, seed: int = 0, repeats: int = 10) -> list[dict]:
    """Permutation importance: how much the corrected prediction's error grows (in percentage points)
    when one piece of information given to the AI is scrambled across the held-out shipments.
    The physics estimate the correction is added to is kept intact."""
    rng = np.random.default_rng(seed)
    phys_col = HYBRID_FEATURES.index("phys_logit")

    base_logit = test.hybrid[:, phys_col]  # the physics estimate itself is never scrambled

    def mae(X):
        return float(np.mean(np.abs(expit(base_logit + model.correction(X)) - test.obs)))

    base = mae(test.hybrid)
    out = []
    for j, f in enumerate(HYBRID_FEATURES):
        deltas = []
        for _ in range(repeats):
            X = test.hybrid.copy()
            X[:, j] = rng.permutation(X[:, j])
            deltas.append(mae(X) - base)
        out.append({"feature": f, "label": FEATURE_LABELS[f], "importance_pp": float(100 * np.mean(deltas))})
    return sorted(out, key=lambda d: -d["importance_pp"])


def model_meta(trained_on: str, n: int, test_metrics: dict, extra: dict | None = None) -> dict:
    return {
        "trained_on": trained_on,                 # "simulated" until real shipments replace them
        "n_shipments": n,
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "model": "GradientBoostingRegressor on logit residual (physics + AI correction)",
        "sklearn_version": sklearn.__version__,
        "features": HYBRID_FEATURES,
        "test_metrics": test_metrics,
        **(extra or {}),
    }


def correct_one(row: dict, model: CorrectionModel | None = None) -> dict | None:
    """AI-corrected survival for one planned shipment (row in RAW_COLUMNS format)."""
    model = model or CorrectionModel.load()
    if model is None:
        return None
    p = physics_prediction(row)
    f = feature_row(row, p)
    x = np.array([[f[k] for k in HYBRID_FEATURES]])
    corr = float(model.correction(x)[0])
    corrected = float(expit(logit(p["phys_survival"]) + corr))
    return {
        "physics_survival_pct": round(100 * p["phys_survival"], 2),
        "corrected_survival_pct": round(100 * corrected, 2),
        "adjustment_pp": round(100 * (corrected - p["phys_survival"]), 2),
        "trained_on": model.meta.get("trained_on", "unknown"),
        "n_shipments": model.meta.get("n_shipments"),
    }
