"""Parameters computed from other parameters.

unionised_ammonia: the toxic NH3 fraction of total ammonia nitrogen (TAN),
which rises steeply with pH and temperature (Emerson et al., 1975):

    pKa = 0.09018 + 2729.92 / (T + 273.15)
    NH3 = TAN / (1 + 10^(pKa - pH))
"""
from __future__ import annotations

from typing import Callable, Optional


def unionised_ammonia(values: dict[str, Optional[float]]) -> Optional[float]:
    tan, ph, temp = values.get("ammonia"), values.get("ph"), values.get("temperature")
    if tan is None or ph is None or temp is None:
        return None
    pka = 0.09018 + 2729.92 / (temp + 273.15)
    return round(tan / (1 + 10 ** (pka - ph)), 5)


DERIVATIONS: dict[str, Callable[[dict[str, Optional[float]]], Optional[float]]] = {
    "unionised_ammonia": unionised_ammonia,
}
