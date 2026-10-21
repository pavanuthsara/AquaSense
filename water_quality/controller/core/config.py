"""Load and validate config.yaml into typed dataclasses.

The rest of the code only ever sees these dataclasses, never raw YAML, so a
typo in the config fails loudly at start-up instead of silently at run-time.

Environment overrides:
    AQUASENSE_CONFIG  path to an alternative config file
    AQUASENSE_DB      path to the SQLite database (one per experiment run)
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.yaml"

SOURCES = {"payload", "simulated", "auto", "derived"}
DRIVERS = {"mock", "esp32_http"}
CONDITIONS = {"below_min", "above_max", "out_of_range"}
ACTIONS = {"hold", "pulse"}
MODES = {"AUTO", "MANUAL"}


@dataclass
class ParameterConfig:
    name: str
    label: str
    unit: str
    source: str
    min: Optional[float]
    max: Optional[float]
    deadband: float = 0.0
    critical_margin: float = 0.0
    valid_min: Optional[float] = None
    valid_max: Optional[float] = None
    derive: Optional[str] = None
    simulation: dict = field(default_factory=dict)


@dataclass
class ActuatorConfig:
    name: str
    label: str
    driver: str
    power_w: float = 0.0
    options: dict = field(default_factory=dict)  # driver-specific, e.g. url


@dataclass
class RuleConfig:
    parameter: str
    condition: str
    actuator: str
    action: str = "hold"
    pulse_seconds: float = 0.0
    cooldown_seconds: float = 0.0


@dataclass
class MqttConfig:
    enabled: bool = False
    host: str = "localhost"
    port: int = 1883
    topic: str = "aquasense/+/readings"


@dataclass
class Settings:
    db_path: Path
    default_tank: str
    default_mode: str
    engine: str
    data_gap_s: Optional[float]
    mqtt: MqttConfig
    parameters: dict[str, ParameterConfig]
    actuators: dict[str, ActuatorConfig]
    rules: list[RuleConfig]


def _require(cond: bool, msg: str) -> None:
    if not cond:
        raise ValueError(f"config.yaml: {msg}")


def load_settings(path: str | Path | None = None) -> Settings:
    path = Path(path or os.environ.get("AQUASENSE_CONFIG") or DEFAULT_CONFIG_PATH)
    raw = yaml.safe_load(path.read_text())

    parameters: dict[str, ParameterConfig] = {}
    for name, p in (raw.get("parameters") or {}).items():
        p = dict(p)
        param = ParameterConfig(
            name=name,
            label=p.pop("label", name),
            unit=p.pop("unit", ""),
            source=p.pop("source", "payload"),
            min=p.pop("min", None),
            max=p.pop("max", None),
            deadband=float(p.pop("deadband", 0.0)),
            critical_margin=float(p.pop("critical_margin", 0.0)),
            valid_min=p.pop("valid_min", None),
            valid_max=p.pop("valid_max", None),
            derive=p.pop("derive", None),
            simulation=p.pop("simulation", {}) or {},
        )
        _require(not p, f"parameter '{name}' has unknown keys {list(p)}")
        _require(param.source in SOURCES, f"parameter '{name}': source must be one of {SOURCES}")
        _require(param.source != "derived" or param.derive,
                 f"parameter '{name}': derived parameters need a 'derive' function name")
        parameters[name] = param

    actuators: dict[str, ActuatorConfig] = {}
    for name, a in (raw.get("actuators") or {}).items():
        a = dict(a)
        act = ActuatorConfig(
            name=name,
            label=a.pop("label", name),
            driver=a.pop("driver", "mock"),
            power_w=float(a.pop("power_w", 0.0)),
            options=a,  # whatever is left is passed to the driver
        )
        _require(act.driver in DRIVERS, f"actuator '{name}': driver must be one of {DRIVERS}")
        actuators[name] = act

    rules: list[RuleConfig] = []
    for r in raw.get("rules") or []:
        rule = RuleConfig(**r)
        _require(rule.parameter in parameters, f"rule references unknown parameter '{rule.parameter}'")
        _require(rule.actuator in actuators, f"rule references unknown actuator '{rule.actuator}'")
        _require(rule.condition in CONDITIONS, f"rule condition must be one of {CONDITIONS}")
        _require(rule.action in ACTIONS, f"rule action must be one of {ACTIONS}")
        _require(rule.action != "pulse" or rule.pulse_seconds > 0, "pulse rules need pulse_seconds > 0")
        rules.append(rule)

    db = Path(os.environ.get("AQUASENSE_DB") or raw.get("database", "controller.db"))
    if not db.is_absolute() and "AQUASENSE_DB" not in os.environ:
        db = path.parent / db  # relative to the config file, not the cwd

    mode = str(raw.get("default_mode", "AUTO")).upper()
    _require(mode in MODES, f"default_mode must be one of {MODES}")

    return Settings(
        db_path=db,
        default_tank=str(raw.get("default_tank", "tank1")),
        default_mode=mode,
        engine=raw.get("engine", "threshold"),
        data_gap_s=raw.get("data_gap_s"),
        mqtt=MqttConfig(**(raw.get("mqtt") or {})),
        parameters=parameters,
        actuators=actuators,
        rules=rules,
    )
