# AquaSense

Appetite-based fish feeding and aquarium monitoring system.

## Start developing

Follow the [new developer setup guide](docs/DEVELOPER_SETUP.md) to run the
backend and PostgreSQL with Docker and connect the Flutter mobile app.

- `backend/`: Java 21 / Spring Boot API; [backend documentation](backend/README.md).
- `mobile_app/`: Flutter app; [mobile documentation](mobile_app/README.md).
- Root Python scripts: fish detection, tracking, and appetite research.

Docker setup, from the repository root:

```powershell
Copy-Item .env.example .env
# Fill in .env using the setup guide before starting.
docker compose up --build -d
docker compose logs -f backend
```

## Research dependencies

The Python research workflow is separate from the API and mobile setup:

```text
pip install ultralytics opencv-python numpy pandas
```
