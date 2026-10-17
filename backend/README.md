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

## Verify

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
.\mvnw.cmd test
```

Tests use an in-memory database and test-only token configuration.
