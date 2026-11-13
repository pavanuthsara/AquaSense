"""Plain data objects passed between the pipeline stages.

    Reading       one timestamped sample of every configured parameter
    Command       what a control engine wants an actuator to do
    ActuatorEvent an ON/OFF transition that actually happened (logged to DB)
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class Status(str, Enum):
    OK = "OK"
    WARNING = "WARNING"      # outside the safe range
    CRITICAL = "CRITICAL"    # outside the safe range by more than critical_margin
    FAULT = "FAULT"          # physically impossible value -> sensor problem
    MISSING = "MISSING"      # parameter not measured in this reading


class Mode(str, Enum):
    AUTO = "AUTO"
    MANUAL = "MANUAL"


@dataclass
class ParamValue:
    name: str
    value: Optional[float]
    source: Optional[str]          # payload | simulated | derived | None
    status: Status = Status.MISSING
    side: Optional[str] = None     # "low" | "high" when out of range


@dataclass
class Reading:
    tank_id: str
    ts: float                                   # epoch seconds (sensor time)
    values: dict[str, ParamValue] = field(default_factory=dict)

    def usable(self, name: str) -> Optional[float]:
        """Value safe to use for control: None if missing or a sensor fault."""
        pv = self.values.get(name)
        if pv is None or pv.value is None or pv.status in (Status.FAULT, Status.MISSING):
            return None
        return pv.value


@dataclass
class Command:
    actuator: str
    action: str                    # "on" | "off" | "pulse"
    reason: str = ""
    parameter: Optional[str] = None
    duration_s: float = 0.0        # only for "pulse"


@dataclass
class ActuatorEvent:
    tank_id: str
    actuator: str
    action: str                    # "ON" | "OFF"
    ts: float
    source: str                    # "auto" | "manual" | "system"
    engine: str
    reason: str = ""
    duration_s: Optional[float] = None   # set on OFF: how long it was ON
