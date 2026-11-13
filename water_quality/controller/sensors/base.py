"""Sensor-source interface.

Every configured parameter gets one SensorSource per tank. The ingest service
asks each source for a value; it does not care whether that value came from
the ESP32 JSON, a simulator, or a formula. Swapping a simulated sensor for a
real one is therefore a one-word change of `source:` in config.yaml.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

# What the plant simulator needs to know about actuators:
#   {"aerator": {"on": True, "pulses": 0}, "dosing_pump": {"on": False, "pulses": 3}}
ActuatorActivity = dict[str, dict]


class SensorSource(ABC):
    @abstractmethod
    def read(self, payload_value: Optional[float], ts: float,
             activity: ActuatorActivity) -> tuple[Optional[float], Optional[str]]:
        """Return (value, origin) where origin is 'payload' or 'simulated'
        (or (None, None) if the parameter is not available)."""
