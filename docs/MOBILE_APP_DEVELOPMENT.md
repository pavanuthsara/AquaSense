# AquaSense Mobile Development

This file is the source of truth for the feeding mobile application's backlog,
current task, implementation decisions, verification, and completed work.

## Status Values

- `Not started`
- `In progress`
- `Blocked`
- `Done`

Only one task should normally be marked `In progress`.

## Current Task

No task is currently in progress. The recommended next task is
**MOB-007 — Worker invitations and roles**.

## Task Backlog

| ID | Task | Depends on | Status |
|---|---|---|---|
| MOB-001 | Flutter application foundation | — | Done |
| MOB-002 | Three onboarding screens | MOB-001 | Done |
| MOB-003 | Authentication interface and secure session handling | MOB-001 | Done |
| MOB-004 | Google authentication backend | MOB-003 | Done |
| MOB-005 | Aquarium facility creation | MOB-004 | Done |
| MOB-006 | Multiple-facility switching | MOB-005 | Done |
| MOB-007 | Worker invitations and roles | MOB-005 | Not started |
| MOB-008 | Tank-group management | MOB-005, MOB-007 | Not started |
| MOB-009 | Tank and tag management | MOB-008 | Not started |
| MOB-010 | Tank-detail screen | MOB-009 | Not started |
| MOB-011 | Group feeding schedules | MOB-008 | Not started |
| MOB-012 | Per-tank schedule overrides | MOB-010, MOB-011 | Not started |
| MOB-013 | Feeder calibration and portion preview | MOB-010 | Not started |
| MOB-014 | Device health integration | MOB-010 | Not started |
| MOB-015 | Appetite-observation ingestion | MOB-013, MOB-014 | Not started |
| MOB-016 | Scheduled feeding-session state machine | MOB-012–MOB-015 | Not started |
| MOB-017 | Dashboard and feeding history | MOB-016 | Not started |
| MOB-018 | In-app alert center | MOB-016, MOB-017 | Not started |
| MOB-019 | Android push notifications | MOB-018 | Not started |
| MOB-020 | Safety-checked manual feeding | MOB-014, MOB-016, MOB-017 | Not started |
| MOB-021 | Offline and recovery behavior | Earlier application features | Not started |
| MOB-022 | Security and scale validation | Completed feature set | Not started |
| MOB-023 | End-to-end research workflow validation | Completed feature set | Not started |

## Task Definitions

### MOB-001 — Flutter application foundation

- Replace the generated counter application.
- Establish feature-based folders, application theme, routing, error handling,
  and environment configuration.
- Add development and test configuration without committing secrets.
- Create placeholder routes for onboarding, authentication, and home.
- Add basic app-startup and navigation tests.

**Done when:** the app starts successfully, uses the AquaSense theme, and
navigation tests pass.

### MOB-002 — Three onboarding screens

Implement the three approved onboarding pages, controls, page indicators,
local completion state, and the ability to reopen onboarding later.

### MOB-003 — Authentication interface and secure session handling

Build the Google sign-in experience, authentication states, secure token
storage abstraction, authentication repository, and development/mock provider.

### MOB-004 — Google authentication backend

Validate Google identity, create or update local users, issue AquaSense tokens,
protect APIs, and test authentication and token expiry.

### MOB-005 — Aquarium facility creation

Add facility ownership, first-facility setup, facility APIs, and idempotent
creation.

### MOB-006 — Multiple-facility switching

Add facility selection, persistence of the last facility, request scoping, and
safe handling of inaccessible facilities.

### MOB-007 — Worker invitations and roles

Add owner and worker roles, email invitations, acceptance and revocation, and
backend/UI permission enforcement.

### MOB-008 — Tank-group management

Add flat facility groups with owner management, worker viewing, tank counts,
and safe archival rules.

### MOB-009 — Tank and tag management

Add tank metadata, tags, owner management, grouping, pagination, search,
filters, and validation with 1,000 seeded tanks.

### MOB-010 — Tank-detail screen

Show tank, device, count, schedule, feeding, and activity information with
role-aware actions and complete UI states.

### MOB-011 — Group feeding schedules

Add daily group session times, facility-timezone interpretation, automation
pausing, and read-only worker access.

### MOB-012 — Per-tank schedule overrides

Add explicit group inheritance or complete tank-level replacement schedules.

### MOB-013 — Feeder calibration and portion preview

Add owner-controlled, versioned feeder-unit calibration and bounded portion
calculation without claiming unverified grams.

### MOB-014 — Device health integration

Model camera, edge-processor, and feeder health; accept heartbeats; display
status; and fail safely when hardware is unhealthy.

### MOB-015 — Appetite-observation ingestion

Accept and validate appetite results, guppy counts, confidence, model metadata,
and count inconsistencies.

### MOB-016 — Scheduled feeding-session state machine

Create idempotent scheduled sessions, apply every safety gate, and record
explicit command, skip, block, and failure outcomes.

### MOB-017 — Dashboard and feeding history

Add facility summaries and filterable, cursor-paginated facility and tank
feeding history.

### MOB-018 — In-app alert center

Add actionable feeding/device alerts, severity, acknowledgement, context, and
deep links.

### MOB-019 — Android push notifications

Register Android devices, group low-appetite pushes, immediately deliver
critical failures, and support preferences and deep links.

### MOB-020 — Safety-checked manual feeding

Allow authorized manual requests with confirmation, reason, safety gates,
idempotency, command tracking, and auditing.

### MOB-021 — Offline and recovery behavior

Cache read-only data, label stale content, prevent offline mutations, and
recover after connection or session interruption.

### MOB-022 — Security and scale validation

Validate authorization boundaries, token and invitation behavior, sensitive
logging, and operation with at least 1,000 tanks.

### MOB-023 — End-to-end research workflow validation

Validate the full scheduled and manual feeding workflows, complete Android
usability evaluation, and document demonstrated capabilities and limitations.

## Working Method

1. Select the next unblocked task.
2. Mark it `In progress` here.
3. Implement only that task and its required tests.
4. Verify its acceptance condition.
5. Add a dated work-log entry.
6. Mark it `Done`, or `Blocked` with the exact reason.
7. Record the recommended next task without starting it automatically.

## Work Log

### 2026-10-12 — MOB-001: Flutter application foundation

- Status: Done
- Summary: Replaced the generated counter demo with the AquaSense application
  shell, Material 3 theme, named routing, environment configuration, global
  Flutter error handling, and onboarding/sign-in/home placeholder screens.
- Files added: `mobile_app/lib/app/`, `mobile_app/lib/core/`,
  `mobile_app/lib/features/`, and `mobile_app/test/app_startup_test.dart`.
- Files changed: `mobile_app/lib/main.dart` and `mobile_app/README.md`.
- Backend/API changes: None. Development defaults to the Android emulator
  backend address, while production requires an explicit API base URL.
- Tests performed: Dart formatting, `flutter analyze --no-pub`,
  `flutter test --no-pub`, and `flutter build apk --debug --no-pub`.
- Test results: Static analysis reported no issues; all three startup/routing
  widget tests passed; Android debug APK built successfully.
- Decisions made: Use a feature-based directory structure, Material 3 with an
  AquaSense teal seed color, named routes for the first application flows, and
  compile-time Dart defines for non-secret environment configuration.
- Known limitations: The three routes intentionally contain placeholders.
  Onboarding content and persistence belong to MOB-002; authentication behavior
  and secure sessions belong to MOB-003.
- Recommended next task: MOB-002 — Three onboarding screens.

### 2026-10-13 — MOB-002: Three onboarding screens

- Status: Done
- Summary: Added three responsive onboarding pages covering tank organization,
  appetite-aware feeding, and alerts/human control. Added Skip, Next, Get
  started, animated page indicators, saved completion, returning-user startup
  routing, and an onboarding replay action.
- Files added: Onboarding repository contract, shared-preferences adapter,
  startup gate, and completed onboarding presentation under
  `mobile_app/lib/features/onboarding/`.
- Files changed: Application bootstrap/routing, home placeholder,
  `mobile_app/pubspec.yaml`, lockfile, Android NDK/application configuration,
  generated plugin registration, mobile run guide, and startup/widget tests.
- Backend/API changes: None.
- Tests performed: Dart formatting, `flutter analyze --no-pub`,
  `flutter test --no-pub`, and `flutter build apk --debug --no-pub`.
- Test results: Static analysis reported no issues; all six onboarding,
  persistence-flow, replay, routing, and startup tests passed; Android debug APK
  built successfully with the required NDK configuration.
- Decisions made: Use `SharedPreferencesAsync` behind an onboarding repository,
  default safely to onboarding if the completion state cannot be read, and keep
  persistence replaceable in tests. Use Flutter-native illustrations so this
  stage introduces no image-asset maintenance.
- Known limitations: Authentication remains a placeholder for MOB-003. Until a
  Settings screen exists, onboarding replay is exposed through the dashboard
  header. Windows Developer Mode may need to be enabled when Flutter creates
  plugin links during dependency resolution. The local Android toolchain also
  reports unaccepted SDK licenses, which must be accepted before the first
  connected-device run.
- Recommended next task: MOB-003 — Authentication interface and secure session
  handling.

### 2026-10-14 — MOB-003: Authentication interface and secure session handling

- Status: Done
- Summary: Replaced the authentication placeholder with a complete Google
  sign-in interface and application-wide authentication controller. Added
  checking, signed-out, signing-in, signed-in, signing-out, cancellation, and
  retryable error behavior; restored sessions at startup; and added user-aware
  home and sign-out behavior.
- Files added: Authentication domain models and repository contracts, encrypted
  session-storage adapter, development and pending-production providers,
  authentication controller/scope/gate, completed sign-in screen, reusable test
  fake, authentication widget tests, and secure-storage tests.
- Files changed: Application bootstrap/scope/routing, startup gate, home screen,
  shared placeholder widget, mobile run guide, Android configuration,
  `mobile_app/pubspec.yaml`, lockfile, generated plugin registration, and
  existing startup tests.
- Backend/API changes: None. The backend exchange remains MOB-004.
- Tests performed: Dart formatting, `flutter analyze --no-pub`,
  `flutter test --no-pub`, and two Android debug build checks while aligning
  native plugin requirements.
- Test results: Static analysis reported no issues; all 13 onboarding,
  authentication-state, session-restoration, sign-out, routing, and encrypted
  storage tests passed; the Android debug APK built successfully against SDK 36.
- Decisions made: Keep UI and state management independent of the eventual
  Google/backend implementation through `AuthenticationRepository`; use
  `flutter_secure_storage` for access and refresh tokens; use an explicitly
  disclosed local owner in development; disable Android app backup; and support
  Android 6.0/API 23 or newer for the secure-storage requirement.
- Known limitations: **Continue with Google** uses the local development account
  and does not open the real Google account chooser. Production sign-in reports
  that backend integration is pending. Google identity validation, token
  exchange/refresh, and `/me` belong to MOB-004.
- Recommended next task: MOB-004 — Google authentication backend.

### 2026-10-14 — MOB-004: Google authentication backend

- Status: Done
- Summary: Added Google ID-token verification, local user creation/update,
  short-lived AquaSense access JWTs, hashed and rotating refresh tokens,
  refresh-token revocation, stateless API security, and the Google-to-backend
  exchange in the Flutter app. Replaced the temporary Android package with
  `com.aquasense.mobile` so OAuth registration has a stable application ID.
- Files added: Backend authentication configuration, entities, repositories,
  services, Google verifier, controllers/error handling, Flyway migration,
  backend test configuration and authentication tests; Flutter Google token
  provider, authentication API client, production repository, and repository
  tests; `backend/README.md`.
- Files changed: Backend dependencies and runtime configuration; Flutter
  bootstrap/environment, sign-in disclosure, dependencies and generated plugin
  registration; Android manifests, package/application ID and activity;
  `mobile_app/README.md`.
- Backend/API changes: Added `POST /api/v1/auth/google/exchange`,
  `POST /api/v1/auth/refresh`, `GET /api/v1/auth/me`, and
  `POST /api/v1/auth/logout`. All other endpoints now require a valid AquaSense
  bearer token. Added `app_users` and `refresh_tokens` tables through Flyway.
- Tests performed: Java 21 Maven test suite, Dart formatting, Flutter static
  analysis, Flutter test suite, and Android debug APK build with the real-auth
  compile-time configuration path enabled.
- Test results: All 11 backend tests passed; all 17 Flutter tests passed;
  static analysis reported no issues; Android debug APK built successfully.
- Decisions made: Validate Google signature/expiry through Google's JWK set and
  additionally require the configured audience, accepted issuer, verified
  email, and subject; issue 15-minute HMAC-SHA256 access tokens and 30-day
  opaque refresh tokens; store only SHA-256 refresh-token hashes; rotate each
  refresh token once; keep secrets in environment/build configuration; retain
  the disclosed mock sign-in when no Google client ID is supplied.
- Known limitations: A live Google account chooser and PostgreSQL deployment
  were not exercised because project-specific Google OAuth credentials and a
  configured local database were not provided. The code path, API behavior,
  security rules, migrations, mobile integration, and Android build are
  automated-test verified. Revoked refresh-token rows are retained for audit
  and will need a scheduled cleanup policy in a later hardening task.
- Recommended next task: MOB-005 — Aquarium facility creation.

### 2026-10-15 — MOB-005: Aquarium facility creation

- Status: Done
- Summary: Added aquarium facility and owner-membership persistence, retry-safe
  facility creation, facility listing and selection, server-provided IANA time
  zones, and the authenticated Flutter flow for first-aquarium setup. Owners
  with an existing aquarium now enter a facility-aware empty home screen.
- Files added: Backend facility entities, role, repositories, service,
  controller, Flyway migration, and facility API integration tests; Flutter
  facility domain/repository contracts, development and HTTP adapters,
  repository scope, facility gate, setup screen, empty home screen, reusable
  facility test fake, repository tests, and widget tests.
- Files changed: Backend user repository, shared API error handler and backend
  guide; Flutter application/bootstrap dependency wiring, authentication gate,
  routing, mobile guide, and existing startup/authentication tests. Removed the
  superseded generic home placeholder.
- Backend/API changes: Added `POST /api/v1/facilities`,
  `GET /api/v1/facilities`, `GET /api/v1/facilities/{facilityId}`, and
  `GET /api/v1/facilities/timezones`; added `facilities` and
  `facility_memberships` tables. Creation requires an idempotency key, creates
  an `OWNER` membership atomically, returns the original facility for an exact
  retry, and rejects key reuse with different input.
- Tests performed: Java 21 Maven integration/unit suite, Dart formatting,
  Flutter static analysis, Flutter test suite, and Android debug APK build with
  the real authentication/backend compile-time path enabled.
- Test results: All 18 backend tests passed; all 26 Flutter tests passed;
  static analysis reported no issues; Android debug APK built successfully.
- Decisions made: Use IANA time-zone IDs supplied by the backend; serialize
  facility creation per owner to make concurrent retry handling deterministic;
  return not-found for inaccessible facility selection to avoid exposing other
  tenants; preserve a creation key across unchanged mobile retries; and select
  the first accessible facility until a dedicated switcher is implemented.
- Known limitations: Multiple-facility selection is not persisted and the app
  automatically opens the first accessible facility. Facility switching and
  removed-access handling belong to MOB-006. Worker membership behavior belongs
  to MOB-007, and tank/group actions remain later tasks.
- Recommended next task: MOB-006 — Multiple-facility switching.

### 2026-10-17 — MOB-006: Multiple-facility switching

- Status: Done
- Summary: Added an aquarium switcher, additional-aquarium creation flow,
  per-user persistence of the last selected facility, backend access
  verification before switching, and safe fallback when a saved or newly
  selected facility is no longer accessible.
- Files added: Flutter facility-selection storage contract and shared-
  preferences implementation, selection controller, dependency and selected-
  facility scopes, facility-switching widget tests, selection-store test, and
  reusable selection-store test fake.
- Files changed: Flutter bootstrap/application dependency wiring, authenticated
  routing, facility gate, setup and home screens, mobile guide, existing mobile
  tests and facility fake; backend facility integration tests.
- Backend/API changes: No production endpoint or schema changes were required.
  The existing authenticated facility list, creation, and facility-detail APIs
  support multiple memberships. Added integration coverage proving that one
  owner can list multiple facilities without seeing another owner's facility.
- Tests performed: Java 21 Maven integration/unit suite, Dart formatting,
  Flutter static analysis, Flutter test suite, and Android debug APK build with
  the production authentication/backend compile-time path enabled.
- Test results: All 19 backend tests passed; all 32 Flutter tests passed;
  static analysis reported no issues; Android debug APK built successfully.
- Decisions made: Store the selected facility ID under a user-specific local
  key; verify facility access with the backend before changing workspaces; use
  an inherited selected-facility scope for future facility-bound requests; and
  key the complete facility workspace by facility ID so widget state and future
  cached data cannot leak across aquarium switches.
- Known limitations: The selection is device-local rather than synchronized
  across devices. Tank, group, schedule, and dashboard data do not exist yet;
  their repositories must use the selected-facility scope when implemented.
  Worker membership and permission changes belong to MOB-007.
- Recommended next task: MOB-007 — Worker invitations and roles.

