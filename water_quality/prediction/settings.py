"""Configuration for the prediction layer.

Interval, lag window and horizon are all configurable; everything downstream
derives its step counts from `PrepConfig`.
"""
from __future__ import annotations

from dataclasses import dataclass, field

# The four parameters the monitoring baseline logs and we forecast.
PARAMS = ["do", "ph", "ammonia", "temperature"]

PRETTY = {"do": "Dissolved oxygen", "ph": "pH", "ammonia": "Ammonia",
          "temperature": "Temperature"}
UNITS = {"do": "mg/L", "ph": "", "ammonia": "mg/L", "temperature": "°C"}

# Biologically plausible ranges for water that holds LIVE fish. Stricter than
# the sensor's electrical range: values outside are probe faults, not water.
#   temperature  DS18B20 reports -127 when unplugged
#   do           > 20 mg/L is far beyond saturation at 22-30 °C; 0.0 = dead probe
#   ph           IoTPond probes drift to negative / ~3 after August (fish alive)
#   ammonia      IoTPond logs up to 1e8; > 10 mg/L TAN for weeks is not survivable
PLAUSIBLE = {
    "temperature": (10.0, 40.0),
    "do": (0.05, 20.0),
    "ph": (4.5, 10.0),
    "ammonia": (0.0, 10.0),
}

# A sensor reporting the exact same value for this long is stuck, not stable.
# Temperature (0.0625 °C resolution) can legitimately sit still for a while.
STUCK_HOURS = {"temperature": 12.0, "do": 1.0, "ph": 1.0, "ammonia": 1.0}

# Raw readings a bin needs before its median is trusted. DO and ammonia swing
# by several mg/L between 20-s samples, so one reading says little; temperature
# and pH are smooth, and the logger often drops to ~1 reading per bin at night.
MIN_SAMPLES_PER_BIN = {"temperature": 1, "ph": 1, "do": 3, "ammonia": 3}


@dataclass
class PrepConfig:
    freq_min: int = 10            # resample interval (minutes)
    lag_steps: int = 12           # past readings used as features (12 x 10 min = 2 h)
    horizon_steps: int = 1        # steps forecast ahead (1 x 10 min = 10 min)
    gap_fill_min: int = 30        # interpolate gaps up to this long; longer stay NaN
    hampel_window: int = 7        # trailing window (steps) for spike removal
    hampel_sigmas: float = 3.0
    smooth_steps: int = 3         # trailing rolling-median denoise; 1 = off
    min_pond_rows: int = 5000     # skip ponds with less raw data than this
    params: list[str] = field(default_factory=lambda: list(PARAMS))

    @property
    def freq(self) -> str:
        return f"{self.freq_min}min"

    @property
    def gap_fill_steps(self) -> int:
        return self.gap_fill_min // self.freq_min
