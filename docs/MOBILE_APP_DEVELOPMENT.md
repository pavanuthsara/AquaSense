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

No task is currently in progress. **MOB-017 — Dashboard and feeding history**
is the recommended next task.

## Task Backlog

| ID | Task | Depends on | Status |
|---|---|---|---|
| MOB-001 | Flutter application foundation | — | Done |
| MOB-002 | Three onboarding screens | MOB-001 | Done |
| MOB-003 | Authentication interface and secure session handling | MOB-001 | Done |
| MOB-004 | Google authentication backend | MOB-003 | Done |
| MOB-005 | Aquarium facility creation | MOB-004 | Done |
| MOB-006 | Multiple-facility switching | MOB-005 | Done |
| MOB-007 | Worker invitations and roles | MOB-005 | Done |
| MOB-008 | Tank-group management | MOB-005, MOB-007 | Done |
| MOB-009 | Tank and tag management | MOB-008 | Done |
| MOB-010 | Tank-detail screen | MOB-009 | Done |
| MOB-011 | Group feeding schedules | MOB-008 | Done |
| MOB-012 | Per-tank schedule overrides | MOB-010, MOB-011 | Done |
| MOB-013 | Feeder calibration and portion preview | MOB-010 | Done |
| MOB-014 | Device health integration | MOB-010 | Done |
| MOB-015 | Appetite-observation ingestion | MOB-013, MOB-014 | Done |
| MOB-016 | Scheduled feeding-session state machine | MOB-012–MOB-015 | Done |
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

### 2026-10-19 — MOB-007: Worker invitations and roles

- Status: Done
- Summary: Added email-bound worker invitations, seven-day expiry, acceptance,
  revocation, worker removal, team member views, and owner/worker permission
  enforcement. Owners can manage workers from the selected aquarium, while
  workers receive a read-only team view. Signed-in users see invitations sent
  to their verified Google email and can accept one before creating an
  aquarium or while already belonging to another aquarium.
- Files added: Backend invitation entity/status, repository, service,
  controller, Flyway migration, and team API integration tests; Flutter team
  domain models, owner/worker team screen, pending-invitations screen, and
  invitation/team widget tests.
- Files changed: Backend facility membership/repositories and integration-test
  cleanup; Flutter facility repository contracts and HTTP/development/test
  adapters, facility gate, selection controller, home screen, HTTP repository
  tests, backend/mobile guides, and this development record.
- Backend/API changes: Added
  `GET /api/v1/facilities/{facilityId}/members`, owner-only facility invitation
  list/create/revoke endpoints, owner-only worker removal,
  `GET /api/v1/invitations/me`, and
  `POST /api/v1/invitations/{invitationId}/accept`. Added the
  `facility_invitations` table. Duplicate active invitations and invitations
  for existing members are rejected; acceptance is idempotent for the invited
  user; inaccessible resources are not disclosed.
- Tests performed: Java 21 Maven integration/unit suite, Dart formatting check,
  Flutter static analysis, complete Flutter test suite, and Android debug APK
  build with production-style API and Google client configuration.
- Test results: All 25 backend tests passed; all 38 Flutter tests passed;
  formatting was unchanged; static analysis reported no issues; Android debug
  APK built successfully.
- Decisions made: Match invitations only to the normalized email stored from a
  verified Google identity; create worker membership only upon acceptance; use
  a seven-day invitation lifetime; serialize invitation creation through a
  facility database lock for duplicate protection; retain accepted, revoked,
  and expired invitation records for traceability; enforce permissions in the
  backend and additionally hide owner-only controls from workers.
- Known limitations: The system does not send invitation email; the invitation
  becomes visible inside AquaSense after the worker signs in with the matching
  Google account. Invitation lifetime is currently fixed at seven days. Owner
  transfer and real-time forced navigation after membership removal are not
  included; removed access is rejected by the backend and reconciled on the
  next facility refresh or app start.
- Recommended next task: MOB-008 — Tank-group management.

### 2026-10-19 — MOB-008: Tank-group management

- Status: Done
- Summary: Added flat, facility-scoped tank groups with owner-only creation,
  renaming, and safe archival. Owners and workers can view active and archived
  groups with server-provided tank counts, while workers receive a read-only
  interface. Empty, loading, retryable error, and pull-to-refresh states are
  included.
- Files added: Backend tank-group entity, repository, service, controller,
  Flyway migration, and API integration tests; Flutter tank-group domain model,
  management screen, and widget tests.
- Files changed: Flutter facility repository contract and HTTP/development/test
  adapters, facility routing and home screen, HTTP repository tests, backend
  and mobile guides, and this development record.
- Backend/API changes: Added
  `GET /api/v1/facilities/{facilityId}/tank-groups`,
  `POST /api/v1/facilities/{facilityId}/tank-groups`,
  `PATCH /api/v1/facilities/{facilityId}/tank-groups/{groupId}`, and
  `POST /api/v1/facilities/{facilityId}/tank-groups/{groupId}/archive`.
  Added the `tank_groups` table with normalized names, tank counts, timestamps,
  and soft-archive state. Writes require the owner role; member reads remain
  facility-scoped and inaccessible facility/group identifiers are not leaked.
- Tests performed: Java 21 Maven integration/unit suite, Dart formatting check,
  Flutter static analysis, complete Flutter test suite, focused repository and
  widget tests, and Android debug APK build with production-style API and
  Google client configuration.
- Test results: All 30 backend tests passed; all 42 Flutter tests passed;
  formatting was unchanged; static analysis reported no issues; Android debug
  APK built successfully.
- Decisions made: Keep groups flat; normalize whitespace and case for unique
  active names; retain archived groups for history; allow reuse of a name after
  archival; order active groups before archived groups; use a server-owned tank
  count and reject archival whenever it is nonzero; serialize group naming
  changes with a facility lock and lock a group while archiving it.
- Known limitations: Individual tanks do not exist until MOB-009, so groups
  created in the current application show zero tanks. MOB-009 must update the
  group count atomically when tanks are created, moved, or archived and use the
  group lock when assigning tanks. Nested groups, manual ordering, unarchiving,
  and permanent deletion are intentionally not included.
- Recommended next task: MOB-009 — Tank and tag management.

### 2026-10-19 — MOB-009: Tank and tag management

- Status: Done
- Summary: Added facility-scoped tank persistence and a paginated mobile tank
  inventory. Owners can create, edit, move, pause, tag, and archive tanks;
  owners and workers can search by name/code and filter by status, group,
  unassigned state, and tag. Group tank counts are updated transactionally.
- Files added: Backend tank entity/status, repository, service, controller,
  Flyway migration, and tank API integration tests; Flutter tank domain model,
  tank list and form screens, and tank management widget tests.
- Files changed: Backend tank-group count behavior; Flutter facility repository
  contract and HTTP/development/test adapters, facility routing and home screen,
  HTTP repository tests, backend/mobile guides, and this development record.
- Backend/API changes: Added paginated/filterable
  `GET /api/v1/facilities/{facilityId}/tanks`,
  `GET /api/v1/facilities/{facilityId}/tank-tags`, owner-only tank create/edit/
  archive endpoints, the `tanks` and `tank_tags` tables, facility-unique
  normalized tank codes, and atomic group-count maintenance.
- Tests performed: Java 21 Maven integration/unit suite, a real 1,000-entity
  backend seed/search/filter/pagination test, Dart formatting check, Flutter
  static analysis, complete Flutter test suite, focused tank repository/widget
  tests, and Android debug APK build with production-style configuration.
- Test results: All 35 backend tests and all 46 Flutter tests passed; formatting
  was unchanged; static analysis reported no issues; Android debug APK built
  successfully. The 1,000-tank test verified server pagination, search, status,
  group, unassigned, and tag filtering, and the mobile scale test verified that
  the inventory remains paginated and searchable.
- Decisions made: Use server-side pages of 50 with a maximum backend page size
  of 100; keep archived tanks out of the default view; reserve tank codes after
  archival for unambiguous history; normalize tags to lowercase; retain an
  explicit unassigned-tanks view; and serialize facility/group mutations so
  group counts cannot drift during tank moves.
- Known limitations: There is no bulk CSV import or bulk edit workflow; the
  requirement is satisfied through scalable paginated/searchable individual
  management. Detected counts remain empty until observation ingestion in
  MOB-015. Permanent deletion and restoration of archived tanks are not
  included.
- Recommended next task: MOB-010 — Tank-detail screen.

### 2026-10-19 — MOB-010: Tank-detail screen

- Status: Done
- Summary: Added a role-aware tank detail screen showing identity, group,
  tags, automation, expected/detected guppy counts, confidence, observation
  freshness, hardware state, feeding schedule, last/next feeding, and recent
  activity. Loading, retryable error, no-data, stale, offline, unhealthy, and
  not-configured states are represented explicitly. Workers can inspect tanks
  without seeing owner-only edit or archive actions.
- Files added: Flutter tank-detail presentation screen.
- Files changed: Backend tank detail response; Flutter tank domain/repository
  adapters, tank list/form screens and their navigation, HTTP and fake
  repository tests, tank management widget tests, guides, and this development
  record.
- Backend/API changes: Added
  `GET /api/v1/facilities/{facilityId}/tanks/{tankId}` with a facility-scoped
  tank snapshot, observation freshness, device state, schedule/feeding
  placeholders, and recent tank activity. Both roles can read it; mutations
  remain owner-only.
- Tests performed: Backend role/facility-isolation and detail-state integration
  tests; Flutter HTTP mapping tests; owner and worker widget tests; Dart
  formatting check; Flutter static analysis and full test suite; Android debug
  APK build.
- Test results: All 35 backend tests and all 46 Flutter tests passed; the detail
  tests verified stale and absent observations, offline/not-configured hardware,
  schedule and activity rendering, owner actions, and worker action hiding.
  The Android APK built successfully.
- Decisions made: Expose truthful explicit no-data/not-configured states rather
  than fabricate device, schedule, observation, or feeding data; keep detail
  access available to both roles; enforce owner mutations in the backend as
  well as hiding them in the worker interface; and preserve one detail contract
  for later monitoring and feeding tasks to populate.
- Known limitations: Device health is `NOT_CONFIGURED` until MOB-014; detected
  counts and confidence require MOB-015; schedules require MOB-011/MOB-012;
  last/next feeding and operational history require MOB-016/MOB-017. Current
  activity includes tank creation/settings changes rather than feeding events.
- Recommended next task: MOB-011 — Group feeding schedules.

### 2026-10-20 — MOB-011: Group feeding schedules

- Status: Done
- Summary: Added facility-scoped daily feeding schedules for tank groups.
  Owners can configure one or more session-start times, enable automatic
  feeding, or pause it without losing the times. Workers receive a read-only
  schedule view. Group cards show the effective times, automation state, and
  aquarium timezone.
- Files added: Backend group-feeding-time entity and Flyway migration; Flutter
  group feeding schedule screen.
- Files changed: Backend tank-group model, repository, service, controller,
  integration tests, and guide; Flutter facility repository contracts and
  HTTP/development/test adapters, tank-group domain/list UI, repository and
  widget tests, mobile guide, and this development record.
- Backend/API changes: Added owner-only
  `PUT /api/v1/facilities/{facilityId}/tank-groups/{groupId}/feeding-schedule`.
  Group responses now include `feedingTimes`, `feedingAutomationEnabled`, and
  `nextSessionAt`. Added `group_feeding_times` and the group automation flag.
- Tests performed: Java 21 Maven integration/unit suite, timezone conversion
  and role/validation integration tests, Dart formatting, Flutter static
  analysis, focused repository/widget tests, full Flutter test suite, and an
  Android debug APK build with production-style API/Google configuration.
- Test results: All 37 backend tests and all 48 Flutter tests passed; static
  analysis reported no issues; the Android debug APK built successfully.
- Decisions made: Store recurring schedule inputs as `HH:mm` local wall-clock
  times and calculate each next occurrence using the facility's IANA timezone;
  persist that occurrence as a UTC instant; sort times and reject duplicates;
  limit a group to 24 daily sessions; preserve times while paused but clear
  pending execution instants; start newly created groups paused; and pause a
  schedule automatically when its group is archived.
- Known limitations: MOB-011 stores the next execution snapshot but does not
  yet run feeding sessions or advance it after execution; that belongs to the
  MOB-016 scheduler. Per-tank inheritance and overrides belong to MOB-012.
  The development-only mobile repository displays configured local times but
  leaves server-authoritative UTC conversion to the backend.
- Recommended next task: MOB-012 — Per-tank schedule overrides.

### 2026-10-20 — MOB-012: Per-tank schedule overrides

- Status: Done
- Summary: Added explicit per-tank schedule modes. A tank can inherit the
  complete current schedule from its group or use a complete tank-specific
  replacement. Tank details clearly identify the source and effective times;
  owners can switch modes and edit overrides, while workers retain read-only
  visibility. Unassigned inherited tanks are automatically paused.
- Files added: Backend tank schedule mode and tank-feeding-time entities,
  Flyway migration, and Flutter tank feeding schedule screen.
- Files changed: Backend tank model, repository, service, controller,
  integration tests, and guide; Flutter tank domain/repository adapters, tank
  form/detail screens, development and test repositories, HTTP and widget
  tests, mobile guide, and this development record.
- Backend/API changes: Added owner-only
  `PUT /api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule`, the
  `schedule_mode` tank field, and `tank_feeding_times`. Tank responses expose
  schedule mode, while detail responses expose inherited, effective, and next
  execution values.
- Tests performed: Java 21 Maven integration/unit suite; inherited, override,
  role, validation, group-change, and unassigned-tank safety integration tests;
  Dart formatting; Flutter static analysis; focused API/widget tests; complete
  Flutter regression suite; and Android debug APK build.
- Test results: All 39 backend tests and all 49 Flutter tests passed; static
  analysis reported no issues; the Android debug APK built successfully.
- Decisions made: Treat overrides as complete replacements rather than partial
  additions; retain recurring times as facility-local `HH:mm` values and store
  override next occurrences as UTC instants; delete tank-specific times when
  returning to inheritance; immediately reflect later group schedule changes;
  limit overrides to 24 unique times; and fail safely by forcing automation
  off whenever an unassigned tank has no override.
- Known limitations: The scheduler does not yet consume or advance the stored
  next occurrence; that belongs to MOB-016. There is no bulk override editor,
  and enabling/disabling a tank's overall automation remains a separate tank
  setting. The override screen copies inherited times as an editing starting
  point but saves them as a full replacement.
- Recommended next task: MOB-013 — Feeder calibration and portion preview.

### 2026-10-20 — MOB-013: Feeder calibration and portion preview

- Status: Done
- Summary: Added immutable, versioned facility feeder calibrations and a
  tank-level portion preview. Owners can publish calibration versions using
  abstract feeder units; owners and workers can preview a bounded portion from
  detected, expected, or manually supplied fish counts. The interface avoids
  unvalidated physical-mass claims.
- Files added: Backend feeder calibration entity, repository, service,
  controller, and Flyway migration; Flutter calibration/portion domain model,
  portion preview screen, and calculation tests.
- Files changed: Backend tank integration tests and guide; Flutter facility
  repository contract and HTTP/development/test adapters, tank detail screen,
  repository/widget tests, mobile guide, and this development record.
- Backend/API changes: Added
  `GET/POST /api/v1/facilities/{facilityId}/feeder-calibration` and
  `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/portion-preview`.
  Added `feeder_calibrations`; each owner update appends a facility-unique
  version, and the latest version is active.
- Tests performed: Java 21 Maven integration/unit suite; calibration version,
  owner/worker authorization, default count, minimum, normal, maximum, and
  zero-fish calculation coverage; Dart formatting; Flutter static analysis;
  local fixed-decimal calculation tests; HTTP and owner/worker widget tests;
  complete Flutter regression suite; and Android debug APK build.
- Test results: All 41 backend tests and all 53 Flutter tests passed; static
  analysis reported no issues; the Android debug APK built successfully.
- Decisions made: Use facility-wide abstract feeder actuation units; calculate
  `fish count × units per fish` to four decimal places; apply a positive
  minimum and maximum while always returning zero movement for zero fish;
  default previews to detected count and then expected count; use scaled
  fixed-decimal arithmetic in Flutter to match backend decimal behavior; keep
  versions immutable; and restrict publishing to owners while allowing
  workers to inspect previews.
- Known limitations: Feeder units have not been converted to or displayed as
  physical mass because experimental validation is still required. The app
  displays only the active calibration rather than full version history.
  Calibration is facility-wide until device-specific feeder identity and
  health are introduced in MOB-014.
- Recommended next task: MOB-014 — Device health integration.

### 2026-10-20 — MOB-014: Device health integration

- Status: Done
- Summary: Added per-tank camera, edge-processor, and feeder identities with
  authenticated heartbeats and derived online, stale, offline, unhealthy, and
  not-configured states. Tank details now show component health and whether
  feeding is blocked. Owners can provision or rotate one-time device tokens;
  workers receive read-only health visibility.
- Files added: Backend device type/state and tank-device entities, repository,
  health service, controller, Flyway migration, and device-state unit test.
- Files changed: Backend security configuration, tank detail controller and
  integration tests, backend guide; Flutter tank domain and repository
  contract, HTTP/development/test adapters, tank detail screen, HTTP/widget
  tests, mobile guide, and this development record.
- Backend/API changes: Added authenticated member endpoint
  `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/device-health`, owner-only
  `POST /api/v1/facilities/{facilityId}/tanks/{tankId}/devices/{type}/provision`,
  and device-token-authenticated `POST /api/v1/device-heartbeats`. Tank detail
  responses now include aggregate and per-component health plus
  `feedingAllowed`. Device tokens are stored only as SHA-256 hashes.
- Tests performed: Java 21 Maven unit/integration suite; schema migration,
  membership, owner/worker authorization, credential validation, healthy and
  unhealthy heartbeat, aggregation, timeout-state, and feeding-safety tests;
  Dart formatting; Flutter static analysis; HTTP and widget tests; complete
  Flutter regression suite; and Android debug APK build.
- Test results: All 43 backend tests and all 55 Flutter tests passed; static
  analysis reported no issues; the Android debug APK built successfully.
- Decisions made: Require camera, edge processor, and feeder to all be online
  and healthy before feeding is allowed; mark heartbeats stale after two
  minutes and offline after ten; prioritize not-configured, unhealthy,
  offline, then stale when deriving aggregate health; return provisioning
  tokens once and invalidate the old token on rotation; reset health to
  offline after rotation; and keep heartbeat authentication separate from
  user JWT authentication.
- Known limitations: Automatic and manual feeder command flows do not exist
  until MOB-016 and MOB-020. MOB-014 supplies and tests the reusable
  `requireFeedingReady` safety gate, but those later command services must call
  it before dispatching hardware commands. Device credentials currently have
  no explicit revoke action beyond rotation, and heartbeat thresholds are
  fixed backend constants.
- Recommended next task: MOB-015 — Appetite-observation ingestion.

### 2026-10-21 — MOB-015: Appetite-observation ingestion

- Status: Done
- Summary: Added authenticated appetite-observation ingestion for tank edge
  processors. Observations retain the detected guppy count, confidence,
  appetite result, model version, observation/receipt times, and explicit
  safety flags. The latest observation and owner-review reasons now appear on
  tank details. Only valid observations update trusted tank count data or pass
  the reusable feeding-decision guard.
- Files added: Backend appetite result and observation entities, observation
  repository, service, controller, and Flyway migration.
- Files changed: Backend security configuration, tank model/detail controller,
  integration tests, and guide; Flutter tank domain, HTTP and test adapters,
  tank detail UI, repository/widget tests, mobile guide, and this development
  record.
- Backend/API changes: Added device-token-authenticated
  `POST /api/v1/device-observations` and member-authenticated
  `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-observation`.
  Tank detail responses now include the latest appetite observation. Added
  `appetite_observations` with source-device and tank relationships, safety
  flags, and a tank/time index. Device credential verification is reused from
  MOB-014.
- Tests performed: Clean Java 21 Maven unit/integration suite; Flyway
  migration, valid, stale, low-confidence, inconsistent-count, source-device
  type, tank-ownership, trusted-count update, and feeding-decision rejection
  tests; Dart formatting; Flutter static analysis; HTTP parsing and tank-detail
  widget tests; complete Flutter regression suite; and Android debug APK build.
- Test results: All 44 backend tests and all 55 Flutter tests passed; all 10
  source migrations applied on a clean build; formatting required no changes;
  static analysis reported no issues; and the Android debug APK built
  successfully.
- Decisions made: Accept observations only from a provisioned edge processor
  assigned to the same tank; treat data older than five minutes or more than
  one minute in the future as stale; flag confidence below 80%; flag a count
  difference greater than the larger of five fish or 20% of the expected
  count; retain invalid observations for audit/review without replacing the
  trusted detected count; and re-check freshness when a feeding decision is
  requested so previously valid data cannot remain usable indefinitely.
- Known limitations: MOB-015 exposes only the latest observation in the app;
  filterable history belongs to later monitoring work. Appetite is currently
  binary (`HIGH` or `LOW`) and thresholds are backend constants. Ingestion
  does not yet deduplicate retried edge observations. The guard validates the
  observation, but the complete health, schedule, cooldown, appetite outcome,
  portion, command, and retry flow belongs to MOB-016.
- Recommended next task: MOB-016 — Scheduled feeding-session state machine.

### 2026-10-21 — MOB-016: Scheduled feeding-session state machine

- Status: Done
- Summary: Added the scheduled feeding state machine and background scheduler.
  Every tank/schedule occurrence creates at most one durable session. The
  decision path checks automation, required device health, cooldown,
  observation freshness, confidence, fish-count consistency, appetite, and a
  positive bounded calibration before making a feeder command available.
  Commands remain `COMMAND_SENT` until authenticated feeder feedback explicitly
  records `DELIVERED` or `FAILED`.
- Files added: Feeding outcome and session models; feeding-session, group-time,
  and tank-time repositories; state-machine and scheduler services;
  feeding-session/feeder-command controller; and Flyway migration V11.
- Files changed: Backend application scheduling and security configuration;
  group/tank schedule models; tank repository; calibration service; tank API
  integration tests; backend guide; and this development record.
- Backend/API changes: Added the `feeding_sessions` table with a unique
  tank/scheduled-occurrence key and indexed pending-command lookup. Added member
  `GET /api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-session/latest`,
  device-authenticated `GET /api/v1/feeder-commands/next`, and
  `POST /api/v1/feeder-commands/{sessionId}/feedback`. Enabled a 30-second
  scheduler and normalized occurrences to database timestamp precision.
- Tests performed: Clean Java 21 Maven unit/integration suite; migration and
  state tests for paused automation, unhealthy hardware, missing/stale
  observation, low confidence, count inconsistency, low appetite, missing
  calibration, command creation, idempotent retry, cooldown, feeder polling,
  repeated/conflicting feedback, failed feedback, and confirmed delivery; Dart
  formatting; Flutter static analysis; complete Flutter regression suite; and
  Android debug APK build.
- Test results: All 45 backend tests and all 55 Flutter tests passed; all 11
  source migrations applied on a clean build; formatting required no changes;
  Flutter static analysis reported no issues; and the Android debug APK built
  successfully.
- Decisions made: Use a durable outcome per scheduled occurrence; serialize
  same-tank processing with a database lock and also enforce a unique database
  key; apply a 15-minute cooldown from the latest sent command; process only
  positive, bounded calibrated portions; use device credentials for command
  polling and feedback; and never equate command dispatch with physical food
  delivery.
- Known limitations: The feeder currently polls for commands and pending
  commands have no expiry/timeout policy. Feeding history and mobile dashboard
  visibility belong to MOB-017, alerts belong to MOB-018, and manual feeding
  belongs to MOB-020. Multi-instance scheduler claiming has not yet been added,
  so production scheduling should run as a single scheduler instance until a
  distributed claim/lease mechanism is implemented.
- Recommended next task: MOB-017 — Dashboard and feeding history.

