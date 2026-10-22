"""Novelty check: has the AI second opinion seen shipments like this one?

The AI correction only learns from past shipments, so it is only trustworthy for shipments that look
like ones it has seen. Two simple checks decide what the exporter is shown:

* range check: every number (fish size, packing density, gas-to-water ratio, trip length, hottest
  temperature, fasting time) must lie inside the lowest-highest seen in the records, and the species,
  sedative and zeolite choice must all have been seen before;
* similar-shipment count: how many records are close to this shipment on ALL inputs at once.

=========================  ===============================================================
level / ai_display         what the exporter sees
=========================  ===============================================================
``many`` / ``full``        physics prediction plus the AI second opinion
``few`` / ``limited``      physics prediction, AI shown but marked "limited experience"
``new`` / ``hidden``       physics only, with a note that no comparable shipments exist yet
=========================  ===============================================================

A new combination is not a failure case: the physics makes the prediction, and the shipment's
recorded outcome becomes the first data point for that combination.

Features are unit-free ratios or fixed units (g, h, C) so that records from different bag sizes compare
directly. Records are read from ``data/shipments/real_shipments.csv`` (columns: see ``REQUIRED`` and
``OPTIONAL``; the shipment template's ``temp_low_c``/``temp_high_c`` are accepted in place of
``temp_max_c``). ``load_ai_history`` returns the table the saved AI model was trained on, so the check
describes what the AI has actually seen.
"""
from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass, field
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHIPMENTS_DIR = ROOT / "data" / "shipments"
REAL_SHIPMENTS_CSV = SHIPMENTS_DIR / "real_shipments.csv"
MODEL_META = ROOT / "models" / "correction_model.json"

MIN_SIMILAR = 5             # fewer similar past shipments than this -> "limited experience"
MIN_SPECIES_RECORDS = 10    # real shipments of a species before its borrowed-value safety margin is dropped
RELATIVE_TOL = 0.25         # "similar": fish size, density, gas:water and trip length within 25 %
TEMP_TOL_C = 2.0            # ... hottest temperature within 2 C
FASTING_TOL_H = 12.0        # ... fasting within 12 h

REQUIRED = ("species", "fish_mass_g", "fish_per_bag", "water_l", "gas_l", "duration_h", "temp_max_c")
OPTIONAL = {"fasting_h": 24.0, "zeolite_g_per_l": 0.0, "anaesthetic": ""}
TEMP_COLUMNS = ("temp_low_c", "temp_high_c")  # shipment template; hottest = max of the two

# (attribute, plain-language name, unit, ("rel", fraction) or ("abs", amount))
NUMERIC = [
    ("fish_mass_g", "fish size", "g", ("rel", RELATIVE_TOL)),
    ("density_g_per_l", "packing density", "g/L", ("rel", RELATIVE_TOL)),
    ("gas_to_water", "gas-to-water ratio", "", ("rel", RELATIVE_TOL)),
    ("duration_h", "trip length", "h", ("rel", RELATIVE_TOL)),
    ("temp_max_c", "hottest temperature", "C", ("abs", TEMP_TOL_C)),
    ("fasting_h", "fasting time", "h", ("abs", FASTING_TOL_H)),
]
CATEGORICAL = ["species", "anaesthetic", "uses_zeolite"]


@dataclass(frozen=True)
class ShipmentFeatures:
    """One shipment as the novelty check sees it (one bag type, hot end of the temperature range)."""

    species: str
    fish_mass_g: float
    fish_per_bag: int
    water_l: float
    gas_l: float
    duration_h: float
    temp_max_c: float
    fasting_h: float = 24.0
    zeolite_g_per_l: float = 0.0
    anaesthetic: str = ""  # "" = none

    @property
    def density_g_per_l(self) -> float:
        return self.fish_per_bag * self.fish_mass_g / self.water_l

    @property
    def gas_to_water(self) -> float:
        return self.gas_l / self.water_l

    @property
    def uses_zeolite(self) -> bool:
        return self.zeolite_g_per_l > 0


@dataclass
class NoveltyResult:
    level: str                  # many | few | new
    ai_display: str             # full | limited | hidden
    similar_shipments: int
    records: int
    out_of_range: list[str] = field(default_factory=list)
    message: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


def _fmt(v: float) -> str:
    return f"{v:.3g}" if abs(v) < 100 else f"{v:.0f}"


def _close(a: float, b: float, tol: tuple[str, float]) -> bool:
    kind, amount = tol
    if kind == "abs":
        return abs(a - b) <= amount
    return abs(a - b) <= amount * max(abs(a), abs(b), 1e-12)


class ShipmentHistory:
    """Past shipments the AI layer has learned from."""

    def __init__(self, records: list[ShipmentFeatures] | None = None, label: str = "past shipments"):
        self.records = list(records or [])
        self.label = label  # how the messages name the records, e.g. "simulated shipments"

    def __len__(self) -> int:
        return len(self.records)

    @classmethod
    def from_csv(cls, path: str | Path) -> "ShipmentHistory":
        with open(path, newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            columns = set(reader.fieldnames or [])
            if columns.issuperset(TEMP_COLUMNS):
                columns.add("temp_max_c")
            missing = [c for c in REQUIRED if c not in columns]
            if missing:
                raise ValueError(f"{Path(path).name}: missing columns {missing}")
            records, sources = [], set()
            for row in reader:
                get = lambda k: (row.get(k) or "").strip()  # noqa: E731
                anaesthetic = get("anaesthetic")
                sources.add(get("source").lower())
                temp_max = (float(get("temp_max_c")) if get("temp_max_c")
                            else max(float(get(c)) for c in TEMP_COLUMNS))
                records.append(ShipmentFeatures(
                    species=get("species"), fish_mass_g=float(get("fish_mass_g")),
                    fish_per_bag=int(float(get("fish_per_bag"))), water_l=float(get("water_l")),
                    gas_l=float(get("gas_l")), duration_h=float(get("duration_h")),
                    temp_max_c=temp_max,
                    fasting_h=float(get("fasting_h") or OPTIONAL["fasting_h"]),
                    zeolite_g_per_l=float(get("zeolite_g_per_l") or OPTIONAL["zeolite_g_per_l"]),
                    anaesthetic="" if anaesthetic.lower() in ("", "none") else anaesthetic))
        return cls(records, "simulated shipments" if sources == {"simulated"} else "past shipments")

    def count_species(self, species: str) -> int:
        return sum(r.species == species for r in self.records)

    def out_of_range(self, x: ShipmentFeatures) -> list[str]:
        """Plain-language reasons why ``x`` lies outside anything recorded (empty = inside)."""
        if not self.records:
            return ["no shipments have been recorded yet"]
        reasons = []
        if x.species not in {r.species for r in self.records}:
            reasons.append(f"{x.species.replace('_', ' ')} has not been shipped before")
        if x.anaesthetic not in {r.anaesthetic for r in self.records}:
            reasons.append("no recorded shipment used this sedative" if x.anaesthetic
                           else "every recorded shipment used a sedative")
        if x.uses_zeolite not in {r.uses_zeolite for r in self.records}:
            reasons.append("no recorded shipment used zeolite" if x.uses_zeolite
                           else "every recorded shipment used zeolite")
        for attr, name, unit, _ in NUMERIC:
            seen = [getattr(r, attr) for r in self.records]
            v, lo, hi = getattr(x, attr), min(seen), max(seen)
            u = f" {unit}" if unit else ""
            if v > hi:
                reasons.append(f"{name} {_fmt(v)}{u} is higher than any recorded ({_fmt(hi)}{u})")
            elif v < lo:
                reasons.append(f"{name} {_fmt(v)}{u} is lower than any recorded ({_fmt(lo)}{u})")
        return reasons

    def similar(self, x: ShipmentFeatures) -> int:
        """Records with the same species, sedative and zeolite choice, and every number within tolerance."""
        return sum(all(getattr(r, c) == getattr(x, c) for c in CATEGORICAL)
                   and all(_close(getattr(r, a), getattr(x, a), tol) for a, _, _, tol in NUMERIC)
                   for r in self.records)

    def check(self, x: ShipmentFeatures) -> NoveltyResult:
        reasons = self.out_of_range(x)
        k = self.similar(x) if not reasons else 0
        if reasons or k == 0:
            why = "; ".join(reasons) if reasons else "no recorded shipment is close to this one"
            return NoveltyResult(
                "new", "hidden", k, len(self), reasons,
                f"No comparable shipments exist yet ({why}). This plan is based on the physics only. "
                "Record how this shipment arrives: it becomes the first data point for this combination.")
        label = self.label if k != 1 else self.label.removesuffix("s")
        if k < MIN_SIMILAR:
            return NoveltyResult(
                "few", "limited", k, len(self), [],
                f"Limited experience: only {k} {label} {'are' if k != 1 else 'is'} similar to this one. "
                "The AI second opinion is shown for interest only; the plan follows the physics.")
        return NoveltyResult(
            "many", "full", k, len(self), [],
            f"{k} {label} are similar to this one, so the AI second opinion has enough experience "
            "to correct the physics estimate.")


@lru_cache(maxsize=4)
def _load_cached(path: str, mtime: float) -> ShipmentHistory:
    return ShipmentHistory.from_csv(path)


def load_history(path: str | Path = REAL_SHIPMENTS_CSV) -> ShipmentHistory:
    """Recorded shipments; empty if the file does not exist yet."""
    p = Path(path)
    if not p.exists():
        return ShipmentHistory()
    return _load_cached(str(p), p.stat().st_mtime)


def load_ai_history(meta_path: str | Path = MODEL_META) -> ShipmentHistory:
    """The shipments the saved AI model was trained on; empty if there is no model or its table is gone."""
    p = Path(meta_path)
    if not p.exists():
        return ShipmentHistory()
    data_file = json.loads(p.read_text(encoding="utf-8")).get("data_file")
    return load_history(SHIPMENTS_DIR / data_file) if data_file else ShipmentHistory()
