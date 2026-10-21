"""THE BASELINE: threshold-based reactive control.

For every rule in config.yaml, on every reading:

    hold rule  (aerator, heater)
        value outside the safe range and actuator OFF  -> turn ON
        actuator ON and value back inside by deadband   -> turn OFF
        otherwise                                       -> no change

    pulse rule (dosing pump)
        value outside the safe range and the cooldown since the last pulse
        has elapsed                                     -> pulse for N seconds

The engine is *reactive*: it only acts after a limit has already been
crossed. That is exactly the behaviour the predictive controller is meant to
improve on.

Missing values and sensor faults are ignored (the actuator keeps its state),
so an unplugged probe reading -127 °C never switches the heater on.
"""
from __future__ import annotations

from typing import Optional

from ..core.config import ParameterConfig, RuleConfig
from ..core.models import Command, Reading
from .base import ControlEngine


def violated(condition: str, p: ParameterConfig, v: float) -> bool:
    """Is the value on the wrong side of the limit(s) this rule watches?"""
    low = p.min is not None and v < p.min
    high = p.max is not None and v > p.max
    return {"below_min": low, "above_max": high, "out_of_range": low or high}[condition]


def recovered(condition: str, p: ParameterConfig, v: float) -> bool:
    """Back inside the safe range by at least the deadband (hysteresis)."""
    ok_low = p.min is None or v >= p.min + p.deadband
    ok_high = p.max is None or v <= p.max - p.deadband
    return {"below_min": ok_low, "above_max": ok_high, "out_of_range": ok_low and ok_high}[condition]


def describe(condition: str, p: ParameterConfig, v: float) -> str:
    """Human-readable reason, stored with every actuator event."""
    if p.min is not None and v < p.min:
        return f"{p.name}={v:g} < min {p.min:g}"
    if p.max is not None and v > p.max:
        return f"{p.name}={v:g} > max {p.max:g}"
    return f"{p.name}={v:g} back in range"


class ThresholdEngine(ControlEngine):
    name = "threshold"

    def decide(self, reading: Reading, actuators: dict[str, dict]) -> list[Command]:
        commands: list[Command] = []
        for rule in self.settings.rules:
            value = reading.usable(rule.parameter)
            if value is None:
                continue  # no data or sensor fault -> don't act on it
            p = self.settings.parameters[rule.parameter]
            state = actuators.get(rule.actuator, {})
            cmd = (self._hold(rule, p, value, state) if rule.action == "hold"
                   else self._pulse(rule, p, value, state, reading.ts))
            if cmd:
                commands.append(cmd)
        return commands

    @staticmethod
    def _hold(rule: RuleConfig, p: ParameterConfig, v: float, state: dict) -> Optional[Command]:
        if not state.get("on") and violated(rule.condition, p, v):
            return Command(rule.actuator, "on", describe(rule.condition, p, v), p.name)
        if state.get("on") and recovered(rule.condition, p, v):
            return Command(rule.actuator, "off", describe(rule.condition, p, v), p.name)
        return None

    @staticmethod
    def _pulse(rule: RuleConfig, p: ParameterConfig, v: float, state: dict,
               now: float) -> Optional[Command]:
        if not violated(rule.condition, p, v):
            return None
        last = state.get("last_pulse_ts")
        if last is not None and now - last < rule.cooldown_seconds:
            return None  # still in lock-out: let the last dose mix in
        return Command(rule.actuator, "pulse", describe(rule.condition, p, v), p.name,
                       duration_s=rule.pulse_seconds)
