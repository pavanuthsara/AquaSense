"""Sensor-time clock.

All durations (actuator run-time, time out of range) are measured on the
*readings' own timestamps*, not on the server's wall clock. That way a CSV
replayed at 100x speed still yields run-time in real pond hours, and the
baseline and predictive controllers can be compared on identical data.

For a live ESP32 the two clocks are the same anyway.
"""
from __future__ import annotations

import time
from typing import Optional


class SensorClock:
    def __init__(self) -> None:
        self._latest: dict[str, float] = {}

    def advance(self, tank_id: str, ts: float) -> float:
        """Record a new reading time. Time never runs backwards: an
        out-of-order reading is processed at the latest known time."""
        now = max(ts, self._latest.get(tank_id, ts))
        self._latest[tank_id] = now
        return now

    def last(self, tank_id: str) -> Optional[float]:
        """Time of the latest reading, or None if the tank has never reported."""
        return self._latest.get(tank_id)

    def now(self, tank_id: str) -> float:
        """Current sensor time for a tank (wall clock if no reading yet)."""
        return self._latest.get(tank_id, time.time())

    def seed(self, tank_id: str, ts: float) -> None:
        """Restore the clock from the database after a restart."""
        self._latest[tank_id] = max(ts, self._latest.get(tank_id, ts))
