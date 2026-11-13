"""SIMULATED shipment records from a "pretend reality".

Why not just use the simulator's own output? Because the AI layer learns where the simulator is
WRONG. On its own output the simulator is never wrong, so the AI would learn nothing. Instead we
build a second, secretly different world ("pretend reality") and record what happens there, the
way real shipments would be recorded. The AI must then discover the differences from data alone.

The hidden differences are plausible ways the real world may differ from the calibrated model:

1. Guppies breathe ~20 % faster than the size-scaled tiger barb estimate.
2. Bags are moved around in transit, so oxygen enters the water faster than in the still lab
   bag (more on longer trips with more handling, plus random variation).
3. Sedated fish tolerate CO2 better (seen in the Pramod validation: the model under-credits
   anaesthetics), and fish tolerate CO2 less when it is warm.
4. The real temperature runs up to 1 C above the forecast range.
5. Handling stress varies from shipment to shipment (unobservable noise).
6. Deaths are counted fish by fish (binomial counting noise).

Items 1-4 are learnable from the recorded shipment details; 5-6 are noise that no model can learn.
None of these settings are used anywhere else; they exist only to test the AI pipeline.
"""
from __future__ import annotations

import csv
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np

from ..config import Unpacking, load_species
from ..model import bag_defaults, simulate
from ..uncertainty import random_profile
from .physics import OUTCOME_COLUMNS, RAW_COLUMNS, interventions_for, shipment_for


@dataclass(frozen=True)
class PretendReality:
    guppy_o2_factor: float = 1.20
    motion_kla_gain: float = 2.0         # kLa_true = kLa_lab * (1 + gain * motion)
    sedated_co2_tolerance: float = 1.35  # co2_ref multiplier when an anaesthetic is used
    heat_co2_sensitivity: float = 0.02   # per C above 25 C, co2_ref shrinks by this fraction
    forecast_bias_c: float = 1.0         # real journey up to this much hotter than forecast high
    stress_sd: float = 0.30              # log-normal spread of handling stress


def sample_shipment(rng: np.random.Generator, i: int) -> dict:
    species = "guppy" if rng.random() < 0.8 else "tiger_barb"
    if species == "guppy":
        mass = float(rng.uniform(0.2, 0.5))
        water = float(rng.choice([0.3, 0.4, 0.5, 0.75, 1.0]))
    else:
        mass = float(rng.uniform(6.0, 15.0))
        water = float(rng.choice([0.75, 1.0, 1.5, 2.0]))
    gas = round(water * float(rng.uniform(1.0, 3.0)), 2)
    density = float(np.exp(rng.uniform(np.log(8.0), np.log(200.0))))  # g/L, safe to badly overpacked
    fish = max(1, int(round(density * water / mass)))
    t_low = float(rng.uniform(20.0, 29.0))
    t_high = t_low + float(rng.uniform(0.0, 5.0))
    return {
        "id": f"sim-{i:05d}",
        "source": "simulated",
        "species": species,
        "fish_mass_g": round(mass, 3),
        "fish_per_bag": fish,
        "water_l": water,
        "gas_l": gas,
        "duration_h": float(rng.choice([12, 18, 24, 30, 36, 42, 48, 60, 72])),
        "temp_low_c": round(t_low, 1),
        "temp_high_c": round(t_high, 1),
        "fasting_h": float(rng.choice([0, 12, 24, 48], p=[0.15, 0.2, 0.45, 0.2])),
        "zeolite_g_per_l": float(rng.choice([0.0, 20.0], p=[0.7, 0.3])),
        "anaesthetic": str(rng.choice(["none", "ms222_40mgL", "benzocaine_20mgL"], p=[0.6, 0.25, 0.15])),
        "bags": int(rng.integers(5, 31)),
    }


def true_outcome(row: dict, rng: np.random.Generator, world: PretendReality = PretendReality()) -> dict:
    """Run the shipment in the pretend reality and count the survivors."""
    sp = load_species(row["species"])
    t_low, t_high = float(row["temp_low_c"]), float(row["temp_high_c"])
    profile = random_profile(rng, t_low, t_high + world.forecast_bias_c * rng.random(), float(row["duration_h"]))
    t_mean = float(np.mean([t for _, t in profile]))

    co2_ref = sp.co2_ref * (world.sedated_co2_tolerance if row["anaesthetic"] != "none" else 1.0)
    co2_ref *= max(0.7, 1.0 - world.heat_co2_sensitivity * (t_mean - 25.0))
    sp_true = sp.with_overrides(
        o2_rate=sp.o2_rate * (world.guppy_o2_factor if row["species"] == "guppy" else 1.0),
        stress_amp=sp.stress_amp * float(rng.lognormal(0.0, world.stress_sd)),
        co2_ref=co2_ref,
    )
    motion = float(np.clip(0.2 + 0.008 * float(row["duration_h"]) + rng.normal(0.0, 0.15), 0.0, 1.0))
    kla = bag_defaults()["sealed_bag_kla_per_h"]["value"] * (1.0 + world.motion_kla_gain * motion)

    sh = replace(shipment_for(row, profile), kla_per_h=kla)
    r = simulate(sp_true, sh, interventions_for(row), Unpacking(), dt_out=1.0)
    p_true = float(r.summary["survival_after_unpacking"])

    counted = int(row["fish_per_bag"]) * int(row["bags"])
    alive = int(rng.binomial(counted, min(max(p_true, 0.0), 1.0)))
    return {"fish_counted": counted, "fish_alive": alive, "observed_survival": alive / counted}


def generate(n: int, seed: int = 0, world: PretendReality = PretendReality()) -> list[dict]:
    rng = np.random.default_rng(seed)
    rows = []
    for i in range(n):
        row = sample_shipment(rng, i)
        row.update(true_outcome(row, rng, world))
        rows.append(row)
    return rows


CSV_COLUMNS = ["id", "source", *RAW_COLUMNS, "bags", *OUTCOME_COLUMNS]


def write_csv(rows: list[dict], path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_COLUMNS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    return path


def read_csv(path: Path) -> list[dict]:
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))
