# AquaSense Mobile App

Flutter application for AquaSense aquarium monitoring and appetite-aware
feeding.

## Current Authentication Behavior

MOB-004 connects the authentication interface to Google and the AquaSense API.
When a Google Web OAuth client ID is supplied, **Continue with Google** opens
the Android account chooser, sends the returned ID token to the backend, and
stores only the resulting AquaSense access and refresh tokens in encrypted
device storage.

If no Google client ID is supplied, development builds intentionally use the
local test owner from MOB-003. The sign-in screen clearly labels that mode.
After sign-in, an owner with no aquariums is guided through naming the first
aquarium and selecting its scheduling time zone. Returning owners enter the
last aquarium they selected on that device. Tap the aquarium name in the app
bar to switch workspaces or create another aquarium. Selections are stored per
signed-in user, verified against the backend before switching, and safely fall
back to another accessible aquarium when access has been removed.

Owners can open **Workers** from an aquarium home screen to invite a worker by
their verified Google email, review invitation status, revoke a pending
invitation, or remove a worker. Workers can open the aquarium team as a
read-only view and do not see owner-only controls. A matching invitation is
shown after the invited person signs in with Google; they can accept it before
creating their own aquarium or from the invitation indicator on an existing
aquarium home screen. AquaSense does not send invitation email yet.

Tap the grid icon on an aquarium home screen to open **Tank groups**. Owners
can add and rename flat groups and archive groups that contain no tanks.
Workers receive the same group list and tank counts as a read-only view.
Archived groups remain visible for operational history.

Open a group to view its daily feeding schedule in the aquarium timezone.
Owners can add or remove session times, enable automatic feeding, or pause it
without losing the configured times. Workers can inspect the same schedule
and its next stored UTC execution time, but all schedule controls are
read-only.

From an active tank's detail screen, owners can choose **Inherit group** or
**Tank override**. Inheritance always shows the group's current schedule; an
override is a complete tank-specific replacement rather than a partial merge.
Unassigned tanks remain paused until an owner supplies an override or assigns
the tank to a group. Workers can see the effective schedule and its source but
cannot edit it.

Use the scale action on a tank detail screen to preview its portion from the
detected or expected fish count. Previews use versioned, facility-wide feeder
units with minimum and maximum safety bounds. Owners can publish a new
calibration version; workers can inspect calculations but cannot change the
calibration. The app does not display physical mass because that conversion
has not yet been experimentally validated.

Open **Tanks** from the aquarium home screen to browse the paginated inventory.
Search by name or code, filter by current status, group, unassigned tanks, or
tag, and load further pages when required. Owners can add, edit, move, pause,
and archive tanks; workers receive the same inventory and detail information
without management controls. Each tank detail shows expected and detected
guppy counts, confidence and observation freshness, group and tags, automation
state, device status, schedule, recent feeding times, and activity. The
hardware section shows separate camera, edge-processor, and feeder states,
last heartbeats, health messages, and whether feeding is safety-blocked.
Owners can connect a component or rotate its heartbeat token; the token is
shown once for copying into that device. Workers have read-only health access.
Schedule, observation, and feeding sections clearly say when later-stage data
has not been configured yet.

When the edge processor submits an appetite observation, tank details show
the appetite result, detected count, confidence, observation time, and model
version. Stale, low-confidence, and expected-count mismatch reasons are shown
clearly, together with whether the observation is valid for a feeding
decision. Invalid data remains visible for review but does not replace the
tank's trusted detected count.

The aquarium home screen includes a live feeding-operations dashboard with
active tank totals, the next 24 hours of sessions, recent delivered, skipped,
blocked, and failed outcomes, and hardware that needs attention. Open
**History** for cursor-paginated records filtered by group, source, outcome,
or date. A tank's detail screen opens the same view already scoped to that
tank. Loading, empty, retry, refresh, and additional-page states are handled
without blocking the primary tank-navigation controls.

## Environments

Configuration is supplied with compile-time Dart defines. Do not place API
credentials or other secrets in source control.

Development uses the Android emulator host address by default:

```powershell
flutter run --dart-define=AQUASENSE_ENV=development
```

To use another backend address:

```powershell
flutter run `
  --dart-define=AQUASENSE_ENV=development `
  --dart-define=AQUASENSE_API_BASE_URL=http://192.168.1.10:8080
```

Real authentication requires both the backend address and the Google Web OAuth
client ID:

```powershell
flutter run `
  --dart-define=AQUASENSE_API_BASE_URL=http://192.168.1.10:8080 `
  --dart-define=AQUASENSE_GOOGLE_SERVER_CLIENT_ID=<Web OAuth client ID>
```

Production builds must additionally set
`--dart-define=AQUASENSE_ENV=production`; they reject missing API and Google
configuration at startup.

## One-time Google setup for Android

1. In Google Cloud, configure the OAuth consent screen.
2. Create an **Android OAuth client** for package `com.aquasense.mobile` and
   the SHA-1 fingerprint of the signing certificate.
3. Create a **Web application OAuth client**. Use that same Web client ID for
   the mobile `AQUASENSE_GOOGLE_SERVER_CLIENT_ID` define and backend
   `AQUASENSE_GOOGLE_CLIENT_ID` environment variable.

For the debug certificate fingerprint on Windows:

```powershell
keytool -list -v -alias androiddebugkey `
  -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -storepass android -keypass android
```

## Verification

```powershell
flutter analyze
flutter test
```

Development progress and decisions are recorded in
`../docs/MOBILE_APP_DEVELOPMENT.md`.

## Run on a Physical Android Phone

### One-time laptop setup

1. Enable **Developer Mode** in Windows under **Settings → System → For
   developers**. This lets Flutter create the plugin links used by local
   persistence.
2. Accept the Android SDK licenses:

   ```powershell
   flutter doctor --android-licenses
   ```

   Enter `y` for each license, then run `flutter doctor` and confirm that the
   Android toolchain is ready.
3. In Android Studio, install the **Flutter** plugin if it is not already
   installed. The Dart plugin is installed with it.

### Enable the phone

1. Open the phone's **Settings → About phone** and tap **Build number** seven
   times to enable Developer options.
2. Open **Developer options** and enable **USB debugging**.
3. Connect the phone with a USB data cable, choose **File transfer** if asked,
   and accept the RSA debugging prompt on the phone.

### Run from a terminal

From the `mobile_app` directory:

```powershell
flutter pub get
flutter devices
flutter run --dart-define=AQUASENSE_ENV=development
```

If more than one Android device is listed, pass the required device ID:

```powershell
flutter run -d <device-id> --dart-define=AQUASENSE_ENV=development
```

For real Google sign-in, start the backend first and replace `192.168.1.10`
with the laptop's Wi-Fi IPv4 address shown by `ipconfig`. The phone and laptop
must be on the same network. Allow Java through Windows Firewall if the phone
cannot reach port 8080. While the app is running, press `r` in the terminal for
hot reload or `R` for a full restart.

### Run from Android Studio

1. Open the `mobile_app` folder as the project.
2. Wait for Flutter dependency resolution and Android indexing to finish.
3. Select the connected phone in the device selector.
4. Open `lib/main.dart` and select **Run**.

If the phone is not listed, unlock it, reconnect the cable, confirm USB
debugging, and run `flutter devices` again. A phone-manufacturer USB driver may
also be required on Windows.

To test onboarding as a new user again, clear AquaSense's storage from the
phone's **Settings → Apps → AquaSense → Storage**, or uninstall and reinstall
the app. After onboarding, the temporary dashboard also has a help icon that
reopens the pages without clearing data.
