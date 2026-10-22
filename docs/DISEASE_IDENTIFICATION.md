# AquaSense Disease Identification (Damith's component)

This file is the backlog and build plan for the image-based guppy disease check
in the AquaSense app. It sits next to `docs/MOBILE_APP_DEVELOPMENT.md` (the
feeding backlog) and uses the same working method, but its own `DIS-` task IDs
so the two backlogs don't clash.

## What the feature does

A farmer opens their aquarium in the app, taps **Check fish health**, takes or
picks a photo of one fish, and the phone tells them **Healthy**, **White spot**,
or **Not sure, take another photo**. The result is saved to the aquarium's
history on the backend, so everyone in that aquarium can see past checks.

## Key decisions (read before starting)

- **The model runs on the phone, not on the server.** The trained TFLite file is
  bundled with the app and run with the `tflite_flutter` package. This works
  offline at a farm and matches the project goal of on-site edge use. The
  Raspberry Pi version can reuse the same model later.
- **The backend stores results only, never photos.** Smaller, simpler, and no
  privacy questions about storing farm photos.
- **The model file.** `guppy_baseline_dynamic.tflite` (3.3 MB) and `labels.txt`
  (`healthy`, `white_spot`) from the Research Guppi project,
  `model/runs/final_2026-10-16/`. Model version string:
  `guppy-white-spot-2026-10-16`.
- **Image preparation must match training exactly** (see `predict_pi.py`):
  convert to RGB, letterbox to a square of the model's input size (keep the
  aspect ratio, pad with black, image centred), keep pixel values 0-255 (do
  **not** divide by 255; the model does its own scaling). Read the input size and
  type from the model at runtime instead of hard-coding them.
- **"Not sure" rule.** If the top score is below **0.6**, show "Not sure, take
  another photo" instead of a disease name. Keep 0.6 in one constant.
- **Honest wording.** The app says this is a screening aid, not a diagnosis. The
  model is overconfident, so show the result plainly and don't present the score
  as certainty.
- **Follow the existing app's patterns.** Feature folders
  (`lib/features/<name>/{domain,data,presentation}`), a repository interface with
  an HTTP version and a development (in-memory) version, `InheritedWidget`
  scopes for dependencies, `Idempotency-Key` on create requests, and fakes in
  `test/fakes/`. Look at `lib/features/facility/` as the model to copy.
- **Labels are not hard-coded into logic.** Read them from the labels file so
  swapping in a 3-class model (healthy / white spot / fin rot) later only means
  replacing two asset files and adding one entry to the disease info list.

## Task backlog

| ID | Task | Depends on | Status |
|---|---|---|---|
| DIS-001 | Setup: branch, docs, model assets, packages | — | Done |
| DIS-002 | Disease-check history API (backend) | — | Done |
| DIS-003 | Domain models, interfaces and disease info | DIS-001 | Done |
| DIS-004 | Image preparation (letterbox) with tests | DIS-003 | Done |
| DIS-005 | On-device TFLite classifier | DIS-004 | Done |
| DIS-006 | Photo source (camera and gallery) | DIS-003 | Done |
| DIS-007 | Disease check screen | DIS-005, DIS-006 | Done |
| DIS-008 | Save results and history screen | DIS-002, DIS-007 | Done |
| DIS-009 | Home screen entry and app wiring | DIS-007, DIS-008 | Done |
| DIS-010 | Real-phone test with own fish | DIS-009 | Not started |
| DIS-011 | Video check: models and setup | DIS-009 | Done |
| DIS-012 | Python reference fixtures | DIS-011 | Done |
| DIS-013 | Fish finder in Dart | DIS-012 | Done |
| DIS-014 | Fish crop classifier in Dart | DIS-012 | Done |
| DIS-015 | Tracker, per-fish vote, video answer | DIS-013, DIS-014 | Done |
| DIS-016 | Video source and frame extraction | DIS-011 | Not started |
| DIS-017 | Video check UI | DIS-015, DIS-016 | Not started |
| DIS-018 | On-device parity check, performance, docs | DIS-017 | Not started |

Give your agent one task at a time, in this order. After each task: run the
checks under "Verify every task", update the status and add a work-log entry at
the bottom of this file, the same way `MOBILE_APP_DEVELOPMENT.md` does.

## DIS-001 — Setup

- `git pull` on main first (MOB-005 and MOB-006 are already merged), then create
  a branch such as `disease-check`.
- Add this file as `docs/DISEASE_IDENTIFICATION.md` and add one line to the top
  of `MOBILE_APP_DEVELOPMENT.md` pointing to it.
- Copy the model into `mobile_app/assets/models/guppy_disease.tflite` and
  `mobile_app/assets/models/guppy_disease_labels.txt`, and list both under
  `flutter: assets:` in `pubspec.yaml`.
- Add packages: `flutter pub add tflite_flutter image_picker image` (use versions
  that work with Flutter 3.32.4, which CI uses).
- Android: `image_picker` needs camera permission for taking photos; follow its
  README for `AndroidManifest.xml`.

**Done when:** `flutter pub get`, `flutter analyze` and `flutter test` still pass
with no new code.

## DIS-002 — Disease-check history API (backend)

A finished version of this task, with tests passing, is in
`DIS-002-backend.patch`. Apply it with `git apply DIS-002-backend.patch` from the
repo root, or ask the agent to build it from this description.

- New package `com.aquasense.backend.disease` (model, repository, service, web),
  same layout as `facility`.
- Flyway `V3__create_disease_check_tables.sql`: table `disease_checks` with `id`,
  `facility_id` (FK, cascade delete), `checked_by_user_id`, `request_key`,
  `predicted_label`, `confidence` (0-1), `uncertain`, `model_version`, optional
  `tank_label` and `note`, `checked_at`, `created_at`; unique
  `(checked_by_user_id, request_key)`; index on `(facility_id, checked_at DESC)`.
- `POST /api/v1/facilities/{facilityId}/disease-checks` with an `Idempotency-Key`
  header: same key and same body returns the original (200), same key with a
  different body returns 409 `idempotency_conflict`.
- `GET /api/v1/facilities/{facilityId}/disease-checks?limit=20`: newest first,
  limit 1-100.
- Only members of the aquarium can read or write (reuse `FacilityService.get`,
  which returns 404 `facility_not_found` otherwise).
- Validation: label matches `[a-z][a-z0-9_]{0,39}`, confidence 0-1, `checkedAt`
  not in the future (5 minutes of clock slack). Store `checkedAt` to the
  millisecond so retries compare equal.
- Integration tests like `FacilityApiIntegrationTests`: needs login, record and
  list newest first, retry gives no duplicate, key conflict, bad input, another
  user gets 404.

**Done when:** `mvnw test` passes (25 tests with the patch).

## DIS-003 — Domain models, interfaces and disease info

In `lib/features/disease_check/domain/`:

- `DiseasePrediction`: list of (label, score), top label, confidence,
  `isUncertain`, model version, time taken.
- `DiseaseCheckRecord`: a saved check as the backend returns it.
- `DiseaseClassifier` interface: `Future<DiseasePrediction> classify(Uint8List
  imageBytes)` and `dispose()`.
- `DiseaseCheckRepository` interface: `saveCheck(facilityId, prediction,
  tankLabel, note, idempotencyKey)` and `listChecks(facilityId, limit)`, plus a
  `DiseaseCheckException` like `FacilityException`.
- `FishPhotoSource` interface: `takePhoto()` and `pickFromGallery()`, each
  returning image bytes or null if cancelled.
- `DiseaseInfo` list: for each label, a display name, a one-line description, a
  colour/icon, and short plain advice. Example for white spot: small white dots
  like salt grains on the body and fins; separate the fish if you can, raise the
  temperature slowly, and ask an expert about treatment. Unknown labels fall back
  to the raw label name.

**Done when:** it compiles and `flutter analyze` is clean (no UI yet).

## DIS-004 — Image preparation with tests

In `lib/features/disease_check/data/image_preprocessor.dart`, a pure Dart
function using the `image` package: decode bytes, fix the photo's rotation from
its EXIF data, convert to RGB, letterbox to `size x size` (keep aspect ratio,
black padding, centred), and return a flat `Float32List` (or `Uint8List` for a
uint8 model) of length `size*size*3`, values 0-255.

Tests in `test/disease_image_preprocessor_test.dart`:

- a wide image gets black bars top and bottom, a tall one left and right;
- the output length and value range are right;
- a corrupt file gives a clear error, not a crash.

Optional but good for the thesis: dump the prepared tensor for one fish photo and
run the same photo through `predict_pi.py`; the two scores should agree to about
0.01. This shows the phone sees the image the same way as training.

**Done when:** the new tests pass.

## DIS-005 — On-device TFLite classifier

`lib/features/disease_check/data/tflite_disease_classifier.dart`:

- Load the model lazily on the first check with `Interpreter.fromAsset`, and the
  labels from the labels asset.
- Read input shape and type from `interpreter.getInputTensor(0)`.
- Run image preparation in a background isolate (`compute`) so the screen doesn't
  freeze, then `interpreter.run`.
- Turn the output into `DiseasePrediction`, applying the 0.6 rule.
- `dispose()` closes the interpreter.

Widget tests can't load the native TFLite library, so tests use a
`FakeDiseaseClassifier` in `test/fakes/`. This class is checked on a real phone
in DIS-010.

**Done when:** it compiles, analyze is clean, and the Android debug APK builds.

## DIS-006 — Photo source

`lib/features/disease_check/data/image_picker_photo_source.dart` implements
`FishPhotoSource` with `image_picker`. Ask for a reduced size
(`maxWidth`/`maxHeight` about 1024, quality about 90) so a 12 MP photo doesn't
slow the phone down; the model only needs a small image. Add a
`FakeFishPhotoSource` in `test/fakes/`.

**Done when:** it compiles and analyze is clean.

## DIS-007 — Disease check screen

`lib/features/disease_check/presentation/disease_check_screen.dart`, with these
states:

- **Start:** short tips ("one fish, close up, filling most of the photo, good
  light, no glare"), and two buttons: **Take photo** and **Choose from gallery**.
- **Checking:** the photo with a progress indicator.
- **Result:** the photo; a result card with the disease name, colour and icon,
  the description and advice from `DiseaseInfo`; scores for each label as small
  bars; optional tank name and note fields; **Save to history** and **Check
  another fish** buttons.
- **Not sure:** same as result but says "Not sure, take another photo" and
  repeats the photo tips.
- **Error:** model or photo failed, with **Try again**.

Always show the line "Screening aid only, not a diagnosis."

Widget tests with the fakes: healthy result, white spot result, not sure result,
cancelled photo goes back to start, classifier error shows retry.

**Done when:** the tests pass.

## DIS-008 — Save results and history screen

- `HttpDiseaseCheckRepository` (copy the shape of `HttpFacilityRepository`:
  bearer token, `Idempotency-Key`, error mapping) and
  `DevelopmentDiseaseCheckRepository` (in memory, used when there is no Google
  client ID, like the other development repositories).
- **Save to history** sends the result with a new key; a retry after a failure
  reuses the same key so nothing is saved twice. Show a snackbar on success and a
  retry message on failure.
- `disease_history_screen.dart`: list of past checks for the selected aquarium
  (date and time, result chip, tank, who checked, note), with empty, loading and
  error states, and pull to refresh.
- Tests: HTTP repository test with a mock client (like
  `http_facility_repository_test.dart`), save retry keeps the key, history shows
  items newest first, empty state.

**Done when:** the tests pass.

## DIS-009 — Home screen entry and app wiring

- Add a `DiseaseCheckScope` (classifier, repository, photo source) and create
  them in `bootstrap.dart` next to the facility repositories. Make the new
  `AquaSenseApp` parameters optional so the existing tests keep working.
- On `FacilityHomeScreen`, add a **Check fish health** card under the summary
  cards that opens the check screen, and a **History** link. Use the
  `SelectedFacilityScope` facility ID for saving and listing.
- Keep the change to the teammate's home screen small, and mention it in the PR
  so they know.
- Test: from the home screen, tap the card and see the check screen.

**Done when:** all mobile tests pass, the debug APK builds, and the CI workflow
(format, analyze, test, build) would pass.

## DIS-010 — Real-phone test with own fish

- Install the debug APK on an Android phone (development sign-in works without
  Google setup).
- Photograph 10-20 of your own fish (healthy, and any with white spot), one fish
  filling the frame. Note what the app says for each, how long a check takes, and
  any wrong answers.
- Record the results in the work log. This is your fair test on fish the model
  has never seen, and it is useful for the thesis and viva.

**Done when:** results are written down here.

## Later tasks (not now)

- **DIS-011 Fin rot:** when the 3-class model is ready, replace the two asset
  files, add fin rot to `DiseaseInfo`, update the model version string.
- **DIS-012 Tank link:** when tanks exist (MOB-009), replace the free-text tank
  name with a tank picker.
- **DIS-013 Raspberry Pi camera:** the Pi runs the same model and posts results to
  the same history API.
- **DIS-014 Severity:** low / medium / high, once there is enough low-severity
  data.

## Verify every task

Mobile (from `mobile_app/`):

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

Backend (from `backend/`): `mvnw test`.

## How to explain it in the thesis or viva

The phone takes a photo and prepares it the same way the training images were
prepared: square, fish centred, black padding, pixel values unchanged. The
MobileNetV3 model inside the app gives a score for each class. If the best score
is below 0.6 the app says it isn't sure and asks for a better photo. Otherwise it
shows the class with plain advice. Only the result (class, score, model version,
time, optional tank and note) is sent to the AquaSense backend, which stores it
per aquarium and only shows it to members of that aquarium. Running the model on
the phone means the check works offline at a farm, and the same model file can
run on a Raspberry Pi later.

## Work log

### 2026-10-22 — DIS-015: Tracker, per-fish vote and video answer — Done

- `domain/video_check_result.dart`: `VideoAnswer`, `VideoFishResult`,
  `VideoCheckResult` (overall answer, per-fish list with id/answer/mean/frames/
  thumbnail, counts, noFishSeen).
- `domain/video_check_analyzer.dart`: `verdict`, `fishAnswer` (0.6 average AND
  >=50% of frames at 0.6), `videoAnswer`, `sameFish` (IoU>0.2 or centres within
  0.75x the larger side), and `VideoCheckAnalyzer` that follows each fish across
  frames exactly as the main loop of check_video.py (first track with
  `n-last<=3 and last!=n and sameFish`, else new id). Keeps the best-scoring
  crop thumbnail per fish.
- Tests `test/video/video_check_analyzer_test.dart`:
  - hand-made: one confident frame cannot decide, 3-frame minimum, gap of 4
    starts a new track, same-frame boxes never merge, too-small joins without a
    score, verdict/video-answer rules.
  - **replay**: reads `checked.csv`, reconstructs the true frame number from
    `time_s` (frames with no detections are omitted from the CSV, so
    `n = round(t/0.5)+1` and empty frames are fed as `[]`), and reproduces the
    SAME fish id for every row and the SAME 8 per-fish answers and video answer
    as `expected_answers.json` (WHITE SPOT FOUND; fish 1/4/5/8/14 white spot,
    9/13 not sure, 16 healthy).
- Photo mode untouched. `dart format`/`analyze` clean, `flutter test` 114
  passed. Next: DIS-016 (video source and frame extraction).


### 2026-10-22 — DIS-014: Fish crop classifier in Dart — Done

- `domain/fish_crop_classifier.dart`: `FishCropResult` (whiteSpotScore,
  isNotFish, probs) and the `FishCropClassifier` interface.
- `data/crop_preprocessor.dart`: `cropBoxWithMargin` (12% margin, truncate +
  clamp), `cropRegion`, `prepareCropInput` (AREA/average resize, BLACK pad,
  floor centring, float 0..255, NHWC), `whiteSpotScoreFrom` (renormalised over
  healthy+white_spot), `isNotFishFrom` (argmax == not_fish).
- `data/tflite_fish_crop_classifier.dart`: loads `guppy_video_model.tflite` +
  labels, checks 3 outputs == 3 labels, preprocess in an isolate, returns the
  renormalised score and not_fish flag.
- Tests `test/video/fish_crop_parity_test.dart`:
  - `cropBoxWithMargin` == Python `crop_box` for every fixture box, plus a
    border clamp/truncate case.
  - `prepareCropInput` vs `crop_input_k_j.png` mean abs diff **0.91 / 0.95 /
    0.79** (budget 2.0).
  - `whiteSpotScoreFrom(probs)` == saved score within 1e-6; `isNotFishFrom`
    matches; argmax rule unit test.
- Photo mode untouched. `dart format`/`analyze` clean, `flutter test` 104
  passed. Next: DIS-015 (tracker, per-fish vote, video answer).


### 2026-10-22 — DIS-013: Fish finder in Dart — Done

- `domain/`: `DecodedFrame` (RGB bytes + size + timeMs, isolate-safe),
  `FishBox` (x0,y0,x1,y1,score with IoU), `FishDetector` interface.
- `data/detector_preprocessor.dart`: `prepareDetectorInput` — letterbox to 512,
  grey-114 pad, floor centring, linear resize, RGB /255, **NCHW**. Top-level for
  `compute`.
- `data/detection_decoder.dart`: `decodeDetections` (conf filter, conditional
  *512 scaling, letterbox-inverse mapping, truncate+clamp) and a public
  `nonMaxSuppression` / `rectIou` matching `cv2.dnn.NMSBoxes`.
- `data/tflite_fish_detector.dart`: lazy load, checks NCHW 512 input and a
  size-5 output axis (transposes `[N,5]` to `[5,N]`), preprocess in an isolate.
- Tests `test/video/fish_detector_parity_test.dart` (pure Dart, fixtures):
  - `prepareDetectorInput` vs `det_input_k.png` mean abs pixel diff **1.55 /
    0.49 / 0.46** (budget 2.0); padding placement checked.
  - `decodeDetections(det_output_k.bin)` == `boxes_k.json` within 1 px, exact
    count and order, all 3 frames.
  - NMS unit tests (overlap drop, disjoint keep, below-threshold keep).
- Photo mode untouched. `dart format`/`analyze` clean, `flutter test` 93 passed
  (11 new). Next: DIS-014 (fish crop classifier).


### 2026-10-22 — DIS-012: Python reference fixtures — Done

- `tools/make_video_fixtures.py` imports the real `FishFinder` and `SpotModel`
  from `video_check/check_video.py` and the v5 models from the `1_models`
  folders, and writes parity fixtures to
  `mobile_app/test/fixtures/video_parity/`.
- Installed `ai-edge-litert`, `opencv-python-headless`, `numpy` locally to run
  the reference (not committed).
- Clip used: the owner's own tank video `WhatsApp Video 2026-10-16 at
  11.34.27.mp4` (no white-spot TikTok clip was on this machine; a healthy clip
  would work for pixel parity too, but this one exercises white-spot paths). No
  video file is committed.
- Fixtures (2.63 MB total, under the 3 MB budget): `frame_{1..3}.png`
  (720x1280), `det_input_{k}.png` (512x512), `det_output_{k}.bin`
  (5x5376 float32 LE), `boxes_{k}.json`, `crop_input_{k}_{j}.png` (224x224),
  `crops_{k}.json` (probs, white-spot score, not_fish), `checked.csv`,
  `expected_answers.json`, `manifest.json`.
- The three sampled frames have 1 box each (pixel parity); the full-run
  `checked.csv` has 80 frames and 8 tracked fish for the DIS-015 replay test.
- **Reference per-fish answers** (from check_video.py, the targets Dart must
  reproduce): fish 1 white spot (0.94/30), 4 white spot (0.99/3), 5 white spot
  (0.73/5), 8 white spot (0.70/6), 9 not sure (0.64/3), 13 not sure (0.48/3),
  14 white spot (0.96/7), 16 healthy (0.38/6). **Video answer: WHITE SPOT
  FOUND** (5 white spot, 1 healthy, 2 not sure). Reference speed: 179 ms/frame
  on the laptop CPU.
- Next: DIS-013 (fish finder in Dart).


### 2026-10-22 — DIS-011: Video check models and setup — Done

- Branch `feature/video-disease-check` off `feature/disease-identification`.
- Copied the two video-pipeline models into `mobile_app/assets/models/` and
  verified md5s against the source `1_models` folders:
  - `fish_detector.tflite` (YOLO11n fish finder) `a915e2bbac39c4cc911df2da90b06dad`
  - `guppy_video_model.tflite` (v5 3-class) `bf01e88db3b0843dbfc178e033463c08`
  - `guppy_video_labels.txt` = healthy / not_fish / white_spot
  All three registered under `flutter: assets:` and confirmed not git-ignored.
- Added version constants `videoModelVersion = 'guppy-video-v5-2026-10-19'` and
  `fishFinderVersion = 'fish-finder-yolo11n-2026-10-19'` next to
  `bundledModelVersion`.
- New `domain/video_check_settings.dart` holds every pipeline constant
  (PAD 0.12, SURE 0.6, MIN_FISH_PX 48, MIN_FRAMES 3, finder conf 0.4, NMS IoU
  0.5, 2 fps, track gap 3, input sizes 512/224), each pointing to its
  counterpart in `check_video.py`.
- `assets/models/README.md` documents each model, its source and md5.
- Photo mode untouched. Checks: `dart format` clean, `flutter analyze` clean,
  `flutter test` 82 passed.
- Read `video_check/check_video.py` fully first; it is the reference. One note
  to flag (below). Next: DIS-012 (Python fixtures).

**Note on check_video.py vs the task spec:** they agree. The default white-spot
model in the script is already `guppy_video_model.tflite` with
`labels_video.txt`, and the finder's box-scaling is conditional
(`multiply by 512 only when values <= 2.0`), both matching the spec. The crop
classifier reads the model's own input dtype and does not divide by 255, as the
spec states for the v5 float model. No disagreements found so far.


### 2026-10-19 — DIS-002: Disease-check history API (backend) — Done

- Built from the task description (the patch file was not on disk); same shape as
  the supplied patch.
- Files: `backend/src/main/java/com/aquasense/backend/disease/{model,repository,service,web}`,
  `V3__create_disease_check_tables.sql`, `ApiExceptionHandler` (new handler),
  `DiseaseCheckApiIntegrationTests`, `backend/README.md`.
- Tests: `mvnw test` on JDK 22, 25 tests, 0 failures (6 new disease-check tests).
- Next: DIS-001.

### 2026-10-19 — DIS-001: Setup — Done

- Branch: `feature/disease-identification`, rebased onto `origin/main` (includes
  MOB-005, MOB-006 and CI).
- Model assets copied from `Downloads/RP Test/` to
  `mobile_app/assets/models/guppy_disease.tflite` (3.3 MB) and
  `guppy_disease_labels.txt` (`healthy`, `white_spot`); both listed in
  `pubspec.yaml`.
- Packages added: `tflite_flutter ^0.12.1`, `image_picker ^1.2.1`, `image ^4.12.0`.
- Android: no `AndroidManifest.xml` change. The `image_picker` README requires no
  Android configuration (it opens the system camera app); only iOS needs usage
  descriptions. Adding a `CAMERA` permission would then require a runtime
  prompt, so it was left out.
- Toolchain (local only): Flutter 3.32.4, JDK 17, Android SDK 36 installed under
  `D:\dev`. Windows Developer Mode must be on for plugin symlinks.
- Tests: see the verification results in the commit for this task.
- Next: DIS-003.

### 2026-10-20 — DIS-003: Domain models, interfaces and disease info — Done

- Merged `main` into this branch first (MOB-007 to MOB-014). The disease-check
  migration became `V10__create_disease_check_tables.sql`, because main
  already uses V3 to V9. Backend: 49 tests pass.
- Added `lib/features/disease_check/domain/`: `DiseasePrediction` (scores
  sorted highest first, the 0.6 "not sure" rule, bundled model version),
  `DiseaseCheckRecord`, the `DiseaseClassifier`, `DiseaseCheckRepository`
  and `FishPhotoSource` interfaces, and `DiseaseInfo` (plain advice for each
  label, with a readable fallback for new labels such as fin rot).
- Tests: `test/disease_prediction_test.dart` (4 tests). Analyze is clean.
- Next: DIS-004.

### 2026-10-20 — DIS-004: Image preparation with tests — Done

- Added `lib/features/disease_check/data/image_preprocessor.dart`: decode,
  turn upright from EXIF, shrink so the longer side is the model size, centre
  on a black square, return RGB values 0-255 (not divided by 255). Same steps
  and rounding as `ImageOps.pad` in `predict_pi.py`. It is a top-level
  function so it can run in a background isolate.
- Tests: `test/disease_image_preprocessor_test.dart` (5 tests: wide and tall
  letterboxing, value range, uint8 output, corrupt file).
- Parity check against `predict_pi.py`: 13 photos (7 white spot, 6 healthy;
  sizes 170 px to 1280x720) were prepared by this Dart code and by Pillow, and
  both tensors were run through the bundled model. Every photo got the same
  answer; the largest score difference was 0.0001. Pixels differ by 1-8 out of
  255 on average, because Pillow smooths more when shrinking big photos; the
  model is not sensitive to this.
- Next: DIS-005.

### 2026-10-20 — DIS-005: On-device TFLite classifier — Done (APK build still to check)

- Added `lib/features/disease_check/data/tflite_disease_classifier.dart`. It
  loads the model and labels on the first check (not at app start), reads the
  input size and type from the model, prepares the photo in a background
  isolate with `compute`, runs the model, and returns a `DiseasePrediction`.
  It refuses a labels file that doesn't match the model's number of outputs,
  and allows a retry if loading failed.
- The input is written straight into the input tensor's bytes, so no large
  nested Dart lists are built.
- Tests: `test/tflite_disease_classifier_test.dart` (float and quantised
  output decoding). Widget tests cannot load native TFLite, so the class itself
  is checked on a real phone in DIS-010.
- Not checked: `flutter build apk --debug`. The cloud machine that wrote this
  task cannot download the Android SDK. Run it on your PC; CI also builds the
  APK.
- Next: DIS-006.

### 2026-10-20 — DIS-006: Photo source — Done

- Added `ImagePickerPhotoSource` (camera and gallery through `image_picker`).
  Photos are shrunk to at most 1024 px while picking, so the check stays fast.
  Camera or gallery errors become a `FishPhotoException` with a plain message.
- Added test fakes: `FakeFishPhotoSource` and `FakeDiseaseClassifier` (used by
  the screen tests in DIS-007).
- Analyze is clean.
- Next: DIS-007.

### 2026-10-20 — DIS-007: Disease check screen — Done

- Added `DiseaseCheckController` (start, checking, result, error) and
  `DiseaseCheckScreen`. Start shows photo tips and **Take photo** /
  **Choose from gallery**. A result shows the photo, the answer in a coloured
  card (teal for healthy, red for a disease, grey for not sure), the
  description and advice from `DiseaseInfo`, and a score bar for each label.
  A score under 0.6 shows **Not sure, take another photo** and repeats the
  tips. Errors offer **Try again** with the same photo. The line "Screening
  aid only, not a diagnosis" is always shown.
- The screen takes an optional `resultActionsBuilder`, used in DIS-008 to add
  saving.
- Tests: `test/disease_check_screen_test.dart` (8 tests: start screen, white
  spot, healthy, not sure, cancelled camera, model error and retry, camera
  error, check another fish).
- Next: DIS-008.

### 2026-10-20 — DIS-008: Save results and history screen — Done

- Added `HttpDiseaseCheckRepository` (same shape as `HttpFacilityRepository`:
  bearer token, `Idempotency-Key`, server error codes) and
  `DevelopmentDiseaseCheckRepository` (in memory, for builds without a Google
  client ID). Only the result is sent; blank tank and note fields are left out.
- Added `SaveDiseaseCheckPanel`: optional tank and note, **Save to history**.
  The request key is made once per result and reused on retry, so a failed and
  retried save is stored once.
- Added `DiseaseHistoryScreen`: newest first (up to 50), result chip, score,
  time, tank, who checked, note; loading, empty and error states; pull to
  refresh.
- Tests: `test/disease_check_history_test.dart` (7 tests: HTTP save, list and
  errors, missing session, development retry, save retry keeps the key,
  history order and filtering by aquarium, empty and error states).
- Next: DIS-009.

### 2026-10-20 — DIS-009: Home screen entry and app wiring — Done

- Added `DiseaseCheckScope` (classifier, repository, photo source) above
  `MaterialApp` in `app.dart`. The three new `AquaSenseApp` parameters are
  optional, so existing tests did not change. `bootstrap.dart` uses the HTTP
  repository with real sign-in and the in-memory one otherwise. The model is
  still only loaded on the first check.
- Added `FishHealthCard` (**Check fish health** and **History**). It finds the
  selected aquarium and the disease parts through scopes, so the change to the
  shared `facility_home_screen.dart` is one import and two lines under the
  tanks panel.
- Tests: `test/disease_check_flow_test.dart` (home, check, save with tank
  name, history).
- Full checks: `dart format` clean, `flutter analyze --fatal-infos` clean,
  `flutter test` 82 passed (27 of them new), backend `mvnw test` 49 passed.
  `flutter build apk --debug` was not run (no Android SDK on the cloud
  machine); run it on your PC.
- Next: DIS-010 (real-phone test with your own fish).
