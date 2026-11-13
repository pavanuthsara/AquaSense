"""`python -m controller [--host 0.0.0.0] [--port 8000]`

Use --host 0.0.0.0 so the ESP32 on the same Wi-Fi can reach the server.
"""
import argparse

import uvicorn

parser = argparse.ArgumentParser(description="AquaSense baseline controller")
parser.add_argument("--host", default="127.0.0.1", help="0.0.0.0 = reachable from the ESP32")
parser.add_argument("--port", type=int, default=8000)
args = parser.parse_args()

uvicorn.run("controller.main:create_app", factory=True, host=args.host, port=args.port)
