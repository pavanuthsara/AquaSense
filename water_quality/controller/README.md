# AquaSense — Threshold-based Reactive Baseline Controller

The **baseline** that the AquaSense predictive controller is compared against.
It monitors water quality, raises alerts when a parameter leaves its safe range,
and *reacts* by switching actuators (aerator, heater, pH dosing pump). It logs
everything needed to measure its resource use: every ON/OFF event, run-time per
actuator, an energy estimate, and the time each parameter spent out of range.

Current hardware: the ESP32 sends **temperature** only, and no actuators are wired.
Every sensor and actuator is pluggable, so the missing ones are simulated. You
replace a simulated one with real hardware by changing one word in `config.yaml`.

---

## 1. Quick start

```bash
cd water_quality/controller
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# build the React dashboard once (Node 20.19+; needs internet the first time)
cd web && npm install && npm run build && cd ..

cd ..                         # run everything from water_quality/
python -m controller          # -> http://127.0.0.1:8000
```

Open **http://127.0.0.1:8000** for the dashboard, and **http://127.0.0.1:8000/docs**
to try the API interactively.

### Working on the dashboard (React + Vite)

```bash
python -m controller          # terminal 1: backend on :8000 (from water_quality/)
cd controller/web && npm run dev   # terminal 2: http://localhost:5173 with hot reload
```

The Vite dev server proxies `/api` (including the live SSE stream) to `:8000`.
Run `npm run build` when you're done. FastAPI serves `web/dist` at `/`, so
no Node is needed to run the finished system.

## 2. Demo without hardware

In a second terminal (from `water_quality/`, venv active):

```bash
# Pretend to be the ESP32 (temperature only; DO/pH/ammonia simulated server-side)
python -m controller.tools.simulate                          # normal pond
python -m controller.tools.simulate --scenario cold_snap     # temp drops -> heater ON -> recovers -> OFF
python -m controller.tools.simulate --scenario do_crash      # DO falls -> aerator ON
python -m controller.tools.simulate --scenario sensor_fault  # random -127 °C readings are rejected

# Replay real IoTPond data (all 4 parameters "real")
python -m controller.tools.replay_csv --file data/IoTpond1.csv --tank pond1             # as fast as possible (~5 s for 83k rows)
python -m controller.tools.replay_csv --file data/IoTpond1.csv --tank pond1 --speed 3600 # 1 pond-hour per second, watch live
python -m controller.tools.replay_csv --tank pond1 --params temperature --speed 600      # mimic today's hardware
```

By default `simulate` plays one pond-hour per real minute (`--step 60 --interval 1`).
Pick the tank in the dashboard's top bar.

## 3. Connecting the ESP32

The ESP32 talks to the Mac **over Wi-Fi**. The USB cable is only for power,
flashing and the Serial Monitor.

1. Put the Mac and the ESP32 on the same Wi-Fi network.
2. Find the Mac's IP address: `ipconfig getifaddr en0` (e.g. `192.168.1.23`).
3. Start the server so other devices can reach it: `python -m controller --host 0.0.0.0`.
   If macOS asks whether to allow incoming connections, click **Allow**.
4. Have the ESP32 POST JSON to `http://<mac-ip>:8000/api/readings`.
   A ready-to-flash sketch (Wi-Fi reconnect, error messages on the Serial Monitor) is in
   [`firmware/aquasense_temp/aquasense_temp.ino`](firmware/aquasense_temp/aquasense_temp.ino).
   The minimal version:

```cpp
#include <WiFi.h>
#include <HTTPClient.h>
#include <OneWire.h>
#include <DallasTemperature.h>

const char* WIFI_SSID = "your-wifi";
const char* WIFI_PASS = "your-password";
const char* SERVER    = "http://192.168.1.23:8000/api/readings";   // your Mac's IP

OneWire oneWire(4);                     // DS18B20 data pin
DallasTemperature sensors(&oneWire);

void setup() {
  Serial.begin(115200);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  sensors.begin();
}

void loop() {
  sensors.requestTemperatures();
  float t = sensors.getTempCByIndex(0);   // -127 if unplugged: the server flags it as a FAULT

  HTTPClient http;
  http.begin(SERVER);
  http.addHeader("Content-Type", "application/json");
  String body = String("{\"tank_id\":\"tank1\",\"temperature\":") + String(t, 3) + "}";
  int code = http.POST(body);
  Serial.printf("POST %d %s\n", code, body.c_str());
  http.end();
  delay(5000);                            // one reading every 5 s
}
```

Payload format: any subset of the parameters is accepted.

```json
{"tank_id": "tank1", "timestamp": 1760000000, "temperature": 25.4, "do": 6.1, "ph": 7.2, "ammonia": 0.12}
```

- `timestamp` is optional: the server uses its own time if it is missing. Epoch seconds, epoch milliseconds or ISO-8601 all work.
- The aliases `temp`, `dissolved_oxygen`, `pH` and `tan` are also accepted.
- MQTT is supported too: set `mqtt.enabled: true` in the config and publish the same JSON to `aquasense/<tank_id>/readings`.

## 4. Configuration (`config.yaml`)

| What | Where | Values |
|---|---|---|
| Safe range | `parameters.<p>.min / max` | null means no limit on that side |
| Real or simulated sensor | `parameters.<p>.source` | `payload` (real), `simulated`, `auto` (real if sent, otherwise simulated), `derived` |
| Real or mock actuator | `actuators.<a>.driver` | `mock` (log only), `esp32_http` (+ `url`) |
| Control rules | `rules` | `below_min` / `above_max` / `out_of_range` → `hold` or `pulse` |
| Hysteresis | `parameters.<p>.deadband` | 0 means pure on/off control |
| WARNING → CRITICAL | `parameters.<p>.critical_margin` | distance beyond the limit |
| Sensor-fault filter | `parameters.<p>.valid_min / valid_max` | outside this range the value is a FAULT and never used for control |
| Data-outage watchdog | `data_gap_s` | see §7 |

Default safe ranges are typical for ornamental tropical fish: temperature 24–28 °C,
DO ≥ 5 mg/L, pH 6.5–8.0, TAN ≤ 0.5 mg/L, unionised NH₃ ≤ 0.05 mg/L.
Change them to suit your species.

**When the DO probe arrives:** set `do.source: payload` and send `"do"` from the ESP32.
**When the relays are wired:** set `aerator.driver: esp32_http` with `url: http://<esp32-ip>`,
then implement `POST /actuator` on the ESP32 (protocol in `actuators/esp32_http.py`).

Use another config or database without editing the file:
`AQUASENSE_CONFIG=my.yaml AQUASENSE_DB=runs/exp1.db python -m controller`.

## 5. The baseline control logic

```
for each reading:
    for each parameter: value → OK / WARNING / CRITICAL / FAULT / MISSING
    alerts: raise when a value goes out of range, escalate, clear when it is back in range
    if AUTO mode, for each rule:
        hold  (aerator, heater): out of range and OFF → ON
                                 ON and back inside the range by the deadband → OFF
        pulse (dosing pump):     out of range and cooldown elapsed → run 5 s, then 10 min lock-out
```

- **MANUAL mode:** alerts still fire, but the engine does not switch anything. The dashboard ON/OFF buttons are enabled. In AUTO mode they are disabled, so operator actions never mix with the baseline's own decisions.
- **Missing values and sensor faults never trigger an action.**
- High temperature and ammonia have no actuator, so they raise alerts only.

## 6. Architecture

```
ESP32 ──HTTP POST──┐                         ┌── engines/threshold.py   (BASELINE)
MQTT ──────────────┼─► services/ingest.py ───┤   engines/predictive.py  (future)
tools/simulate.py ─┤    │ sensors/ (real/sim/derived)
tools/replay_csv ──┘    │ core/ranges.py  → services/alerts.py
                        │ core/storage.py (SQLite)
                        └ actuators/ (mock | esp32_http) → run-time + energy log
                               ▲
web/ (React) ◄── api/routes.py (REST + Server-Sent Events)
```

```
controller/
├── config.yaml          safe ranges, real/simulated, rules
├── main.py, __main__.py app wiring / entry point
├── core/                config loader, data models, range classifier, sensor clock, SQLite storage
├── sensors/             payload (real), simulated (+ plant model), derived (NH₃)
├── actuators/           base bookkeeping, mock, esp32_http, manager
├── engines/             ControlEngine interface + ThresholdEngine (baseline)
├── services/            ingest loop, alerts, metrics, MQTT listener
├── api/                 REST routes
├── web/                 React + Vite dashboard
│   └── src/             App.jsx, api.js, hooks.js (SSE + throttled fetch),
│                        components/ (cards, Recharts history, actuators, alerts, metrics, logs)
├── tools/               simulate, replay_csv, export_metrics
└── tests/               pytest
```

The **engine** is the only part that will change for the predictive controller.
Ingestion, actuators, logging and metrics are shared, which keeps the comparison
like-for-like. To add it, subclass `ControlEngine` in `engines/`, register it in
`engines/__init__.py`, and set `engine: predictive`.

## 7. Measurement design (important for the comparison)

- **Sensor time, not wall-clock time.** All durations use the readings' own
  timestamps, so a 4-month CSV replayed in 5 seconds still reports run-time in
  real pond hours. Manual commands are stamped with the latest reading time.
- **Data-gap watchdog.** The IoTPond CSVs contain ~600 gaps longer than 15 min,
  some lasting days. Without a watchdog, an actuator that happened to be ON
  when the data stopped would accrue days of run-time. After `data_gap_s`
  (default 900 s) without data, running actuators are logged OFF and alerts are
  closed at *last reading + 900 s* (source `system`). The engine then decides
  afresh on the next reading. Metrics report `observed_s`, and % out-of-range
  uses observed time as its denominator.
- **Alerts are episodes.** One alert row per excursion (raised → cleared) with
  its peak value. Total time out of range is `Σ(cleared − raised)`.
- **Energy proxy.** `Wh = run-time × power_w` (rated power set in the config).

### Metrics

Shown on the dashboard, available from `GET /api/metrics`, and exportable from any run's database:

```bash
python -m controller.tools.export_metrics --db controller/controller.db --tank pond1 --csv baseline_pond1.csv
```

| Metric | Meaning |
|---|---|
| `actuators.*.runtime_s` / `switch_ons` / `energy_wh` | resource use |
| `parameters.*.excursions` / `critical_excursions` | how often the water left the safe range |
| `parameters.*.time_out_of_range_s` / `pct_time_out_of_range` | how long it stayed out |
| `parameters.*.sensor_faults` | rejected impossible readings |
| `response.<param>-><actuator>` | excursions acted on, and mean delay from alert to actuator ON |

For a reactive controller the delay is 0 by construction: it acts on the same
reading that crossed the limit, never earlier. The predictive controller's
advantage should show up as *fewer excursions and less time out of range for
the same or lower run-time*.

### Suggested experiment protocol

```bash
# 1. Baseline run: fresh database, fixed input
AQUASENSE_DB=runs/baseline_pond1.db python -m controller
python -m controller.tools.replay_csv --file data/IoTpond1.csv --tank pond1
python -m controller.tools.export_metrics --db runs/baseline_pond1.db --csv runs/baseline_pond1.csv
# 2. Predictive run: same CSV, same config.yaml (ranges), engine: predictive, its own DB
```

Raw data loads straight into pandas:

```python
import sqlite3, pandas as pd
con = sqlite3.connect("runs/baseline_pond1.db")
wide = pd.read_sql("SELECT * FROM readings WHERE tank_id='pond1'", con) \
         .pivot_table(index="ts", columns="parameter", values="value")
events = pd.read_sql("SELECT * FROM actuator_events", con)
```

## 8. Known limitations and things to state in the report

- **The simulated plant model** (DO, pH and ammonia drift; aerator, heater and dosing effects) only exists to demo the closed loop. Do not use it for results: compare the controllers on replayed real data.
- **In replay, actuators do not affect the water.** The data was recorded without your controller, so replay measures *how the controller would respond to that water*: its decisions, alerts and run-time. It cannot measure the effect of those actions on water quality. Closed-loop effects need the real tank, or a validated plant model.
- **Units in the IoTPond dataset.** DO and ammonia are labelled "g/ml". The values look like mg/L, but ammonia ranges up to 15+ (median ~0.46), and the DO signal is very noisy, jumping 4.5 → 15.8 mg/L within seconds. On `IoTpond1.csv` the baseline switches the aerator on 10,636 times because of that noise. That chatter is a genuine finding about reactive threshold control on noisy sensors, but check the units before you report thresholds.
- **One dosing pump, one direction.** pH out of range on *either* side triggers the dosing pump, as specified. In reality you would need an acid and a base pump: split the rule into `below_min` → base pump and `above_max` → acid pump once the hardware exists.
- **Manual actions** are stamped with the latest sensor time, not the moment the button was pressed.

## 9. Tests

```bash
cd water_quality
python -m pytest controller/tests -q
```

The tests cover:
- range classification and sensor faults
- hysteresis and pulse cooldown
- run-time in sensor time and the energy estimate
- the data-gap watchdog
- the alert lifecycle
- MANUAL vs AUTO mode
- simulated/derived parameter filling
- the NH₃ formula
- a REST API round trip
