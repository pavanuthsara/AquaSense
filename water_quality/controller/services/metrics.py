"""Evaluation metrics: how well and at what cost did the controller do?

Everything is computed from the database, so the same function scores the
baseline run and, later, the predictive run (use one DB file per run).

    resource use   actuator run-time, switch-ON count, energy estimate (Wh)
    water quality  excursions per parameter, time out of range, % of observed time
    data coverage  window length, data gaps longer than data_gap_s
    reactivity     delay between a limit being crossed and the actuator acting
"""
from __future__ import annotations

from typing import Optional

from ..core.config import Settings
from ..core.storage import Storage

# Which alert sides each rule condition responds to.
RULE_SIDES = {"below_min": ("low",), "above_max": ("high",), "out_of_range": ("low", "high")}


def compute_metrics(settings: Settings, storage: Storage, tank_id: str,
                    actuator_summary: list[dict], now: Optional[float] = None) -> dict:
    window = storage.query(
        "SELECT MIN(ts) AS start, MAX(ts) AS end, COUNT(DISTINCT ts) AS samples "
        "FROM readings WHERE tank_id = ?", (tank_id,))[0]
    end = now or window["end"]
    duration = (end - window["start"]) if window["start"] is not None and end else 0.0

    # Data outages: time beyond the watchdog limit is not "observed" time and
    # is excluded from the % out-of-range denominator.
    gap_limit = settings.data_gap_s
    gaps = storage.query(
        """SELECT gap FROM (SELECT ts - LAG(ts) OVER (ORDER BY ts) AS gap
                            FROM (SELECT DISTINCT ts FROM readings WHERE tank_id = ?))
           WHERE gap > ?""", (tank_id, gap_limit)) if gap_limit else []
    unobserved = sum(g["gap"] - gap_limit for g in gaps)
    observed = max(0.0, duration - unobserved)

    # ---- water quality: alert episodes per parameter
    parameters = {}
    for name in settings.parameters:
        rows = storage.query(
            """SELECT side, severity, raised_at, COALESCE(cleared_at, ?) AS end_at
               FROM alerts WHERE tank_id = ? AND parameter = ?""", (end, tank_id, name))
        excursions = [r for r in rows if r["side"] != "fault"]
        out_s = sum(max(0.0, r["end_at"] - r["raised_at"]) for r in excursions)
        parameters[name] = {
            "excursions": len(excursions),
            "critical_excursions": sum(r["severity"] == "CRITICAL" for r in excursions),
            "sensor_faults": len(rows) - len(excursions),
            "time_out_of_range_s": round(out_s, 1),
            "pct_time_out_of_range": round(100 * out_s / observed, 2) if observed else 0.0,
        }

    # ---- reactivity: for every excursion a rule should handle, how long until
    #      that rule's actuator switched ON?
    response = {}
    for rule in settings.rules:
        sides = RULE_SIDES[rule.condition]
        rows = storage.query(
            f"""SELECT a.raised_at,
                       (SELECT MIN(e.ts) FROM actuator_events e
                        WHERE e.tank_id = a.tank_id AND e.actuator = ? AND e.action = 'ON'
                          AND e.ts >= a.raised_at AND e.ts <= COALESCE(a.cleared_at, ?)) AS acted_at
                FROM alerts a
                WHERE a.tank_id = ? AND a.parameter = ?
                  AND a.side IN ({",".join("?" * len(sides))})""",
            (rule.actuator, end, tank_id, rule.parameter, *sides))
        delays = [r["acted_at"] - r["raised_at"] for r in rows if r["acted_at"] is not None]
        response[f"{rule.parameter}->{rule.actuator}"] = {
            "excursions": len(rows),
            "acted_on": len(delays),
            "mean_delay_s": round(sum(delays) / len(delays), 1) if delays else None,
        }

    return {
        "tank_id": tank_id,
        "engine": settings.engine,
        "window": {"start": window["start"], "end": end,
                   "duration_s": round(duration, 1), "observed_s": round(observed, 1),
                   "data_gaps": len(gaps), "samples": window["samples"]},
        "actuators": {a["name"]: {k: a[k] for k in ("runtime_s", "switch_ons", "energy_wh")}
                      for a in actuator_summary},
        "total_energy_wh": round(sum(a["energy_wh"] for a in actuator_summary), 3),
        "parameters": parameters,
        "response": response,
    }
