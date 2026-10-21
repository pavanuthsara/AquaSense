"""FastAPI application: wires config -> storage -> control loop -> API + dashboard.

Run:  python -m controller            (from the water_quality/ folder)
 or:  uvicorn controller.main:create_app --factory
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from .api.routes import build_router
from .core.config import Settings, load_settings
from .core.storage import Storage
from .services.ingest import IngestService

# React + Vite dashboard (controller/web). `npm run build` writes web/dist.
DASHBOARD_DIR = Path(__file__).resolve().parent / "web" / "dist"
NOT_BUILT = """<!doctype html><meta charset="utf-8"><title>AquaSense</title>
<body style="font-family:system-ui;padding:2rem;max-width:40rem">
<h1>Dashboard not built yet</h1>
<p>The API is running (<a href="/docs">/docs</a>). Build the React dashboard once:</p>
<pre>cd controller/web
npm install
npm run build</pre>
<p>or run <code>npm run dev</code> there and open <a href="http://localhost:5173">localhost:5173</a>.</p>"""

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)-7s %(name)s: %(message)s")
log = logging.getLogger("aquasense")


def create_app(settings: Optional[Settings] = None) -> FastAPI:
    settings = settings or load_settings()
    storage = Storage(settings.db_path)
    service = IngestService(settings, storage)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        listener = None
        if settings.mqtt.enabled:
            from .services.mqtt_listener import MqttListener
            listener = MqttListener(settings.mqtt, service)
            listener.start()
        log.info("engine=%s db=%s sensors=%s actuators=%s", settings.engine, settings.db_path,
                 {n: p.source for n, p in settings.parameters.items()},
                 {n: a.driver for n, a in settings.actuators.items()})
        yield
        if listener:
            listener.stop()
        storage.commit()

    app = FastAPI(title="AquaSense baseline controller", lifespan=lifespan)
    app.state.service = service
    app.include_router(build_router(service))
    if (DASHBOARD_DIR / "index.html").exists():
        app.mount("/", StaticFiles(directory=DASHBOARD_DIR, html=True), name="dashboard")
    else:
        app.add_api_route("/", lambda: HTMLResponse(NOT_BUILT), include_in_schema=False)
    return app
