"""Behavioural tests of the baseline: thresholds, hysteresis, pulses,
run-time accounting, alerts, modes and the REST API."""
from fastapi.testclient import TestClient

from controller.core.models import Reading, ParamValue, Status
from controller.core.ranges import classify
from controller.engines.threshold import ThresholdEngine
from controller.main import create_app
from controller.sensors.derived import unionised_ammonia

from .conftest import T0


def reading(ts, **values):
    r = Reading("tank1", ts)
    for k, v in values.items():
        r.values[k] = ParamValue(k, v, "payload", Status.OK)
    return r


# ------------------------------------------------------------- classification
def test_classify(settings):
    t = settings.parameters["temperature"]          # 24..28, critical margin 2
    assert classify(t, 26.0) == (Status.OK, None)
    assert classify(t, 23.5) == (Status.WARNING, "low")
    assert classify(t, 21.0) == (Status.CRITICAL, "low")
    assert classify(t, 28.5) == (Status.WARNING, "high")
    assert classify(t, -127.0) == (Status.FAULT, None)  # DS18B20 unplugged
    assert classify(t, None) == (Status.MISSING, None)


# ------------------------------------------------------------- engine logic
def test_hold_rule_with_hysteresis(settings):
    eng = ThresholdEngine(settings)                 # DO min 5.0, deadband 0.3
    off, on = {"aerator": {"on": False}}, {"aerator": {"on": True}}
    assert [c.action for c in eng.decide(reading(T0, do=4.8), off)] == ["on"]
    assert eng.decide(reading(T0, do=5.1), on) == []          # inside deadband: stay ON
    assert [c.action for c in eng.decide(reading(T0, do=5.4), on)] == ["off"]
    assert eng.decide(reading(T0, do=6.0), off) == []


def test_pulse_rule_cooldown(settings):
    eng = ThresholdEngine(settings)                 # pH 6.5..8.0, 5 s pulse, 600 s cooldown
    cmds = eng.decide(reading(T0, ph=6.2), {"dosing_pump": {"on": False, "last_pulse_ts": None}})
    assert cmds[0].action == "pulse" and cmds[0].duration_s == 5
    state = {"dosing_pump": {"on": False, "last_pulse_ts": T0}}
    assert eng.decide(reading(T0 + 300, ph=6.2), state) == []          # locked out
    assert len(eng.decide(reading(T0 + 600, ph=6.2), state)) == 1      # cooldown over


def test_sensor_fault_is_ignored(service):
    out = service.ingest({"tank_id": "tank1", "timestamp": T0, "temperature": -127})
    assert out["values"]["temperature"]["status"] == "FAULT"
    assert not any(e["actuator"] == "heater" for e in out["actuator_events"])


# ------------------------------------------------- end-to-end via the service
def test_heater_runtime_uses_sensor_time(service):
    service.ingest({"tank_id": "tank1", "timestamp": T0, "temperature": 23.0})           # ON
    service.ingest({"tank_id": "tank1", "timestamp": T0 + 600, "temperature": 23.9})     # still ON
    service.ingest({"tank_id": "tank1", "timestamp": T0 + 1200, "temperature": 24.1})    # deadband: ON
    out =service.ingest({"tank_id": "tank1", "timestamp": T0 + 1800, "temperature": 24.5})  # OFF
    assert [e["action"] for e in out["actuator_events"] if e["actuator"] == "heater"] == ["OFF"]
    heater = next(a for a in service.state("tank1")["actuators"] if a["name"] == "heater")
    assert heater["runtime_s"] == 1800
    assert heater["switch_ons"] == 1
    assert heater["energy_wh"] == 50.0             # 0.5 h x 100 W


def test_data_gap_watchdog(service):
    service.ingest({"tank_id": "tank1", "timestamp": T0, "temperature": 23.0})              # heater ON
    out = service.ingest({"tank_id": "tank1", "timestamp": T0 + 86400, "temperature": 23.0})  # 1 day later
    heater = next(a for a in service.state("tank1")["actuators"] if a["name"] == "heater")
    assert heater["is_on"]                                     # re-decided on the new reading
    assert heater["runtime_s"] == service.settings.data_gap_s  # not 86400
    assert any(a["parameter"] == "temperature" for a in out["alerts_raised"])  # new episode


def test_alert_episode_lifecycle(service):
    service.ingest({"tank_id": "tank1", "timestamp": T0, "temperature": 23.5})        # WARNING
    service.ingest({"tank_id": "tank1", "timestamp": T0 + 60, "temperature": 21.0})   # -> CRITICAL
    active = service.storage.active_alerts("tank1")
    temp_alert = next(a for a in active if a["parameter"] == "temperature")
    assert temp_alert["severity"] == "CRITICAL" and temp_alert["peak_value"] == 21.0
    service.ingest({"tank_id": "tank1", "timestamp": T0 + 120, "temperature": 25.0})  # clear
    log = [a for a in service.storage.alerts("tank1") if a["parameter"] == "temperature"]
    assert len(log) == 1 and log[0]["cleared_at"] == T0 + 120


def test_manual_mode(service):
    import pytest
    with pytest.raises(PermissionError):
        service.manual_command("tank1", "aerator", "on")          # AUTO: refused
    service.set_mode("tank1", "MANUAL")
    out = service.ingest({"tank_id": "tank1", "timestamp": T0, "temperature": 20.0})
    assert out["actuator_events"] == []                           # engine does not act
    assert out["alerts_raised"]                                   # but alerts still fire
    assert service.manual_command("tank1", "aerator", "on")[0]["action"] == "ON"


def test_simulated_parameters_fill_in(service):
    out = service.ingest({"tank_id": "tank1", "timestamp": T0, "temperature": 25.0})
    assert out["values"]["temperature"]["source"] == "payload"
    assert out["values"]["do"]["source"] == "simulated"
    assert out["values"]["nh3"]["source"] == "derived"
    out = service.ingest({"tank_id": "tank1", "timestamp": T0 + 60, "temperature": 25.0, "do": 7.1})
    assert out["values"]["do"] == {"value": 7.1, "source": "payload", "status": "OK"}


def test_unionised_ammonia():
    # ~1.7 % of TAN is NH3 at pH 7.5 / 25 °C (textbook value)
    assert abs(unionised_ammonia({"ammonia": 1.0, "ph": 7.5, "temperature": 25}) - 0.0175) < 0.001


# --------------------------------------------------------------------- API
def test_api_roundtrip(settings):
    with TestClient(create_app(settings)) as client:
        r = client.post("/api/readings", json={"tank_id": "t9", "timestamp": T0, "temperature": 23})
        assert r.status_code == 200
        assert client.post("/api/readings", json={"temperature": "hot"}).status_code == 422
        assert client.post("/api/actuators/heater", json={"tank_id": "t9", "action": "off"}).status_code == 409
        state = client.get("/api/state", params={"tank_id": "t9"}).json()
        assert any(a["name"] == "heater" and a["is_on"] for a in state["actuators"])
        m = client.get("/api/metrics", params={"tank_id": "t9"}).json()
        assert m["response"]["temperature->heater"]["acted_on"] == 1
        assert client.get("/").status_code == 200   # dashboard served
