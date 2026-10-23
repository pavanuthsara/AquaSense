# Calibration and validation — Pramod et al. (2010)

Reproduce: `python -m transit_sim calibrate` (add `--write` to update `config/`).
Figure: `pramod2010_calibration.png` · Numbers: `calibration_result.json`.

## Protocol

| Stage | Data used | Parameters fitted |
|---|---|---|
| 1 | Control bag: DO, TAN, CO2 | `o2_rate`, `tan_rate`, `stress_amp`, sealed-bag `kLa` |
| 2 | Control bag: cumulative mortality | GUTS `kd`, `b`, `z` |
| 3 | Each anaesthetic bag: DO, TAN, CO2 | `metabolic_factor`, `excretion_factor`, `stress_factor` |
| 4 | — | **Predicted, not fitted:** anaesthetic-bag mortality; pH of all bags |

## Fitted values

| Parameter | Value | Meaning |
|---|---|---|
| `o2_rate` | 26.4 mg O2/kg/h | routine O2 use of a 12 g tiger barb at 22 °C, after handling stress |
| `tan_rate` | 4.59 mg N/kg/h | ammonia excretion (inside the tench range 1.95–8.80) |
| `stress_amp` | 0.57 | metabolism is +57 % right after packing, decaying with τ = 4 h |
| `kLa` (sealed bag) | 0.066 /h | slow O2/CO2 exchange between still water and the gas headspace |
| GUTS `kd`, `z` | at lower bounds (≈0) | data favour pure cumulative damage: no recovery and no threshold within 48 h |
| GUTS `b·kd` | 6.2×10⁻⁴ per TU·h² | hazard grows with accumulated toxic load → deaths start ~20 h, then accelerate |
| MS-222 40 mg/L | O2 ×0.88, TAN ×0.46, stress ×0.36 | |
| Benzocaine 20 mg/L | O2 ×0.91, TAN ×0.50, stress ×0.77 | |

## Fit quality

RMSE in units of the variable; NSE = Nash–Sutcliffe efficiency (1 = perfect, 0 = no better than the mean).

| Bag | DO | TAN | CO2 | pH (check) | Mortality |
|---|---|---|---|---|---|
| Control | 0.86 (0.94) | 0.90 (0.97) | 6.1 (0.94) | 0.36 (−0.12) | 0.40 (0.99) |
| MS-222 | 0.48 (0.96) | 0.30 (0.99) | 4.4 (0.96) | 0.43 (−2.4) | **predicted** 11.4 % vs 8.4 % at 48 h |
| Benzocaine | 0.72 (0.92) | 0.53 (0.97) | 5.6 (0.92) | 0.51 (−5.5) | **predicted** 12.7 % vs 9.0 % at 48 h |

## Findings worth discussing in the thesis

1. **Pramod's CO2 and pH cannot both be right under carbonate equilibrium.** At the stated alkalinity
   (65 mg/L CaCO3), the titrimetric CO2 implies pH 0.3–0.5 lower than the meter readings at 6–36 h.
   DO and CO2 tell the same respiration story (RQ 0.9), so the model trusts them and predicts pH.
   A plausible explanation is CO2 loss when bags were opened for the pH reading — the same
   rebound effect the simulator models at unpacking.
2. **Low O2 use in the bag.** The fitted 26 mg O2/kg/h is well below routine rates in the literature
   (100+ mg/kg/h). Two independent measurements (DO and CO2) agree on it. Either fish in a dark, still,
   sealed bag drop towards standard metabolism, or both methods under-read. Guppy predictions scale
   from this number, so it is the most important parameter to confirm with the physical experiment.
3. **The water, not the headspace, runs out of oxygen.** The headspace still holds ~80 % O2 at 48 h;
   DO falls because still water takes O2 from the gas slowly (kLa 0.066 /h). Bag motion during real
   transport will increase kLa — measure or vary it.
4. **Ammonia does not add alkalinity here** (`alk_from_tan = 0`). Letting excreted NH3 raise alkalinity
   makes the anaesthetic bags' CO2 and pH go the wrong way relative to control. Zero coupling
   (Na⁺/NH4⁺ exchange at the gill) fits the cross-treatment pattern best:

   | `alk_from_tan` | MS-222 CO2 RMSE | Benzocaine CO2 RMSE | MS-222 predicted mortality |
   |---|---|---|---|
   | 0.0 | 4.4 | 5.6 | 11.4 % |
   | 0.5 | 5.5 | 8.8 | 12.8 % |
   | 1.0 | 7.5 | 10.8 | 13.8 % |

5. **Deaths are driven by CO2, not ammonia.** NH3 stays below 0.02 mg/L throughout (low pH). The
   accumulated CO2 toxic load explains the delayed, accelerating mortality curve. This updates the
   "two killers, two modifiers" framing: CO2 is a killer as well as a modifier.
6. **Mortality prediction is directionally right but under-credits anaesthetics.** From water quality
   alone the model captures about half of the anaesthetic benefit (control 15.0 % → predicted 11.4 %,
   observed 8.4 %). Sedation probably also lowers sensitivity, not only exposure. This gap is the
   job of the ML correction layer.

## Limits

- Single study, single species, one density, one temperature; 6 fish per bag makes mortality coarse.
- Intermediate points are digitised (see `data/pramod2010/SOURCE.md`).
- Guppy parameters are inherited and size-scaled; not yet validated (Teo et al. 1989 needed).
- Zeolite kinetics and the feeding-state factors are placeholders, flagged in `README.md`.
