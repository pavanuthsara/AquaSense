"""Shipment table <-> physics simulator.

One row = one completed shipment (or one planned shipment at prediction time). Real shipment records
and simulated ones share the same raw columns (``RAW_COLUMNS``), so swapping simulated data for real
data needs no code change.
"""
from __future__ import annotations

import numpy as np

from ..config import Interventions, Shipment, Unpacking, load_interventions, load_species
from ..model import simulate

# Raw columns of a shipment record (what an exporter can write down).
RAW_COLUMNS = [
    "species",          # guppy | tiger_barb
    "fish_mass_g",      # mean weight per fish
    "fish_per_bag",
    "water_l",          # water per bag
    "gas_l",            # oxygen per bag
    "duration_h",       # packing -> fish out of the bag
    "temp_low_c",       # expected / logged temperature range
    "temp_high_c",
    "fasting_h",        # hours without food before packing
    "zeolite_g_per_l",  # 0 or dose
    "anaesthetic",      # none | ms222_40mgL | benzocaine_20mgL
]
# Outcome columns (only for completed shipments).
OUTCOME_COLUMNS = ["fish_counted", "fish_alive", "observed_survival"]

ANAESTHETICS = ("none", "ms222_40mgL", "benzocaine_20mgL")


def interventions_for(row: dict) -> Interventions:
    kw = {}
    sed = row.get("anaesthetic") or "none"
    if sed != "none":
        e = load_interventions()[sed]
        kw = {k: e[k] for k in ("metabolic_factor", "excretion_factor", "stress_factor") if k in e}
    return Interventions(starvation_h=float(row["fasting_h"]), zeolite_g_per_l=float(row["zeolite_g_per_l"]), **kw)


def shipment_for(row: dict, temperature) -> Shipment:
    return Shipment(fish_count=int(row["fish_per_bag"]), fish_mass_g=float(row["fish_mass_g"]),
                    water_l=float(row["water_l"]), gas_l=float(row["gas_l"]),
                    duration_h=float(row["duration_h"]), temperature_c=temperature)


def physics_prediction(row: dict) -> dict:
    """What the physics simulator predicts for this shipment (typical temperature = middle of range)."""
    sp = load_species(row["species"])
    t_mid = 0.5 * (float(row["temp_low_c"]) + float(row["temp_high_c"]))
    r = simulate(sp, shipment_for(row, t_mid), interventions_for(row), Unpacking(), dt_out=1.0)
    s = r.summary
    return {
        "phys_survival": s["survival_after_unpacking"],
        "phys_survival_arrival": s["survival_at_arrival"],
        "phys_min_do": s["min_do_mgL"],
        "phys_max_co2": s["max_co2_mgL"],
        "phys_peak_nh3_unpack": s["peak_nh3_unpacking_mgL"] or 0.0,
    }


def logit(p, eps: float = 0.005):
    p = np.clip(np.asarray(p, dtype=float), eps, 1 - eps)
    return np.log(p / (1 - p))


def expit(x):
    return 1.0 / (1.0 + np.exp(-np.asarray(x, dtype=float)))
