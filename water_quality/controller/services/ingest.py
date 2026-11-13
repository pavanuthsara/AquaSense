"""The control loop: one call to `ingest()` per sensor reading.

    payload JSON
        -> resolve every parameter (real / simulated / derived)   sensors/
        -> classify against safe ranges                           core/ranges.py
        -> store reading                                          core/storage.py
        -> raise / clear alerts                                   services/alerts.py
        -> if AUTO: engine decides, actuators execute + log       engines/, actuators/

REST, MQTT and the replay tools all end up here, so every input path behaves
identically. A single lock serialises the loop (readings, manual commands and
mode changes never interleave).
"""
from __future__ import annotations

import logging
import math
import random
import threading
import time
from datetime import datetime, timezone
from typing import Any, Optional

from ..actuators.manager import ActuatorManager
from ..core.clock import SensorClock
from ..core.config import Settings
from ..core.models import Command, Mode, ParamValue, Reading, Status
from ..core.ranges import classify
from ..core.storage import Storage
from ..engines import build_engine
from ..sensors import build_source
from ..sensors.base import SensorSource
from ..sensors.derived import DERIVATIONS
from .alerts import AlertService

log = logging.getLogger("aquasense.ingest")

# Alternative field names accepted from devices.
ALIASES = {"temp": "temperature", "dissolved_oxygen": "do", "pH": "ph", "tan": "ammonia"}


def parse_timestamp(value: Any) -> float:
    """Accept epoch seconds, epoch milliseconds, ISO-8601 text, or nothing (= now)."""
    if value is None or value == "":
        return time.time()
    if isinstance(value, (int, float)):
        return value / 1000 if value > 1e12 else float(value)
    try:
        return parse_timestamp(float(value))
    except ValueError:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()


class IngestService:
    def __init__(self, settings: Settings, storage: Storage, seed: Optional[int] = None) -> None:
        self.settings = settings
        self.storage = storage
        self.clock = SensorClock()
        self.engine = build_engine(settings)
        self.actuators = ActuatorManager(settings, storage)
        self.alerts = AlertService(settings, storage, self.engine.name)
        self.rng = random.Random(seed)
        self._sensors: dict[str, dict[str, SensorSource]] = {}
        self._modes: dict[str, str] = storage.get_modes()
        self.lock = threading.RLock()
        self.version = 0  # bumped on every change; the dashboard stream watches it

        # Resume where we left off after a restart.
        for tank_id, ts in storage.latest_ts().items():
            self.clock.seed(tank_id, ts)
        self.actuators.restore()

    # ------------------------------------------------------------------ helpers
    def _sensors_for(self, tank_id: str) -> dict[str, SensorSource]:
        if tank_id not in self._sensors:
            self._sensors[tank_id] = {
                name: build_source(cfg, self.rng)
                for name, cfg in self.settings.parameters.items() if cfg.source != "derived"
            }
        return self._sensors[tank_id]

    def mode(self, tank_id: str) -> str:
        return self._modes.get(tank_id, self.settings.default_mode)

    def tanks(self) -> list[str]:
        return sorted(set(self.storage.tanks()) | set(self._modes) | {self.settings.default_tank})

    def _watchdog(self, tank_id: str, ts: float) -> None:
        """After a data outage longer than `data_gap_s`, log running actuators
        OFF and close alerts at the moment the outage began (last reading +
        data_gap_s). The engine then decides afresh on the new reading."""
        gap, last = self.settings.data_gap_s, self.clock.last(tank_id)
        if not gap or last is None or ts - last <= gap:
            return
        cutoff = last + gap
        log.warning("tank %s: no data for %.0fs, watchdog at %.0f", tank_id, ts - last, cutoff)
        for name, act in self.actuators.for_tank(tank_id).items():
            if act.is_on:
                self.actuators.execute(tank_id, Command(name, "off", f"no data for {gap:.0f}s (watchdog)"),
                                       cutoff, "system", self.engine.name)
        self.alerts.close_all(tank_id, cutoff)

    # ------------------------------------------------------------- main loop
    def ingest(self, payload: dict, commit: bool = True) -> dict:
        """Process one reading. Raises ValueError on malformed input."""
        payload = {ALIASES.get(k, k): v for k, v in payload.items()}
        tank_id = str(payload.get("tank_id") or self.settings.default_tank)
        ts = parse_timestamp(payload.get("timestamp"))

        with self.lock:
            self._watchdog(tank_id, ts)
            # Time never runs backwards (see core/clock.py).
            now = self.clock.advance(tank_id, ts)
            activity = self.actuators.activity(tank_id)
            reading = Reading(tank_id, now)

            # 1. measured / simulated parameters
            for name, source in self._sensors_for(tank_id).items():
                raw = payload.get(name)
                if raw is not None:
                    try:
                        raw = float(raw)
                    except (TypeError, ValueError):
                        raise ValueError(f"'{name}' must be a number, got {raw!r}")
                    if math.isnan(raw):
                        raw = None
                value, origin = source.read(raw, now, activity)
                status, side = classify(self.settings.parameters[name], value)
                reading.values[name] = ParamValue(name, value, origin, status, side)

            # 2. derived parameters (only from trustworthy inputs)
            usable = {n: reading.usable(n) for n in reading.values}
            for name, cfg in self.settings.parameters.items():
                if cfg.source == "derived":
                    value = DERIVATIONS[cfg.derive](usable)
                    status, side = classify(cfg, value)
                    reading.values[name] = ParamValue(name, value, "derived", status, side)

            # 3. store, 4. alerts
            self.storage.insert_reading(reading)
            raised = self.alerts.evaluate(reading)

            # 5. reactive control (AUTO only; MANUAL still records alerts)
            events = []
            if self.mode(tank_id) == Mode.AUTO.value:
                for cmd in self.engine.decide(reading, activity):
                    events += self.actuators.execute(tank_id, cmd, now, "auto", self.engine.name)

            if commit:
                self.storage.commit()
            self.version += 1

        return {
            "tank_id": tank_id,
            "ts": now,
            "values": {n: {"value": pv.value, "source": pv.source, "status": pv.status.value}
                       for n, pv in reading.values.items()},
            "alerts_raised": raised,
            "actuator_events": [e.__dict__ for e in events],
        }

    def ingest_many(self, payloads: list[dict]) -> int:
        """Bulk ingest (CSV replay): same pipeline, one commit at the end."""
        with self.lock:
            try:
                for i, p in enumerate(payloads):
                    try:
                        self.ingest(p, commit=False)
                    except ValueError as exc:
                        raise ValueError(f"reading #{i}: {exc}") from exc
            finally:
                self.storage.commit()  # keep what was processed before an error
        return len(payloads)

    # ------------------------------------------------------ dashboard actions
    def set_mode(self, tank_id: str, mode: str) -> str:
        mode = mode.upper()
        if mode not in (Mode.AUTO.value, Mode.MANUAL.value):
            raise ValueError("mode must be AUTO or MANUAL")
        with self.lock:
            self._modes[tank_id] = mode
            self.storage.set_mode(tank_id, mode)
            self.storage.commit()
            self.version += 1
        log.info("tank %s -> %s mode", tank_id, mode)
        return mode

    def manual_command(self, tank_id: str, actuator: str, action: str) -> list[dict]:
        """ON/OFF from the dashboard. Only allowed in MANUAL mode so the
        baseline's own decisions are never mixed with operator actions."""
        action = action.lower()
        if action not in ("on", "off"):
            raise ValueError("action must be 'on' or 'off'")
        with self.lock:
            if self.mode(tank_id) != Mode.MANUAL.value:
                raise PermissionError("switch the tank to MANUAL mode first")
            if actuator not in self.actuators.for_tank(tank_id):
                raise KeyError(actuator)
            # Stamped with the latest sensor time so run-time stays consistent.
            events = self.actuators.execute(
                tank_id, Command(actuator, action, "manual"), self.clock.now(tank_id),
                "manual", self.engine.name)
            self.storage.commit()
            self.version += 1
        return [e.__dict__ for e in events]

    # ------------------------------------------------------------ read model
    def state(self, tank_id: str) -> dict:
        """Everything the dashboard's live view needs, in one object."""
        latest = self.storage.latest_values(tank_id)
        now = self.clock.now(tank_id) if latest else None
        params = []
        for name, cfg in self.settings.parameters.items():
            row = latest.get(name)
            params.append({
                "name": name, "label": cfg.label, "unit": cfg.unit,
                "min": cfg.min, "max": cfg.max, "configured_source": cfg.source,
                "value": row["value"] if row else None,
                "status": row["status"] if row else Status.MISSING.value,
                "source": row["source"] if row else None,
                "ts": row["ts"] if row else None,
            })
        return {
            "tank_id": tank_id,
            "mode": self.mode(tank_id),
            "engine": self.engine.name,
            "now": now,
            "parameters": params,
            "actuators": self.actuators.summary(tank_id, now),
            "active_alerts": self.storage.active_alerts(tank_id),
        }
