"""Export evaluation metrics from a run's database (server need not be running).

    python -m controller.tools.export_metrics                        # default DB, all tanks
    python -m controller.tools.export_metrics --db runs/baseline.db --tank pond1 --csv out.csv

Prints the metrics as JSON and optionally writes a flat CSV
(tank, group, item, metric, value) that is easy to put next to the
predictive controller's numbers in a results table.

For raw data analysis, the readings table loads straight into pandas:
    pd.read_sql("SELECT * FROM readings", sqlite3.connect(db)).pivot_table(
        index="ts", columns="parameter", values="value")
"""
from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path

from ..actuators.manager import ActuatorManager
from ..core.config import load_settings
from ..core.storage import Storage
from ..services.metrics import compute_metrics


def flatten(m: dict) -> list[tuple]:
    rows = [(m["tank_id"], "window", "", k, v) for k, v in m["window"].items()]
    rows.append((m["tank_id"], "energy", "total", "energy_wh", m["total_energy_wh"]))
    for group in ("actuators", "parameters", "response"):
        for item, metrics in m[group].items():
            rows += [(m["tank_id"], group, item, k, v) for k, v in metrics.items()]
    return rows


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", type=Path, help="database file (default: from config.yaml)")
    ap.add_argument("--config", type=Path, help="config.yaml used for the run")
    ap.add_argument("--tank", help="tank id (default: all tanks in the DB)")
    ap.add_argument("--csv", type=Path, help="also write a flat CSV here")
    args = ap.parse_args()

    if args.db:
        os.environ["AQUASENSE_DB"] = str(args.db)
    settings = load_settings(args.config)
    if not settings.db_path.exists():
        raise SystemExit(f"no database at {settings.db_path}")
    storage = Storage(settings.db_path)
    actuators = ActuatorManager(settings, storage)
    actuators.restore()
    latest = storage.latest_ts()

    results = []
    for tank in [args.tank] if args.tank else sorted(latest):
        now = latest.get(tank)
        results.append(compute_metrics(settings, storage, tank, actuators.summary(tank, now), now))

    print(json.dumps(results, indent=2))
    if args.csv:
        with args.csv.open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["tank_id", "group", "item", "metric", "value"])
            for m in results:
                w.writerows(flatten(m))
        print(f"wrote {args.csv}")


if __name__ == "__main__":
    main()
