"""Registry of control engines, selected by `engine:` in config.yaml."""
from __future__ import annotations

from ..core.config import Settings
from .base import ControlEngine
from .threshold import ThresholdEngine

ENGINES: dict[str, type[ControlEngine]] = {
    ThresholdEngine.name: ThresholdEngine,
    # "predictive": PredictiveEngine,   <- future work
}


def build_engine(settings: Settings) -> ControlEngine:
    try:
        return ENGINES[settings.engine](settings)
    except KeyError:
        raise ValueError(f"unknown engine '{settings.engine}', choose from {list(ENGINES)}")
