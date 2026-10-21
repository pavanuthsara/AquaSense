"""Transit advisory: a full packing plan, not just a fish count.

Supervisor requirement (2026-10-21): the exporter must be told how the oxygen is used and how fast,
how fast fish will die, which chemicals / add-ons to use and how much, and what happens at unpacking.

Method
------
1. Candidate add-on plans (basic, longer fasting, zeolite, MS-222, benzocaine, combinations) are
   built from what the exporter allows.
2. For each plan, the largest fish count per bag is found whose survival AFTER UNPACKING stays at or
   above the target at the hot end of the temperature range (warmer is always worse in this model,
   so the constant high temperature is the worst case). Bisection on fish count.
3. The best plan is re-run over the whole temperature range (constant low/mid/high + random
   profiles) to report the median and worst-case timelines.
4. Oxygen, mortality, chemistry, temperature and unpacking sections are derived from those runs.
"""
from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field, replace

import numpy as np

from . import chemistry as chem
from .config import Interventions, Shipment, Species, Unpacking, load_interventions, load_species
from .model import SimulationResult, simulate
from .uncertainty import run_temperature_range

# ----------------------------------------------------------------------------- add-on catalogue
# Doses and evidence come from the literature collected in the project handoff. "simulated" means
# the bag model includes the add-on's effect; "evidence only" means it is listed but not modelled.
ADDONS = {
    "fasting": {
        "name": "Fasting before packing",
        "simulated": True,
        "evidence": "Pramod et al. 2010 fasted fish 24 h (model reference). Fed fish use ~35 % more O2 "
                    "(Ruiz-Jarabo & de Pedro 2024) and excrete up to ~3x more ammonia (tench data).",
        "caution": "Do not fast longer than 48 h without species-specific advice; weak fish handle transport worse.",
    },
    "zeolite": {
        "name": "Zeolite (clinoptilolite)",
        "dose_g_per_l": 20.0,
        "simulated": True,
        "evidence": "Teo, Chen & Lee 1989 (guppy): 20 g/L optimal; higher doses caused turbidity and more deaths. "
                    "Uptake kinetics in the model are PROVISIONAL.",
        "caution": "Rinse before use to limit turbidity. Salt in the water reduces zeolite effectiveness.",
    },
    "ms222_40mgL": {
        "name": "MS-222 (tricaine methanesulfonate)",
        "dose_mg_per_l": 40.0,
        "simulated": True,
        "evidence": "Pramod et al. 2010 (tiger barb, light sedation): ammonia -54 %, mortality 15.3 % -> 8.4 %. "
                    "Effect calibrated on tiger barb only.",
        "caution": "MS-222 is acidic; follow label/buffering guidance. Check the importing country's rules "
                   "on anaesthetics. Overdose kills - the dose effect is not monotonic.",
    },
    "benzocaine_20mgL": {
        "name": "Benzocaine",
        "dose_mg_per_l": 20.0,
        "simulated": True,
        "evidence": "Pramod et al. 2010 (tiger barb): ammonia -50 %, mortality 15.3 % -> 9.0 %. "
                    "Effect calibrated on tiger barb only.",
        "caution": "Not water-soluble: dissolve in ethanol/acetone first. Narrower safety margin than MS-222 "
                   "(Kiessling et al. 2009). Check the importing country's rules.",
    },
    "phenoxyethanol": {
        "name": "2-Phenoxyethanol",
        "dose_text": "0.11-0.22 g/L",
        "simulated": False,
        "evidence": "Teo, Chen & Lee 1989 (guppy): zero mortality in packing trials; suppresses O2 use "
                    "(Teo & Chen 1993). Not yet in the model.",
        "caution": "Evidence only - not simulated. Confirm dose for the species before use.",
    },
    "tris_buffer": {
        "name": "Tris buffer",
        "dose_text": "0.02 M, pH 8",
        "simulated": False,
        "evidence": "Teo, Chen & Lee 1989 (guppy) reported lowest mortality with 0.02 M Tris at pH 8.",
        "caution": "Not recommended by the model: holding pH high keeps more ammonia in the toxic NH3 form "
                   "during transit. Use only with zeolite and short trips.",
    },
}


MIN_GAIN_SHARE = 0.95  # add-ons that gain < 5 % more fish per bag are not recommended


@dataclass
class AdvisoryRequest:
    species: str = "guppy"
    fish_mass_g: float = 0.3
    total_fish: int | None = None          # fish to ship in total (optional) -> number of bags
    water_l: float = 0.4
    gas_l: float = 1.2
    duration_h: float = 24.0
    temp_low_c: float = 24.0
    temp_high_c: float = 28.0
    target_survival: float = 0.95          # 5 % DOA = industry warranty threshold (Lim et al. 2003)
    allow_anaesthetic: bool = True
    allow_zeolite: bool = True
    max_fasting_h: float = 48.0
    initial_ph: float = 7.4
    alkalinity_mgL_caco3: float = 65.0
    initial_tan_mgL: float = 0.3
    kla_per_h: float | None = None
    samples: int = 10                      # random temperature profiles for the final check
    seed: int = 0

    def validate(self) -> None:
        checks = [
            (self.fish_mass_g > 0, "fish_mass_g must be > 0"),
            (self.water_l > 0, "water_l must be > 0"),
            (self.gas_l > 0, "gas_l must be > 0"),
            (0 < self.duration_h <= 120, "duration_h must be in (0, 120]"),
            (0 <= self.temp_low_c <= 40 and 0 <= self.temp_high_c <= 40, "temperatures must be 0-40 C"),
            (0.5 <= self.target_survival < 1.0, "target_survival must be in [0.5, 1)"),
            (self.total_fish is None or self.total_fish > 0, "total_fish must be > 0"),
            (0 <= self.samples <= 50, "samples must be 0-50"),
        ]
        for ok, msg in checks:
            if not ok:
                raise ValueError(msg)


@dataclass
class Plan:
    key: str
    label: str
    interventions: Interventions
    addons: list[str]
    fasting_h: float
    max_fish: int = 0
    survival_at_max: float = 0.0
    doses: list[dict] = field(default_factory=list)


# ----------------------------------------------------------------------------- helpers
def _shipment(req: AdvisoryRequest, n: int, temp) -> Shipment:
    return Shipment(fish_count=n, fish_mass_g=req.fish_mass_g, water_l=req.water_l, gas_l=req.gas_l,
                    duration_h=req.duration_h, temperature_c=temp, initial_tan_mgL=req.initial_tan_mgL,
                    initial_ph=req.initial_ph, alkalinity_mgL_caco3=req.alkalinity_mgL_caco3,
                    kla_per_h=req.kla_per_h)


def _survival(sp: Species, req: AdvisoryRequest, plan: Plan, n: int, temp: float) -> float:
    r = simulate(sp, _shipment(req, n, temp), plan.interventions, Unpacking(), dt_out=1.0)
    return r.summary["survival_after_unpacking"]


def _max_fish(sp: Species, req: AdvisoryRequest, plan: Plan) -> tuple[int, float]:
    """Largest n with survival >= target at the hot end of the range (bisection)."""
    t = max(req.temp_low_c, req.temp_high_c)
    if _survival(sp, req, plan, 1, t) < req.target_survival:
        return 0, _survival(sp, req, plan, 1, t)
    # upper bound: 400 g of fish per litre is far beyond any real bag
    hi = max(2, int(400.0 * req.water_l / req.fish_mass_g))
    lo = 1
    if _survival(sp, req, plan, hi, t) >= req.target_survival:
        return hi, _survival(sp, req, plan, hi, t)
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if _survival(sp, req, plan, mid, t) >= req.target_survival:
            lo = mid
        else:
            hi = mid
    return lo, _survival(sp, req, plan, lo, t)


def _plans(req: AdvisoryRequest) -> list[Plan]:
    table = load_interventions()
    fast = [24.0] + ([48.0] if req.max_fasting_h >= 48 else [])
    fast = [f for f in fast if f <= max(req.max_fasting_h, 24.0)]
    sed_opts: list[str | None] = [None]
    if req.allow_anaesthetic:
        sed_opts += [k for k in ("ms222_40mgL", "benzocaine_20mgL") if k in table]
    zeo_opts = [0.0] + ([ADDONS["zeolite"]["dose_g_per_l"]] if req.allow_zeolite else [])
    plans = []
    for f in fast:
        for sed in sed_opts:
            for z in zeo_opts:
                kw = {}
                if sed:
                    e = table[sed]
                    kw = {k: e[k] for k in ("metabolic_factor", "excretion_factor", "stress_factor") if k in e}
                iv = Interventions(starvation_h=f, zeolite_g_per_l=z, **kw)
                addons = (["zeolite"] if z else []) + ([sed] if sed else [])
                parts = [f"fast {f:g} h"] + [ADDONS[a]["name"].split(" (")[0] for a in addons]
                key = "|".join([f"fast{f:g}"] + addons)
                plans.append(Plan(key=key, label=" + ".join(parts), interventions=iv, addons=addons, fasting_h=f))
    return plans


def _doses(plan: Plan, req: AdvisoryRequest) -> list[dict]:
    out = [{"addon": "fasting", "name": ADDONS["fasting"]["name"], "amount": f"{plan.fasting_h:g} h before packing",
            "per_bag": None, "simulated": True, "evidence": ADDONS["fasting"]["evidence"],
            "caution": ADDONS["fasting"]["caution"]}]
    for a in plan.addons:
        info = ADDONS[a]
        if "dose_mg_per_l" in info:
            amount = f"{info['dose_mg_per_l']:g} mg/L"
            per_bag = f"{info['dose_mg_per_l'] * req.water_l:.1f} mg per bag ({req.water_l:g} L)"
        else:
            amount = f"{info['dose_g_per_l']:g} g/L"
            per_bag = f"{info['dose_g_per_l'] * req.water_l:.1f} g per bag ({req.water_l:g} L)"
        out.append({"addon": a, "name": info["name"], "amount": amount, "per_bag": per_bag, "simulated": True,
                    "evidence": info["evidence"], "caution": info["caution"]})
    return out


def _series(r: SimulationResult, step_h: float = 1.0) -> dict:
    """Down-sample a run to roughly hourly points for charts / API payloads."""
    idx = [0]
    for i, t in enumerate(r.t):
        if t - r.t[idx[-1]] >= step_h - 1e-9 or r.phase[i] != r.phase[idx[-1]]:
            idx.append(i)
    if idx[-1] != len(r.t) - 1:
        idx.append(len(r.t) - 1)
    pick = lambda a, nd=4: [round(float(a[i]), nd) for i in idx]  # noqa: E731
    gas0 = float(r.gas_o2_atm[0]) or 1.0
    gas = [round(float(100 * r.gas_o2_atm[i] / gas0), 1) if r.phase[i] == 0 else None for i in idx]
    return {"t_h": pick(r.t, 2), "do_mgL": pick(r.do, 2), "gas_o2_pct": gas,
            "tan_mgL": pick(r.tan, 2), "co2_mgL": pick(r.co2, 1), "ph": pick(r.ph, 2), "nh3_mgL": pick(r.nh3, 4),
            "alive_pct": pick(100 * r.survival, 2), "temp_c": pick(r.temp, 1), "opened": [int(r.phase[i]) for i in idx]}


def _first_time(r: SimulationResult, mask) -> float | None:
    i = np.where(mask)[0]
    return float(r.t[i[0]]) if len(i) else None


def _oxygen_section(r: SimulationResult, sp: Species, sh: Shipment, worst: SimulationResult) -> dict:
    transit = r.phase == 0
    t = r.t[transit]
    tk = chem.kelvin(r.temp[transit])
    gas_mg = r.gas_o2_atm[transit] * sh.gas_l / (chem.R_GAS * tk) * chem.MW_O2 * 1000.0
    water_mg = r.do[transit] * sh.water_l
    total = gas_mg + water_mg
    used = float(total[0] - total[-1])
    hours = float(t[-1] - t[0]) or 1.0
    first6 = np.searchsorted(t, 6.0)
    rate_start = float((total[0] - total[min(first6, len(t) - 1)]) / max(t[min(first6, len(t) - 1)], 1e-6))
    rate_avg = used / hours
    t_crit = _first_time(r, transit & (r.do < sp.do_crit))
    t_crit_worst = _first_time(worst, (worst.phase == 0) & (worst.do < sp.do_crit))
    gas_left = float(r.gas_o2_atm[transit][-1] / r.gas_o2_atm[0] * 100)
    limiting = "water" if (t_crit is not None or r.do[transit].min() < 2 * sp.do_crit) and gas_left > 30 else (
        "headspace" if gas_left <= 30 else "none")
    msg = {
        "water": "The bag still has oxygen gas, but it moves into still water too slowly: the WATER runs short. "
                 "More water surface/motion or fewer fish helps more than extra gas.",
        "headspace": "The oxygen gas itself is being used up: increase the gas volume or reduce fish.",
        "none": "Oxygen is not the limiting factor for this plan.",
    }[limiting]
    return {
        "o2_total_start_mg": round(float(total[0]), 1),
        "o2_used_mg": round(used, 1),
        "o2_left_pct": round(float(total[-1] / total[0] * 100), 1),
        "gas_o2_left_pct": round(gas_left, 1),
        "use_rate_first_6h_mg_per_h": round(rate_start, 2),
        "use_rate_average_mg_per_h": round(rate_avg, 2),
        "use_per_fish_mg_per_h": round(rate_avg / max(sh.fish_count, 1), 3),
        "min_water_do_mgL": round(float(r.do[transit].min()), 2),
        "do_critical_mgL": sp.do_crit,
        "hours_to_critical_do": t_crit,
        "hours_to_critical_do_worst": t_crit_worst,
        "limiting": limiting,
        "explanation": (f"Fish use about {rate_start:.1f} mg O2/h in the first 6 h (handling stress), then "
                        f"{rate_avg:.1f} mg/h on average; {used:.0f} of {total[0]:.0f} mg is used over the trip. ")
                       + msg,
    }


def _mortality_section(med: SimulationResult, worst: SimulationResult, sh: Shipment, target: float) -> dict:
    def at(r, h):
        transit = r.phase == 0
        i = min(np.searchsorted(r.t[transit], h), transit.sum() - 1)
        return round(float(100 * r.survival[transit][i]), 2)

    checkpoints = sorted({h for h in (6, 12, 24, 36, 48, 72) if h <= sh.duration_h} | {sh.duration_h})
    first_loss = _first_time(med, med.survival < 0.99)
    first_loss_w = _first_time(worst, worst.survival < 0.99)
    safe_w = _first_time(worst, worst.survival < target)
    surv_arrive = float(med.summary["survival_at_arrival"])
    surv_after = float(med.summary["survival_after_unpacking"])
    dead = sh.fish_count * (1 - surv_after)
    dead_w = sh.fish_count * (1 - float(worst.summary["survival_after_unpacking"]))
    return {
        "survival_at_checkpoints_pct": [{"hour": h, "median": at(med, h), "worst": at(worst, h)} for h in checkpoints],
        "survival_at_arrival_pct": round(100 * surv_arrive, 2),
        "survival_after_unpacking_pct": round(100 * surv_after, 2),
        "worst_survival_after_unpacking_pct": round(100 * float(worst.summary["survival_after_unpacking"]), 2),
        "expected_dead_per_bag": round(dead, 1),
        "expected_dead_per_bag_worst": round(dead_w, 1),
        "hours_to_first_1pct_loss": first_loss,
        "hours_to_first_1pct_loss_worst": first_loss_w,
        "hours_until_below_target_worst": safe_w,
        "main_cause": med.summary["main_driver"],
        "cause_share_pct": {k: round(100 * v, 1) for k, v in med.summary["stress_share"].items()},
        "explanation": (
            f"Deaths are expected to start around hour {first_loss:.0f}" if first_loss is not None
            else "No deaths are expected during transit")
        + (f" (hour {first_loss_w:.0f} in the hottest case)" if first_loss_w is not None else "")
        + f". Main cause: {med.summary['main_driver']}. About {dead:.1f} of {sh.fish_count} fish per bag "
          f"(worst case {dead_w:.1f}) are expected to be lost.",
    }


def _chemistry_section(med: SimulationResult) -> dict:
    s = med.summary
    return {
        "max_co2_mgL": round(s["max_co2_mgL"], 1),
        "final_ph": round(s["final_ph"], 2),
        "final_tan_mgL": round(s["final_tan_mgL"], 2),
        "max_nh3_transit_mgL": round(s["max_nh3_transit_mgL"], 4),
        "explanation": (f"Fish breathe out CO2, which builds up to {s['max_co2_mgL']:.0f} mg/L (harmful above "
                        f"~20 mg/L) and pulls pH down to {s['final_ph']:.2f}. The low pH keeps ammonia "
                        f"({s['final_tan_mgL']:.1f} mg/L total) mostly in its harmless form during the trip."),
    }


def _unpacking_section(med: SimulationResult, worst: SimulationResult) -> dict:
    s, w = med.summary, worst.summary
    peak, peak_w = s["peak_nh3_unpacking_mgL"], w["peak_nh3_unpacking_mgL"]
    danger = (peak_w or 0) > 0.02
    steps = [
        "Float the closed bag in the receiving tank 15-20 min to match temperature.",
        "Open the bag only when ready to move the fish - CO2 escapes within minutes and pH rises.",
        "Net the fish out; do NOT pour bag water into the tank.",
        "If the fish must stay in bag water, add tank water gradually and keep the time short.",
    ]
    return {
        "ph_after_opening": round(s["peak_ph_unpacking"], 2),
        "peak_nh3_mgL": round(peak, 4),
        "peak_nh3_mgL_worst": round(peak_w, 4),
        "times_transit_level": round(peak / max(s["max_nh3_transit_mgL"], 1e-9), 1),
        "danger": danger,
        "explanation": (f"When the bag is opened, CO2 escapes and pH jumps to {s['peak_ph_unpacking']:.2f}. "
                        f"The ammonia that was harmless becomes toxic: NH3 rises to {peak:.3f} mg/L "
                        f"({'above' if peak > 0.02 else 'below'} the 0.02 mg/L safe level)."),
        "steps": steps,
    }


def _temperature_section(sp: Species, req: AdvisoryRequest, plan: Plan, n: int) -> dict:
    temps = np.arange(16, 35, 1.0)
    surv = [_survival(sp, req, plan, n, float(t)) for t in temps]
    ok = [float(t) for t, s in zip(temps, surv) if s >= req.target_survival]
    t_max = max(ok) if ok else None
    hot = req.temp_high_c
    if t_max is None:
        advice = "This plan does not reach the target at any temperature tested."
    elif hot > t_max:
        advice = (f"The forecast reaches {hot:g} C but this plan is only safe up to {t_max:g} C: "
                  "use an insulated box with cold (gel) packs or reduce fish.")
    else:
        advice = (f"Safe up to {t_max:g} C at this load; the forecast maximum is {hot:g} C. "
                  "Use an insulated box to keep it there.")
    return {"max_safe_constant_temp_c": t_max,
            "curve": [{"temp_c": float(t), "survival_pct": round(100 * s, 2)} for t, s in zip(temps, surv)],
            "advice": advice}


# ----------------------------------------------------------------------------- public API
def advise(req: AdvisoryRequest) -> dict:
    req.validate()
    sp = load_species(req.species)
    plans = _plans(req)
    for p in plans:
        p.max_fish, p.survival_at_max = _max_fish(sp, req, p)
        p.doses = _doses(p, req)

    basic = plans[0]
    # An add-on must earn its place: among plans within 5 % of the best fish count, take the one with
    # the fewest chemicals, then the shortest fasting, then the most fish.
    top = max(p.max_fish for p in plans)
    near = [p for p in plans if p.max_fish >= MIN_GAIN_SHARE * top]
    best = min(near, key=lambda p: (len(p.addons), p.fasting_h, -p.max_fish))
    chem_free = max((p for p in plans if not p.addons), key=lambda p: (p.max_fish, -p.fasting_h))

    warnings = []
    if sp.name != "tiger_barb":
        warnings.append(f"{sp.name}: parameters are scaled from the tiger barb calibration (Pramod 2010) and "
                        "not yet validated for this species. Treat numbers as provisional.")
    if any(a in ("ms222_40mgL", "benzocaine_20mgL") for a in best.addons) and sp.name != "tiger_barb":
        warnings.append("Anaesthetic effects were calibrated on tiger barb; the effect on this species is assumed.")
    if "zeolite" in best.addons:
        warnings.append("Zeolite uptake kinetics are provisional (to be calibrated from Teo et al. 1989).")

    result: dict = {
        "request": asdict(req),
        "species": {"name": sp.name, "scientific_name": sp.scientific_name},
        "target_survival_pct": round(100 * req.target_survival, 1),
        "warnings": warnings,
        "options": [{"key": p.key, "label": p.label, "recommended": False, "max_fish_per_bag": p.max_fish,
                     "density_g_per_l": round(p.max_fish * req.fish_mass_g / req.water_l, 1),
                     "survival_hot_case_pct": round(100 * p.survival_at_max, 2),
                     "gain_vs_basic_pct": (round(100 * (p.max_fish - basic.max_fish) / basic.max_fish, 1)
                                           if basic.max_fish else None),
                     "addons": p.addons, "doses": p.doses} for p in plans],
    }
    if best.max_fish == 0:
        result["feasible"] = False
        result["recommendation"] = {
            "summary": (f"No plan keeps {100 * req.target_survival:.0f}% of fish alive for {req.duration_h:g} h at "
                        f"{req.temp_high_c:g} C, even with one fish per bag. Shorten the journey, lower the "
                        "temperature, or use more water per bag.")}
        return result

    result["feasible"] = True
    for o in result["options"]:
        o["recommended"] = o["key"] == best.key
    n = best.max_fish
    rr = run_temperature_range(sp, _shipment(req, n, req.temp_high_c), req.temp_low_c, req.temp_high_c,
                               best.interventions, Unpacking(), samples=req.samples, seed=req.seed, dt_out=0.25)
    med_i = int(np.argsort([r.summary["survival_after_unpacking"] for r in rr.runs])[len(rr.runs) // 2])
    med, worst = rr.runs[med_i], rr.worst
    sh = _shipment(req, n, req.temp_high_c)

    bags = math.ceil(req.total_fish / n) if req.total_fish else None
    result["recommendation"] = {
        "plan_key": best.key,
        "plan_label": best.label,
        "fish_per_bag": n,
        "density_g_per_l": round(n * req.fish_mass_g / req.water_l, 1),
        "bags_needed": bags,
        "fish_per_bag_without_chemicals": chem_free.max_fish,
        "bags_needed_without_chemicals": (math.ceil(req.total_fish / chem_free.max_fish)
                                          if req.total_fish and chem_free.max_fish else None),
        "doses": best.doses,
        "not_simulated_options": [{"addon": k, "name": v["name"], "amount": v["dose_text"],
                                   "evidence": v["evidence"], "caution": v["caution"]}
                                  for k, v in ADDONS.items() if not v["simulated"]],
        "summary": (f"Pack {n} fish per bag ({n * req.fish_mass_g / req.water_l:.0f} g/L) with: {best.label}. "
                    + (f"{bags} bags for {req.total_fish} fish. " if bags else "")
                    + f"Expected survival after unpacking: {100 * med.summary['survival_after_unpacking']:.1f}% "
                      f"(worst case {100 * worst.summary['survival_after_unpacking']:.1f}%) over "
                      f"{req.temp_low_c:g}-{req.temp_high_c:g} C."),
    }
    result["survival_band_pct"] = {k: round(100 * v, 2) for k, v in rr.stats["survival_after_unpacking"].items()}
    result["oxygen"] = _oxygen_section(med, sp, sh, worst)
    result["mortality"] = _mortality_section(med, worst, sh, req.target_survival)
    result["chemistry"] = _chemistry_section(med)
    result["unpacking"] = _unpacking_section(med, worst)
    result["temperature"] = _temperature_section(sp, req, best, n)
    result["timeline"] = {"median": _series(med), "worst": _series(worst), "worst_label": rr.worst_label}
    return result


def advise_text(adv: dict) -> str:
    """Plain-text rendering of an advisory (CLI)."""
    if not adv["feasible"]:
        return adv["recommendation"]["summary"]
    rec = adv["recommendation"]
    lines = ["PACKING PLAN", "  " + rec["summary"]]
    if rec.get("bags_needed_without_chemicals"):
        lines.append(f"  Without chemicals: {rec['fish_per_bag_without_chemicals']} fish/bag -> "
                     f"{rec['bags_needed_without_chemicals']} bags.")
    lines.append("\nWHAT TO ADD")
    for d in rec["doses"]:
        lines.append(f"  - {d['name']}: {d['amount']}" + (f" = {d['per_bag']}" if d["per_bag"] else ""))
        lines.append(f"      why: {d['evidence']}")
        lines.append(f"      caution: {d['caution']}")
    lines += ["\nOXYGEN", "  " + adv["oxygen"]["explanation"]]
    if adv["oxygen"]["hours_to_critical_do"] is not None:
        lines.append(f"  Water oxygen falls below {adv['oxygen']['do_critical_mgL']} mg/L at hour "
                     f"{adv['oxygen']['hours_to_critical_do']:.1f}.")
    lines += ["\nHOW FAST FISH DIE", "  " + adv["mortality"]["explanation"]]
    for c in adv["mortality"]["survival_at_checkpoints_pct"]:
        lines.append(f"  hour {c['hour']:>4g}: {c['median']:6.2f}% alive (worst {c['worst']:.2f}%)")
    lines += ["\nWATER CHEMISTRY", "  " + adv["chemistry"]["explanation"]]
    lines += ["\nTEMPERATURE", "  " + adv["temperature"]["advice"]]
    lines += ["\nUNPACKING", "  " + adv["unpacking"]["explanation"]] + [f"  {i + 1}. {s}" for i, s in
                                                                         enumerate(adv["unpacking"]["steps"])]
    lines += ["\nALL OPTIONS (max fish per bag at the hot end)"]
    for o in adv["options"]:
        lines.append(f"  {o['max_fish_per_bag']:>5d}  {o['label']}")
    if adv["warnings"]:
        lines += ["\nNOTES"] + [f"  ! {w}" for w in adv["warnings"]]
    return "\n".join(lines)
