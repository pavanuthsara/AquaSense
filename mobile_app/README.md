# AquaSense Mobile App

Flutter application for AquaSense aquarium monitoring and appetite-aware
feeding.

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
