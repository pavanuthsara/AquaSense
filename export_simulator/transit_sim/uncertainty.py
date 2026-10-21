"""Temperature uncertainty: simulate a shipment across a temperature RANGE instead of one value.

Exporters usually know only a band ("the hold will be 24-30 C"), not the exact profile. We run:

* three constant cases: low, middle and high end of the range;
* ``samples`` random but smooth profiles that wander inside the range (a new knot every
  ``knot_h`` hours, linear in between), seeded so results are reproducible.

The packing decision should use the pessimistic end (``survival_p10`` / ``worst``), not the middle.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

from .config import Interventions, Shipment, Species, Unpacking
from .model import SimulationResult, simulate


@dataclass
class RangeResult:
    t_low: float
    t_high: float
    runs: list[SimulationResult]
    labels: list[str]
    worst: SimulationResult
    worst_label: str
    stats: dict


def random_profile(rng: np.random.Generator, t_low: float, t_high: float, duration_h: float,
                   knot_h: float = 6.0) -> list[tuple[float, float]]:
    knots = np.arange(0.0, duration_h + knot_h, knot_h)
    knots[-1] = max(knots[-1], duration_h)
    return [(float(t), float(rng.uniform(t_low, t_high))) for t in knots]


def run_temperature_range(species: Species, shipment: Shipment, t_low: float, t_high: float,
                          interventions: Interventions | None = None,
                          unpacking: Unpacking | None = Unpacking(), samples: int = 20,
                          seed: int = 0, knot_h: float = 6.0, dt_out: float = 0.25) -> RangeResult:
    if t_high < t_low:
        t_low, t_high = t_high, t_low
    rng = np.random.default_rng(seed)
    cases: list[tuple[str, float | list]] = [
        (f"constant {t_low:g} C", t_low),
        (f"constant {(t_low + t_high) / 2:g} C", (t_low + t_high) / 2),
        (f"constant {t_high:g} C", t_high),
    ]
    cases += [(f"random profile {i + 1}", random_profile(rng, t_low, t_high, shipment.duration_h, knot_h))
              for i in range(samples)]

    runs, labels = [], []
    for label, temp in cases:
        runs.append(simulate(species, replace(shipment, temperature_c=temp), interventions, unpacking, dt_out))
        labels.append(label)

    key = "survival_after_unpacking" if unpacking is not None else "survival_at_arrival"
    arrival = np.array([r.summary["survival_at_arrival"] for r in runs])
    after = np.array([r.summary[key] for r in runs])
    i_worst = int(np.argmin(after))
    stats = {
        "temperature_range_c": [t_low, t_high],
        "n_runs": len(runs),
        "survival_at_arrival": {"min": float(arrival.min()), "p10": float(np.percentile(arrival, 10)),
                                "median": float(np.median(arrival)), "max": float(arrival.max())},
        "survival_after_unpacking": {"min": float(after.min()), "p10": float(np.percentile(after, 10)),
                                     "median": float(np.median(after)), "max": float(after.max())},
        "worst_case": labels[i_worst],
        "worst_case_summary": runs[i_worst].summary,
    }
    return RangeResult(t_low, t_high, runs, labels, runs[i_worst], labels[i_worst], stats)


def explain_range(rr: RangeResult) -> str:
    a = rr.stats["survival_at_arrival"]
    u = rr.stats["survival_after_unpacking"]
    return "\n".join([
        f"Temperature {rr.t_low:g}-{rr.t_high:g} C ({rr.stats['n_runs']} simulated journeys):",
        f"  Survival at arrival:     {100 * a['min']:.1f}% (worst) | {100 * a['p10']:.1f}% (P10) | "
        f"{100 * a['median']:.1f}% (median) | {100 * a['max']:.1f}% (best)",
        f"  Survival after unpacking: {100 * u['min']:.1f}% (worst) | {100 * u['p10']:.1f}% (P10) | "
        f"{100 * u['median']:.1f}% (median) | {100 * u['max']:.1f}% (best)",
        f"  Worst case: {rr.worst_label}. Base packing decisions on the worst case / P10, not the median.",
    ])
