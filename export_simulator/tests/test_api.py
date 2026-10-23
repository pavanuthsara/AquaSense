import pytest
from fastapi.testclient import TestClient

from transit_sim.api import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json()["status"] == "ok"


def test_options_lists_species_and_addons():
    body = client.get("/v1/options").json()
    assert {s["key"] for s in body["species"]} >= {"guppy", "tiger_barb"}
    assert "ms222_40mgL" in body["anaesthetics"]
    assert "zeolite" in body["addons"]


def test_advisory_endpoint():
    r = client.post("/v1/advisory", json={"species": "guppy", "fish_mass_g": 0.3, "total_fish": 500, "water_l": 0.4,
                                          "gas_l": 1.2, "duration_h": 24, "temp_low_c": 24, "temp_high_c": 27,
                                          "samples": 2})
    assert r.status_code == 200
    body = r.json()
    assert body["feasible"] and body["recommendation"]["fish_per_bag"] > 0
    assert body["oxygen"]["explanation"]
    assert r.headers["X-Advisory-Feasible"] == "true"
    assert int(r.headers["X-Advisory-Fish-Per-Bag"]) == body["recommendation"]["fish_per_bag"]
    assert int(r.headers["X-Advisory-Bags-Needed"]) == body["recommendation"]["bags_needed"]


def test_advisory_validation():
    assert client.post("/v1/advisory", json={"water_l": -1}).status_code == 422
    assert client.post("/v1/advisory", json={"species": "shark"}).status_code == 422


def test_simulate_endpoint():
    r = client.post("/v1/simulate", json={"fish_count": 20, "fish_mass_g": 0.3, "water_l": 0.4, "gas_l": 1.2,
                                          "duration_h": 12, "anaesthetic": "ms222_40mgL"})
    assert r.status_code == 200
    assert r.json()["summary"]["survival_at_arrival"] > 0.9


def test_service_key(monkeypatch):
    monkeypatch.setenv("EXPORT_SIM_SERVICE_KEY", "s3cret")
    assert client.get("/v1/options").status_code == 401
    assert client.get("/v1/options", headers={"X-Service-Key": "s3cret"}).status_code == 200
    assert client.get("/health").status_code == 200


def test_check_mode_endpoint():
    r = client.post("/v1/advisory", json={"total_fish": 1000, "water_l": 0.4, "gas_l": 1.2, "duration_h": 36,
                                          "temp_low_c": 24, "temp_high_c": 28, "samples": 0,
                                          "mode": "check", "fish_per_bag": 150})
    assert r.status_code == 200
    assert r.json()["verdict"]["meets_target"] is False
    assert r.headers["X-Advisory-Meets-Target"] == "false"
    bad = client.post("/v1/advisory", json={"mode": "check", "fish_per_bag": 10, "check_anaesthetic": "x"})
    assert bad.status_code == 422
