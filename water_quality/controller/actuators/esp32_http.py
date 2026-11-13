"""Real actuator driven by the ESP32 over HTTP (for when relays are wired).

Expected ESP32 endpoint (to implement in the firmware):

    POST {url}/actuator
    {"tank_id": "tank1", "actuator": "aerator", "state": "ON"}          # hold
    {"tank_id": "tank1", "actuator": "dosing_pump", "pulse_seconds": 5} # pulse

Respond with HTTP 200 on success. Pulse timing is done on the ESP32 so a
lost network connection cannot leave the pump running.

Enable in config.yaml:
    dosing_pump:
      driver: esp32_http
      url: http://192.168.1.50
"""
from __future__ import annotations

import json
import urllib.request

from .base import Actuator, ActuatorError

TIMEOUT_S = 3


class Esp32HttpActuator(Actuator):
    def _post(self, body: dict) -> None:
        url = self.cfg.options.get("url")
        if not url:
            raise ActuatorError(f"actuator '{self.name}': esp32_http driver needs a 'url'")
        req = urllib.request.Request(
            url.rstrip("/") + "/actuator",
            data=json.dumps({"tank_id": self.tank_id, "actuator": self.name, **body}).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
                if resp.status != 200:
                    raise ActuatorError(f"ESP32 returned HTTP {resp.status}")
        except OSError as exc:  # connection refused, timeout, DNS, ...
            raise ActuatorError(f"ESP32 unreachable at {url}: {exc}") from exc

    def _drive(self, on: bool) -> None:
        self._post({"state": "ON" if on else "OFF"})

    def _drive_pulse(self, seconds: float) -> None:
        self._post({"pulse_seconds": seconds})
