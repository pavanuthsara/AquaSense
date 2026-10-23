"""Mechanistic time-step model of a sealed live-fish transport bag.

State (per bag):
    do      dissolved O2 (mg/L)
    tan     total ammonia nitrogen (mg/L)
    dic     dissolved inorganic carbon (mmol/L)
    alk     total alkalinity incl. NH3 (meq/L)
    n_o2    O2 in the gas headspace (mmol)
    n_co2   CO2 in the gas headspace (mmol)
    q_z     ammonia held on zeolite (mg N/L of water)
    damage  GUTS scaled damage (toxic units)
    hazard  cumulative hazard (survival = exp(-hazard))

Processes:
    respiration    O2 uptake = rate(mass, T, stress, feeding, sedation, DO) x live biomass
    CO2 production = RQ x O2 uptake (mol/mol)
    excretion      TAN, excreted as NH3 -> raises alkalinity by 1 eq per mol N
    gas exchange   O2 and CO2 between water and headspace (two-film, kLa)
    zeolite        PROVISIONAL first-order ammonium uptake towards capacity
    mortality      GUTS-RED-SD (Jager et al. 2011) on summed toxic units of NH3, CO2, hypoxia
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import yaml
from scipy.integrate import solve_ivp

from . import chemistry as chem
from .config import CONFIG_DIR, Interventions, Shipment, Species, Unpacking

# CO2 diffuses a little slower than O2: kLa_CO2 = kLa_O2 * sqrt(D_CO2 / D_O2)
CO2_KLA_RATIO = 0.89

# Feeding state (specific dynamic action). PROVISIONAL, see README "Assumptions".
# Normalised so that 24 h starvation (Pramod 2010 protocol) gives factor 1.
_SDA_TAU_H = 12.0
_SDA_O2_AMP = 0.43   # fed fish ~ +35 % O2 (Ruiz-Jarabo & de Pedro 2024, goldfish)
_SDA_TAN_AMP = 3.4   # fed fish ~ 3x TAN excretion (tench, low vs high ration)

# Zeolite (clinoptilolite) kinetics. PROVISIONAL until Teo et al. 1989 full text is digitised.
ZEOLITE_RATE_L_PER_G_H = 0.05
ZEOLITE_CAPACITY_MG_N_PER_G = 5.0

STATE = ("do", "tan", "dic", "alk", "n_o2", "n_co2", "q_z", "damage", "hazard")
IDX = {k: i for i, k in enumerate(STATE)}


def bag_defaults() -> dict:
    with open(CONFIG_DIR / "bag.yaml", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _feeding_factor(starvation_h: float, amp: float) -> float:
    return (1.0 + amp * math.exp(-starvation_h / _SDA_TAU_H)) / (1.0 + amp * math.exp(-24.0 / _SDA_TAU_H))


@dataclass
class SimulationResult:
    t: np.ndarray
    do: np.ndarray
    tan: np.ndarray
    co2: np.ndarray        # free CO2, mg/L
    ph: np.ndarray
    nh3: np.ndarray        # un-ionized ammonia, mg/L
    gas_o2_atm: np.ndarray
    survival: np.ndarray   # fraction alive
    damage: np.ndarray
    temp: np.ndarray
    phase: np.ndarray      # 0 = sealed transit, 1 = opened / unpacking
    tu_nh3: np.ndarray
    tu_co2: np.ndarray
    tu_do: np.ndarray
    summary: dict = field(default_factory=dict)

    def as_rows(self) -> list[dict]:
        keys = ["t", "do", "tan", "co2", "ph", "nh3", "gas_o2_atm", "survival", "damage", "temp", "phase"]
        return [{k: float(getattr(self, k)[i]) for k in keys} for i in range(len(self.t))]


class BagModel:
    def __init__(self, species: Species, shipment: Shipment,
                 interventions: Interventions | None = None) -> None:
        self.sp = species
        self.sh = shipment
        self.iv = interventions or Interventions()
        bag = bag_defaults()
        self.kla = shipment.kla_per_h if shipment.kla_per_h is not None else bag["sealed_bag_kla_per_h"]["value"]
        self.mass_factor = (shipment.fish_mass_g / species.ref_mass_g) ** species.mass_exponent
        self.feed_o2 = _feeding_factor(self.iv.starvation_h, _SDA_O2_AMP)
        self.feed_tan = _feeding_factor(self.iv.starvation_h, _SDA_TAN_AMP)

    # ------------------------------------------------------------------ helpers
    def initial_state(self) -> np.ndarray:
        sh = self.sh
        t0 = sh.temperature_at(0.0)
        alk = chem.alkalinity_from_caco3(sh.alkalinity_mgL_caco3) + self.iv.extra_alkalinity_meq
        dic = chem.dic_from_ph_alk(sh.initial_ph, chem.alkalinity_from_caco3(sh.alkalinity_mgL_caco3),
                                   sh.initial_tan_mgL, t0)
        p_o2 = sh.gas_o2_fraction
        do0 = sh.initial_do_mgL if sh.initial_do_mgL is not None else chem.o2_henry_mgL_per_atm(t0) * p_o2
        n_gas = sh.gas_l / (chem.R_GAS * chem.kelvin(t0)) * 1000.0  # mmol of gas
        y = np.zeros(len(STATE))
        y[IDX["do"]] = do0
        y[IDX["tan"]] = sh.initial_tan_mgL
        y[IDX["dic"]] = dic
        y[IDX["alk"]] = alk
        y[IDX["n_o2"]] = n_gas * p_o2
        y[IDX["n_co2"]] = n_gas * chem.CO2_AIR_ATM * (1.0 - p_o2)
        return y

    def _metabolic_multiplier(self, t: float, temp: float) -> float:
        sp = self.sp
        stress = 1.0 + sp.stress_amp * self.iv.stress_factor * math.exp(-t / sp.stress_tau_h)
        q10 = sp.q10 ** ((temp - sp.ref_temp_c) / 10.0)
        return self.mass_factor * q10 * stress

    def diagnostics(self, y: np.ndarray, temp: float) -> dict:
        ph = chem.solve_ph(y[IDX["dic"]], y[IDX["alk"]], y[IDX["tan"]], temp)
        co2_mmol = y[IDX["dic"]] * chem.free_co2_fraction(ph, temp)
        nh3 = y[IDX["tan"]] * chem.unionized_fraction(ph, temp)
        do = max(y[IDX["do"]], 0.0)
        sp = self.sp
        tu_nh3 = nh3 / sp.nh3_lc50
        tu_co2 = co2_mmol * chem.MW_CO2 / sp.co2_ref
        tu_do = max(0.0, sp.do_crit / max(do, 0.05) - 1.0)
        return dict(ph=ph, co2_mmol=co2_mmol, nh3=nh3, tu_nh3=tu_nh3, tu_co2=tu_co2, tu_do=tu_do)

    # ------------------------------------------------------------------ ODE
    def rhs(self, t: float, y: np.ndarray, *, opened: bool, temp: float, t_since_pack: float,
            kla_open: float = 0.0) -> np.ndarray:
        sp, sh, iv = self.sp, self.sh, self.iv
        vw, vg = sh.water_l, sh.gas_l
        d = self.diagnostics(y, temp)
        do = max(y[IDX["do"]], 0.0)

        survival = math.exp(-y[IDX["hazard"]])
        live_kg = sh.biomass_kg * survival
        mult = self._metabolic_multiplier(t_since_pack, temp)
        hyp = 1.0 / (1.0 + (sp.do_half_uptake / max(do, 1e-6)) ** sp.hypoxia_hill)

        exc = iv.excretion_factor if iv.excretion_factor is not None else iv.metabolic_factor
        o2_use = sp.o2_rate * mult * iv.metabolic_factor * self.feed_o2 * hyp * live_kg   # mg O2/h
        tan_out = sp.tan_rate * mult * exc * self.feed_tan * live_kg                      # mg N/h
        co2_out_mmol = sp.rq * o2_use / chem.MW_O2                  # mmol/h

        # gas exchange
        tk = chem.kelvin(temp)
        if opened:
            p_o2 = chem.O2_AIR_FRACTION
            p_co2 = chem.CO2_AIR_ATM
            kla = kla_open
        else:
            p_o2 = y[IDX["n_o2"]] / 1000.0 * chem.R_GAS * tk / vg
            p_co2 = y[IDX["n_co2"]] / 1000.0 * chem.R_GAS * tk / vg
            kla = self.kla
        o2_flux = kla * (chem.o2_henry_mgL_per_atm(temp) * p_o2 - do)                  # mg/L/h into water
        co2_flux = kla * CO2_KLA_RATIO * (chem.co2_henry_mmolL_per_atm(temp) * p_co2 - d["co2_mmol"])  # mmol/L/h

        # zeolite (ammonium exchange)
        zeo = 0.0
        if iv.zeolite_g_per_l > 0:
            cap = ZEOLITE_CAPACITY_MG_N_PER_G * iv.zeolite_g_per_l
            zeo = ZEOLITE_RATE_L_PER_G_H * iv.zeolite_g_per_l * y[IDX["tan"]] * max(0.0, 1.0 - y[IDX["q_z"]] / cap)

        # mortality (GUTS-RED-SD on summed toxic units)
        stress_tu = d["tu_nh3"] + d["tu_co2"] + d["tu_do"]
        d_damage = sp.guts_kd * (stress_tu - y[IDX["damage"]])
        hazard_rate = sp.guts_b * max(0.0, y[IDX["damage"]] - sp.guts_z)

        dy = np.zeros_like(y)
        dy[IDX["do"]] = o2_flux - o2_use / vw
        dy[IDX["tan"]] = tan_out / vw - zeo
        dy[IDX["dic"]] = co2_out_mmol / vw + co2_flux
        dy[IDX["alk"]] = sp.alk_from_tan * tan_out / vw / chem.MW_N  # NH3 excretion consumes H+
        if not opened:
            dy[IDX["n_o2"]] = -o2_flux * vw / chem.MW_O2
            dy[IDX["n_co2"]] = -co2_flux * vw
        dy[IDX["q_z"]] = zeo
        dy[IDX["damage"]] = d_damage
        dy[IDX["hazard"]] = hazard_rate
        return dy

    # ------------------------------------------------------------------ run
    def _integrate(self, y0, t0, t1, dt_out, *, opened, temp_fn, kla_open=0.0):
        n = max(int(round((t1 - t0) / dt_out)), 1)
        t_eval = np.linspace(t0, t1, n + 1)

        def f(t, y):
            return self.rhs(t, y, opened=opened, temp=temp_fn(t), t_since_pack=t, kla_open=kla_open)

        sol = solve_ivp(f, (t0, t1), y0, t_eval=t_eval, method="LSODA", rtol=1e-6, atol=1e-8,
                        max_step=0.25 if opened else 1.0)
        if not sol.success:
            raise RuntimeError(sol.message)
        return sol.t, sol.y

    def run(self, unpacking: Unpacking | None = Unpacking(), dt_out: float = 0.25) -> SimulationResult:
        sh = self.sh
        y0 = self.initial_state()
        ts, ys = self._integrate(y0, 0.0, sh.duration_h, dt_out, opened=False, temp_fn=sh.temperature_at)
        phases = [np.zeros_like(ts)]
        temps = [np.array([sh.temperature_at(t) for t in ts])]
        if unpacking is not None and unpacking.duration_h > 0:
            t_end = sh.duration_h
            t_un = unpacking.temperature_c if unpacking.temperature_c is not None else sh.temperature_at(t_end)
            t2, y2 = self._integrate(ys[:, -1], t_end, t_end + unpacking.duration_h, min(dt_out, 0.05),
                                     opened=True, temp_fn=lambda _t: t_un, kla_open=unpacking.kla_open_per_h)
            ts = np.concatenate([ts, t2[1:]])
            ys = np.concatenate([ys, y2[:, 1:]], axis=1)
            phases.append(np.ones(len(t2) - 1))
            temps.append(np.full(len(t2) - 1, t_un))
        phase = np.concatenate(phases)
        temp = np.concatenate(temps)
        diag = [self.diagnostics(ys[:, i], temp[i]) for i in range(len(ts))]
        res = SimulationResult(
            t=ts,
            do=ys[IDX["do"]],
            tan=ys[IDX["tan"]],
            co2=np.array([d["co2_mmol"] * chem.MW_CO2 for d in diag]),
            ph=np.array([d["ph"] for d in diag]),
            nh3=np.array([d["nh3"] for d in diag]),
            gas_o2_atm=np.where(phase == 0,
                                ys[IDX["n_o2"]] / 1000.0 * chem.R_GAS * chem.kelvin(temp) / sh.gas_l,
                                chem.O2_AIR_FRACTION),
            survival=np.exp(-ys[IDX["hazard"]]),
            damage=ys[IDX["damage"]],
            temp=temp,
            phase=phase,
            tu_nh3=np.array([d["tu_nh3"] for d in diag]),
            tu_co2=np.array([d["tu_co2"] for d in diag]),
            tu_do=np.array([d["tu_do"] for d in diag]),
        )
        res.summary = summarise(res, self.sp)
        return res


def summarise(r: SimulationResult, sp: Species) -> dict:
    transit = r.phase == 0
    opened = r.phase == 1
    i_arr = int(np.where(transit)[0][-1])
    out = {
        "survival_at_arrival": float(r.survival[i_arr]),
        "survival_after_unpacking": float(r.survival[-1]),
        "min_do_mgL": float(r.do[transit].min()),
        "final_do_mgL": float(r.do[i_arr]),
        "final_tan_mgL": float(r.tan[i_arr]),
        "max_co2_mgL": float(r.co2[transit].max()),
        "final_ph": float(r.ph[i_arr]),
        "max_nh3_transit_mgL": float(r.nh3[transit].max()),
        "peak_nh3_unpacking_mgL": float(r.nh3[opened].max()) if opened.any() else None,
        "peak_ph_unpacking": float(r.ph[opened].max()) if opened.any() else None,
    }
    below = np.where(transit & (r.do < sp.do_crit))[0]
    out["hours_to_do_crit"] = float(r.t[below[0]]) if len(below) else None
    # attribute damage to stressors (integrated toxic units during transit)
    dt = np.gradient(r.t)
    contrib = {"ammonia (NH3)": float(np.sum(r.tu_nh3 * dt)),
               "carbon dioxide": float(np.sum(r.tu_co2 * dt)),
               "low oxygen": float(np.sum(r.tu_do * dt))}
    total = sum(contrib.values()) or 1.0
    out["stress_share"] = {k: v / total for k, v in contrib.items()}
    out["main_driver"] = max(contrib, key=contrib.get)
    return out


def simulate(species: Species, shipment: Shipment, interventions: Interventions | None = None,
             unpacking: Unpacking | None = Unpacking(), dt_out: float = 0.25) -> SimulationResult:
    return BagModel(species, shipment, interventions).run(unpacking=unpacking, dt_out=dt_out)
