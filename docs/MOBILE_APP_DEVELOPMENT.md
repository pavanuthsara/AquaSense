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

No task is currently in progress.

**Recommended next task:** MOB-002 — Three onboarding screens.

## Task Backlog

| ID | Task | Depends on | Status |
|---|---|---|---|
| MOB-001 | Flutter application foundation | — | Done |
| MOB-002 | Three onboarding screens | MOB-001 | Not started |
| MOB-003 | Authentication interface and secure session handling | MOB-001 | Not started |
| MOB-004 | Google authentication backend | MOB-003 | Not started |
| MOB-005 | Aquarium facility creation | MOB-004 | Not started |
| MOB-006 | Multiple-facility switching | MOB-005 | Not started |
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

