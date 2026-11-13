"""Water and gas chemistry for a sealed fish-transport bag.

All functions are pure. Temperatures are in degrees Celsius unless the name says ``_k``.

References
----------
- Benson, B. B. & Krause, D. (1984). Limnol. Oceanogr. 29:620-632 (O2 solubility).
- Weiss, R. F. (1974). Mar. Chem. 2:203-215 (CO2 solubility, K0).
- Plummer, L. N. & Busenberg, E. (1982). Geochim. Cosmochim. Acta 46:1011-1040 (K1, K2).
- Emerson, K. et al. (1975). J. Fish. Res. Board Can. 32:2379-2383 (ammonia pKa).
"""
from __future__ import annotations

import math

R_GAS = 0.082057  # L atm mol-1 K-1
MW_O2 = 32.00
MW_CO2 = 44.01
MW_N = 14.007
O2_AIR_FRACTION = 0.20946
CO2_AIR_ATM = 4.2e-4


def kelvin(temp_c: float) -> float:
    return temp_c + 273.15


def water_vapour_atm(temp_c: float) -> float:
    """Saturation vapour pressure of water (atm), Antoine-type fit, 0-40 C."""
    return math.exp(11.8571 - 3840.70 / kelvin(temp_c) - 216961.0 / kelvin(temp_c) ** 2)


def o2_saturation_air_mgL(temp_c: float) -> float:
    """Freshwater O2 solubility (mg/L) in equilibrium with moist air at 1 atm (Benson & Krause 1984)."""
    t = kelvin(temp_c)
    ln_c = (-135.29996 + 1.572288e5 / t - 6.637149e7 / t**2
            + 1.243678e10 / t**3 - 8.621061e11 / t**4)
    return math.exp(ln_c) * MW_O2 / 1000.0  # umol/kg -> mg/L (density ~ 1)


def o2_henry_mgL_per_atm(temp_c: float) -> float:
    """Henry coefficient for O2: dissolved mg/L per atm partial pressure."""
    p_o2_air = O2_AIR_FRACTION * (1.0 - water_vapour_atm(temp_c))
    return o2_saturation_air_mgL(temp_c) / p_o2_air


def co2_henry_mmolL_per_atm(temp_c: float) -> float:
    """CO2 solubility K0 (mmol/L/atm), Weiss (1974) freshwater."""
    t = kelvin(temp_c)
    ln_k0 = -58.0931 + 90.5069 * (100.0 / t) + 22.2940 * math.log(t / 100.0)
    return math.exp(ln_k0) * 1000.0


def carbonate_constants(temp_c: float) -> tuple[float, float, float]:
    """Return (K1, K2, Kw) for freshwater (Plummer & Busenberg 1982; Kw after Harned & Owen)."""
    t = kelvin(temp_c)
    log_k1 = (-356.3094 - 0.06091964 * t + 21834.37 / t
              + 126.8339 * math.log10(t) - 1684915.0 / t**2)
    log_k2 = (-107.8871 - 0.03252849 * t + 5151.79 / t
              + 38.92561 * math.log10(t) - 563713.9 / t**2)
    pkw = 4470.99 / t - 6.0875 + 0.01706 * t
    return 10.0**log_k1, 10.0**log_k2, 10.0**(-pkw)


def ammonia_pka(temp_c: float) -> float:
    """Emerson et al. (1975): pKa = 0.09018 + 2729.92 / T(K)."""
    return 0.09018 + 2729.92 / kelvin(temp_c)


def unionized_fraction(ph: float, temp_c: float) -> float:
    """Fraction of total ammonia present as toxic NH3: f = 1 / (1 + 10^(pKa - pH))."""
    return 1.0 / (1.0 + 10.0 ** (ammonia_pka(temp_c) - ph))


def _alkalinity_residual(h: float, dic: float, tan_mmol: float, k1: float, k2: float,
                         kw: float, kn: float) -> float:
    denom = h * h + k1 * h + k1 * k2
    carb = dic * (k1 * h + 2.0 * k1 * k2) / denom
    nh3 = tan_mmol * kn / (kn + h)
    return carb + nh3 + kw * 1e3 / h - h * 1e3  # all in mmol/L (meq/L)


def solve_ph(dic_mmol: float, alk_meq: float, tan_mgL: float, temp_c: float) -> float:
    """pH from DIC (mmol/L), total alkalinity (meq/L) and total ammonia (mg N/L).

    Total alkalinity here includes the NH3 term, so ammonia excreted as NH3 raises it.
    Solved by bisection on log10[H+] (robust, monotone).
    """
    k1, k2, kw = carbonate_constants(temp_c)
    kn = 10.0 ** (-ammonia_pka(temp_c))
    tan_mmol = max(tan_mgL, 0.0) / MW_N
    dic = max(dic_mmol, 0.0)
    lo, hi = 3.0, 11.5  # pH bounds
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        h = 10.0 ** (-mid)
        # residual = species alkalinity - total alkalinity; increases with pH
        if _alkalinity_residual(h, dic, tan_mmol, k1, k2, kw, kn) - alk_meq > 0:
            hi = mid
        else:
            lo = mid
    return 0.5 * (lo + hi)


def free_co2_fraction(ph: float, temp_c: float) -> float:
    """Fraction of DIC present as dissolved CO2 (alpha0)."""
    k1, k2, _ = carbonate_constants(temp_c)
    h = 10.0 ** (-ph)
    return h * h / (h * h + k1 * h + k1 * k2)


def dic_from_ph_alk(ph: float, alk_meq: float, tan_mgL: float, temp_c: float) -> float:
    """Initial DIC (mmol/L) consistent with a measured pH and alkalinity."""
    k1, k2, kw = carbonate_constants(temp_c)
    kn = 10.0 ** (-ammonia_pka(temp_c))
    h = 10.0 ** (-ph)
    tan_mmol = tan_mgL / MW_N
    non_carb = tan_mmol * kn / (kn + h) + kw * 1e3 / h - h * 1e3
    per_dic = (k1 * h + 2.0 * k1 * k2) / (h * h + k1 * h + k1 * k2)
    return max(alk_meq - non_carb, 0.0) / per_dic


def alkalinity_from_caco3(mg_l_caco3: float) -> float:
    """Convert alkalinity in mg/L as CaCO3 to meq/L."""
    return mg_l_caco3 / 50.04
