"""REST API (interactive docs at http://localhost:8000/docs).

    POST /api/readings              one reading from the ESP32 / simulator
    POST /api/readings/batch        many readings (CSV replay)
    GET  /api/tanks                 known tank ids
    GET  /api/state                 live snapshot for the dashboard
    GET  /api/stream                same snapshot pushed via Server-Sent Events
    GET  /api/history               time series of one parameter
    GET  /api/alerts                alert log
    GET  /api/actuators/events      actuator ON/OFF log
    POST /api/mode                  AUTO / MANUAL
    POST /api/actuators/{name}      manual ON / OFF (MANUAL mode only)
    GET  /api/metrics               evaluation metrics (run-time, excursions, ...)
"""
from __future__ import annotations

import asyncio
import json
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict

from ..services.ingest import IngestService
from ..services.metrics import compute_metrics


class ReadingIn(BaseModel):
    """Any subset of parameters is accepted; unknown fields are ignored."""
    model_config = ConfigDict(extra="allow", json_schema_extra={
        "example": {"tank_id": "tank1", "timestamp": 1760000000, "temperature": 25.4}})
    tank_id: Optional[str] = None
    timestamp: Optional[float | str] = None


class ModeIn(BaseModel):
    tank_id: str
    mode: str          # AUTO | MANUAL


class ActuatorCommandIn(BaseModel):
    tank_id: str
    action: str        # on | off


def build_router(service: IngestService) -> APIRouter:
    r = APIRouter(prefix="/api")

    def tank(tank_id: Optional[str]) -> str:
        return tank_id or service.settings.default_tank

    # ---------------------------------------------------------------- ingest
    @r.post("/readings")
    def post_reading(body: ReadingIn):
        try:
            return service.ingest(body.model_dump(exclude_none=True))
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    @r.post("/readings/batch")
    def post_batch(body: list[ReadingIn]):
        try:
            n = service.ingest_many([b.model_dump(exclude_none=True) for b in body])
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        return {"ingested": n}

    # ----------------------------------------------------------------- reads
    @r.get("/tanks")
    def tanks():
        return service.tanks()

    @r.get("/config")
    def config():
        s = service.settings
        return {"engine": s.engine, "default_tank": s.default_tank,
                "parameters": {n: p.__dict__ for n, p in s.parameters.items()},
                "actuators": {n: {"label": a.label, "driver": a.driver, "power_w": a.power_w}
                              for n, a in s.actuators.items()},
                "rules": [x.__dict__ for x in s.rules]}

    @r.get("/state")
    def state(tank_id: Optional[str] = None):
        return service.state(tank(tank_id))

    @r.get("/stream")
    async def stream(request: Request, tank_id: Optional[str] = None):
        """Push the state whenever anything changes (polled every 0.5 s)."""
        t = tank(tank_id)

        async def events():
            seen = -1
            while not await request.is_disconnected():
                if service.version != seen:
                    seen = service.version
                    snapshot = await asyncio.to_thread(service.state, t)
                    yield f"data: {json.dumps(snapshot)}\n\n"
                await asyncio.sleep(0.5)

        return StreamingResponse(events(), media_type="text/event-stream")

    @r.get("/history")
    def history(parameter: str, tank_id: Optional[str] = None,
                since: Optional[float] = None, limit: int = Query(500, le=20000)):
        if parameter not in service.settings.parameters:
            raise HTTPException(404, f"unknown parameter '{parameter}'")
        return service.storage.history(tank(tank_id), parameter, since, limit)

    @r.get("/alerts")
    def alerts(tank_id: Optional[str] = None, active: bool = False,
               limit: int = Query(100, le=5000)):
        t = tank(tank_id)
        return service.storage.active_alerts(t) if active else service.storage.alerts(t, limit)

    @r.get("/actuators/events")
    def actuator_events(tank_id: Optional[str] = None, limit: int = Query(100, le=5000)):
        return service.storage.events(tank(tank_id), limit)

    @r.get("/metrics")
    def metrics(tank_id: Optional[str] = None):
        t = tank(tank_id)
        st = service.state(t)
        return compute_metrics(service.settings, service.storage, t, st["actuators"], st["now"])

    # --------------------------------------------------------------- control
    @r.post("/mode")
    def set_mode(body: ModeIn):
        try:
            return {"tank_id": body.tank_id, "mode": service.set_mode(body.tank_id, body.mode)}
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    @r.post("/actuators/{name}")
    def command(name: str, body: ActuatorCommandIn):
        try:
            return service.manual_command(body.tank_id, name, body.action)
        except PermissionError as exc:
            raise HTTPException(409, str(exc))
        except KeyError:
            raise HTTPException(404, f"unknown actuator '{name}'")
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    return r
