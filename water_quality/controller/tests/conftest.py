import pytest

from controller.core.config import load_settings
from controller.core.storage import Storage
from controller.services.ingest import IngestService

T0 = 1_760_000_000.0  # fixed sensor time so tests are deterministic


@pytest.fixture
def settings(tmp_path, monkeypatch):
    monkeypatch.setenv("AQUASENSE_DB", str(tmp_path / "test.db"))
    return load_settings()


@pytest.fixture
def service(settings):
    return IngestService(settings, Storage(settings.db_path), seed=1)
