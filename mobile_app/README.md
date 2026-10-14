# AquaSense Mobile App

Flutter application for AquaSense aquarium monitoring and appetite-aware
feeding.

## Current Authentication Behavior

MOB-003 provides the complete authentication interface, state management, and
encrypted access/refresh-token storage. Development builds intentionally use a
local test owner when **Continue with Google** is selected. No Google account
data is requested yet.

Real Google identity verification and AquaSense backend token exchange belong
to MOB-004. The development notice on the sign-in screen makes this distinction
visible while testing on a phone.

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

Production builds must explicitly provide `AQUASENSE_API_BASE_URL`:

```powershell
flutter build apk `
  --dart-define=AQUASENSE_ENV=production `
  --dart-define=AQUASENSE_API_BASE_URL=https://api.example.com
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

The current onboarding and placeholder screens do not require the backend to
be running. While the app is running, press `r` in the terminal for hot reload
or `R` for a full restart.

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
