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
| DIS-003 | Domain models, interfaces and disease info | DIS-001 | Not started |
| DIS-004 | Image preparation (letterbox) with tests | DIS-003 | Not started |
| DIS-005 | On-device TFLite classifier | DIS-004 | Not started |
| DIS-006 | Photo source (camera and gallery) | DIS-003 | Not started |
| DIS-007 | Disease check screen | DIS-005, DIS-006 | Not started |
| DIS-008 | Save results and history screen | DIS-002, DIS-007 | Not started |
| DIS-009 | Home screen entry and app wiring | DIS-007, DIS-008 | Not started |
| DIS-010 | Real-phone test with own fish | DIS-009 | Not started |

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
