"""AquaSense export advisor — demo UI.

Run from the export_simulator folder (so .streamlit/config.toml applies the theme):
    streamlit run app/streamlit_app.py
"""
from __future__ import annotations

import sys
from html import escape
from pathlib import Path

import plotly.graph_objects as go
import streamlit as st

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from transit_sim import available_species  # noqa: E402
from transit_sim.advisor import AdvisoryRequest, advise  # noqa: E402

st.set_page_config(page_title="Export transit advisor", page_icon="🐟", layout="wide")

DARK = st.context.theme.type == "dark"
# Series colours: reference palette slots 1-2 (checked for colour-blind separation), stepped for the dark surface.
MEDIAN, WORST = ("#3987e5", "#d95926") if DARK else ("#2a78d6", "#eb6834")
OTHER = "#4a4a47" if DARK else "#c9c8c1"  # options that are not highlighted
CRIT, OPENED, GRID, MUTED = "#d03b3b", "#eda100", "rgba(128,128,128,0.18)", "#898781"
SIDEBAR_BG = "#141b1d" if DARK else "#f4fafa"  # .streamlit/config.toml

st.html("""<style>
.side-h {font-size: .72rem; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; opacity: .6;
         margin: .9rem 0 -.2rem;}
.brand {font-weight: 700; font-size: 1.05rem;}
.brand span {opacity: .6; font-weight: 500;}
.st-key-plan_shipment {position: sticky; bottom: 0; z-index: 5; padding: .6rem 0 .8rem;
                       background: linear-gradient(transparent, SIDEBAR_BG 30%);}
.verdict {--tone: #0ca30c; border-radius: .9rem; padding: 1.1rem 1.4rem 1.2rem;
          border: 1px solid color-mix(in srgb, var(--tone) 40%, transparent);
          background: color-mix(in srgb, var(--tone) 7%, transparent);}
.verdict.danger {--tone: #d03b3b;}
.verdict .status {display: flex; gap: .55rem; align-items: flex-start; font-weight: 600; line-height: 1.45;}
.verdict .status .icon {flex: none; width: 1.35rem; height: 1.35rem; border-radius: 50%; background: var(--tone);
                        color: #fff; font-size: .85rem; font-weight: 800; display: grid; place-items: center;}
.verdict .lead {margin-top: .9rem; font-size: 1.05rem; opacity: .75;}
.verdict .big {font-size: 3.1rem; font-weight: 800; line-height: 1.05;}
.verdict .big small {font-size: 1.25rem; font-weight: 500; margin-left: .45rem;}
.verdict .plan {opacity: .75; margin-top: .25rem;}
.verdict .compare {font-size: .9rem; opacity: .8; margin-top: .8rem;}
.figures {display: flex; flex-wrap: wrap; margin-top: 1rem; border-radius: .7rem; background: rgba(128,128,128,.09);}
.figures > div {flex: 1 1 7rem; padding: .65rem .8rem; text-align: center;
                border-left: 1px solid rgba(128,128,128,.2);}
.figures > div:first-child {border-left: none;}
.figures .v {font-size: 1.45rem; font-weight: 750; line-height: 1.2;}
.figures .l {font-size: .85rem; opacity: .75;}
.figures .n {font-size: .78rem; opacity: .55;}
.lead-text {border-left: 3px solid rgba(128,128,128,.35); padding: .15rem 0 .15rem .9rem; margin: .2rem 0 .8rem;
            font-size: 1.02rem; line-height: 1.55;}
.legend {display: flex; flex-wrap: wrap; gap: .4rem 1.4rem; font-size: .85rem; opacity: .85; margin: .2rem 0 .4rem;}
.legend span {display: inline-flex; align-items: center; gap: .45rem;}
.legend i {display: inline-block; width: 22px; height: 0; border-top: 2.5px solid;}
.legend i.dash {border-top-style: dashed;}
.legend i.dot {border-top: 2px dotted;}
.legend i.box {height: 12px; width: 14px; border: none; background: rgba(237,161,0,.28);}
.step {font-size: .75rem; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; opacity: .55;}
.dose {font-size: 1.35rem; font-weight: 750; margin: .1rem 0 .3rem;}
</style>""".replace("SIDEBAR_BG", SIDEBAR_BG))

ICONS = {"ok": '<span class="icon">✓</span>', "danger": '<span class="icon">✕</span>'}


@st.cache_data(show_spinner=False)
def run_advice(req_dict: dict) -> dict:
    return advise(AdvisoryRequest(**req_dict))


def nice(name: str) -> str:
    return name.replace("_", " ").capitalize()


def lead(text: str) -> None:
    st.html(f'<div class="lead-text">{escape(text)}</div>')


def legend(tl: dict, limit: bool = True) -> None:
    worst = escape(tl["worst_label"].replace(" C", " °C"))
    st.html(f'<div class="legend"><span><i style="border-color:{MEDIAN}"></i>Typical journey</span>'
            f'<span><i class="dash" style="border-color:{WORST}"></i>Worst journey ({worst})</span>'
            '<span><i class="box"></i>Bag opened</span>'
            + (f'<span><i class="dot" style="border-color:{CRIT}"></i>Limit</span>' if limit else "") + "</div>")


def line_chart(title: str, unit: str, tl: dict, key: str, ref: float | None = None, ref_label: str = "",
               height: int = 260, y_range: list | None = None, x_range: list | None = None,
               zero: bool = True, fmt: str = ".2f") -> go.Figure:
    med, worst = tl["median"], tl["worst"]
    fig = go.Figure()
    opened = [t for t, o in zip(med["t_h"], med["opened"]) if o]
    if opened:
        fig.add_vrect(x0=opened[0], x1=med["t_h"][-1], fillcolor=OPENED, opacity=0.18, line_width=0, layer="below")
    fig.add_trace(go.Scatter(x=worst["t_h"], y=worst[key], name="Worst", mode="lines",
                             line=dict(color=WORST, width=2, dash="dash"),
                             hovertemplate=f"%{{y:{fmt}}} {unit}"))
    fig.add_trace(go.Scatter(x=med["t_h"], y=med[key], name="Typical", mode="lines", line=dict(color=MEDIAN, width=2.5),
                             hovertemplate=f"%{{y:{fmt}}} {unit}"))
    if ref is not None:
        fig.add_hline(y=ref, line=dict(color=CRIT, dash="dot", width=1.5), annotation_text=ref_label,
                      annotation_position="top left", annotation_font=dict(size=11, color=CRIT))
    fig.update_layout(title=dict(text=f"{title} <span style='font-size:12px;color:{MUTED}'>{unit}</span>",
                                 font=dict(size=14), x=0, xanchor="left"),
                      height=height, margin=dict(l=0, r=10, t=34, b=0), showlegend=False, hovermode="x unified",
                      xaxis=dict(gridcolor=GRID, ticksuffix=" h", range=x_range, hoverformat=".1f"),
                      yaxis=dict(gridcolor=GRID, rangemode="tozero" if zero else "normal", range=y_range))
    return fig


def chart(fig: go.Figure, where=st) -> None:
    where.plotly_chart(fig, width="stretch", config={"displayModeBar": False})


def side_heading(text: str) -> None:
    st.html(f'<div class="side-h">{escape(text)}</div>')


# ----------------------------------------------------------------------------- inputs
MODE_LABELS = {
    "suggest": "Suggest the number of bags",
    "fixed_bags": "I'll set the number of bags",
    "check": "Check my own packing",
}
MODE_CAPTIONS = [
    "We choose fish per bag, bags and add-ons",
    "We check whether your bags are enough",
    "We test your fish per bag and add-ons",
]
ANAES_LABELS = {None: "None", "ms222_40mgL": "MS-222 40 mg/L", "benzocaine_20mgL": "Benzocaine 20 mg/L"}

with st.sidebar:
    st.html('<div class="brand">🐟 AquaSense <span>· Export planning</span></div>')
    side_heading("How do you want to plan?")
    mode = st.radio("Planning mode", list(MODE_LABELS), format_func=MODE_LABELS.get, captions=MODE_CAPTIONS,
                    label_visibility="collapsed")
    side_heading("Shipment")
    species_list = available_species()
    species = st.selectbox("Species", species_list, index=species_list.index("guppy"), format_func=nice)
    with st.form("plan", border=False, enter_to_submit=True):
        mass = st.number_input("Average fish weight (g)", 0.05, 200.0, 0.3 if species == "guppy" else 12.0, step=0.05)
        total = st.number_input("Total fish to ship", 0, 1_000_000, 1000, step=100,
                                help="Used to work out the number of bags. 0 = not set."
                                     if mode != "fixed_bags" else None)
        bags = fish_per_bag = None
        if mode == "fixed_bags":
            bags = st.number_input("Number of bags you have", 1, 100_000, 20, step=1)
        if mode == "check":
            fish_per_bag = st.number_input("Fish per bag (your packing)", 1, 100_000, 60, step=5)
        side_heading("Journey")
        hours = st.slider("Door-to-door time (h)", 6, 96, 36, step=2)
        t_lo, t_hi = st.slider("Expected temperature range (°C)", 15.0, 35.0, (24.0, 28.0), step=0.5)
        side_heading("Bag")
        c1, c2 = st.columns(2)
        water = c1.number_input("Water (L)", 0.05, 20.0, 0.4, step=0.05)
        gas = c2.number_input("Oxygen (L)", 0.05, 40.0, 1.2, step=0.1)
        target = st.slider("Minimum survival after unpacking (%)", 80.0, 99.5, 95.0, step=0.5,
                           help="5% dead on arrival is the usual industry warranty limit.")
        check_fast, check_zeo, check_anaes = 24.0, False, None
        if mode == "check":
            side_heading("What you put in the bag")
            check_fast = st.select_slider("Fasting before packing (h)", [0, 12, 24, 48], 24)
            check_anaes = st.selectbox("Anaesthetic", list(ANAES_LABELS), format_func=ANAES_LABELS.get)
            check_zeo = st.checkbox("Zeolite 20 g/L", False)
        side_heading("Allowed add-ons" if mode != "check" else "Add-ons allowed for the recommendation")
        allow_anaes = st.checkbox("Anaesthetics (MS-222 / benzocaine)", True)
        allow_zeo = st.checkbox("Zeolite", True)
        max_fast = st.select_slider("Longest fasting allowed (h)", [24, 48], 48)
        with st.expander("Water & advanced"):
            ph0 = st.number_input("Packing water pH", 5.5, 9.0, 7.4, step=0.1)
            alk = st.number_input("Alkalinity (mg/L CaCO₃)", 5.0, 400.0, 65.0, step=5.0)
            kla = st.number_input("Bag gas transfer kLa (1/h)", 0.0, 5.0, 0.0, step=0.05,
                                  help="0 = the calibrated static bag. Higher = more bag motion.")
            samples = st.slider("Random temperature profiles", 0, 30, 10)
        st.form_submit_button("Plan shipment", type="primary", icon=":material/play_arrow:", width="stretch",
                              key="plan_shipment")

req = dict(species=species, fish_mass_g=float(mass), total_fish=int(total) or None, water_l=float(water),
           gas_l=float(gas), duration_h=float(hours), temp_low_c=float(t_lo), temp_high_c=float(t_hi),
           target_survival=float(target) / 100.0, allow_anaesthetic=allow_anaes, allow_zeolite=allow_zeo,
           max_fasting_h=float(max_fast), initial_ph=float(ph0), alkalinity_mgL_caco3=float(alk),
           kla_per_h=float(kla) or None, samples=int(samples), mode=mode,
           bags=int(bags) if bags else None, fish_per_bag=int(fish_per_bag) if fish_per_bag else None,
           check_fasting_h=float(check_fast), check_zeolite=bool(check_zeo), check_anaesthetic=check_anaes)

# ----------------------------------------------------------------------------- header
st.title("Export transit advisor")
st.caption("Predicts what happens inside the sealed bag during the trip and at unpacking, and how to pack for it.")

try:
    with st.spinner("Simulating packing options…"):
        adv = run_advice(req)
except ValueError as exc:
    st.error(f"Check the inputs: {exc}", icon=":material/error:")
    st.stop()

r = adv["request"]
with st.container(horizontal=True, gap="small"):
    st.badge(nice(r["species"]) + f" · {r['fish_mass_g']:g} g", icon=":material/water:", color="gray")
    if r["total_fish"]:
        st.badge(f"{r['total_fish']:,} fish", color="gray")
    st.badge(f"{r['duration_h']:g} h door to door", icon=":material/schedule:", color="gray")
    st.badge(f"{r['temp_low_c']:g}–{r['temp_high_c']:g} °C", icon=":material/thermostat:", color="gray")
    st.badge(f"{r['water_l']:g} L water + {r['gas_l']:g} L O₂ per bag", color="gray")
    st.badge(f"target ≥ {adv['target_survival_pct']:g}% alive", icon=":material/flag:", color="gray")

rec, verdict = adv["recommendation"], adv.get("verdict", {})
if not adv["feasible"]:
    st.html(f'<div class="verdict danger"><div class="status">{ICONS["danger"]}<div>No safe packing for this trip'
            f'</div></div><div class="plan" style="margin-top:.6rem">{escape(rec["summary"])}</div></div>')
    for w in adv["warnings"]:
        st.caption("Note: " + w)
    st.stop()

# ----------------------------------------------------------------------------- verdict
mo, un, tl = adv["mortality"], adv["unpacking"], adv["timeline"]
ai, experience = adv.get("ai_correction"), adv.get("experience") or {}
ok = verdict.get("meets_target", True)
status = (f"Meets the {adv['target_survival_pct']:g}% survival target, even on the hottest journey."
          if mode == "suggest" else verdict.get("message", ""))
figures = []
if rec["bags_needed"]:
    note = f"for {r['total_fish']:,} fish"
    if mode == "suggest" and rec["bags_needed_without_chemicals"]:
        saved = rec["bags_needed_without_chemicals"] - rec["bags_needed"]
        note = f"saves {saved} vs no chemicals" if saved > 0 else note
    figures.append((f"{rec['bags_needed']:,}", "bags", note))
figures += [(f"{mo['survival_after_unpacking_pct']:.1f}%", "alive after unpacking",
             f"worst {mo['worst_survival_after_unpacking_pct']:.1f}%"),
            (f"{mo['expected_dead_per_bag']:.1f}", "lost per bag", f"worst {mo['expected_dead_per_bag_worst']:.1f}")]
if verdict.get("expected_dead_total") is not None and rec["bags_needed"]:
    figures.append((f"{verdict['expected_dead_total']:,}", "fish lost in total", "typical journey"))
compare = ""
if mode != "suggest" and verdict.get("recommended_fish_per_bag"):
    compare = (f"Recommended plan: {verdict['recommended_fish_per_bag']} fish per bag with "
               f"{verdict['recommended_plan_label']}"
               + (f" → {verdict['recommended_bags']:,} bags." if verdict.get("recommended_bags") else "."))

lead_word = {"suggest": "Pack", "fixed_bags": "Your bags hold", "check": "You pack"}[mode]
left, right = st.columns([5, 3], gap="medium")
left.html(
    f'<div class="verdict {"ok" if ok else "danger"}">'
    f'<div class="status">{ICONS["ok" if ok else "danger"]}<div>{escape(status)}</div></div>'
    f'<div class="lead">{lead_word}</div>'
    f'<div class="big">{rec["fish_per_bag"]}<small>fish per bag</small></div>'
    f'<div class="plan">with {escape(rec["plan_label"])} · {rec["density_g_per_l"]:.0f} g of fish per litre</div>'
    '<div class="figures">'
    + "".join(f'<div><div class="v">{v}</div><div class="l">{lab}</div><div class="n">{escape(n)}</div></div>'
              for v, lab, n in figures)
    + "</div>" + (f'<div class="compare">{escape(compare)}</div>' if compare else "") + "</div>")

with right.container(border=True):
    st.markdown("**What you put in the bag**" if mode == "check" else "**Packing checklist**")
    for i, d in enumerate(rec["doses"], 1):
        st.markdown(f"{i}. **{d['name'].split(' (')[0]}** — {d['per_bag'] or d['amount']}")
    if mode == "suggest" and rec["fish_per_bag_without_chemicals"] and any(d["addon"] != "fasting"
                                                                          for d in rec["doses"]):
        st.caption(f"Without chemicals: {rec['fish_per_bag_without_chemicals']} fish per bag"
                   + (f" → {rec['bags_needed_without_chemicals']:,} bags." if rec["bags_needed_without_chemicals"]
                      else "."))
    st.divider()
    if ai:
        st.markdown(f"**AI second opinion** · {ai['corrected_survival_pct']:.1f}% alive after unpacking")
        if ai.get("display") == "limited":
            st.badge("Limited experience", icon=":material/info:", color="orange")
        st.caption(f"Physics {ai['physics_survival_pct']:.1f}%, AI adjusts {ai['adjustment_pp']:+.1f} points. "
                   f"{ai['note']}")
    else:
        st.markdown("**AI second opinion** · not shown")
        st.caption("No recorded shipments like this one yet, so the plan uses the physics only. Details in "
                   "*Method & AI*." if experience.get("ai_display") == "hidden" else "No trained AI model yet.")

if un["danger"]:
    st.warning(f"**Take care when opening the bags.** {un['explanation']} See *Unpacking* below.",
               icon=":material/warning:")
if adv["warnings"]:
    n = len(adv["warnings"])
    with st.expander(f"About this estimate · {n} note{'s' if n > 1 else ''} on accuracy", icon=":material/info:"):
        st.markdown("\n".join(f"- {w}" for w in adv["warnings"]))

# ----------------------------------------------------------------------------- details
st.space("small")
tabs = st.tabs(["Before you pack", "Survival", "Inside the bag", "Temperature", "Unpacking", "Compare options",
                "Method & AI"], key="detail_tabs")

with tabs[0]:
    cols = st.columns(len(rec["doses"]))
    for i, (col, d) in enumerate(zip(cols, rec["doses"]), 1):
        with col.container(border=True, height="stretch"):
            st.html(f'<div class="step">Step {i}</div><div><b>{escape(d["name"])}</b></div>'
                    f'<div class="dose">{escape(d["per_bag"] or d["amount"])}</div>'
                    + (f'<div style="opacity:.65;font-size:.9rem">{escape(d["amount"])} of bag water</div>'
                       if d["per_bag"] else ""))
            st.markdown(f"**Why:** {d.get('why', d['evidence'])}")
            st.markdown(f":orange[**Take care:**] {d['caution']}")
    with st.expander("Other add-ons to consider — backed by studies, not simulated in this plan"):
        for d in rec["not_simulated_options"]:
            st.markdown(f"**{d['name']}** ({d['amount']}): {d.get('why', d['evidence'])}  \n"
                        f":orange[Take care:] {d['caution']}")

with tabs[1]:
    lead(mo["explanation"])
    band = adv["survival_band_pct"]
    m = st.columns(4)
    m[0].metric("Typical journey", f"{band['median']:.1f}%", border=True, help="Median of the simulated journeys")
    m[1].metric("9 in 10 journeys above", f"{band['p10']:.1f}%", border=True)
    m[2].metric("Worst journey", f"{band['min']:.1f}%", border=True)
    m[3].metric("Best journey", f"{band['max']:.1f}%", border=True)
    legend(tl)
    a, b = st.columns([3, 2], gap="medium")
    low = min(min(tl["worst"]["alive_pct"]), adv["target_survival_pct"])
    chart(line_chart("Fish alive", "%", tl, "alive_pct", adv["target_survival_pct"],
                     f"target {adv['target_survival_pct']:g}%", height=360, y_range=[max(0.0, low - 3), 100.5],
                     zero=False), a)
    b.dataframe([{"Hour": x["hour"], "Typical": x["median"], "Worst": x["worst"]}
                 for x in mo["survival_at_checkpoints_pct"]], hide_index=True, width="stretch",
                column_config={"Hour": st.column_config.NumberColumn(format="%d h"),
                               "Typical": st.column_config.NumberColumn("Alive, typical", format="%.1f%%"),
                               "Worst": st.column_config.NumberColumn("Alive, worst", format="%.1f%%")})
    b.markdown("**What harms the fish**")
    b.dataframe([{"Cause": k[0].upper() + k[1:], "Share": v} for k, v in mo["cause_share_pct"].items()],
                hide_index=True, width="stretch",
                column_config={"Share": st.column_config.ProgressColumn("Share of the harm", format="%.0f%%",
                                                                        min_value=0, max_value=100)})

with tabs[2]:
    ox, ch = adv["oxygen"], adv["chemistry"]
    legend(tl)
    st.subheader("Oxygen")
    lead(ox["explanation"])
    m = st.columns(4)
    m[0].metric("O₂ use, first 6 h", f"{ox['use_rate_first_6h_mg_per_h']} mg/h", border=True,
                help="Higher at first because of handling stress")
    m[1].metric("O₂ use, average", f"{ox['use_rate_average_mg_per_h']} mg/h", border=True,
                help=f"{ox['use_per_fish_mg_per_h']} mg per fish per hour")
    m[2].metric("O₂ gas left at arrival", f"{ox['gas_o2_left_pct']}%", border=True)
    m[3].metric(f"Water O₂ below {ox['do_critical_mgL']:g} mg/L",
                f"hour {ox['hours_to_critical_do']:.0f}" if ox["hours_to_critical_do"] is not None else "never",
                border=True, help="When the dissolved oxygen in the water becomes critical (typical journey)")
    a, b = st.columns(2, gap="medium")
    chart(line_chart("Oxygen in the water", "mg/L", tl, "do_mgL", ox["do_critical_mgL"], "critical"), a)
    chart(line_chart("Oxygen gas left in the bag", "% of packed", tl, "gas_o2_pct", y_range=[0, 105], fmt=".0f"), b)
    st.subheader("Water chemistry")
    lead(ch["explanation"])
    m = st.columns(4)
    m[0].metric("Highest CO₂", f"{ch['max_co2_mgL']:.0f} mg/L", border=True, help="Harmful above about 20 mg/L")
    m[1].metric("pH at arrival", f"{ch['final_ph']:.2f}", border=True)
    m[2].metric("Total ammonia at arrival", f"{ch['final_tan_mgL']:.1f} mg/L", border=True)
    m[3].metric("Toxic ammonia in transit", f"{ch['max_nh3_transit_mgL']:.3f} mg/L", border=True,
                help="Highest NH₃ before the bag is opened. Safe below 0.02 mg/L.")
    a, b = st.columns(2, gap="medium")
    chart(line_chart("Free CO₂", "mg/L", tl, "co2_mgL", 20, "harmful above", fmt=".0f"), a)
    chart(line_chart("pH", "", tl, "ph", zero=False), b)
    a, b = st.columns(2, gap="medium")
    chart(line_chart("Toxic ammonia (NH₃)", "mg/L", tl, "nh3_mgL", 0.02, "safe limit", fmt=".3f"), a)
    chart(line_chart("Total ammonia", "mg/L", tl, "tan_mgL"), b)

with tabs[3]:
    te = adv["temperature"]
    t_max = te["max_safe_constant_temp_c"]
    (st.warning if t_max is None or r["temp_high_c"] > t_max else st.success)(te["advice"], icon=":material/thermostat:")
    m = st.columns(3)
    m[0].metric("Safe up to", f"{t_max:g} °C" if t_max is not None else "—", border=True,
                help="Highest constant temperature that keeps survival above the target with this packing")
    m[1].metric("Forecast", f"{r['temp_low_c']:g}–{r['temp_high_c']:g} °C", border=True)
    m[2].metric("Margin", f"{t_max - r['temp_high_c']:+g} °C" if t_max is not None else "—", border=True,
                help="Safe-up-to temperature minus the forecast maximum")
    a, b = st.columns([3, 2], gap="medium")
    fig = go.Figure(go.Scatter(x=[p["temp_c"] for p in te["curve"]], y=[p["survival_pct"] for p in te["curve"]],
                               mode="lines+markers", line=dict(color=MEDIAN, width=2.5), marker=dict(size=8),
                               hovertemplate="%{x:.0f} °C: %{y:.1f}% alive<extra></extra>"))
    fig.add_vrect(x0=r["temp_low_c"], x1=r["temp_high_c"], fillcolor="rgba(128,128,128,0.16)", line_width=0,
                  layer="below", annotation_text="forecast", annotation_position="top left",
                  annotation_font=dict(size=11))
    fig.add_hline(y=adv["target_survival_pct"], line=dict(color=CRIT, dash="dot", width=1.5),
                  annotation_text=f"target {adv['target_survival_pct']:g}%", annotation_position="bottom left",
                  annotation_font=dict(size=11, color=CRIT))
    fig.update_layout(title=dict(text="Fish alive after unpacking at each constant temperature", font=dict(size=14),
                                 x=0, xanchor="left"),
                      height=360, margin=dict(l=0, r=10, t=34, b=0), showlegend=False,
                      xaxis=dict(gridcolor=GRID, ticksuffix=" °C", dtick=2), yaxis=dict(gridcolor=GRID, ticksuffix="%"))
    chart(fig, a)
    with b:
        legend(tl, limit=False)
        chart(line_chart("Temperature in the simulated journeys", "°C", tl, "temp_c", height=300, zero=False,
                         fmt=".1f"))

with tabs[4]:
    (st.error if un["danger"] else st.info)(un["explanation"], icon=":material/warning:" if un["danger"] else None)
    m = st.columns(4)
    m[0].metric("pH after opening", f"{un['ph_after_opening']:.2f}", border=True)
    m[1].metric("Toxic ammonia peak", f"{un['peak_nh3_mgL']:.3f} mg/L", border=True, help="Typical journey")
    m[2].metric("Peak, worst journey", f"{un['peak_nh3_mgL_worst']:.3f} mg/L", border=True)
    m[3].metric("vs during the trip", f"{un['times_transit_level']:g}×", border=True,
                help="Peak after opening divided by the highest level while the bag was sealed")
    opened = [t for t, o in zip(tl["median"]["t_h"], tl["median"]["opened"]) if o]
    zoom = [max(0.0, opened[0] - 5), tl["median"]["t_h"][-1]] if opened else None
    legend(tl)
    a, b = st.columns(2, gap="medium")
    chart(line_chart("pH around opening", "", tl, "ph", x_range=zoom, zero=False), a)
    chart(line_chart("Toxic ammonia around opening", "mg/L", tl, "nh3_mgL", 0.02, "safe limit", x_range=zoom,
                     fmt=".3f"), b)
    st.subheader("How to unpack")
    for i, s in enumerate(un["steps"], 1):
        st.markdown(f"{i}. {s}")

with tabs[5]:
    opts = sorted(adv["options"], key=lambda o: o["max_fish_per_bag"])
    top = max(o["max_fish_per_bag"] for o in opts) or 1

    def tag(o):
        return " · ".join(t for t, on in (("recommended", o["recommended"]),
                                          ("your plan" if mode == "check" else "shown plan",
                                           o.get("selected") and not o["recommended"])) if on)

    colours = [MEDIAN if o["recommended"] else WORST if o.get("selected") else OTHER for o in opts]
    fig = go.Figure(go.Bar(y=[o["label"] for o in opts], x=[o["max_fish_per_bag"] for o in opts], orientation="h",
                           marker=dict(color=colours, cornerradius=4),
                           text=[f"{o['max_fish_per_bag']}" + (f"  ·  {tag(o)}" if tag(o) else "") for o in opts],
                           textposition="outside", cliponaxis=False,
                           hovertemplate="%{y}: %{x} fish per bag<extra></extra>"))
    if mode != "suggest":
        fig.add_vline(x=rec["fish_per_bag"], line=dict(color=CRIT, dash="dot", width=2),
                      annotation_text=f"{'your' if mode == 'check' else 'needed'}: {rec['fish_per_bag']} per bag",
                      annotation_position="top", annotation_font=dict(size=11, color=CRIT))
    fig.update_layout(title=dict(text="Most fish per bag that stays above the target on the hottest journey",
                                 font=dict(size=14), x=0, xanchor="left"),
                      height=90 + 30 * len(opts), margin=dict(l=0, r=10, t=40, b=0), bargap=0.35, showlegend=False,
                      xaxis=dict(gridcolor=GRID, range=[0, max(top, rec["fish_per_bag"]) * 1.3]))
    lead("Each bar is one combination of fasting, zeolite and anaesthetic. An add-on is only recommended if it "
         "lets you pack at least 5% more fish than the simpler plan.")
    chart(fig)
    with st.expander("Show as a table"):
        st.dataframe([{"Plan": o["label"], "Fish per bag": o["max_fish_per_bag"], "g/L": o["density_g_per_l"],
                       "vs basic": o["gain_vs_basic_pct"], "": tag(o).capitalize()} for o in opts[::-1]],
                     hide_index=True, width="stretch",
                     column_config={"Fish per bag": st.column_config.ProgressColumn(format="%d", min_value=0,
                                                                                    max_value=top),
                                    "g/L": st.column_config.NumberColumn("Fish density", format="%.1f g/L"),
                                    "vs basic": st.column_config.NumberColumn("vs fasting only", format="%+.0f%%")})

with tabs[6]:
    method = adv.get("method", {})
    a, b = st.columns([3, 2], gap="large")
    with a:
        st.subheader("How AquaSense works this out")
        st.markdown("\n".join(f"{i}. {step}" for i, step in enumerate(method.get("steps", []), 1)))
    with b:
        st.subheader("How sure we are")
        st.markdown("\n".join(f"- {note}" for note in method.get("confidence", [])))
        with st.expander("Studies the simulator is built on"):
            for src in method.get("sources", []):
                st.markdown(f"**{src['title']}**  \n{src['used_for']}")
            st.caption("Each add-on is based on: " + "; ".join(
                f"{d['name']}: {d['source']}" for d in rec["doses"] if d.get("source")))

    st.divider()
    st.subheader("AI correction layer")
    st.markdown(
        "The physics simulator predicts survival from how the bag works. The AI layer learns, from completed "
        "shipments, **where the physics is usually wrong** and corrects it. It predicts only the difference, so it "
        "needs little data and leaves the physics unchanged when it has seen nothing.")
    if experience:
        {"full": st.success, "limited": st.warning, "hidden": st.info}[experience["ai_display"]](
            f"**Has the AI seen shipments like this?** {experience['message']}")
        if experience["out_of_range"]:
            st.markdown("\n".join(f"- {x}" for x in experience["out_of_range"]))
    if ai:
        m = st.columns(3)
        m[0].metric("Physics estimate", f"{ai['physics_survival_pct']:.1f}%", border=True)
        m[1].metric("AI-corrected", f"{ai['corrected_survival_pct']:.1f}%", f"{ai['adjustment_pp']:+.1f} pts",
                    border=True)
        m[2].metric(f"Training shipments ({ai['trained_on']})", f"{ai['n_shipments']}", border=True)
    ml_dir = ROOT / "reports" / "ml"
    if (ml_dir / "ml_result.json").exists():
        if '"trained_on": "simulated"' in (ml_dir / "ml_result.json").read_text(encoding="utf-8"):
            st.warning("Trained on **simulated** shipments: this shows the method works and how much data it needs. "
                       "It is not real-world accuracy. Real shipment records will replace the simulated data.",
                       icon=":material/science:")
        imgs = [(img, cap) for img, cap in (("learning_curve.png", "Error vs number of completed shipments"),
                                            ("predicted_vs_observed.png", "Predicted vs observed on unseen shipments"),
                                            ("feature_importance.png", "What the AI pays attention to"))
                if (ml_dir / img).exists()]
        for i in range(0, len(imgs), 2):
            for col, (img, cap) in zip(st.columns(2, gap="medium"), imgs[i:i + 2]):
                col.image(str(ml_dir / img), caption=cap)
    else:
        st.info("No AI model trained yet. Run: `python -m transit_sim ml train`")

st.divider()
st.caption("Estimates from a simulation. See *Method & AI* for how they are worked out. "
           "Not a substitute for species-specific veterinary advice.")
