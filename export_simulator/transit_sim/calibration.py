"""Calibrate the bag model to Pramod et al. (2010) and validate it.

Protocol (each stage only sees the data it is allowed to see):

1. Water quality, control bag  -> o2_rate, tan_rate, stress_amp, sealed-bag kLa
   fitted to DO, TAN and CO2. pH is NOT fitted: it is predicted from carbonate chemistry and
   used as a check (Pramod's titrimetric CO2 and pH are not mutually consistent; see README).
2. Mortality, control bag      -> GUTS kd, b, z fitted to the cumulative mortality curve.
3. Anaesthetic bags            -> one metabolic factor + one excretion factor per anaesthetic,
   fitted to that bag's DO, TAN and CO2.
4. Validation                  -> mortality of the anaesthetic bags is PREDICTED (no mortality
   data used for them) and compared with the observed curves. pH is compared for all bags.
"""
from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import yaml
from scipy.optimize import least_squares

from .config import CONFIG_DIR, SPECIES_DIR, Interventions, Shipment, Species, load_species
from .model import BagModel, bag_defaults

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "pramod2010" / "timeseries.csv"
TREATMENTS = ("control", "ms222", "benzocaine")
LABELS = {"control": "Control", "ms222": "MS-222 40 mg/L", "benzocaine": "Benzocaine 20 mg/L"}

# Measurement scales used to weight residuals (roughly the digitising error + between-bag SE).
SIGMA = {"do": 0.5, "tan": 0.5, "co2": 3.0, "ph": 0.05, "mortality": 1.0}


def load_pramod() -> dict[str, dict[str, np.ndarray]]:
    out: dict[str, dict[str, list]] = {}
    with open(DATA, encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            d = out.setdefault(r["treatment"], {k: [] for k in ("t", "do", "tan", "co2", "ph", "nh3", "mortality")})
            d["t"].append(float(r["time_h"]))
            d["do"].append(float(r["do_mgL"]))
            d["tan"].append(float(r["tan_mgL"]))
            d["co2"].append(float(r["co2_mgL"]))
            d["ph"].append(float(r["ph"]))
            d["nh3"].append(float(r["nh3_mgL"]) if r["nh3_mgL"] else float("nan"))
            d["mortality"].append(float(r["mortality_pct"]))
    return {k: {kk: np.array(vv) for kk, vv in v.items()} for k, v in out.items()}


def pramod_shipment(kla: float | None = None) -> Shipment:
    """The Pramod 2010 bag: 6 x 12 g tiger barb, 1 L water, 1:3 O2:water, 22 C, 48 h."""
    return Shipment(fish_count=6, fish_mass_g=12.0, water_l=1.0, gas_l=1.0 / 3.0, duration_h=48.0,
                    temperature_c=22.0, gas_o2_fraction=1.0, initial_do_mgL=20.0,
                    initial_tan_mgL=0.58, initial_ph=7.40, alkalinity_mgL_caco3=65.0, kla_per_h=kla)


def _run(sp: Species, kla: float, iv: Interventions | None = None):
    return BagModel(sp, pramod_shipment(kla), iv).run(unpacking=None, dt_out=6.0)


def _resid(r, obs, keys) -> np.ndarray:
    parts = []
    for k in keys:
        model = {"do": r.do, "tan": r.tan, "co2": r.co2, "ph": r.ph,
                 "mortality": 100.0 * (1.0 - r.survival)}[k]
        parts.append((model - obs[k]) / SIGMA[k])
    return np.concatenate(parts)


def fit_metrics(model: np.ndarray, obs: np.ndarray) -> dict:
    err = model - obs
    ss_res = float(np.sum(err**2))
    ss_tot = float(np.sum((obs - obs.mean()) ** 2)) or 1.0
    return {"rmse": float(np.sqrt(np.mean(err**2))), "bias": float(np.mean(err)),
            "nse": 1.0 - ss_res / ss_tot, "end_model": float(model[-1]), "end_obs": float(obs[-1])}


@dataclass
class CalibrationResult:
    species: Species
    kla: float
    anaesthetics: dict
    metrics: dict
    runs: dict          # treatment -> SimulationResult at dt 0.25 h
    data: dict

    def to_json(self) -> dict:
        return {
            "species_parameters": {k: getattr(self.species, k) for k in
                                   ("o2_rate", "tan_rate", "stress_amp", "guts_kd", "guts_b", "guts_z")},
            "sealed_bag_kla_per_h": self.kla,
            "anaesthetics": self.anaesthetics,
            "metrics": self.metrics,
        }


def calibrate(base: Species | None = None) -> CalibrationResult:
    data = load_pramod()
    sp = base or load_species("tiger_barb")
    ctrl = data["control"]

    # ---- stage 1: water quality of the control bag
    def r1(lp):
        o2, tan, amp, kla = np.exp(lp)
        s = sp.with_overrides(o2_rate=o2, tan_rate=tan, stress_amp=amp, guts_b=0.0)
        return _resid(_run(s, kla), ctrl, ("do", "tan", "co2"))

    lo, hi = np.log([5, 0.5, 1e-3, 1e-3]), np.log([1000, 50, 20, 20])
    f1 = least_squares(r1, np.log([60, 5, 0.5, 0.1]), bounds=(lo, hi))
    o2, tan, amp, kla = np.exp(f1.x)
    sp = sp.with_overrides(o2_rate=o2, tan_rate=tan, stress_amp=amp)

    # ---- stage 2: GUTS on control mortality
    def r2(lp):
        kd, b, z = np.exp(lp)
        s = sp.with_overrides(guts_kd=kd, guts_b=b, guts_z=z)
        return _resid(_run(s, kla), ctrl, ("mortality",))

    best = None
    for kd0 in (0.02, 0.1, 0.5):
        for z0 in (0.3, 0.5, 0.7):
            f = least_squares(r2, np.log([kd0, 0.05, z0]),
                              bounds=(np.log([1e-4, 1e-4, 1e-4]), np.log([5, 10, 5])))
            if best is None or f.cost < best.cost:
                best = f
    kd, b, z = np.exp(best.x)
    sp = sp.with_overrides(guts_kd=kd, guts_b=b, guts_z=z)

    # ---- stage 3: anaesthetic factors (water quality only)
    anaesthetics = {}
    for trt in ("ms222", "benzocaine"):
        obs = data[trt]

        def r3(lp, obs=obs):
            mf, ef, sf = np.exp(lp)
            iv = Interventions(metabolic_factor=mf, excretion_factor=ef, stress_factor=sf)
            return _resid(_run(sp.with_overrides(guts_b=0.0), kla, iv), obs, ("do", "tan", "co2"))

        f3 = least_squares(r3, np.log([0.8, 0.5, 0.5]), bounds=(np.log([0.05, 0.05, 1e-3]), np.log([2.0, 2.0, 2.0])))
        mf, ef, sf = np.exp(f3.x)
        anaesthetics[trt] = {"metabolic_factor": float(mf), "excretion_factor": float(ef),
                             "stress_factor": float(sf)}

    # ---- stage 4: full runs + validation metrics
    runs, metrics = {}, {}
    for trt in TREATMENTS:
        iv = Interventions(**anaesthetics[trt]) if trt in anaesthetics else Interventions()
        coarse = _run(sp, kla, iv)
        runs[trt] = BagModel(sp, pramod_shipment(kla), iv).run(unpacking=None, dt_out=0.25)
        obs = data[trt]
        model_vals = {"do": coarse.do, "tan": coarse.tan, "co2": coarse.co2, "ph": coarse.ph,
                      "mortality": 100.0 * (1.0 - coarse.survival)}
        metrics[trt] = {k: fit_metrics(model_vals[k], obs[k]) for k in model_vals}
        metrics[trt]["role"] = {
            "control": "calibration: DO/TAN/CO2 + mortality; check: pH",
        }.get(trt, "calibration: DO/TAN/CO2 (3 factors); PREDICTED: mortality, pH")
    return CalibrationResult(sp, float(kla), anaesthetics, metrics, runs, data)


def write_config(cal: CalibrationResult) -> None:
    """Write calibrated values back into the YAML configs (keeps every other entry)."""
    path = SPECIES_DIR / "tiger_barb.yaml"
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    src = "Calibrated to Pramod et al. 2010 control bag (python -m transit_sim calibrate)"
    for key, note in (("o2_rate", "DO+TAN+CO2"), ("tan_rate", "DO+TAN+CO2"), ("stress_amp", "DO+TAN+CO2"),
                      ("guts_kd", "mortality"), ("guts_b", "mortality"), ("guts_z", "mortality")):
        raw["parameters"][key] = {"value": round(float(getattr(cal.species, key)), 5),
                                  "source": f"{src}; fitted to {note}"}
    path.write_text(yaml.safe_dump(raw, sort_keys=False, allow_unicode=True), encoding="utf-8")

    bag = bag_defaults()
    bag["sealed_bag_kla_per_h"] = {"value": round(cal.kla, 5),
                                   "source": "Calibrated to Pramod et al. 2010 control bag (static lab bag, 1 L water, 0.33 L O2)"}
    (CONFIG_DIR / "bag.yaml").write_text(yaml.safe_dump(bag, sort_keys=False), encoding="utf-8")

    iv = {
        "ms222_40mgL": {**{k: round(v, 4) for k, v in cal.anaesthetics["ms222"].items()},
                        "species": "tiger_barb",
                        "source": "Calibrated to Pramod et al. 2010 MS-222 bag (DO/TAN/CO2)"},
        "benzocaine_20mgL": {**{k: round(v, 4) for k, v in cal.anaesthetics["benzocaine"].items()},
                             "species": "tiger_barb",
                             "source": "Calibrated to Pramod et al. 2010 benzocaine bag (DO/TAN/CO2)"},
    }
    (CONFIG_DIR / "interventions.yaml").write_text(yaml.safe_dump(iv, sort_keys=False), encoding="utf-8")


def write_report(cal: CalibrationResult, out_dir: Path) -> list[Path]:
    from .plots import calibration_figure

    out_dir.mkdir(parents=True, exist_ok=True)
    paths = [calibration_figure(cal, out_dir / "pramod2010_calibration.png")]
    (out_dir / "calibration_result.json").write_text(json.dumps(cal.to_json(), indent=2), encoding="utf-8")
    paths.append(out_dir / "calibration_result.json")
    return paths
