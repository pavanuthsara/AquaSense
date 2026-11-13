"""Alert lifecycle: raise -> (escalate) -> clear.

An alert is one *episode* of a parameter being out of range, not one row per
bad reading. That gives clean metrics: number of excursions and total time
out of range = sum(cleared_at - raised_at).

    reading WARNING/CRITICAL, no active alert   -> raise
    reading worse than the active alert         -> escalate severity, track peak
    reading flips from low to high (or fault)   -> clear old, raise new
    reading OK                                  -> clear
    reading MISSING                             -> no change
"""
from __future__ import annotations

import logging
from typing import Optional

from ..core.config import Settings
from ..core.models import Reading, Status
from ..core.storage import Storage

log = logging.getLogger("aquasense.alerts")

SEVERITY_RANK = {"WARNING": 1, "CRITICAL": 2, "FAULT": 1}
ALERTING = (Status.WARNING, Status.CRITICAL, Status.FAULT)


class AlertService:
    def __init__(self, settings: Settings, storage: Storage, engine_name: str) -> None:
        self.settings = settings
        self.storage = storage
        self.engine_name = engine_name
        # (tank_id, parameter) -> active alert row; reloaded so restarts don't
        # leave orphaned "active" alerts
        self._active: dict[tuple[str, str], dict] = {
            (a["tank_id"], a["parameter"]): a for a in storage.active_alerts()
        }

    def _threshold(self, parameter: str, side: str) -> Optional[float]:
        p = self.settings.parameters[parameter]
        return {"low": p.min, "high": p.max}.get(side)

    def evaluate(self, reading: Reading) -> list[dict]:
        """Update alert state from one reading; return newly raised alerts."""
        raised = []
        for pv in reading.values.values():
            key = (reading.tank_id, pv.name)
            active = self._active.get(key)

            if pv.status in ALERTING:
                side = pv.side or "fault"
                if active and active["side"] != side:
                    self._clear(key, reading.ts)
                    active = None
                if active is None:
                    raised.append(self._raise(key, side, pv.status.value, pv.value, reading.ts))
                else:
                    self._escalate(active, pv.status.value, pv.value)
            elif pv.status == Status.OK and active:
                self._clear(key, reading.ts)
        return raised

    def close_all(self, tank_id: str, ts: float) -> None:
        """Data outage: we can no longer claim the tank is out of range."""
        for key in [k for k in self._active if k[0] == tank_id]:
            self._clear(key, ts)

    def _raise(self, key, side, severity, value, ts) -> dict:
        tank_id, parameter = key
        threshold = self._threshold(parameter, side)
        alert_id = self.storage.open_alert(tank_id, parameter, side, severity,
                                           value, threshold, ts, self.engine_name)
        alert = {"id": alert_id, "tank_id": tank_id, "parameter": parameter, "side": side,
                 "severity": severity, "value": value, "peak_value": value,
                 "threshold": threshold, "raised_at": ts, "cleared_at": None}
        self._active[key] = alert
        log.warning("ALERT %s %s/%s %s value=%s limit=%s",
                    severity, tank_id, parameter, side, value, threshold)
        return alert

    def _escalate(self, alert: dict, severity: str, value: float) -> None:
        worse = (value < alert["peak_value"]) if alert["side"] == "low" else \
                (value > alert["peak_value"]) if alert["side"] == "high" else False
        new_sev = severity if SEVERITY_RANK[severity] > SEVERITY_RANK[alert["severity"]] \
            else alert["severity"]
        if worse or new_sev != alert["severity"]:
            alert["peak_value"] = value if worse else alert["peak_value"]
            alert["severity"] = new_sev
            self.storage.update_alert(alert["id"], new_sev, alert["peak_value"])

    def _clear(self, key, ts) -> None:
        alert = self._active.pop(key)
        self.storage.clear_alert(alert["id"], ts)
        log.info("CLEAR %s/%s (%s)", key[0], key[1], alert["side"])
