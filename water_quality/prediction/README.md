# AquaSense — Prediction layer (forecast + early alerts)

Forecasts DO, pH, ammonia and temperature 10 min ahead (default; set
`horizon_steps` in `settings.py` or pass `--horizon`) and raises an
**early alert** ("Ammonia unsafe in ~1 h") while the value is still safe.
The reactive rule engine in `controller/` alerts only *after* a value has
crossed its limit.

```text
ESP32 ──POST──▶ controller (:8000) ──▶ SQLite readings ──read-only──▶ prediction service (:8001)
                     │  rule engine, actuators                          │  clean → models → alerts
                     └──────────── dashboard (React) ◀──────────────────┘
```

The prediction layer is a separate process. It only reads the controller's
database, so stopping it leaves monitoring untouched. A cause-analysis layer
can later call `live.forecast_tank()` directly.

| File | Step | What it does |
|---|---|---|
| `settings.py` | – | interval, lag window, horizon, plausibility limits |
| `data_prep.py` | 1 | raw logs → clean 10-min grid → lag-feature dataset |
| `models.py` | 2 | Persistence, LinearTrend, Ridge, GBoost (multi-step, direct) |
| `alerts.py` | 3 | time-to-breach logic, alert scoring; limits from `controller/config.yaml` |
| `evaluate.py` | 4 | held-out comparison: RMSE/MAE/MAPE/R²/skill per horizon + alert scores |
| `train.py`, `live.py`, `service.py` | 3/5 | fit on all data, live forecast, REST API |

## Run (from `water_quality/`, using `.venv`)

```bash
pip install -r requirements.txt
python -m prediction.data_prep      # step 1: cleaning report + outputs/prediction/clean_grid.csv.gz
python -m prediction.evaluate       # step 4: comparison tables (~10 s; ~4 min with --horizon 18)
python -m prediction.train          # fit deployed models -> outputs/prediction/models/
python -m prediction.service        # API on :8001  (GET /forecast?tank_id=pond1, /health, /docs)
python -m pytest prediction/tests
```

**Google Colab:** upload `water_quality/AquaSense_Prediction_Colab.ipynb` to
Colab and run all. It carries its own copy of this code, asks for the CSVs,
prints every table (incl. alert F1) and downloads the trained models. After
changing the code here, rebuild it with `python -m prediction.make_colab`.

Every script takes `--freq` (min), `--lags`, `--horizon` (steps), and either
`--db controller/controller.db --tank tank1` for your own logs or `--data` for
the CSVs. The dashboard finds the service at `<same host>:8001`; override it
with `VITE_FORECAST_URL`.

## Data preparation (step 1)

IoTPond logs every 20 s. Cleaning, per pond:
1. Drop ponds 10–12 (< 1k timed rows) and rows copied between ponds (pond 2 repeats pond 1 from July).
2. Values outside what live fish survive → missing (`PLAUSIBLE`).
3. Sensor stuck on one exact value > 1 h (12 h for temperature) → missing.
4. 10-min median bins (DO/ammonia need ≥ 3 raw readings, temperature/pH ≥ 1).
5. Trailing spike filter, fill gaps ≤ 30 min, trailing 3-step rolling median.

All grid filters look only backwards, so live data gets identical cleaning.

## Results (held-out test = latest 20% of the timeline; 10-min steps, 2-h window)

Skill = 1 − RMSE / RMSE(persistence). Above 0 means better than "nothing changes".

### Deployed setting: 10-min horizon (`horizon_steps = 1`)

| Parameter | Best model | Skill +10 min | Alert F1 (tuned margin) | F1 at plain limit | Precision / recall |
|---|---|---|---|---|---|
| Temperature | GBoost | +0.11 | **0.53** | 0.39 | 0.43 / 0.69 |
| Ammonia | GBoost | +0.09 | **0.57** | 0.53 | 0.60 / 0.55 |
| DO | GBoost | +0.07 | **0.42** | 0.42 | 0.49 / 0.37 |
| pH | GBoost | +0.08 | – | – | only 4 breaches in test |

The alert margin (see `alerts.py`) is tuned for F1 on validation data only.
Tried and rejected: a direct "will it breach?" classifier (F1 no better).
At 10 min, warnings can be at most 10 min early. A longer horizon is the biggest
F1 lever for temperature (0.50 → 0.71 at 30 min → 0.75 at 1 h, tuned margin),
while DO gets worse with horizon in this data (0.34 → 0.13 → 0.09).

### Comparison: 3-h horizon (`--horizon 18`)

| Parameter | Best model | Skill +1 h | Skill +3 h | R² +3 h |
|---|---|---|---|---|
| Temperature | GBoost | +0.30 | +0.44 | 0.96 |
| Ammonia | GBoost | +0.02 | +0.17 | 0.71 |
| DO | (Persistence) | GBoost −0.06 | GBoost −0.10 | 0.82 |
| pH | (Persistence) | Ridge −0.02 | Ridge −0.04 | 0.98 |

Early alerts (breach = 2 consecutive forecast steps outside the safe range,
counted only while the water is still safe):

| Parameter | Model | Precision | Breaches warned | Median earliest warning | Warned ≥ 1 h |
|---|---|---|---|---|---|
| Temperature | GBoost | 0.88 | 93% of 29 | 2.5 h | 90% |
| Ammonia | GBoost | 0.73 | 86% of 43 | 0.5 h | 28% |
| DO | GBoost | 0.53 | 66% of 86 | 0.5 h | 21% |
| DO | LinearTrend | 0.43 | 79% of 86 | 1.2 h | 41% |
| pH | – | – | only 2 breaches in test | – | – |

Persistence and the reactive engine warn 0% of breaches in advance.
Full tables: `outputs/prediction/metrics_by_horizon.csv`, `alert_metrics.csv`.

**Caveats:** IoTPond ammonia is mostly sensor garbage (values up to 10⁸;
10–63% removed per pond), and pH probes fail from August. Treat ammonia and
pH results as weak evidence until you have your own tank's logs. Retrain with
`--db` once you do.

## How much data each model needs (10-min steps)

| Model | Needs | Notes |
|---|---|---|
| Persistence / LinearTrend | none | works from the first 2 h of readings |
| Ridge | ~1–2 weeks continuous (1–2k rows) | few parameters, hard to overfit |
| GBoost | ~1–2 months (5–10k rows), incl. breach events | used here with 19k–54k rows pooled over 8 ponds |
| LSTM/GRU | 20–50k+ rows per parameter | not built: GBoost already wins where anything wins, and torch is not installed |
