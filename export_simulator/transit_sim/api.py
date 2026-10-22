"""HTTP API for the transit simulator, called by the AquaSense Spring Boot backend.

Run:  uvicorn transit_sim.api:app --port 8001
Auth: if the environment variable EXPORT_SIM_SERVICE_KEY is set, every /v1 request must send the same
      value in the X-Service-Key header (the backend holds it; the mobile app never calls this directly).
"""
from __future__ import annotations

import os
from dataclasses import asdict
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from pydantic import BaseModel, Field

from . import __version__
from .advisor import ADDONS, AdvisoryRequest, advise
from .config import Interventions, Shipment, Unpacking, available_species, load_interventions, load_species
from .model import simulate

app = FastAPI(title="AquaSense export transit simulator", version=__version__)


def require_service_key(x_service_key: str | None = Header(default=None)) -> None:
    expected = os.environ.get("EXPORT_SIM_SERVICE_KEY")
    if expected and x_service_key != expected:
        raise HTTPException(status_code=401, detail="invalid service key")


class AdvisoryIn(BaseModel):
    species: str = "guppy"
    fish_mass_g: float = Field(0.3, gt=0, le=500)
    total_fish: int | None = Field(None, gt=0, le=10_000_000)
    water_l: float = Field(0.4, gt=0, le=50)
    gas_l: float = Field(1.2, gt=0, le=100)
    duration_h: float = Field(24.0, gt=0, le=120)
    temp_low_c: float = Field(24.0, ge=0, le=40)
    temp_high_c: float = Field(28.0, ge=0, le=40)
    target_survival: float = Field(0.95, ge=0.5, lt=1.0)
    allow_anaesthetic: bool = True
    allow_zeolite: bool = True
    max_fasting_h: float = Field(48.0, ge=0, le=96)
    initial_ph: float = Field(7.4, ge=5, le=9.5)
    alkalinity_mgL_caco3: float = Field(65.0, gt=0, le=500)
    initial_tan_mgL: float = Field(0.3, ge=0, le=20)
    kla_per_h: float | None = Field(None, gt=0, le=10)
    samples: int = Field(10, ge=0, le=30)
    seed: int = 0
    mode: Literal["suggest", "fixed_bags", "check"] = "suggest"
    bags: int | None = Field(None, gt=0, le=1_000_000)
    fish_per_bag: int | None = Field(None, gt=0, le=1_000_000)
    check_fasting_h: float = Field(24.0, ge=0, le=96)
    check_zeolite: bool = False
    check_anaesthetic: Literal["ms222_40mgL", "benzocaine_20mgL"] | None = None


class SimulateIn(BaseModel):
    species: str = "guppy"
    fish_count: int = Field(..., ge=0, le=100_000)
    fish_mass_g: float = Field(..., gt=0, le=500)
    water_l: float = Field(..., gt=0, le=50)
    gas_l: float = Field(..., gt=0, le=100)
    duration_h: float = Field(..., gt=0, le=120)
    temperature_c: float = Field(25.0, ge=0, le=40)
    anaesthetic: str | None = None
    zeolite_g_per_l: float = Field(0.0, ge=0, le=60)
    starvation_h: float = Field(24.0, ge=0, le=96)
    unpack: bool = True


def _check_species(name: str) -> None:
    if name not in available_species():
        raise HTTPException(status_code=422, detail=f"unknown species '{name}'")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "version": __version__}


@app.get("/v1/options", dependencies=[Depends(require_service_key)])
def options() -> dict:
    species = []
    for name in available_species():
        sp = load_species(name)
        species.append({"key": name, "scientific_name": sp.scientific_name,
                        "validated": name == "tiger_barb", "reference_mass_g": sp.ref_mass_g})
    return {"species": species, "anaesthetics": list(load_interventions()), "addons": ADDONS}


@app.post("/v1/advisory", dependencies=[Depends(require_service_key)])
def advisory(body: AdvisoryIn, response: Response) -> dict:
    """Full advisory. Headline numbers are repeated as X-Advisory-* headers for the Java backend."""
    _check_species(body.species)
    try:
        adv = advise(AdvisoryRequest(**body.model_dump()))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    response.headers["X-Advisory-Feasible"] = "true" if adv["feasible"] else "false"
    response.headers["X-Advisory-Meets-Target"] = "true" if adv.get("verdict", {}).get("meets_target") else "false"
    if adv["feasible"]:
        rec, mort = adv["recommendation"], adv["mortality"]
        response.headers["X-Advisory-Fish-Per-Bag"] = str(rec["fish_per_bag"])
        if rec.get("bags_needed") is not None:
            response.headers["X-Advisory-Bags-Needed"] = str(rec["bags_needed"])
        response.headers["X-Advisory-Survival-Pct"] = str(mort["survival_after_unpacking_pct"])
        response.headers["X-Advisory-Worst-Survival-Pct"] = str(mort["worst_survival_after_unpacking_pct"])
    return adv


@app.post("/v1/simulate", dependencies=[Depends(require_service_key)])
def simulate_one(body: SimulateIn) -> dict:
    _check_species(body.species)
    kw = {}
    if body.anaesthetic:
        table = load_interventions()
        if body.anaesthetic not in table:
            raise HTTPException(status_code=422, detail=f"unknown anaesthetic '{body.anaesthetic}'")
        e = table[body.anaesthetic]
        kw = {k: e[k] for k in ("metabolic_factor", "excretion_factor", "stress_factor") if k in e}
    iv = Interventions(zeolite_g_per_l=body.zeolite_g_per_l, starvation_h=body.starvation_h, **kw)
    sh = Shipment(fish_count=body.fish_count, fish_mass_g=body.fish_mass_g, water_l=body.water_l, gas_l=body.gas_l,
                  duration_h=body.duration_h, temperature_c=body.temperature_c)
    r = simulate(load_species(body.species), sh, iv, Unpacking() if body.unpack else None, dt_out=1.0)
    return {"summary": r.summary, "series": r.as_rows(), "interventions": asdict(iv)}
