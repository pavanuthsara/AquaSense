# Pramod et al. (2010) — digitized transport data

**Source:** Pramod, P. K., Sajeevan, T. P., Ramachandran, A., Thampy, S., & Pai, S. S. (2010).
Effects of two anesthetics on water quality during simulated transport of a tropical ornamental
fish, the Indian tiger barb *Puntius filamentosus*. *North American Journal of Aquaculture*, 72, 290–297.
DOI: 10.1577/A09-063.1

## Experimental setup (from Methods)

| Item | Value |
|---|---|
| Species | Indian tiger barb *Puntius filamentosus* |
| Fish | 6 fish per bag, 12 ± 1 g each (72 g/L) |
| Bag | LDPE 22 × 60 cm, 1 L water, medical O2 at 1:3 oxygen:water (≈0.33 L gas), sealed |
| Water | pH 7.4, total hardness 58 mg/L, total alkalinity 65 mg/L as CaCO3 (1.30 meq/L) |
| Temperature | 22 ± 1 °C, styrofoam box, 48 h |
| Fish condition | Wild-caught, 1 week acclimation, starved 24 h before packing |
| Treatments | Control; MS-222 40 mg/L; benzocaine 20 mg/L (24 bags each) |
| Sampling | 3 bags per treatment every 6 h (destructive) |
| Methods | CO2 titrimetric, DO Winkler, TAN indophenol blue (APHA 1995) |

## How the values were obtained

- 48 h values for DO, TAN, CO2, pH and mortality are **exact values quoted in the text**.
- Baseline TAN 0.58 mg/L is from the text (Fig. 2 plots it as 0).
- Intermediate points were read from Figures 1–6 (embedded 931 px images) by locating the axis
  ticks in pixel space and then the marker centres, cross-checked visually.
  Expected reading error: about ±0.3 mg/L (DO, TAN), ±1.5 mg/L (CO2), ±0.03 (pH), ±0.5 % (mortality).
- `nh3_mgL` (Fig. 3) is the paper's own un-ionized ammonia; it is kept for checking the
  ammonia-equilibrium code, not used for calibration.

**Before thesis submission:** re-digitize with WebPlotDigitizer and record the result here.

## Known inconsistencies in the source

- Titrimetric CO2 and measured pH are not mutually consistent under carbonate equilibrium at the
  stated alkalinity (see `reports/calibration_summary.md`). The model computes pH from chemistry,
  so it cannot match both exactly.
- Mortality with 6 fish per bag is coarse (one fish = 16.7 % of a bag); reported percentages
  are means across bags.
