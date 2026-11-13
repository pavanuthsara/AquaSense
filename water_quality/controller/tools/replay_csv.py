"""Replay an IoTPond CSV into the controller, as if the sensors were live.

Examples (from the water_quality/ folder, with the server running):

    # whole file as fast as possible (all 4 parameters "real")
    python -m controller.tools.replay_csv --file data/IoTpond1.csv --tank pond1

    # 1 hour of pond time per second, watch it on the dashboard
    python -m controller.tools.replay_csv --tank pond1 --speed 3600

    # mimic today's hardware: only temperature is sent, the rest is simulated
    python -m controller.tools.replay_csv --tank pond1 --params temperature --speed 600

Only the HTTP API is used (stdlib only), so this works against any running
server. Feeding the *same* file to the baseline and to the predictive
controller (each with its own DB) gives a like-for-like comparison.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

# CSV column -> controller parameter
COLUMNS = {
    "Temperature (C)": "temperature",
    "Dissolved Oxygen(g/ml)": "do",
    "PH": "ph",
    "Ammonia(g/ml)": "ammonia",
}
CET = timezone(timedelta(hours=1))
DEFAULT_FILE = Path(__file__).resolve().parents[2] / "data" / "IoTpond1.csv"


def parse_time(text: str) -> float:
    """'2021-06-19 00:00:05 CET' -> epoch seconds."""
    text = text.replace(" CET", "").strip()
    return datetime.strptime(text, "%Y-%m-%d %H:%M:%S").replace(tzinfo=CET).timestamp()


def rows(path: Path, tank: str, params: set[str], start: int, every: int, limit: int):
    with path.open(newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in COLUMNS if c not in reader.fieldnames]
        if missing:
            sys.exit(f"CSV is missing columns: {missing}")
        sent = 0
        for i, row in enumerate(reader):
            if i < start or (i - start) % every:
                continue
            reading = {"tank_id": tank, "timestamp": parse_time(row["created_at"])}
            for col, name in COLUMNS.items():
                if name in params and row[col].strip():
                    reading[name] = float(row[col])
            yield reading
            sent += 1
            if limit and sent >= limit:
                return


def post(url: str, body) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", type=Path, default=DEFAULT_FILE)
    ap.add_argument("--url", default="http://127.0.0.1:8000")
    ap.add_argument("--tank", default="pond1")
    ap.add_argument("--params", default="temperature,do,ph,ammonia",
                    help="comma list of parameters to send (others are simulated server-side)")
    ap.add_argument("--speed", type=float, default=0,
                    help="pond seconds per real second (0 = as fast as possible)")
    ap.add_argument("--start", type=int, default=0, help="skip the first N rows")
    ap.add_argument("--every", type=int, default=1, help="send every Nth row (downsample)")
    ap.add_argument("--limit", type=int, default=0, help="stop after N readings (0 = all)")
    ap.add_argument("--batch", type=int, default=500, help="readings per request when --speed 0")
    args = ap.parse_args()

    params = {p.strip() for p in args.params.split(",") if p.strip()}
    stream = rows(args.file, args.tank, params, args.start, max(1, args.every), args.limit)
    n, t_start = 0, time.time()

    if args.speed <= 0:
        batch = []
        for r in stream:
            batch.append(r)
            if len(batch) >= args.batch:
                n += post(args.url + "/api/readings/batch", batch)["ingested"]
                batch = []
                print(f"\r{n} readings", end="", flush=True)
        if batch:
            n += post(args.url + "/api/readings/batch", batch)["ingested"]
    else:
        first_ts = None
        for r in stream:
            first_ts = first_ts or r["timestamp"]
            due = t_start + (r["timestamp"] - first_ts) / args.speed
            time.sleep(max(0.0, due - time.time()))
            res = post(args.url + "/api/readings", r)
            n += 1
            acts = ", ".join(f"{e['actuator']} {e['action']}" for e in res["actuator_events"])
            alerts = ", ".join(f"{a['parameter']} {a['severity']}" for a in res["alerts_raised"])
            print(f"{datetime.fromtimestamp(r['timestamp']):%Y-%m-%d %H:%M:%S} "
                  f"{json.dumps({k: v for k, v in r.items() if k not in ('tank_id', 'timestamp')})}"
                  f"{'  ALERT ' + alerts if alerts else ''}{'  -> ' + acts if acts else ''}")

    print(f"\nreplayed {n} readings into tank '{args.tank}' in {time.time() - t_start:.1f}s")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nstopped")
    except OSError as exc:
        sys.exit(f"cannot reach the controller ({exc}). Is `python -m controller` running?")
