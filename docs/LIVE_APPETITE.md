# Live behavior extraction and appetite inference

Run these commands from the AquaSense repository root with the research
virtual environment active. Start DroidCam and use the camera index and
capture backend that already show your tank correctly.

## 1. Train and export the live model

```powershell
python train_live_rf.py
```

This reads `output/poc_features.csv`, keeps labeled PRE (before feeding)
10-second windows, and exports `models/random_forest_live_pre.joblib`.
It uses four measurements already calculated by `SegmentStats`:

| Input | Meaning |
| --- | --- |
| `avg_speed_norm_per_sec` | Mean tracked displacement per second, normalized by the tank crop |
| `upper_zone_pct` | Percentage of detections in the upper third of that crop |
| `mean_group_distance_norm` | Mean pairwise spacing, normalized by the crop |
| `direction_change_fraction` | Fraction of valid direction checks that turn at least 45 degrees |

The target is `HIGH` or `LOW`, derived from `appetite_label`. Neither response
latency nor FEED/POST measurements are inputs. `train_rf_v3.py` requires those
later measurements and cannot be used as this PRE-window model. The existing
training experiments are unchanged.

Evaluation holds out one complete session at a time. Missing feature values
are imputed inside each training fold, not from held-out sessions. After
evaluation, a final pipeline is fitted on the usable PRE windows and saved
with its feature order and window settings. Class names are saved directly;
inference does not assume a numeric class means High.

On the current dataset (eight sessions: six High, two Low), evaluation used
162 usable PRE windows. Held-out session accuracy was 4/8 (50%), balanced
accuracy 33.3%, and neither Low session was recognized. This is a local
integration demonstration, not a reliable feeding decision model. It needs
more independent labeled sessions and better discrimination of Low appetite.
Multiple windows from eight sessions do not constitute independent new trials.

## 2. Inspect features without appetite inference

```powershell
python byteTrack.py --source 1 --backend msmf --extract-behavior
```

Use your working `--backend` and `--source` values if different. Camera
detections are sampled at approximately 5 FPS; each completed 10-second
window produces one feature row. Live timing uses elapsed capture time,
not a presumed webcam FPS. Frames are read between samples to reduce backlog.

By default behavior mode uses `--imgsz 960 --conf 0.20`, matching the current
offline extractor settings. Plain tracking mode keeps its previous 640/0.25
defaults. Processing needs to keep up with approximately 5 samples per second.

Match the camera framing, tank crop, orientation, lighting, and detection
settings used to create your training CSV. A webcam bridge can change video
resolution; pixel crop coordinates must fit the actual incoming frame.
Pass `--crop LEFT TOP RIGHT BOTTOM` to crop to the same tank area. Upper zone
is measured relative to this crop. Optional `--feed-zone X_MIN Y_MIN X_MAX
Y_MAX` logs feeding-zone behavior, but it is not an input to this model.

## 3. Run live appetite inference

```powershell
python byteTrack.py --source 1 --backend msmf --rf-model models/random_forest_live_pre.joblib
```

The preview collects the first complete window, then displays the predicted
appetite and model probability for the last completed window. These are PRE
estimates: stop this run when adding food. Training on PRE does not establish
that the model works during or after feeding. A probability is not measured
accuracy or a calibrated guarantee.

The monitor reuses the offline `SegmentStats` implementation. For every YOLO
box it supplies the ByteTrack ID and center coordinates normalized to the
current crop. The model sees only the four ordered numeric features. Missing
turn or group-spacing values use the fitted training imputer.

Windows without valid speed measurements or with less than 50% tracking
coverage are marked `INSUFFICIENT_DATA`. Live windows also need at least 25
samples (half the nominal 50). These are basic engineering checks, not validated
appetite thresholds. A long capture stall invalidates a pending old window.
No detections are never converted into a Low appetite prediction. Incomplete
windows are discarded when you stop. Press Q or Esc to stop.

Features and results are written to a unique `output/live_behavior_*.csv`
file. `predicted_appetite` is kept separate from ground-truth `appetite_label`.
To select another output file, pass `--feature-output output/my_live_test.csv`;
an existing file is not overwritten. The CSV includes speed, zones, spacing,
turning, visibility, tracking coverage, sample count, and prediction status.

## 4. Check appetite from the mobile app

The tank detail screen has a **Check current appetite** button. It creates
a tank-scoped request, waits for the laptop to collect a fresh 10-second PRE
window, and displays the returned High/Low label, model probability, and time.
The app shows separate waiting, observing, insufficient-data, and failure states.
An unanswered request expires after 60 seconds. Repeated taps or simultaneous
requests for the same tank share its active check.

1. Rebuild/start the local backend so the appetite-check endpoints and database
   migration are applied. With the root `.env` already configured, run from
   the repository root:

   ```powershell
   docker compose --env-file .env -f backend/compose.yaml up --build -d backend
   ```

2. Run the mobile app and sign in with email/password or Google. The app uses
   the backend by default; Google configuration is optional. The explicit
   `AQUASENSE_USE_DEVELOPMENT_AUTH=true` mode uses demo data instead of live
   appetite checks. Use `http://10.0.2.2:8080` only from an Android emulator,
   or `http://YOUR_LAPTOP_LAN_IP:8080` from a physical phone on the same LAN.
   For a USB-connected phone, forward port 8080 using `adb reverse tcp:8080 tcp:8080`
   and use `http://127.0.0.1:8080` instead.
   Restart the app with your existing Dart defines after updating its code.

3. In that tank's hardware controls, connect/provision **Edge processor**.
   Copy the device ID and one-time token. The laptop is the edge processor for
   this prototype. Each camera process serves only its assigned tank. Do not
   rotate credentials on each check; keep the same provisioned credentials.

4. Set the credentials in the same PowerShell terminal that runs Python:

   ```powershell
   $env:AQUASENSE_EDGE_DEVICE_ID = 'YOUR_PROVISIONED_EDGE_DEVICE_ID'
   $env:AQUASENSE_EDGE_DEVICE_TOKEN = 'YOUR_ONE_TIME_DEVICE_TOKEN'
   python byteTrack.py --source 1 --backend msmf --rf-model models/random_forest_live_pre.joblib --serve-appetite-checks --api-base-url http://localhost:8080
   ```

   Keep your working camera source/backend and training crop options. Tokens
   are read from the environment and are not printed. The Python worker polls
   the API in a background thread so network delays do not block camera frames.

5. Open **Tanks**, tap the same tank, and tap **Check current appetite** in the
   **Current appetite** card near the top of the detail screen.
   Keep the camera steady and wait about 10–15 seconds. The request discards the
   worker's current partial behavior window and starts a new one; it never
   returns an old CSV value as a fresh model result. Keep the camera app open on
   the iPhone; view AquaSense on your emulator/another device in this setup.

These research check results do not create trusted feeding observations or
trigger feeding. The existing automatic feeding observation API is separate.
The current model's weak evaluation is disclosed alongside results in the app.

The authenticated mobile API is:

- `POST /api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-checks`
- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-checks/{checkId}`

The worker API uses the provisioned `X-Device-Id` / `X-Device-Token` headers:

- `GET /api/v1/device-appetite-checks/next` (204 if no check is pending)
- `POST /api/v1/device-appetite-checks/{checkId}/result`

Only facility members can request/read checks. Only the tank's authenticated
edge processor can submit its result. Missing camera data returns no appetite
label; old/expired checks cannot be revived by a delayed response.

## Verify without a camera

```powershell
python -m unittest discover -s tests -p test_live_behavior.py
```
