# AquaSense Backend

Spring Boot API for AquaSense. MOB-004 adds Google identity exchange and
AquaSense-owned access and refresh sessions.

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

The Google client ID must be the Web OAuth client ID also passed to the Flutter
app as `AQUASENSE_GOOGLE_SERVER_CLIENT_ID`. Flyway creates the authentication
tables when the API starts.

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

- `POST /api/v1/auth/google/exchange` validates a Google ID token and returns
  AquaSense access and refresh tokens.
- `POST /api/v1/auth/refresh` rotates a valid refresh token.
- `GET /api/v1/auth/me` returns the user for a valid AquaSense access token.
- `POST /api/v1/auth/logout` revokes the supplied refresh token.

Every other API route is protected unless it is explicitly allowed by the
security configuration. Raw refresh tokens are never stored in the database;
only SHA-256 hashes are retained.

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

Active group names are unique within an aquarium after whitespace and case
normalization. Archived groups are retained for history and returned after
active groups. A group with a nonzero tank count cannot be archived; MOB-009
maintains this server-owned count when tanks are created, moved, or archived.

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

Tank codes are unique within an aquarium after case normalization. Tags are
stored in lowercase, group assignments are aquarium-scoped, and group counts
are updated in the same database transaction as every tank assignment change.
Workers can search and inspect tanks but cannot create, edit, move, or archive
them. Device health, feeding schedules, observations, and feeding history are
represented by explicit not-configured/no-data states until their later tasks
provide those records.

## Verify

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
.\mvnw.cmd test
```

Tests use an in-memory database and test-only token configuration.
