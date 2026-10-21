"""AquaSense export advisor — demo UI.

Run from the export_simulator folder:
    streamlit run app/streamlit_app.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import plotly.graph_objects as go
import streamlit as st

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from transit_sim import available_species  # noqa: E402
from transit_sim.advisor import AdvisoryRequest, advise  # noqa: E402

BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
CRIT, MUTED, GRID = "#c0392b", "#52514e", "rgba(128,128,128,0.18)"

st.set_page_config(page_title="Export transit advisor", page_icon="🐟", layout="wide")


@st.cache_data(show_spinner=False)
def run_advice(req_dict: dict) -> dict:
    return advise(AdvisoryRequest(**req_dict))


def line_chart(title: str, unit: str, tl: dict, key: str, ref: float | None = None, ref_label: str = "",
               show_worst: bool = True, height: int = 300, y_range: list | None = None) -> go.Figure:
    med, worst = tl["median"], tl["worst"]
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=med["t_h"], y=med[key], name="Median journey", mode="lines",
                             line=dict(color=BLUE, width=2.5),
                             hovertemplate="%{x:.0f} h: %{y:.3~f} " + unit + "<extra>median</extra>"))
    if show_worst:
        fig.add_trace(go.Scatter(x=worst["t_h"], y=worst[key], name=f"Worst ({tl['worst_label']})", mode="lines",
                                 line=dict(color=ORANGE, width=2, dash="dash"),
                                 hovertemplate="%{x:.0f} h: %{y:.3~f} " + unit + "<extra>worst</extra>"))
    opened = [t for t, o in zip(med["t_h"], med["opened"]) if o]
    if opened:
        fig.add_vrect(x0=opened[0], x1=med["t_h"][-1], fillcolor="#eda100", opacity=0.15, line_width=0,
                      annotation_text="bag opened", annotation_position="top left",
                      annotation_font=dict(size=11, color=MUTED))
    if ref is not None:
        fig.add_hline(y=ref, line=dict(color=CRIT, dash="dot", width=1.5), annotation_text=ref_label,
                      annotation_position="bottom right", annotation_font=dict(size=11, color=CRIT))
    fig.update_layout(title=dict(text=title, font=dict(size=15)), height=height, margin=dict(l=10, r=10, t=45, b=10),
                      hovermode="x unified", legend=dict(orientation="h", y=-0.22),
                      xaxis=dict(title="Hours since packing", gridcolor=GRID),
                      yaxis=dict(title=unit, gridcolor=GRID, rangemode="tozero", range=y_range))
    return fig


# ----------------------------------------------------------------------------- inputs
with st.sidebar:
    st.header("Shipment")
    species = st.selectbox("Species", available_species(), index=available_species().index("guppy"))
    mass = st.number_input("Average fish weight (g)", 0.05, 200.0, 0.3 if species == "guppy" else 12.0, step=0.05)
    total = st.number_input("Total fish to ship (0 = not set)", 0, 1_000_000, 1000, step=100)
    hours = st.slider("Door-to-door time (h)", 6, 96, 36, step=2)
    t_lo, t_hi = st.slider("Expected temperature range (°C)", 15.0, 35.0, (24.0, 28.0), step=0.5)
    st.header("Bag")
    water = st.number_input("Water per bag (L)", 0.05, 20.0, 0.4, step=0.05)
    gas = st.number_input("Oxygen per bag (L)", 0.05, 40.0, 1.2, step=0.1)
    target = st.slider("Minimum survival after unpacking (%)", 80.0, 99.5, 95.0, step=0.5,
                       help="5 % dead-on-arrival is the usual industry warranty threshold (Lim et al. 2003).")
    st.header("Allowed add-ons")
    allow_anaes = st.checkbox("Anaesthetics (MS-222 / benzocaine)", True)
    allow_zeo = st.checkbox("Zeolite", True)
    max_fast = st.select_slider("Longest fasting allowed (h)", [24, 48], 48)
    with st.expander("Water & advanced"):
        ph0 = st.number_input("Packing water pH", 5.5, 9.0, 7.4, step=0.1)
        alk = st.number_input("Alkalinity (mg/L CaCO3)", 5.0, 400.0, 65.0, step=5.0)
        kla = st.number_input("Bag gas transfer kLa (1/h, 0 = calibrated static bag)", 0.0, 5.0, 0.0, step=0.05)
        samples = st.slider("Random temperature profiles", 0, 30, 10)

req = dict(species=species, fish_mass_g=float(mass), total_fish=int(total) or None, water_l=float(water),
           gas_l=float(gas), duration_h=float(hours), temp_low_c=float(t_lo), temp_high_c=float(t_hi),
           target_survival=float(target) / 100.0, allow_anaesthetic=allow_anaes, allow_zeolite=allow_zeo,
           max_fasting_h=float(max_fast), initial_ph=float(ph0), alkalinity_mgL_caco3=float(alk),
           kla_per_h=float(kla) or None, samples=int(samples))

st.title("Export transit advisor")
st.caption("AquaSense · Export management — predicts what happens inside the sealed bag and how to pack it.")

try:
    with st.spinner("Simulating packing options…"):
        adv = run_advice(req)
except ValueError as exc:
    st.error(f"Check the inputs: {exc}")
    st.stop()

for w in adv["warnings"]:
    st.warning(w, icon="⚠️")

rec = adv["recommendation"]
if not adv["feasible"]:
    st.error(rec["summary"])
    st.stop()

# ----------------------------------------------------------------------------- headline
st.success("**Packing plan:** " + rec["summary"])
c = st.columns(5)
c[0].metric("Fish per bag", rec["fish_per_bag"], help=f"{rec['density_g_per_l']} g/L")
c[1].metric("Bags needed", rec["bags_needed"] if rec["bags_needed"] else "—",
            delta=(f"{rec['bags_needed'] - rec['bags_needed_without_chemicals']} vs no chemicals"
                   if rec["bags_needed"] and rec["bags_needed_without_chemicals"] else None), delta_color="inverse")
c[2].metric("Survival (median)", f"{adv['mortality']['survival_after_unpacking_pct']:.1f}%")
c[3].metric("Survival (worst case)", f"{adv['mortality']['worst_survival_after_unpacking_pct']:.1f}%")
c[4].metric("Expected losses / bag", f"{adv['mortality']['expected_dead_per_bag']:.1f}",
            help=f"worst case {adv['mortality']['expected_dead_per_bag_worst']:.1f}")

tl = adv["timeline"]
tabs = st.tabs(["What to add", "Oxygen", "How fast fish die", "Water chemistry", "Temperature", "Unpacking",
                "All options"])

with tabs[0]:
    st.subheader("Chemicals and preparation — how much")
    for d in rec["doses"]:
        with st.container(border=True):
            st.markdown(f"**{d['name']}** — {d['amount']}" + (f" → **{d['per_bag']}**" if d["per_bag"] else ""))
            st.markdown(f"*Why:* {d['evidence']}")
            st.markdown(f"*Caution:* {d['caution']}")
    st.subheader("Other options (not simulated)")
    for d in rec["not_simulated_options"]:
        st.markdown(f"- **{d['name']}** ({d['amount']}): {d['evidence']} _{d['caution']}_")

with tabs[1]:
    ox = adv["oxygen"]
    st.info(ox["explanation"])
    m = st.columns(4)
    m[0].metric("O₂ use, first 6 h", f"{ox['use_rate_first_6h_mg_per_h']} mg/h")
    m[1].metric("O₂ use, average", f"{ox['use_rate_average_mg_per_h']} mg/h",
                help=f"{ox['use_per_fish_mg_per_h']} mg per fish per hour")
    m[2].metric("O₂ gas left at arrival", f"{ox['gas_o2_left_pct']}%")
    m[3].metric("Water O₂ below critical", f"hour {ox['hours_to_critical_do']:.0f}" if ox["hours_to_critical_do"]
                is not None else "never")
    a, b = st.columns(2)
    a.plotly_chart(line_chart("Oxygen in the water", "mg/L", tl, "do_mgL", ox["do_critical_mgL"], "critical"),
                   width="stretch")
    b.plotly_chart(line_chart("Oxygen gas left in the bag (% of packed)", "%", tl, "gas_o2_pct",
                              y_range=[0, 105]),
                   width="stretch")

with tabs[2]:
    mo = adv["mortality"]
    st.info(mo["explanation"])
    a, b = st.columns([3, 2])
    low = min(min(tl["worst"]["alive_pct"]), adv["target_survival_pct"])
    a.plotly_chart(line_chart("Fish alive", "%", tl, "alive_pct", adv["target_survival_pct"], "target",
                              y_range=[max(0.0, low - 3), 100.5]),
                   width="stretch")
    b.dataframe([{"Hour": x["hour"], "Alive (median) %": x["median"], "Alive (worst) %": x["worst"]}
                 for x in mo["survival_at_checkpoints_pct"]], hide_index=True, width="stretch")
    b.markdown("**What causes the deaths**")
    b.dataframe([{"Cause": k, "Share of toxic load %": v} for k, v in mo["cause_share_pct"].items()],
                hide_index=True, width="stretch")

with tabs[3]:
    st.info(adv["chemistry"]["explanation"])
    a, b, c3 = st.columns(3)
    a.plotly_chart(line_chart("Free CO₂", "mg/L", tl, "co2_mgL", 20, "harmful above"), width="stretch")
    b.plotly_chart(line_chart("pH", "pH", tl, "ph"), width="stretch")
    c3.plotly_chart(line_chart("Toxic ammonia (NH₃)", "mg/L", tl, "nh3_mgL", 0.02, "safe limit"),
                    width="stretch")
    st.plotly_chart(line_chart("Total ammonia", "mg/L", tl, "tan_mgL"), width="stretch")

with tabs[4]:
    te = adv["temperature"]
    st.info(te["advice"])
    fig = go.Figure(go.Scatter(x=[p["temp_c"] for p in te["curve"]], y=[p["survival_pct"] for p in te["curve"]],
                               mode="lines+markers", line=dict(color=BLUE, width=2.5), marker=dict(size=8),
                               hovertemplate="%{x:.0f} °C: %{y:.1f}% alive<extra></extra>"))
    fig.add_vrect(x0=t_lo, x1=t_hi, fillcolor=ORANGE, opacity=0.12, line_width=0,
                  annotation_text="forecast range", annotation_position="top left")
    fig.add_hline(y=adv["target_survival_pct"], line=dict(color=CRIT, dash="dot"), annotation_text="target")
    fig.update_layout(title="Survival after unpacking vs constant temperature (this plan)", height=360,
                      xaxis=dict(title="°C", gridcolor=GRID), yaxis=dict(title="% alive", gridcolor=GRID),
                      margin=dict(l=10, r=10, t=45, b=10))
    st.plotly_chart(fig, width="stretch")
    st.plotly_chart(line_chart("Temperature in the journeys simulated", "°C", tl, "temp_c"), width="stretch")

with tabs[5]:
    un = adv["unpacking"]
    (st.error if un["danger"] else st.info)(un["explanation"])
    st.plotly_chart(line_chart("Toxic ammonia around unpacking", "mg/L", tl, "nh3_mgL", 0.02, "safe limit"),
                    width="stretch")
    st.markdown("**How to unpack**")
    for i, s in enumerate(un["steps"], 1):
        st.markdown(f"{i}. {s}")

with tabs[6]:
    opts = sorted(adv["options"], key=lambda o: o["max_fish_per_bag"])
    fig = go.Figure(go.Bar(y=[o["label"] for o in opts], x=[o["max_fish_per_bag"] for o in opts], orientation="h",
                           marker=dict(color=[ORANGE if o["recommended"] else BLUE for o in opts]),
                           text=[o["max_fish_per_bag"] for o in opts], textposition="outside",
                           hovertemplate="%{y}: %{x} fish per bag<extra></extra>"))
    fig.update_layout(title="Maximum fish per bag at the hot end of the range (orange = recommended)",
                      height=60 + 32 * len(opts), margin=dict(l=10, r=10, t=45, b=10),
                      xaxis=dict(title="fish per bag", gridcolor=GRID))
    st.plotly_chart(fig, width="stretch")
    st.dataframe([{"Plan": o["label"], "Fish/bag": o["max_fish_per_bag"], "g/L": o["density_g_per_l"],
                   "vs basic %": o["gain_vs_basic_pct"], "Recommended": "✓" if o["recommended"] else ""}
                  for o in opts[::-1]], hide_index=True, width="stretch")

st.caption("Model: mechanistic bag simulator calibrated on Pramod et al. (2010). Add-ons must gain ≥5 % more fish "
           "to be recommended. Not a substitute for species-specific veterinary advice.")
