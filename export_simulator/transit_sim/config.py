"""Species parameters, shipment description and interventions.

Species parameters live in ``config/species/*.yaml``. A species file may name a ``base`` species
and override only what differs (e.g. guppy inherits the tiger barb calibration and replaces body
size, temperature and ammonia tolerance).

A species with a ``base`` uses borrowed or published values that no real shipment has confirmed. Its
``rate_uncertainty`` (default ``BORROWED_RATE_UNCERTAINTY``) says how far its oxygen use and ammonia
production may be off; the advisor plans against the high end until real outcomes exist.
"""
from __future__ import annotations

from dataclasses import dataclass, field, fields, replace
from pathlib import Path
from typing import Any

import yaml

CONFIG_DIR = Path(__file__).resolve().parent.parent / "config"
SPECIES_DIR = CONFIG_DIR / "species"
BORROWED_RATE_UNCERTAINTY = 0.3  # +/-30 %: in-bag O2 use was far below published respirometry values


@dataclass(frozen=True)
class Species:
    """Biological parameters. Rates are mass-specific at ``ref_mass_g`` and ``ref_temp_c``."""

    name: str
    scientific_name: str
    ref_mass_g: float
    ref_temp_c: float
    o2_rate: float            # mg O2 / kg / h, routine (post-stress) rate
    tan_rate: float           # mg TAN-N / kg / h
    mass_exponent: float      # mass-specific scaling exponent (rate per kg ~ M^b), b ~ -0.2
    q10: float
    rq: float                 # respiratory quotient, mol CO2 / mol O2
    stress_amp: float         # extra metabolism right after packing (fraction, e.g. 1.0 = doubled)
    stress_tau_h: float       # decay time of handling stress (h)
    do_half_uptake: float     # DO (mg/L) at which O2 uptake falls to half (oxyconformer limit)
    hypoxia_hill: float
    do_crit: float            # DO (mg/L) below which hypoxia starts to cause damage
    nh3_lc50: float           # un-ionized ammonia acute LC50 (mg/L), toxic-unit normaliser
    alk_from_tan: float       # eq alkalinity gained per mol TAN excreted (1 = all as NH3, 0 = Na+/NH4+ exchange)
    co2_ref: float            # CO2 (mg/L) that counts as one toxic unit
    guts_kd: float            # damage recovery/accumulation rate (1/h)
    guts_b: float             # killing rate (1/h per unit damage above threshold)
    guts_z: float             # damage threshold (toxic units)
    sources: dict = field(default_factory=dict, compare=False)
    borrowed_from: str | None = None  # species the unconfirmed values come from (None = measured)
    rate_uncertainty: float = 0.0     # fractional uncertainty of o2_rate and tan_rate

    def with_overrides(self, **kw: Any) -> "Species":
        return replace(self, **kw)


_META_FIELDS = {"name", "scientific_name", "sources", "borrowed_from", "rate_uncertainty"}
_FIELD_NAMES = {f.name for f in fields(Species)} - _META_FIELDS


def _read_yaml(path: Path) -> dict:
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def load_species(name_or_path: str | Path) -> Species:
    """Load a species YAML, resolving ``base`` inheritance."""
    path = Path(name_or_path)
    if not path.suffix:
        path = SPECIES_DIR / f"{name_or_path}.yaml"
    raw = _read_yaml(path)
    params: dict[str, Any] = {}
    sources: dict[str, str] = {}
    if raw.get("base"):
        base = load_species(raw["base"])
        params = {f: getattr(base, f) for f in _FIELD_NAMES}
        sources = {k: f"inherited from {base.name}: {v}" for k, v in base.sources.items()}
    for key, entry in (raw.get("parameters") or {}).items():
        if key not in _FIELD_NAMES:
            raise KeyError(f"{path.name}: unknown parameter '{key}'")
        if isinstance(entry, dict):
            params[key] = float(entry["value"])
            sources[key] = entry.get("source", "")
        else:
            params[key] = float(entry)
    params["name"] = raw["name"]
    params["scientific_name"] = raw.get("scientific_name", "")
    params["sources"] = sources
    params["borrowed_from"] = raw.get("base")
    params["rate_uncertainty"] = float(raw.get("rate_uncertainty",
                                             BORROWED_RATE_UNCERTAINTY if raw.get("base") else 0.0))
    missing = _FIELD_NAMES - params.keys()
    if missing:
        raise KeyError(f"{path.name}: missing parameters {sorted(missing)}")
    return Species(**params)


def available_species() -> list[str]:
    return sorted(p.stem for p in SPECIES_DIR.glob("*.yaml"))


@dataclass(frozen=True)
class Interventions:
    """Packing add-ons.

    metabolic_factor: multiplier on O2 use / CO2 production from sedation (1 = none).
    excretion_factor: multiplier on ammonia excretion (Pramod 2010 shows anaesthetics cut ammonia
        far more than CO2). Calibrated values for tested anaesthetics: ``config/interventions.yaml``.
    zeolite_g_per_l: clinoptilolite dose. Kinetics are PROVISIONAL (see README).
    starvation_h: hours without food before packing. Pramod 2010 used 24 h (reference).
    """

    metabolic_factor: float = 1.0
    excretion_factor: float | None = None  # multiplier on ammonia excretion; None = metabolic_factor
    stress_factor: float = 1.0  # multiplier on the handling-stress spike (sedation blunts it)
    zeolite_g_per_l: float = 0.0
    starvation_h: float = 24.0
    extra_alkalinity_meq: float = 0.0  # e.g. bicarbonate/buffer added to the water


@dataclass(frozen=True)
class Shipment:
    """One bag and its journey."""

    fish_count: int
    fish_mass_g: float
    water_l: float
    gas_l: float
    duration_h: float
    temperature_c: float | list[tuple[float, float]] = 22.0  # constant or [(t_h, temp_c), ...]
    gas_o2_fraction: float = 1.0   # 1.0 = pure medical oxygen
    initial_do_mgL: float | None = None  # None = saturated with the packing gas
    initial_tan_mgL: float = 0.3
    initial_ph: float = 7.4
    alkalinity_mgL_caco3: float = 65.0
    kla_per_h: float | None = None  # water-gas O2 transfer; None = species/bag default

    @property
    def biomass_kg(self) -> float:
        return self.fish_count * self.fish_mass_g / 1000.0

    @property
    def density_g_per_l(self) -> float:
        return self.fish_count * self.fish_mass_g / self.water_l

    def temperature_at(self, t_h: float) -> float:
        prof = self.temperature_c
        if isinstance(prof, (int, float)):
            return float(prof)
        pts = sorted(prof)
        if t_h <= pts[0][0]:
            return pts[0][1]
        for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
            if t_h <= t1:
                return v0 + (v1 - v0) * (t_h - t0) / (t1 - t0)
        return pts[-1][1]


@dataclass(frozen=True)
class Unpacking:
    """What happens when the bag is opened at the destination.

    The gas is replaced by air and CO2 leaves the water quickly, so pH rebounds while the
    accumulated ammonia is still there.
    """

    duration_h: float = 1.0
    kla_open_per_h: float = 4.0  # open, gently mixed bag; ASSUMED
    temperature_c: float | None = None  # None = last transit temperature


def load_interventions() -> dict[str, dict]:
    return _read_yaml(CONFIG_DIR / "interventions.yaml") or {}
