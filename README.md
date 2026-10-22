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
cd backend
docker compose --env-file ../.env up --build -d
docker compose --env-file ../.env logs -f backend
```

Compose lives in `backend/compose.yaml` and starts only the API and PostgreSQL.
Flutter runs from `mobile_app/`; camera tracking and ML run from the repository
root. The explicit `--env-file` keeps the existing root configuration in use.

## Research dependencies

The Python research workflow is separate from the API and mobile setup:

```text
pip install ultralytics opencv-python numpy pandas
```

For live tracking, behavior extraction, and a local PRE-only appetite model,
see the [live appetite guide](docs/LIVE_APPETITE.md). Training and inference
also require `scikit-learn` and `joblib` in the research environment.
