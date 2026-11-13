"""Real sensor: the value is whatever the device sent in its JSON payload."""
from __future__ import annotations

from typing import Optional

from .base import ActuatorActivity, SensorSource


class PayloadSource(SensorSource):
    def read(self, payload_value: Optional[float], ts: float,
             activity: ActuatorActivity) -> tuple[Optional[float], Optional[str]]:
        if payload_value is None:
            return None, None          # sensor did not report this time
        return payload_value, "payload"
