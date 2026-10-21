"""Sensor sources. `build_source` maps the config word to an adapter class."""
from __future__ import annotations

import random

from ..core.config import ParameterConfig
from .base import SensorSource
from .payload import PayloadSource
from .simulated import AutoSource, SimulatedSource


def build_source(cfg: ParameterConfig, rng: random.Random) -> SensorSource:
    """Create the adapter for one parameter (derived ones are handled separately)."""
    if cfg.source == "payload":
        return PayloadSource()
    sim = SimulatedSource(cfg.simulation, cfg.valid_min, cfg.valid_max, rng)
    if cfg.source == "simulated":
        return sim
    if cfg.source == "auto":
        return AutoSource(sim)
    raise ValueError(f"no sensor adapter for source '{cfg.source}'")
