"""Actuator interface.

The base class does all the bookkeeping that the research needs (state,
ON timestamp, run-time of each ON period, pulse count). Subclasses only
implement how to physically switch the device: `_drive()` and `_drive_pulse()`.
So the mock and the real ESP32 driver produce identical logs.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from ..core.config import ActuatorConfig
from ..core.models import ActuatorEvent


class ActuatorError(RuntimeError):
    """Raised by a driver when the hardware command failed."""


class Actuator(ABC):
    def __init__(self, cfg: ActuatorConfig, tank_id: str) -> None:
        self.cfg = cfg
        self.name = cfg.name
        self.tank_id = tank_id
        self.is_on = False
        self.on_since: Optional[float] = None
        self.pulses = 0                      # cumulative pulse count (for the simulator)
        self.last_pulse_ts: Optional[float] = None

    # ----------------------------------------------------- hardware (override)
    @abstractmethod
    def _drive(self, on: bool) -> None:
        """Physically switch the device ON or OFF."""

    @abstractmethod
    def _drive_pulse(self, seconds: float) -> None:
        """Run the device for `seconds` then stop (timed on the device)."""

    # ------------------------------------------------------------ bookkeeping
    def _event(self, action, ts, source, engine, reason, duration=None) -> ActuatorEvent:
        return ActuatorEvent(self.tank_id, self.name, action, ts, source, engine, reason, duration)

    def turn_on(self, ts: float, source: str, engine: str, reason: str = "") -> list[ActuatorEvent]:
        if self.is_on:
            return []
        self._drive(True)
        self.is_on, self.on_since = True, ts
        return [self._event("ON", ts, source, engine, reason)]

    def turn_off(self, ts: float, source: str, engine: str, reason: str = "") -> list[ActuatorEvent]:
        if not self.is_on:
            return []
        self._drive(False)
        duration = max(0.0, ts - (self.on_since or ts))
        self.is_on, self.on_since = False, None
        return [self._event("OFF", ts, source, engine, reason, duration)]

    def pulse(self, ts: float, seconds: float, source: str, engine: str,
              reason: str = "") -> list[ActuatorEvent]:
        """A fixed-length run, logged as an ON/OFF pair `seconds` apart."""
        if self.is_on:
            return []
        self._drive_pulse(seconds)
        self.pulses += 1
        self.last_pulse_ts = ts
        return [self._event("ON", ts, source, engine, reason),
                self._event("OFF", ts + seconds, source, engine, "pulse complete", seconds)]

    def restore(self, is_on: bool, on_since: Optional[float]) -> None:
        """Restore state from the database after a restart (no hardware call)."""
        self.is_on, self.on_since = is_on, on_since if is_on else None

    def current_run_s(self, now: float) -> float:
        """Seconds of the ON period still in progress (0 if OFF)."""
        return max(0.0, now - self.on_since) if self.is_on and self.on_since else 0.0
