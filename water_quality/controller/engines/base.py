"""Control-engine interface.

An engine looks at the latest reading (and the current actuator states) and
returns the commands it wants executed. It never touches hardware, storage or
alerts itself. That separation is what makes the research comparison fair:
the threshold baseline and the predictive controller plug into the *same*
ingestion, actuators and run-time accounting; only `decide()` differs.

To add the predictive controller later:
    1. class PredictiveEngine(ControlEngine) in engines/predictive.py
    2. register it in engines/__init__.py
    3. set `engine: predictive` in config.yaml
"""
from __future__ import annotations

from abc import ABC, abstractmethod

from ..core.config import Settings
from ..core.models import Command, Reading


class ControlEngine(ABC):
    name: str = "base"

    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    @abstractmethod
    def decide(self, reading: Reading, actuators: dict[str, dict]) -> list[Command]:
        """`actuators` maps name -> {"on": bool, "pulses": int, "last_pulse_ts": float|None}."""
