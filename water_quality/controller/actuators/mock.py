"""Simulated actuator: no hardware, it only writes to the log.

Run-time accounting is identical to a real actuator (it lives in the base
class), so resource metrics collected now remain valid later.
"""
from __future__ import annotations

import logging

from .base import Actuator

log = logging.getLogger("aquasense.actuator.mock")


class MockActuator(Actuator):
    def _drive(self, on: bool) -> None:
        log.info("[MOCK] %s/%s -> %s", self.tank_id, self.name, "ON" if on else "OFF")

    def _drive_pulse(self, seconds: float) -> None:
        log.info("[MOCK] %s/%s -> PULSE %.1fs", self.tank_id, self.name, seconds)
