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
# Add-on catalogue. What the exporter sees ("why", "caution") is plain language with no citations;
# the studies behind each item ("source") are only shown in the separate "How we calculate" section.
# "simulated" means the bag model includes the add-on's effect.
ADDONS = {
    "fasting": {
        "name": "Fasting before packing",
        "simulated": True,
        "why": "Fed fish use more oxygen and release much more ammonia into the bag. Not feeding them "
               "before packing keeps the water cleaner for longer.",
        "caution": "Do not fast for more than 48 hours unless you know the species can take it; weak fish "
                   "travel badly.",
        "source": "Pramod et al. 2010; Ruiz-Jarabo & de Pedro 2024; tench feeding data",
    },
    "zeolite": {
        "name": "Zeolite (clinoptilolite)",
        "dose_g_per_l": 20.0,
        "simulated": True,
        "why": "Zeolite soaks up ammonia from the water, so less of it can turn toxic when the bag is opened.",
        "caution": "Rinse it before use or the water turns cloudy. More than this amount does not help. "
                   "Salt in the water makes it work less well.",
        "source": "Teo, Chen & Lee 1989",
    },
    "ms222_40mgL": {
        "name": "MS-222 (tricaine methanesulfonate)",
        "dose_mg_per_l": 40.0,
        "simulated": True,
        "why": "A light sedative. Calm fish breathe more slowly and release about half as much ammonia, "
               "so the bag stays safe for longer.",
        "caution": "It makes the water more acidic; follow the label on buffering. Too much kills fish. "
                   "Check that the importing country allows anaesthetics.",
        "source": "Pramod et al. 2010",
    },
    "benzocaine_20mgL": {
        "name": "Benzocaine",
        "dose_mg_per_l": 20.0,
        "simulated": True,
        "why": "A light sedative. Calm fish release about half as much ammonia and use less oxygen.",
        "caution": "It does not dissolve in water: dissolve it in a little ethanol first. The gap between a "
                   "safe and a harmful dose is small. Check that the importing country allows anaesthetics.",
        "source": "Pramod et al. 2010; Kiessling et al. 2009",
    },
    "phenoxyethanol": {
        "name": "2-Phenoxyethanol",
        "dose_text": "0.11-0.22 g/L",
        "simulated": False,
        "why": "A sedative that has given very good survival in guppy shipping trials.",
        "caution": "Not included in this simulation yet. Confirm the dose for your species before using it.",
        "source": "Teo, Chen & Lee 1989; Teo & Chen 1993",
    },
    "tris_buffer": {
        "name": "Tris buffer",
        "dose_text": "0.02 M, pH 8",
        "simulated": False,
        "why": "Keeps the pH from dropping during the trip.",
        "caution": "Not recommended: keeping the pH high also keeps more of the ammonia toxic. If used, "
                   "only together with zeolite and on short trips.",
        "source": "Teo, Chen & Lee 1989",
    },
}

# The studies the simulator is built on, in plain words. Shown only in "How we calculate".
SOURCES = [
    {"title": "Pramod et al. (2010), North American Journal of Aquaculture 72:290-297",
     "used_for": "A 48-hour shipping trial with tiger barb. The simulator was tuned and checked against its "
                 "oxygen, ammonia, CO2 and death measurements, and it gives the effect of MS-222 and benzocaine."},
    {"title": "Teo, Chen & Lee (1989), Aquaculture 78:321-332",
     "used_for": "Guppy packing trials: zeolite, Tris buffer and 2-phenoxyethanol doses."},
    {"title": "Teo & Chen (1993), Aquaculture and Fisheries Management 24:109-117",
     "used_for": "How guppy oxygen use changes with conditions in a closed bag."},
    {"title": "Emerson et al. (1975), J. Fisheries Research Board of Canada 32:2379-2383",
     "used_for": "How much ammonia is in its toxic form at a given pH and temperature."},
    {"title": "Jager et al. (2011), Environmental Science & Technology 45:2529-2540",
     "used_for": "The method that turns build-up of harmful conditions over time into a survival curve."},
    {"title": "Lim, Dhert & Sorgeloos (2003), Aquaculture Research 34:923-935",
     "used_for": "The usual 5% dead-on-arrival warranty used as the default target."},
    {"title": "Silva et al. (2023)",
     "used_for": "How much toxic ammonia guppies can tolerate."},
    {"title": "Ruiz-Jarabo & de Pedro (2024); Kiessling et al. (2009)",
     "used_for": "Extra oxygen use of fed fish; safety margin of benzocaine."},
]


def _method_section(req: "AdvisoryRequest", sp, n_runs: int) -> dict:
    steps = [
        "We follow the sealed bag hour by hour. The fish use oxygen and give off carbon dioxide (CO2) and "
        "ammonia. Oxygen moves only slowly from the gas into the water.",
        "From the CO2 and the water's buffering we work out the pH. From the pH and temperature we work out "
        "how much of the ammonia is in its toxic form.",
        "Fish are harmed by CO2, toxic ammonia and low oxygen. The harm adds up over the hours, and that "
        "gives how fast fish start to die.",
        f"We run the trip {n_runs} times: at the coolest, middle and warmest temperature you gave, and along "
        "random temperature changes in between. We show the typical trip and the worst one.",
    ]
    if req.mode == "check":
        steps.append("We use exactly your fish per bag and what you put in the bag, then compare it with the "
                     "best plan we can find.")
    else:
        steps.append("We try every combination of fasting, zeolite and anaesthetic and find the most fish per "
                     "bag that stays above your target on the warmest trip. An add-on is only suggested if it "
                     "lets you pack at least 5% more fish.")
    steps.append("Finally we simulate opening the bag: the CO2 escapes, the pH rises and ammonia becomes "
                 "toxic. That is why the plan checks survival after unpacking, not only on arrival.")
    confidence = ["The simulator was checked against a real 48-hour shipping trial. Its oxygen, ammonia, CO2 "
                  "and survival curves matched the measurements closely."]
    if sp.name != "tiger_barb":
        confidence.append(f"That trial used tiger barb. Numbers for {sp.name.replace('_', ' ')} are scaled to "
                          "its body size and have not yet been confirmed with real shipments.")
    confidence.append("The zeolite effect is an early estimate and will be improved with more data.")
    return {"steps": steps, "confidence": confidence, "sources": SOURCES}


MIN_GAIN_SHARE = 0.95  # add-ons that gain < 5 % more fish per bag are not recommended

# How the exporter wants to plan:
#   suggest     the simulator chooses fish per bag (and so the number of bags) and the add-ons
#   fixed_bags  the exporter fixes the number of bags; the simulator says if that is safe and which
#               add-ons are needed, or how many bags are really needed
#   check       the exporter enters their own fish per bag and add-ons; the simulator shows what happens
MODES = ("suggest", "fixed_bags", "check")
ANAESTHETICS = ("ms222_40mgL", "benzocaine_20mgL")


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
    mode: str = "suggest"
    bags: int | None = None                # fixed_bags mode: bags available
    fish_per_bag: int | None = None        # check mode: exporter's own packing
    check_fasting_h: float = 24.0          # check mode add-ons
    check_zeolite: bool = False
    check_anaesthetic: str | None = None

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
            (self.mode in MODES, f"mode must be one of {', '.join(MODES)}"),
        ]
        if self.mode == "fixed_bags":
            checks += [
                (self.total_fish is not None, "fixed_bags mode needs total_fish"),
                (self.bags is not None and self.bags > 0, "fixed_bags mode needs bags > 0"),
                (self.bags is None or self.total_fish is None or self.bags <= self.total_fish,
                 "there are more bags than fish"),
            ]
        if self.mode == "check":
            checks += [
                (self.fish_per_bag is not None and 0 < self.fish_per_bag <= 1_000_000,
                 "check mode needs fish_per_bag > 0"),
                (self.check_anaesthetic in (None, *ANAESTHETICS),
                 f"check_anaesthetic must be one of {', '.join(ANAESTHETICS)} or empty"),
                (0 <= self.check_fasting_h <= 96, "check_fasting_h must be 0-96"),
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


def _make_plan(fasting_h: float, zeolite: bool, anaesthetic: str | None) -> Plan:
    kw = {}
    if anaesthetic:
        e = load_interventions()[anaesthetic]
        kw = {k: e[k] for k in ("metabolic_factor", "excretion_factor", "stress_factor") if k in e}
    z = ADDONS["zeolite"]["dose_g_per_l"] if zeolite else 0.0
    iv = Interventions(starvation_h=fasting_h, zeolite_g_per_l=z, **kw)
    addons = (["zeolite"] if zeolite else []) + ([anaesthetic] if anaesthetic else [])
    parts = [f"fast {fasting_h:g} h"] + [ADDONS[a]["name"].split(" (")[0] for a in addons]
    key = "|".join([f"fast{fasting_h:g}"] + addons)
    return Plan(key=key, label=" + ".join(parts), interventions=iv, addons=addons, fasting_h=fasting_h)


def _plans(req: AdvisoryRequest) -> list[Plan]:
    table = load_interventions()
    fast = [24.0] + ([48.0] if req.max_fasting_h >= 48 else [])
    sed_opts: list[str | None] = [None]
    if req.allow_anaesthetic:
        sed_opts += [k for k in ANAESTHETICS if k in table]
    zeo_opts = [False] + ([True] if req.allow_zeolite else [])
    return [_make_plan(f, z, sed) for f in fast for sed in sed_opts for z in zeo_opts]


def _doses(plan: Plan, req: AdvisoryRequest) -> list[dict]:
    f = ADDONS["fasting"]
    out = [{"addon": "fasting", "name": f["name"], "amount": f"{plan.fasting_h:g} h before packing",
            "per_bag": None, "simulated": True, "why": f["why"], "evidence": f["why"],
            "caution": f["caution"], "source": f["source"]}]
    for a in plan.addons:
        info = ADDONS[a]
        if "dose_mg_per_l" in info:
            amount = f"{info['dose_mg_per_l']:g} mg/L"
            per_bag = f"{info['dose_mg_per_l'] * req.water_l:.1f} mg per bag ({req.water_l:g} L)"
        else:
            amount = f"{info['dose_g_per_l']:g} g/L"
            per_bag = f"{info['dose_g_per_l'] * req.water_l:.1f} g per bag ({req.water_l:g} L)"
        out.append({"addon": a, "name": info["name"], "amount": amount, "per_bag": per_bag, "simulated": True,
                    "why": info["why"], "evidence": info["why"], "caution": info["caution"],
                    "source": info["source"]})
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
        warnings.append(f"The {sp.name.replace('_', ' ')} numbers are estimated from tests on another species "
                        "and have not yet been confirmed with real shipments. Treat them as a guide.")

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
    # ---- choose what to show, depending on the mode
    total = req.total_fish
    rec_bags = math.ceil(total / best.max_fish) if total and best.max_fish else None
    verdict: dict = {"mode": req.mode, "recommended_plan_label": best.label,
                     "recommended_fish_per_bag": best.max_fish, "recommended_bags": rec_bags}

    if req.mode == "suggest":
        if best.max_fish == 0:
            result["feasible"] = False
            result["recommendation"] = {
                "summary": (f"No plan keeps {100 * req.target_survival:.0f}% of fish alive for {req.duration_h:g} h "
                            f"at {req.temp_high_c:g} C, even with one fish per bag. Shorten the journey, lower the "
                            "temperature, or use more water per bag.")}
            result["verdict"] = {**verdict, "meets_target": False, "message": result["recommendation"]["summary"]}
            result["method"] = _method_section(req, sp, 0)
            return result
        chosen, n = best, best.max_fish
    elif req.mode == "fixed_bags":
        n = math.ceil(total / req.bags)
        safe = [p for p in plans if p.max_fish >= n]
        if safe:
            chosen = min(safe, key=lambda p: (len(p.addons), p.fasting_h))
        else:  # not safe with any add-on: show the strongest plan and how many bags are really needed
            chosen = max(plans, key=lambda p: (p.max_fish, -len(p.addons)))
    else:  # check
        chosen = _make_plan(req.check_fasting_h, req.check_zeolite, req.check_anaesthetic)
        chosen.doses = _doses(chosen, req)
        known = next((p for p in plans if p.key == chosen.key), None)
        chosen.max_fish = known.max_fish if known else _max_fish(sp, req, chosen)[0]
        n = int(req.fish_per_bag)

    result["feasible"] = True
    for o in result["options"]:
        o["recommended"] = o["key"] == best.key
        o["selected"] = o["key"] == chosen.key
    if any(a in ANAESTHETICS for a in chosen.addons) and sp.name != "tiger_barb":
        warnings.append("The effect of the anaesthetic was measured on a different species; for this one it "
                        "is an estimate.")
    if "zeolite" in chosen.addons:
        warnings.append("The zeolite effect is an early estimate.")

    rr = run_temperature_range(sp, _shipment(req, n, req.temp_high_c), req.temp_low_c, req.temp_high_c,
                               chosen.interventions, Unpacking(), samples=req.samples, seed=req.seed, dt_out=0.25)
    med_i = int(np.argsort([r.summary["survival_after_unpacking"] for r in rr.runs])[len(rr.runs) // 2])
    med, worst = rr.runs[med_i], rr.worst
    sh = _shipment(req, n, req.temp_high_c)
    surv_med = 100 * med.summary["survival_after_unpacking"]
    surv_worst = 100 * worst.summary["survival_after_unpacking"]
    # Same rule as the optimiser: safe if this count is within the hot-end maximum for these add-ons.
    meets = 0 < n <= chosen.max_fish
    bags = (req.bags if req.mode == "fixed_bags" else math.ceil(total / n) if total else None)
    dead_total = round((total or n * (bags or 1)) * (1 - surv_med / 100))
    target_txt = f"{100 * req.target_survival:.0f}%"
    survival_txt = (f"Expected survival after unpacking: {surv_med:.1f}% (worst case {surv_worst:.1f}%) over "
                    f"{req.temp_low_c:g}-{req.temp_high_c:g} C.")

    if req.mode == "suggest":
        summary = (f"Pack {n} fish per bag ({n * req.fish_mass_g / req.water_l:.0f} g/L) with: {chosen.label}. "
                   + (f"{bags} bags for {total} fish. " if bags else "") + survival_txt)
        message = f"Recommended plan meets the {target_txt} target."
    elif req.mode == "fixed_bags":
        if meets:
            message = (f"{req.bags} bags is enough: {n} fish per bag stays above {target_txt} with {chosen.label}.")
        elif best.max_fish == 0:
            message = (f"Not safe: no packing reaches {target_txt} for this trip, even with one fish per bag.")
        else:
            message = (f"Too few bags: {n} fish per bag is more than the safe maximum of {best.max_fish} "
                       f"(with {best.label}). You need at least {rec_bags} bags.")
        summary = (f"{req.bags} bags for {total} fish = {n} fish per bag "
                   f"({n * req.fish_mass_g / req.water_l:.0f} g/L) with: {chosen.label}. " + survival_txt)
    else:
        if meets:
            message = f"Your packing is safe: survival stays above {target_txt} even in the hottest case."
        else:
            message = (f"Your packing is NOT safe: survival can fall to {surv_worst:.1f}% "
                       f"(target {target_txt}). About {dead_total} fish could die"
                       + (f" across {bags} bags." if bags else " per bag.")
                       + (f" With your add-ons the safe maximum is {chosen.max_fish} fish per bag"
                          if chosen.max_fish else " Your add-ons cannot make this trip safe")
                       + (f"; the best plan allows {best.max_fish} ({best.label})."
                          if best.max_fish else "; no packing is safe for this trip."))
        summary = (f"Your packing: {n} fish per bag ({n * req.fish_mass_g / req.water_l:.0f} g/L) with: "
                   f"{chosen.label}. " + (f"{bags} bags for {total} fish. " if bags else "") + survival_txt)

    result["verdict"] = {**verdict, "meets_target": bool(meets), "survival_median_pct": round(surv_med, 2),
                         "survival_worst_pct": round(surv_worst, 2), "expected_dead_total": dead_total,
                         "safe_max_with_selected_addons": chosen.max_fish,
                         "message": message}
    result["recommendation"] = {
        "plan_key": chosen.key,
        "plan_label": chosen.label,
        "fish_per_bag": n,
        "density_g_per_l": round(n * req.fish_mass_g / req.water_l, 1),
        "bags_needed": bags,
        "fish_per_bag_without_chemicals": chem_free.max_fish,
        "bags_needed_without_chemicals": (math.ceil(total / chem_free.max_fish)
                                          if total and chem_free.max_fish else None),
        "doses": chosen.doses,
        "not_simulated_options": [{"addon": k, "name": v["name"], "amount": v["dose_text"],
                                   "why": v["why"], "evidence": v["why"], "caution": v["caution"],
                                   "source": v["source"]}
                                  for k, v in ADDONS.items() if not v["simulated"]],
        "summary": summary,
    }
    result["survival_band_pct"] = {k: round(100 * v, 2) for k, v in rr.stats["survival_after_unpacking"].items()}
    result["oxygen"] = _oxygen_section(med, sp, sh, worst)
    result["mortality"] = _mortality_section(med, worst, sh, req.target_survival)
    result["chemistry"] = _chemistry_section(med)
    result["unpacking"] = _unpacking_section(med, worst)
    result["temperature"] = _temperature_section(sp, req, chosen, n)
    result["timeline"] = {"median": _series(med), "worst": _series(worst), "worst_label": rr.worst_label}
    result["method"] = _method_section(req, sp, len(rr.runs))
    return result


def advise_text(adv: dict) -> str:
    """Plain-text rendering of an advisory (CLI)."""
    if not adv["feasible"]:
        return adv["recommendation"]["summary"]
    rec = adv["recommendation"]
    verdict = adv.get("verdict", {})
    title = {"suggest": "PACKING PLAN", "fixed_bags": "YOUR BAGS", "check": "YOUR PACKING"}.get(
        verdict.get("mode", "suggest"), "PACKING PLAN")
    lines = [title, "  " + rec["summary"]]
    if verdict.get("mode", "suggest") != "suggest":
        lines.append(("  OK: " if verdict["meets_target"] else "  WARNING: ") + verdict["message"])
    if verdict.get("mode", "suggest") != "suggest" and verdict.get("recommended_fish_per_bag"):
        lines.append(f"  Recommended instead: {verdict['recommended_fish_per_bag']} fish/bag with "
                     f"{verdict['recommended_plan_label']}"
                     + (f" -> {verdict['recommended_bags']} bags." if verdict.get("recommended_bags") else "."))
    elif rec.get("bags_needed_without_chemicals"):
        lines.append(f"  Without chemicals: {rec['fish_per_bag_without_chemicals']} fish/bag -> "
                     f"{rec['bags_needed_without_chemicals']} bags.")
    lines.append("\nWHAT TO ADD")
    for d in rec["doses"]:
        lines.append(f"  - {d['name']}: {d['amount']}" + (f" = {d['per_bag']}" if d["per_bag"] else ""))
        lines.append(f"      why: {d['why']}")
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
