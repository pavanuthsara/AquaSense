# New developer setup

This guide runs the Spring Boot API and PostgreSQL in Docker, with Flutter
running locally through Android Studio or a terminal. Run Compose commands
from `backend/` (the folder containing `compose.yaml`), explicitly selecting
the repository-root `.env` with `--env-file ../.env`. Flutter and Python ML
run outside Docker. Commands below use PowerShell on Windows.

## 1. Install the tools

- Git, and a checkout of this repository.
- Docker Desktop with the WSL 2 backend and **Linux containers** enabled.
  Start Docker Desktop and wait until its engine is running.
- Flutter SDK compatible with `mobile_app/pubspec.yaml` (Dart 3.8.1 or later),
  Android Studio, the Flutter/Dart plugins, and Android SDK tools.
- A physical Android phone with USB debugging enabled, or an Android emulator
  with Google Play services and a Google account.

Verify the tools:

```powershell
docker version
docker compose version
flutter doctor
flutter doctor --android-licenses
flutter devices
```

`docker version` should show both client and server details. Resolve Android
toolchain issues reported by `flutter doctor`. Enable Windows Developer Mode
if Flutter reports that plugin symlinks need it. Docker supplies Java 21,
Maven, and PostgreSQL; you do not need to install those separately.

## 2. Configure Google sign-in

In Google Cloud Console, choose one project for both OAuth clients:

1. Configure Google Auth Platform branding, audience, and consent settings.
   If the app is in testing, add your test Google accounts where required.
2. Create an **Android OAuth client** for package `com.aquasense.mobile` and
   the SHA-1 fingerprint of your local Android signing certificate.
3. Create a **Web application OAuth client** in that same project. Copy its
   client ID, usually ending in `.apps.googleusercontent.com`.

To inspect your debug certificate after building or running the Android app:

```powershell
& 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe' `
  -list -v -alias androiddebugkey `
  -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -storepass android -keypass android
```

Each developer's certificate may differ. Register each required package/SHA-1
combination. Other distribution signing certificates need their own matching
Android OAuth configuration.

The **Web client ID** is used in both backend and Flutter configuration.
The Android client ID must not be substituted for it. This integration uses
Google ID tokens directly; it does not require a Web client secret or a
`google-services.json` file.

## 3. Create local configuration

From the repository root, copy the example once:

```powershell
Copy-Item .env.example .env
```

Generate a JWT signing secret:

```powershell
$jwtBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($jwtBytes)
$rng.Dispose()
[Convert]::ToBase64String($jwtBytes)
```

Open `.env` and fill in:

```dotenv
AQUASENSE_DB_PASSWORD=replace-with-your-local-database-password
AQUASENSE_GOOGLE_CLIENT_ID=replace-with-your-web-client-id.apps.googleusercontent.com
AQUASENSE_JWT_SECRET=replace-with-the-generated-base64-value
AQUASENSE_API_PORT=8080
```

Keep this file private; Git ignores it. Use a password without `$` or `#` for
an uncomplicated local setup, or follow Compose's `.env` quoting rules.
Keep the JWT secret stable between restarts so existing access tokens remain
valid. Compose rejects empty required settings; the backend also validates
that its JWT secret decodes to at least 32 bytes.

The Compose commands explicitly select this root `.env`. Any existing
`backend/.env` is left intact and is not selected by these commands. Flutter does **not** read it;
pass its configuration explicitly in step 5. Environment variables already
set in your terminal override matching `.env` values.

## 4. Build and start the backend and database

From the repository root:

```powershell
cd backend
docker compose --env-file ../.env config --quiet
docker compose --env-file ../.env up --build -d
docker compose --env-file ../.env ps
docker compose --env-file ../.env logs -f backend
```

The project name remains `aquasense` and its `postgres_data` volume keeps the
same name after this move. Existing data is reused; no reset is needed. To run
Compose from the repository root instead, use
`docker compose --env-file .env -f backend/compose.yaml up --build -d`.

The first build downloads dependencies and runs the backend test suite.
PostgreSQL creates the `aquasense` database and user. Once PostgreSQL is
healthy, the API starts and Flyway applies the database migrations.
Wait for the Spring Boot `Started` message and port 8080 startup message.
Press Ctrl+C to stop following logs; the containers continue running.

Check the protected API from your laptop:

```powershell
curl.exe -i http://localhost:8080/api/v1/auth/me
```

An HTTP **401** is expected without a login token and confirms that the API
is responding. A connection failure means it is not reachable yet. Container
status `running` alone does not confirm that Spring Boot has finished starting.
If you changed `AQUASENSE_API_PORT`, use that port in URLs throughout this guide.

PostgreSQL is available to the backend at `db:5432` inside Docker. The current
local configuration also publishes port 5432 on the laptop for database tools;
the app and Python worker use the API, not a direct database connection. To
open its SQL console from `backend/`:

```powershell
docker compose --env-file ../.env exec db psql -U aquasense -d aquasense
```

## 5. Connect the mobile app

In a second terminal, starting from the repository root:

```powershell
cd mobile_app
flutter pub get
flutter devices
```

For an **Android emulator**, use:

```powershell
flutter run `
  --dart-define=AQUASENSE_ENV=development `
  --dart-define=AQUASENSE_API_BASE_URL=http://10.0.2.2:8080 `
  --dart-define=AQUASENSE_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID
```

For a **physical Android phone**, connect it by USB and accept its USB debugging
prompt. Put the laptop and phone on the same Wi-Fi network. Run `ipconfig`,
find the laptop's Wi-Fi IPv4 address, and use it here:

```powershell
flutter run `
  --dart-define=AQUASENSE_ENV=development `
  --dart-define=AQUASENSE_API_BASE_URL=http://YOUR_LAPTOP_WIFI_IP:8080 `
  --dart-define=AQUASENSE_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID
```

Replace the placeholders. Add `-d YOUR_DEVICE_ID` if multiple devices are
connected. The Google Web client ID must exactly match `.env`.
`localhost` on the phone refers to the phone, and `10.0.2.2` is for the emulator.
Allow Docker Desktop's published API port through Windows Firewall for your
private network if needed. The Compose API port is exposed on the laptop's
network interfaces so the phone can reach it; use this HTTP setup for local
development on a trusted network.

Alternatively, with a USB-connected phone, forward the API port:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
```

Then pass `http://127.0.0.1:8080` as the Flutter API URL. Repeat the forwarding
after reconnecting the phone. If using a different host port, forward phone
port 8080 to that host port instead.

To launch through Android Studio's Run button, open `mobile_app`, select the
device, and put the same three `--dart-define=...` arguments in the Flutter
run configuration's **Additional run args** field.

Stop and rerun Flutter after changing Dart defines. Without the Google client
ID, development builds use a local test account instead of real Google sign-in.

## 6. Verify the complete flow

1. Select **Continue with Google** and choose your Google account.
2. Confirm that the app opens your aquarium or the first-aquarium setup screen.
3. Restart the app and confirm that the saved session restores.

Google sign-in requires internet access, including outbound access from the
backend to Google's signing-key endpoint. Local account-selection errors and
backend connection errors are separate parts of the login flow.

## Everyday commands

Run these from `backend/`:

```powershell
# Start existing services.
docker compose --env-file ../.env up -d

# Rebuild and run tests after backend source changes.
docker compose --env-file ../.env up --build -d backend

# Follow both services' logs.
docker compose --env-file ../.env logs -f

# Stop and remove containers, retaining database data.
docker compose --env-file ../.env down
```

Source changes require a backend image rebuild; there is no source bind mount
or automatic Java reload. Re-run `docker compose --env-file ../.env up -d`
after changing the root `.env`; restarting alone does not apply updated
container environment values.

Database data survives rebuilds and `docker compose --env-file ../.env down`.
To deliberately delete **all local Docker database data**, run
`docker compose --env-file ../.env down --volumes`,
then start again. This removes users, aquariums, and other stored records;
sign out or clear the app's storage afterward to discard old session tokens.
Changing `AQUASENSE_DB_PASSWORD` does not change an existing volume's database
password: alter it through PostgreSQL or deliberately reset disposable data.

To run backend tests without starting the services (also runs during builds):

```powershell
docker build --target build -t aquasense-backend-tests .
```

Docker may reuse a successful cached test layer when sources are unchanged.
Use `--no-cache` when you explicitly need a fresh run.

Run Flutter checks from `mobile_app`:

```powershell
flutter analyze
flutter test
```

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Cannot connect to Docker engine / missing Linux engine pipe | Start Docker Desktop, wait for readiness, and select Linux containers. |
| Compose reports a required variable is missing | Create `.env` in the repository root and fill in every required setting. |
| Port 8080 is already allocated | Stop the conflicting service or change `AQUASENSE_API_PORT` and the mobile API URL. |
| Database authentication fails after editing `.env` | The existing database volume still uses its original password; see the data notes above. |
| Backend exits during startup | From `backend/`, read `docker compose --env-file ../.env logs backend db`; check JWT encoding and database credentials. |
| App says it cannot connect to AquaSense | Verify API startup, the phone's API URL, Wi-Fi/firewall or USB forwarding, and the published port. |
| Google chooser closes and reports cancelled without you cancelling | Check Android OAuth package/SHA-1 and the Web client ID's project. Android can report some configuration errors as cancellation. |
| Google token is rejected by the backend | Check that mobile and backend use exactly the same Web OAuth client ID. |
| App signs in as Development Owner | Rebuild with `AQUASENSE_GOOGLE_SERVER_CLIENT_ID` to enable real authentication. |

See the [Google sign-in Android troubleshooting documentation](https://pub.dev/packages/google_sign_in_android#troubleshooting)
and [Docker Compose startup-order documentation](https://docs.docker.com/compose/how-tos/startup-order/).

This Compose setup is for local development. Deployment requires separate
HTTPS, secret management, database backup, and distribution signing configuration.

## Camera / ML connection

Keep the iPhone webcam bridge and Python worker on the laptop so OpenCV can use
the working camera driver. Python connects to `http://localhost:8080` through
Docker's published backend port. The backend uses `db:5432` on the Compose
network. Flutter uses `http://10.0.2.2:8080` on an Android emulator or the laptop's
LAN address on a physical phone. Docker service names such as `backend` and
`db` are not host/phone addresses. See [live appetite setup](LIVE_APPETITE.md).
