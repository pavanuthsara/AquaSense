# AquaSense Backend

Spring Boot API for AquaSense with email/password accounts, Google identity
exchange, and AquaSense-owned access and refresh sessions.

## Run with Docker (recommended for local development)

Follow [the developer setup guide](../docs/DEVELOPER_SETUP.md). Configure the
repository-root `.env` from the root `.env.example`, then from `backend/` run
`docker compose --env-file ../.env up --build -d`. The Compose file is
`backend/compose.yaml`; the explicit environment-file path selects the existing
root credentials even if `backend/.env` also exists. Compose builds and tests the Java 21 API,
starts PostgreSQL, waits for database readiness, and exposes the API on port
8080. Database tables are created by Flyway and data persists in a named
volume. No local Java, Maven, or PostgreSQL installation is needed.

Flutter and the Python camera/ML process run locally outside Docker and connect
to the published API port. From the repository root, the equivalent command is
`docker compose --env-file .env -f backend/compose.yaml up --build -d`.

The instructions below are for running the backend outside Docker.

## Authentication configuration

Nothing secret is committed to the repository. Set these environment variables
before starting the API:

```powershell
$env:AQUASENSE_DB_URL = 'jdbc:postgresql://localhost:5432/aquasense'
$env:AQUASENSE_DB_USERNAME = 'aquasense'
$env:AQUASENSE_DB_PASSWORD = '<your local database password>'
$env:AQUASENSE_GOOGLE_CLIENT_ID = '<Google Web OAuth client ID>'
$env:AQUASENSE_JWT_SECRET = '<Base64-encoded random value of at least 32 bytes>'
```

Generate a suitable local JWT secret without saving it in source control:

```powershell
$secretBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($secretBytes)
[Convert]::ToBase64String($secretBytes)
```

The Google client ID is optional for email/password authentication. To enable
Google login, use the Web OAuth client ID also passed to Flutter as
`AQUASENSE_GOOGLE_SERVER_CLIENT_ID`. Flyway creates and upgrades the
authentication tables when the API starts.

## Run

This project requires Java 21. Android Studio's bundled JDK can be used on
Windows:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
.\mvnw.cmd spring-boot:run
```

The API listens on port 8080 by default.

## Authentication endpoints

- `POST /api/v1/auth/register` accepts `email`, `displayName`, and `password`,
  creates an account, and returns a session with HTTP 201.
- `POST /api/v1/auth/login` accepts `email` and `password` and returns a session.
- `POST /api/v1/auth/google/exchange` validates a Google ID token and returns
  AquaSense access and refresh tokens.
- `POST /api/v1/auth/refresh` rotates a valid refresh token.
- `GET /api/v1/auth/me` returns the user for a valid AquaSense access token.
- `POST /api/v1/auth/logout` revokes the supplied refresh token.

Every other API route is protected unless it is explicitly allowed by the
security configuration. Raw refresh tokens are never stored in the database;
only SHA-256 hashes are retained.

Registration requires a valid email (up to 320 characters), a nonblank display
name (up to 255 characters), and a password of 12–128 characters. Passwords are
stored only as salted PBKDF2-HMAC-SHA256 hashes using Spring Security's v5.8
defaults. Email addresses are trimmed and normalized to lowercase; passwords
are preserved exactly. Duplicate email addresses return HTTP 409, including
addresses already used for Google login. Login failures return a common HTTP
401 message. Accounts are not automatically linked across login methods.

Email registration signs the user in immediately and supports aquarium ownership.
It does not verify mailbox ownership. Password-only accounts cannot list or
accept email-based worker invitations; these still require a verified Google
identity. Email verification, account linking, and password recovery are not
implemented in this flow.

Authentication requests log their arrival, route, response status, and duration
to the container console. Passwords, request bodies, query strings, and tokens
are excluded. Follow them from `backend/` with
`docker compose --env-file ../.env logs -f backend`. Rebuild the backend image
after source changes to enable the new logging in an existing container.

## Facility endpoints

- `POST /api/v1/facilities` creates an aquarium and owner membership. It
  requires an `Idempotency-Key` header so safely repeated requests return the
  original aquarium instead of creating duplicates.
- `GET /api/v1/facilities` lists aquariums accessible to the signed-in user.
- `GET /api/v1/facilities/{facilityId}` selects and returns an accessible
  aquarium without revealing inaccessible aquarium IDs.
- `GET /api/v1/facilities/timezones` returns the supported IANA time-zone IDs.

Facility routes require an AquaSense bearer token.

## Team and invitation endpoints

- `GET /api/v1/facilities/{facilityId}/members` lists aquarium owners and
  workers for any current member.
- `GET /api/v1/facilities/{facilityId}/invitations` lists invitation history
  for an owner.
- `POST /api/v1/facilities/{facilityId}/invitations` creates a seven-day
  worker invitation for an owner-supplied email address.
- `DELETE /api/v1/facilities/{facilityId}/invitations/{invitationId}` revokes
  an invitation before it is accepted.
- `DELETE /api/v1/facilities/{facilityId}/members/{membershipId}` removes a
  worker. Owner membership cannot be removed through this endpoint.
- `GET /api/v1/invitations/me` lists pending invitations matching the signed-in
  user's verified Google email.
- `POST /api/v1/invitations/{invitationId}/accept` accepts a matching
  invitation and creates worker membership.

Invitation creation, listing, revocation, and worker removal are enforced as
owner-only operations by the API. A worker can list the team but receives a
forbidden response for owner-only actions. AquaSense currently exposes
invitations in the app; external invitation-email delivery is not yet included.

## Tank-group endpoints

- `GET /api/v1/facilities/{facilityId}/tank-groups` lists active and archived
  groups, including each group's tank count, for owners and workers.
- `POST /api/v1/facilities/{facilityId}/tank-groups` creates a flat group for
  an owner.
- `PATCH /api/v1/facilities/{facilityId}/tank-groups/{groupId}` renames an
  active group for an owner.
- `POST /api/v1/facilities/{facilityId}/tank-groups/{groupId}/archive`
  archives an empty group for an owner.
- `PUT /api/v1/facilities/{facilityId}/tank-groups/{groupId}/feeding-schedule`
  replaces an active group's daily feeding times and enables or pauses its
  automatic schedule for an owner.

Active group names are unique within an aquarium after whitespace and case
normalization. Archived groups are retained for history and returned after
active groups. A group with a nonzero tank count cannot be archived; MOB-009
maintains this server-owned count when tanks are created, moved, or archived.
Feeding times are submitted and returned as `HH:mm` wall-clock times in the
facility's IANA timezone. The API also stores the next occurrence as a UTC
instant so later feeding workers can execute consistently. Pausing keeps the
configured times but clears their pending execution instants. Workers can read
the schedule through the group list but cannot change it.

## Tank endpoints

- `GET /api/v1/facilities/{facilityId}/tanks` returns a server-paginated tank
  inventory. It supports `page`, `size`, `query`, `status`, `groupId`,
  `unassigned`, and `tag` filters. The default view excludes archived tanks.
- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}` returns tank metadata
  and the current detail snapshot.
- `GET /api/v1/facilities/{facilityId}/tank-tags` lists normalized tags used by
  active tanks.
- `POST /api/v1/facilities/{facilityId}/tanks` creates a tank for an owner.
- `PATCH /api/v1/facilities/{facilityId}/tanks/{tankId}` edits or moves an
  active tank for an owner.
- `POST /api/v1/facilities/{facilityId}/tanks/{tankId}/archive` safely removes
  a tank from active operations for an owner.
- `PUT /api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule`
  switches an active tank between its complete inherited group schedule and a
  complete tank-specific replacement.

Tank codes are unique within an aquarium after case normalization. Tags are
stored in lowercase, group assignments are aquarium-scoped, and group counts
are updated in the same database transaction as every tank assignment change.
Workers can search and inspect tanks but cannot create, edit, move, or archive
them. Device health, feeding schedules, observations, and feeding history are
represented by explicit not-configured/no-data states until their later tasks
provide those records.

Tank details return `scheduleMode`, the effective `feedingTimes`, and the next
UTC execution instant. `INHERITED` always follows the current group schedule;
`OVERRIDE` requires one or more unique tank times and ignores group schedule
changes. An unassigned tank without an override is automatically paused, even
if a client requests automation, so it cannot feed without an effective
schedule.

## Feeder calibration and portion preview

- `GET /api/v1/facilities/{facilityId}/feeder-calibration` returns the latest
  active calibration, or an explicit unconfigured state.
- `POST /api/v1/facilities/{facilityId}/feeder-calibration` publishes an
  immutable new calibration version. Only owners can publish versions.
- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/portion-preview`
  calculates a bounded preview for the supplied `fishCount`, or defaults to
  the detected count and then the expected count.

Calibration values and previews use abstract feeder actuation units with four
decimal places. The calculation is `fish count × units per fish`, bounded by
the active minimum and maximum. A zero fish count always produces zero feeder
movement. Physical mass is intentionally not represented until validated.

## Tank device health

- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/device-health` returns
  aggregate and per-component camera, edge-processor, and feeder health.
- `POST /api/v1/facilities/{facilityId}/tanks/{tankId}/devices/{type}/provision`
  is owner-only and returns a one-time heartbeat token. Provisioning the same
  type again rotates its credential and invalidates the old token.
- `POST /api/v1/device-heartbeats` accepts `X-Device-Id` and
  `X-Device-Token` headers plus `healthy` and an optional status `message`.

A component is stale after two minutes without a heartbeat and offline after
ten minutes. Feeding is allowed only when the camera, edge processor, and
feeder are all configured, online, and healthy. Device tokens are stored as
SHA-256 hashes and are never returned after provisioning.

## Appetite observations

For on-demand research predictions, the mobile tank screen can request a fresh
10-second check. See the [local appetite guide](../docs/LIVE_APPETITE.md#4-check-appetite-from-the-mobile-app)
for camera-worker setup and endpoints. Check results are displayed separately
from trusted observations and do not trigger feeding.

- `POST /api/v1/device-observations` accepts a tank ID, detected guppy count,
  confidence, `HIGH` or `LOW` appetite result, model version, and observation
  timestamp. It uses the MOB-014 device ID/token headers and accepts only an
  edge processor assigned to that tank.
- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-observation`
  returns the latest observation to an aquarium member. Tank-detail responses
  include the same record.

Observations older than five minutes or more than one minute in the future are
stale. Confidence below 80% is low, and detected count is inconsistent when it
differs from expected by more than the larger of five fish or 20%. Flagged
observations remain visible for review but cannot update trusted count data or
pass the feeding-decision safety guard.

## Scheduled feeding sessions

The scheduler checks due tank overrides and inherited group schedules every 30
seconds. It creates at most one session for each tank and scheduled UTC instant,
then evaluates automation, required device health, the 15-minute cooldown,
observation freshness, confidence, count consistency, appetite, and calibrated
portion bounds. Each stopped session retains an explicit skip, block, or failure
reason for later history and alert screens.

- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-session/latest`
  returns the latest session to an aquarium member.
- `GET /api/v1/feeder-commands/next` lets an authenticated feeder poll its next
  pending command using `X-Device-Id` and `X-Device-Token`.
- `POST /api/v1/feeder-commands/{sessionId}/feedback` records the feeder's
  delivered or failed result using the same device credentials.

`COMMAND_SENT` means only that a bounded command is available to the feeder.
The backend records `DELIVERED` only after positive feedback from the feeder;
negative feedback records `FAILED`. Repeated processing of the same occurrence
returns the existing session, and repeated matching feedback is safe.

## Feeding dashboard and history

- `GET /api/v1/facilities/{facilityId}/feeding-dashboard` returns active-tank
  totals, the next 24 hours of scheduled sessions, rolling 24-hour outcome
  counts, non-online devices, and recent sessions.
- `GET /api/v1/facilities/{facilityId}/feeding-history` returns stable,
  cursor-paginated facility history.
- `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-history`
  returns the same history format scoped to one tank.

History can be filtered by `tankId`, `groupId`, `source`, `outcome`, `from`,
and `to`. Page sizes range from 1 to 100 and default to 25. The opaque cursor
combines the scheduled timestamp and session ID so sessions with identical
times cannot be skipped or repeated between pages. Every query verifies the
current user's facility membership and keeps tank and group filters within
that facility.

## Verify

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
.\mvnw.cmd test
```

Tests use an in-memory database and test-only token configuration.
