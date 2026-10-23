# AI correction layer — training summary

Trained on **600 SIMULATED shipments (pretend reality)**, tested on **300 unseen shipments**.

> These results show the method works and how much data it needs. They are **not** real-world accuracy. Real shipment records will replace the simulated ones.

| Method | Mean error (percentage points) | Bias | Safe / not-safe call correct |
|---|---|---|---|
| Physics only | 3.52 | -3.22 | 95% |
| Physics + AI correction | 1.57 | +0.03 | 96% |
| AI only (no physics) | 2.93 | +0.76 | 92% |

## Learning curve (mean error, percentage points)

| Training shipments | Physics only | Physics + AI | AI only |
|---|---|---|---|
| 10 | 3.52 | 2.54 | 16.84 |
| 20 | 3.52 | 2.45 | 8.19 |
| 40 | 3.52 | 2.43 | 7.20 |
| 80 | 3.52 | 2.03 | 4.83 |
| 160 | 3.52 | 1.84 | 3.51 |
| 320 | 3.52 | 1.68 | 3.22 |
| 600 | 3.52 | 1.58 | 2.99 |

## What the AI pays most attention to

- Physics survival estimate (0.76 pp)
- Physics: lowest oxygen (0.43 pp)
- MS-222 (0.35 pp)
- Fish weight (0.22 pp)
- Benzocaine (0.13 pp)
- Trip length (0.08 pp)

Figures: `learning_curve.png`, `predicted_vs_observed.png`, `feature_importance.png`.
