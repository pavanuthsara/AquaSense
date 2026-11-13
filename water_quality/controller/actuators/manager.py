"""Owns every actuator of every tank and logs what they do.

    execute()  apply a Command, persist the resulting ON/OFF events
    summary()  state + run-time + switch count + energy per actuator
"""
from __future__ import annotations

import logging
from typing import Optional

from ..core.config import Settings
from ..core.models import ActuatorEvent, Command
from ..core.storage import Storage
from .base import Actuator, ActuatorError
from .esp32_http import Esp32HttpActuator
from .mock import MockActuator

log = logging.getLogger("aquasense.actuators")

DRIVERS: dict[str, type[Actuator]] = {
    "mock": MockActuator,
    "esp32_http": Esp32HttpActuator,
}


class ActuatorManager:
    def __init__(self, settings: Settings, storage: Storage) -> None:
        self.settings = settings
        self.storage = storage
        self._tanks: dict[str, dict[str, Actuator]] = {}

    def for_tank(self, tank_id: str) -> dict[str, Actuator]:
        """All actuators of a tank, created on first use from config."""
        if tank_id not in self._tanks:
            self._tanks[tank_id] = {
                name: DRIVERS[cfg.driver](cfg, tank_id)
                for name, cfg in self.settings.actuators.items()
            }
        return self._tanks[tank_id]

    def restore(self) -> None:
        """After a restart, actuators whose last event was ON are still ON."""
        for ev in self.storage.last_events():
            act = self.for_tank(ev["tank_id"]).get(ev["actuator"])
            if act is not None:
                act.restore(ev["action"] == "ON", ev["ts"])

    def activity(self, tank_id: str) -> dict[str, dict]:
        """Actuator state as seen by control engines and the plant simulator."""
        return {n: {"on": a.is_on, "pulses": a.pulses, "last_pulse_ts": a.last_pulse_ts}
                for n, a in self.for_tank(tank_id).items()}

    def execute(self, tank_id: str, cmd: Command, ts: float, source: str,
                engine: str) -> list[ActuatorEvent]:
        act = self.for_tank(tank_id).get(cmd.actuator)
        if act is None:
            raise KeyError(f"unknown actuator '{cmd.actuator}'")
        try:
            if cmd.action == "on":
                events = act.turn_on(ts, source, engine, cmd.reason)
            elif cmd.action == "off":
                events = act.turn_off(ts, source, engine, cmd.reason)
            elif cmd.action == "pulse":
                events = act.pulse(ts, cmd.duration_s, source, engine, cmd.reason)
            else:
                raise ValueError(f"unknown action '{cmd.action}'")
        except ActuatorError as exc:
            # Hardware failed: state is unchanged, nothing is logged as run-time.
            log.error("actuator %s/%s failed: %s", tank_id, cmd.actuator, exc)
            return []
        for ev in events:
            self.storage.insert_event(ev)
            log.info("%s %s/%s %s (%s) %s", ev.source.upper(), tank_id, ev.actuator,
                     ev.action, engine, ev.reason)
        return events

    def summary(self, tank_id: str, now: Optional[float]) -> list[dict]:
        """Per actuator: state, total run-time (incl. the current ON period),
        number of switch-ONs and energy estimate (Wh = run-time x rated power)."""
        totals = self.storage.runtime_totals(tank_id)
        out = []
        for name, act in self.for_tank(tank_id).items():
            t = totals.get(name, {})
            current = act.current_run_s(now) if now is not None else 0.0
            runtime = (t.get("runtime_s") or 0.0) + current
            out.append({
                "name": name,
                "label": act.cfg.label,
                "driver": act.cfg.driver,
                "is_on": act.is_on,
                "on_since": act.on_since,
                "runtime_s": round(runtime, 1),
                "switch_ons": t.get("switch_ons") or 0,
                "power_w": act.cfg.power_w,
                "energy_wh": round(runtime / 3600 * act.cfg.power_w, 3),
            })
        return out
