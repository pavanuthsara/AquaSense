#!/usr/bin/env python3
"""Serve the AquaSense dashboard and proxy the component APIs (no extra packages).

The Spring Boot backend does not send CORS headers, so the browser cannot call it
directly from another origin. This server serves the static dashboard and forwards

    /proxy/backend/*  ->  $AQUASENSE_BACKEND_URL   (default http://localhost:8080)
    /proxy/water/*    ->  $AQUASENSE_WATER_URL     (default http://localhost:8000)

including the Authorization header, so the dashboard and the APIs share one origin.

    python3 dashboard/serve.py            # http://localhost:8090
    python3 dashboard/serve.py --port 9000
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPSTREAMS = {
    "backend": os.environ.get("AQUASENSE_BACKEND_URL", "http://localhost:8080").rstrip("/"),
    "water": os.environ.get("AQUASENSE_WATER_URL", "http://localhost:8000").rstrip("/"),
}
FORWARD_HEADERS = ("Authorization", "Content-Type", "Accept")
TIMEOUT_S = 8


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def _send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _proxy(self) -> None:
        parts = self.path.split("/", 3)  # ['', 'proxy', name, rest]
        name = parts[2] if len(parts) > 2 else ""
        rest = parts[3] if len(parts) > 3 else ""
        if name == "config":
            return self._send_json(200, {"upstreams": UPSTREAMS})
        base = UPSTREAMS.get(name)
        if base is None:
            return self._send_json(404, {"error": f"unknown upstream '{name}'"})
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(f"{base}/{rest}", data=body, method=self.command)
        for h in FORWARD_HEADERS:
            if self.headers.get(h):
                req.add_header(h, self.headers[h])
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
                payload = resp.read()
                self.send_response(resp.status)
                self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            self.send_response(exc.code)
            self.send_header("Content-Type", exc.headers.get("Content-Type", "application/json"))
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            return self._send_json(502, {"error": f"{name} unreachable at {base}: {exc}"})
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):  # noqa: N802
        if self.path.startswith("/proxy/"):
            return self._proxy()
        return super().do_GET()

    def do_POST(self):  # noqa: N802
        if self.path.startswith("/proxy/"):
            return self._proxy()
        self.send_error(405)

    def log_message(self, fmt, *args):  # quieter logs
        if "/proxy/" in (args[0] if args else ""):
            return
        super().log_message(fmt, *args)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"AquaSense dashboard: http://{args.host}:{args.port}")
    for name, url in UPSTREAMS.items():
        print(f"  /proxy/{name}/* -> {url}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
