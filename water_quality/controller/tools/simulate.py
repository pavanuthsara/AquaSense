"""Pretend to be the ESP32: post temperature readings like the real device.

Use it to demo the system with no hardware connected. DO / pH / ammonia are
simulated by the server (source: auto), unless a scenario sends them.

    python -m controller.tools.simulate                        # normal pond
    python -m controller.tools.simulate --scenario cold_snap   # heater demo
    python -m controller.tools.simulate --scenario do_crash    # aerator demo
    python -m controller.tools.simulate --scenario sensor_fault

--step is how much pond time passes per reading (default 60 s) and
--interval how long to wait between posts (default 1 s), so the default
plays one pond-hour per real minute.

The script models its own water temperature and reads the heater state back
from the server, so the cold-snap demo shows the full loop:
temperature falls -> alert -> heater ON -> temperature recovers -> heater OFF.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
import time
import urllib.request

SCENARIOS = ("normal", "cold_snap", "do_crash", "sensor_fault")


def call(url: str, body=None) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"},
                                 method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default="http://127.0.0.1:8000")
    ap.add_argument("--tank", default="tank1")
    ap.add_argument("--scenario", choices=SCENARIOS, default="normal")
    ap.add_argument("--interval", type=float, default=1.0, help="real seconds between posts")
    ap.add_argument("--step", type=float, default=60.0, help="pond seconds per reading")
    ap.add_argument("--count", type=int, default=0, help="number of readings (0 = forever)")
    ap.add_argument("--seed", type=int, default=None)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    ts = time.time()
    temp, do = 25.5, 6.5
    i = 0
    while not args.count or i < args.count:
        minutes = i * args.step / 60
        heater_on = False
        if i:  # read actuator state back (closes the loop for the demo)
            state = call(f"{args.url}/api/state?tank_id={args.tank}")
            heater_on = any(a["name"] == "heater" and a["is_on"] for a in state["actuators"])

        # --- water temperature model (per step)
        dt = args.step / 60
        target = 25.5 + 0.4 * math.sin(2 * math.pi * minutes / 1440)   # daily cycle
        if args.scenario == "cold_snap" and 30 <= minutes % 360 < 150:
            target = 21.0                                              # cold night / power cut
        temp += 0.03 * (target - temp) * dt + (0.06 * dt if heater_on else 0)
        reading = {"tank_id": args.tank, "timestamp": ts,
                   "temperature": round(temp + rng.gauss(0, 0.03), 3)}

        if args.scenario == "do_crash":
            # DO sent explicitly (overrides the server simulator): falls, then recovers
            phase = minutes % 240
            do = 6.5 - 3.5 * math.sin(math.pi * phase / 120) if phase < 120 else 6.5
            reading["do"] = round(do + rng.gauss(0, 0.05), 3)
        if args.scenario == "sensor_fault" and rng.random() < 0.05:
            reading["temperature"] = -127.0                          # DS18B20 disconnected

        res = call(f"{args.url}/api/readings", reading)
        line = " ".join(f"{k}={v['value']:.3f}" if v["value"] is not None else f"{k}=–"
                        for k, v in res["values"].items())
        extra = "".join(f"  ALERT {a['parameter']} {a['severity']}" for a in res["alerts_raised"])
        extra += "".join(f"  -> {e['actuator']} {e['action']}" for e in res["actuator_events"])
        print(f"[{time.strftime('%H:%M:%S', time.localtime(ts))}] {line}{extra}", flush=True)

        i += 1
        ts += args.step
        time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nstopped")
    except OSError as exc:
        sys.exit(f"cannot reach the controller ({exc}). Is `python -m controller` running?")
