"""Forecasting service: a small API next to the controller, not inside it.

The ESP32 posts to the controller (:8000) as before; this service only READS
the controller's SQLite database and serves forecasts (:8001). Stopping it
leaves monitoring and the rule engine untouched.

    GET /health                    model + config info
    GET /forecast?tank_id=pond1    forecast path + early alert per parameter

Run (from water_quality/):
    python -m prediction.service                 # http://127.0.0.1:8001/docs
    AQUASENSE_DB=runs/x.db python -m prediction.service --host 0.0.0.0
"""
from __future__ import annotations

import argparse
import os
import threading

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .alerts import CONTROLLER_CONFIG, load_safe_ranges
from .live import forecast_tank, latest_ts, load_bundle, load_reliability
from .train import MODEL_PATH

CACHE_S = 60


def controller_db_path(config_path: str = CONTROLLER_CONFIG) -> str:
    """Same rule as controller/core/config.py: AQUASENSE_DB, else the
    `database` entry relative to the config file."""
    import yaml

    if os.environ.get("AQUASENSE_DB"):
        return os.environ["AQUASENSE_DB"]
    with open(config_path) as f:
        db = yaml.safe_load(f).get("database", "controller.db")
    return db if os.path.isabs(db) else os.path.join(os.path.dirname(config_path), db)


def create_app(db_path: str | None = None, model_path: str = MODEL_PATH) -> FastAPI:
    app = FastAPI(title="AquaSense forecasting service")
    # The dashboard is served by the controller on another port.
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"])

    db = db_path or controller_db_path()
    bundle = load_bundle(model_path)
    limits = load_safe_ranges()
    reliability = load_reliability()
    cache: dict[str, tuple[float, dict]] = {}     # tank -> (latest ts, result)
    lock = threading.Lock()

    @app.get("/health")
    def health():
        cfg = bundle["cfg"]
        return {"ok": True, "database": db, "trained_at": bundle["trained_at"],
                "trained_on": bundle["trained_on"], "freq_min": cfg.freq_min,
                "lag_steps": cfg.lag_steps, "horizon_steps": cfg.horizon_steps,
                "models": {p: m.name for p, m in bundle["models"].items()}}

    @app.get("/forecast")
    def forecast(tank_id: str):
        if not os.path.exists(db):
            raise HTTPException(503, f"controller database not found: {db}")
        end = latest_ts(db, tank_id)
        if end is None:
            raise HTTPException(404, f"no readings for tank '{tank_id}'")
        # Recompute at most once per minute of sensor time: the model works on
        # 10-min steps, and a forecast takes ~1 s (CSV replays post 100s/s).
        key = end // CACHE_S
        with lock:
            hit = cache.get(tank_id)
            if hit and hit[0] == key:
                return hit[1]
        result = forecast_tank(db, tank_id, bundle, limits, reliability)
        with lock:
            cache[tank_id] = (key, result)
        return result

    return app


def main() -> None:
    import uvicorn

    ap = argparse.ArgumentParser(description="AquaSense forecasting service")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8001)
    ap.add_argument("--db", help="controller SQLite DB (default: as the controller)")
    ap.add_argument("--model", default=MODEL_PATH)
    args = ap.parse_args()
    uvicorn.run(create_app(args.db, args.model), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
