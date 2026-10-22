"""Command line: python -m transit_sim {simulate,calibrate,species}."""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

from .config import Interventions, Shipment, Unpacking, available_species, load_interventions, load_species
from .explain import explain
from .model import simulate


def _parse_temp(text: str):
    """'25' or '0:25,12:28,24:24' (hour:temp pairs)."""
    if ":" not in text:
        return float(text)
    return [tuple(float(x) for x in p.split(":")) for p in text.split(",")]


def cmd_simulate(a: argparse.Namespace) -> int:
    sp = load_species(a.species)
    iv_kw = {}
    if a.anaesthetic:
        table = load_interventions()
        if a.anaesthetic not in table:
            print(f"Unknown anaesthetic '{a.anaesthetic}'. Known: {', '.join(table)}", file=sys.stderr)
            return 2
        entry = table[a.anaesthetic]
        iv_kw = {k: entry[k] for k in ("metabolic_factor", "excretion_factor", "stress_factor") if k in entry}
    iv = Interventions(zeolite_g_per_l=a.zeolite, starvation_h=a.starvation, **iv_kw)
    sh = Shipment(fish_count=a.count, fish_mass_g=a.mass, water_l=a.water, gas_l=a.gas, duration_h=a.hours,
                  temperature_c=_parse_temp(a.temp), gas_o2_fraction=a.o2_fraction, initial_tan_mgL=a.tan0,
                  initial_ph=a.ph0, alkalinity_mgL_caco3=a.alkalinity, kla_per_h=a.kla)
    un = None if a.no_unpack else Unpacking(duration_h=a.unpack_hours)
    if a.temp_range:
        return _simulate_range(a, sp, sh, iv, un)
    res = simulate(sp, sh, iv, un)
    if a.json:
        print(json.dumps(res.summary, indent=2))
    else:
        print(explain(res.summary, sp, sh))
    if a.csv:
        rows = res.as_rows()
        with open(a.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
    if a.plot:
        from .plots import scenario_figure
        scenario_figure(res, f"{sp.name}: {sh.fish_count} x {sh.fish_mass_g:g} g, {sh.water_l:g} L, "
                             f"{a.hours:g} h", Path(a.plot), sp.do_crit)
    return 0


def _simulate_range(a, sp, sh, iv, un) -> int:
    from .uncertainty import explain_range, run_temperature_range

    lo, hi = a.temp_range
    rr = run_temperature_range(sp, sh, lo, hi, iv, un, samples=a.samples, seed=a.seed)
    if a.json:
        print(json.dumps(rr.stats, indent=2))
    else:
        print(explain_range(rr))
        print("\nWorst case in detail:")
        print(explain(rr.worst.summary, sp, sh))
    if a.csv:
        with open(a.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["run", "survival_at_arrival", "survival_after_unpacking", "min_do_mgL", "max_co2_mgL",
                        "final_tan_mgL", "peak_nh3_unpacking_mgL", "main_driver"])
            for lbl, r in zip(rr.labels, rr.runs):
                s = r.summary
                w.writerow([lbl, s["survival_at_arrival"], s["survival_after_unpacking"], s["min_do_mgL"],
                            s["max_co2_mgL"], s["final_tan_mgL"], s["peak_nh3_unpacking_mgL"], s["main_driver"]])
    if a.plot:
        from .plots import range_figure
        range_figure(rr, f"{sp.name}: {sh.fish_count} x {sh.fish_mass_g:g} g, {sh.water_l:g} L, "
                         f"{a.hours:g} h, {lo:g}-{hi:g} C", Path(a.plot), sp.do_crit)
    return 0


def cmd_advise(a: argparse.Namespace) -> int:
    from .advisor import AdvisoryRequest, advise, advise_text

    lo, hi = a.temp_range
    if a.mode is None:
        a.mode = "check" if a.fish_per_bag else "fixed_bags" if a.bags else "suggest"
    req = AdvisoryRequest(species=a.species, fish_mass_g=a.mass, total_fish=a.total, water_l=a.water, gas_l=a.gas,
                          duration_h=a.hours, temp_low_c=lo, temp_high_c=hi, target_survival=a.target / 100.0,
                          allow_anaesthetic=not a.no_anaesthetic, allow_zeolite=not a.no_zeolite,
                          max_fasting_h=a.max_fasting, initial_ph=a.ph0, alkalinity_mgL_caco3=a.alkalinity,
                          kla_per_h=a.kla, mode=a.mode, bags=a.bags, fish_per_bag=a.fish_per_bag,
                          check_fasting_h=a.fasting, check_zeolite=a.zeolite, check_anaesthetic=a.anaesthetic)
    try:
        adv = advise(req)
    except ValueError as exc:
        print(f"Invalid input: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(adv, indent=2) if a.json else advise_text(adv))
    return 0


def cmd_calibrate(a: argparse.Namespace) -> int:
    from .calibration import calibrate, write_config, write_report

    cal = calibrate()
    paths = write_report(cal, Path(a.report_dir))
    print(json.dumps(cal.to_json(), indent=2))
    if a.write:
        write_config(cal)
        print("Calibrated values written to config/.")
    print("Report files:", *map(str, paths), sep="\n  ")
    return 0


def cmd_species(_a: argparse.Namespace) -> int:
    for name in available_species():
        sp = load_species(name)
        print(f"{name:12s} {sp.scientific_name}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="transit_sim", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("simulate", help="simulate one bag")
    s.add_argument("--species", default="guppy")
    s.add_argument("--count", type=int, required=True, help="fish per bag")
    s.add_argument("--mass", type=float, required=True, help="mean fish mass (g)")
    s.add_argument("--water", type=float, required=True, help="water volume (L)")
    s.add_argument("--gas", type=float, required=True, help="gas (oxygen) volume (L)")
    s.add_argument("--hours", type=float, required=True, help="transit duration (h)")
    s.add_argument("--temp", default="25", help="'25' or profile '0:25,12:28,36:24'")
    s.add_argument("--temp-range", nargs=2, type=float, metavar=("LOW", "HIGH"),
                   help="uncertain temperature band, e.g. --temp-range 24 30 (overrides --temp)")
    s.add_argument("--samples", type=int, default=20, help="random profiles inside --temp-range")
    s.add_argument("--seed", type=int, default=0, help="random seed for --temp-range profiles")
    s.add_argument("--o2-fraction", type=float, default=1.0)
    s.add_argument("--tan0", type=float, default=0.3, help="initial total ammonia (mg/L)")
    s.add_argument("--ph0", type=float, default=7.4)
    s.add_argument("--alkalinity", type=float, default=65.0, help="mg/L as CaCO3")
    s.add_argument("--kla", type=float, default=None, help="override water-gas transfer (1/h)")
    s.add_argument("--anaesthetic", default=None, help="key from config/interventions.yaml")
    s.add_argument("--zeolite", type=float, default=0.0, help="g/L (PROVISIONAL kinetics)")
    s.add_argument("--starvation", type=float, default=24.0, help="hours fasted before packing")
    s.add_argument("--unpack-hours", type=float, default=1.0)
    s.add_argument("--no-unpack", action="store_true")
    s.add_argument("--json", action="store_true", help="print summary as JSON")
    s.add_argument("--csv", help="write time series CSV")
    s.add_argument("--plot", help="write PNG figure")
    s.set_defaults(func=cmd_simulate)

    ad = sub.add_parser("advise", help="full packing plan: fish per bag, add-ons + doses, O2, deaths, unpacking")
    ad.add_argument("--species", default="guppy")
    ad.add_argument("--mass", type=float, required=True, help="mean fish mass (g)")
    ad.add_argument("--total", type=int, default=None, help="total fish to ship (gives number of bags)")
    ad.add_argument("--water", type=float, required=True, help="water per bag (L)")
    ad.add_argument("--gas", type=float, required=True, help="oxygen per bag (L)")
    ad.add_argument("--hours", type=float, required=True, help="door-to-door transit time (h)")
    ad.add_argument("--temp-range", nargs=2, type=float, metavar=("LOW", "HIGH"), required=True)
    ad.add_argument("--target", type=float, default=95.0, help="minimum survival after unpacking (%%)")
    ad.add_argument("--no-anaesthetic", action="store_true")
    ad.add_argument("--no-zeolite", action="store_true")
    ad.add_argument("--max-fasting", type=float, default=48.0)
    ad.add_argument("--ph0", type=float, default=7.4)
    ad.add_argument("--alkalinity", type=float, default=65.0)
    ad.add_argument("--kla", type=float, default=None)
    ad.add_argument("--mode", choices=["suggest", "fixed_bags", "check"], default=None,
                    help="default: check if --fish-per-bag is given, fixed_bags if --bags, else suggest")
    ad.add_argument("--bags", type=int, default=None, help="fixed_bags: number of bags you have")
    ad.add_argument("--fish-per-bag", type=int, default=None, help="check: your own fish per bag")
    ad.add_argument("--fasting", type=float, default=24.0, help="check: hours fasted before packing")
    ad.add_argument("--zeolite", action="store_true", help="check: zeolite 20 g/L in your bags")
    ad.add_argument("--anaesthetic", choices=["ms222_40mgL", "benzocaine_20mgL"], default=None,
                    help="check: anaesthetic in your bags")
    ad.add_argument("--json", action="store_true")
    ad.set_defaults(func=cmd_advise)

    c = sub.add_parser("calibrate", help="re-fit to Pramod et al. 2010 and write report")
    c.add_argument("--write", action="store_true", help="write fitted values into config/")
    c.add_argument("--report-dir", default=str(Path(__file__).resolve().parent.parent / "reports"))
    c.set_defaults(func=cmd_calibrate)

    sp = sub.add_parser("species", help="list species configs")
    sp.set_defaults(func=cmd_species)
    return p


def main(argv: list[str] | None = None) -> int:
    a = build_parser().parse_args(argv)
    return a.func(a)
