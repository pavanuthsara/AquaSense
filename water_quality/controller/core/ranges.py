"""Classify a single value against its configured safe range.

This is the heart of "threshold monitoring": one pure function, no state,
easy to unit-test and to quote in the report.
"""
from __future__ import annotations

from typing import Optional

from .config import ParameterConfig
from .models import Status


def classify(cfg: ParameterConfig, value: Optional[float]) -> tuple[Status, Optional[str]]:
    """Return (status, side) where side is "low"/"high" when out of range.

        value missing                         -> MISSING
        outside [valid_min, valid_max]        -> FAULT   (sensor error)
        inside  [min, max]                    -> OK
        outside by <= critical_margin         -> WARNING
        outside by >  critical_margin         -> CRITICAL
    """
    if value is None:
        return Status.MISSING, None
    if (cfg.valid_min is not None and value < cfg.valid_min) or \
       (cfg.valid_max is not None and value > cfg.valid_max):
        return Status.FAULT, None

    if cfg.min is not None and value < cfg.min:
        side, excess = "low", cfg.min - value
    elif cfg.max is not None and value > cfg.max:
        side, excess = "high", value - cfg.max
    else:
        return Status.OK, None

    status = Status.CRITICAL if excess > cfg.critical_margin else Status.WARNING
    return status, side
