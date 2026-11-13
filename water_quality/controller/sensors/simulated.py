"""Simulated sensor with a deliberately crude "plant model".

It exists so the dashboard and control loop can be demonstrated before the
DO / pH / ammonia probes are connected. Per minute of sensor time:

    v += reversion * (mean - v)        # water tends back to its normal level
       + drift_per_min                 # natural trend (respiration, nitrification)
       + sum(per_minute effect of every actuator that is ON)
    v += per_pulse effect for every actuator pulse since the last sample
    v += gaussian noise

The model is NOT used for any research result; the comparison between the
baseline and the predictive controller should be run on replayed real data.
"""
from __future__ import annotations

import random
from typing import Optional

from .base import ActuatorActivity, SensorSource

MAX_STEP_MIN = 60.0  # don't extrapolate the model over gaps longer than an hour


class SimulatedSource(SensorSource):
    def __init__(self, sim: dict, valid_min: Optional[float] = None,
                 valid_max: Optional[float] = None, rng: Optional[random.Random] = None):
        self.mean = float(sim.get("mean", 0.0))
        self.value = float(sim.get("start", self.mean))
        self.reversion = float(sim.get("reversion", 0.0))
        self.drift = float(sim.get("drift_per_min", 0.0))
        self.noise = float(sim.get("noise", 0.0))
        self.effects: dict[str, dict] = sim.get("effects", {}) or {}
        self.lo, self.hi = valid_min, valid_max
        self.rng = rng or random.Random()
        self.last_ts: Optional[float] = None
        self.seen_pulses: dict[str, int] = {}

    def step(self, ts: float, activity: ActuatorActivity) -> float:
        dt_min = 0.0 if self.last_ts is None else min(max(ts - self.last_ts, 0) / 60, MAX_STEP_MIN)
        self.last_ts = ts

        v = self.value
        v += (self.reversion * (self.mean - v) + self.drift) * dt_min
        for actuator, effect in self.effects.items():
            state = activity.get(actuator, {})
            if state.get("on"):
                v += effect.get("per_minute", 0.0) * dt_min
            pulses = state.get("pulses", 0)
            new_pulses = pulses - self.seen_pulses.get(actuator, pulses)
            self.seen_pulses[actuator] = pulses
            v += effect.get("per_pulse", 0.0) * new_pulses

        if self.lo is not None:
            v = max(v, self.lo)
        if self.hi is not None:
            v = min(v, self.hi)
        self.value = v
        # noise is measurement noise: added to the reported value, not the state
        return round(v + self.rng.gauss(0, self.noise), 4)

    def anchor(self, ts: float, value: float, activity: ActuatorActivity) -> None:
        """Re-align the model to a real measurement (used by AutoSource)."""
        self.step(ts, activity)
        if (self.lo is None or value >= self.lo) and (self.hi is None or value <= self.hi):
            self.value = value  # never anchor to a sensor-fault value

    def read(self, payload_value, ts, activity):
        return self.step(ts, activity), "simulated"


class AutoSource(SensorSource):
    """Use the device value when present, otherwise fall back to simulation.

    Handy while hardware is being added (and for CSV replay, which sends every
    parameter). For a finished deployment set `source: payload` so a dead
    probe shows up as MISSING instead of being silently simulated.
    """

    def __init__(self, simulator: SimulatedSource):
        self.sim = simulator

    def read(self, payload_value, ts, activity):
        if payload_value is not None:
            self.sim.anchor(ts, payload_value, activity)
            return payload_value, "payload"
        return self.sim.read(None, ts, activity)
