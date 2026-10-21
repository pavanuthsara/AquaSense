"""SQLite persistence (plain SQL, no ORM, so the schema can go in the report).

Tables
    readings         long format: one row per (tank, time, parameter)
    alerts           one row per out-of-range episode (raised -> cleared)
    actuator_events  every ON/OFF transition; OFF rows carry the ON duration
    tank_modes       AUTO / MANUAL per tank

Long-format readings keep the schema fixed when parameters are added; use
pandas `pivot` to get a wide table for analysis.

Writes are not committed per statement: the ingest service calls commit()
once per reading (or once per batch), which keeps CSV replay fast.
"""
from __future__ import annotations

import sqlite3
import threading
from pathlib import Path
from typing import Optional

from .models import ActuatorEvent, Reading

SCHEMA = """
CREATE TABLE IF NOT EXISTS readings (
    id        INTEGER PRIMARY KEY,
    tank_id   TEXT    NOT NULL,
    ts        REAL    NOT NULL,          -- epoch seconds (sensor time)
    parameter TEXT    NOT NULL,
    value     REAL,
    source    TEXT,                      -- payload | simulated | derived
    status    TEXT    NOT NULL           -- OK | WARNING | CRITICAL | FAULT
);
CREATE INDEX IF NOT EXISTS ix_readings ON readings (tank_id, parameter, ts);

CREATE TABLE IF NOT EXISTS alerts (
    id          INTEGER PRIMARY KEY,
    tank_id     TEXT NOT NULL,
    parameter   TEXT NOT NULL,
    side        TEXT,                    -- low | high | fault
    severity    TEXT NOT NULL,           -- WARNING | CRITICAL | FAULT (worst seen)
    value       REAL,                    -- value when raised
    peak_value  REAL,                    -- worst value during the episode
    threshold   REAL,                    -- the limit that was crossed
    raised_at   REAL NOT NULL,
    cleared_at  REAL,                    -- NULL while active
    engine      TEXT
);
CREATE INDEX IF NOT EXISTS ix_alerts ON alerts (tank_id, raised_at);

CREATE TABLE IF NOT EXISTS actuator_events (
    id         INTEGER PRIMARY KEY,
    tank_id    TEXT NOT NULL,
    actuator   TEXT NOT NULL,
    action     TEXT NOT NULL,            -- ON | OFF
    ts         REAL NOT NULL,
    duration_s REAL,                     -- on OFF rows: seconds it was ON
    source     TEXT NOT NULL,            -- auto | manual | system
    engine     TEXT,
    reason     TEXT
);
CREATE INDEX IF NOT EXISTS ix_events ON actuator_events (tank_id, actuator, ts);

CREATE TABLE IF NOT EXISTS tank_modes (
    tank_id TEXT PRIMARY KEY,
    mode    TEXT NOT NULL
);
"""


class Storage:
    def __init__(self, db_path: str | Path) -> None:
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        # One shared connection guarded by a lock: REST handlers, the MQTT
        # thread and the dashboard stream all go through here.
        self.conn = sqlite3.connect(str(db_path), check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.executescript(SCHEMA)
        self.lock = threading.RLock()

    def commit(self) -> None:
        with self.lock:
            self.conn.commit()

    def query(self, sql: str, args: tuple = ()) -> list[dict]:
        """Read-only SQL helper (also used by services/metrics.py)."""
        with self.lock:
            return [dict(r) for r in self.conn.execute(sql, args).fetchall()]

    _q = query

    def _x(self, sql: str, args: tuple = ()) -> int:
        with self.lock:
            return self.conn.execute(sql, args).lastrowid

    # ---------------------------------------------------------------- readings
    def insert_reading(self, r: Reading) -> None:
        rows = [(r.tank_id, r.ts, pv.name, pv.value, pv.source, pv.status.value)
                for pv in r.values.values() if pv.value is not None]
        with self.lock:
            self.conn.executemany(
                "INSERT INTO readings (tank_id, ts, parameter, value, source, status) "
                "VALUES (?, ?, ?, ?, ?, ?)", rows)

    def latest_values(self, tank_id: str) -> dict[str, dict]:
        rows = self._q(
            """SELECT r.* FROM readings r
               JOIN (SELECT parameter, MAX(ts) AS ts FROM readings
                     WHERE tank_id = ? GROUP BY parameter) m
                 ON r.parameter = m.parameter AND r.ts = m.ts
               WHERE r.tank_id = ?""", (tank_id, tank_id))
        return {r["parameter"]: r for r in rows}

    def history(self, tank_id: str, parameter: str,
                since: Optional[float] = None, limit: int = 500) -> list[dict]:
        rows = self._q(
            """SELECT ts, value, status, source FROM readings
               WHERE tank_id = ? AND parameter = ? AND ts >= ?
               ORDER BY ts DESC LIMIT ?""",
            (tank_id, parameter, since or 0, limit))
        return rows[::-1]  # oldest first for charting

    def tanks(self) -> list[str]:
        return [r["tank_id"] for r in self._q(
            "SELECT DISTINCT tank_id FROM readings ORDER BY tank_id")]

    def latest_ts(self) -> dict[str, float]:
        return {r["tank_id"]: r["ts"] for r in self._q(
            "SELECT tank_id, MAX(ts) AS ts FROM readings GROUP BY tank_id")}

    # ------------------------------------------------------------------ alerts
    def open_alert(self, tank_id: str, parameter: str, side: str, severity: str,
                   value: float, threshold: Optional[float], ts: float, engine: str) -> int:
        return self._x(
            """INSERT INTO alerts (tank_id, parameter, side, severity, value,
                                   peak_value, threshold, raised_at, engine)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (tank_id, parameter, side, severity, value, value, threshold, ts, engine))

    def update_alert(self, alert_id: int, severity: str, peak_value: float) -> None:
        self._x("UPDATE alerts SET severity = ?, peak_value = ? WHERE id = ?",
                (severity, peak_value, alert_id))

    def clear_alert(self, alert_id: int, ts: float) -> None:
        self._x("UPDATE alerts SET cleared_at = ? WHERE id = ?", (ts, alert_id))

    def active_alerts(self, tank_id: Optional[str] = None) -> list[dict]:
        if tank_id is None:
            return self._q("SELECT * FROM alerts WHERE cleared_at IS NULL")
        return self._q("SELECT * FROM alerts WHERE tank_id = ? AND cleared_at IS NULL "
                       "ORDER BY raised_at DESC", (tank_id,))

    def alerts(self, tank_id: str, limit: int = 100) -> list[dict]:
        return self._q("SELECT * FROM alerts WHERE tank_id = ? "
                       "ORDER BY raised_at DESC LIMIT ?", (tank_id, limit))

    # --------------------------------------------------------------- actuators
    def insert_event(self, e: ActuatorEvent) -> None:
        self._x(
            """INSERT INTO actuator_events
               (tank_id, actuator, action, ts, duration_s, source, engine, reason)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (e.tank_id, e.actuator, e.action, e.ts, e.duration_s,
             e.source, e.engine, e.reason))

    def events(self, tank_id: str, limit: int = 100) -> list[dict]:
        return self._q("SELECT * FROM actuator_events WHERE tank_id = ? "
                       "ORDER BY ts DESC, id DESC LIMIT ?", (tank_id, limit))

    def last_events(self) -> list[dict]:
        """Most recent event per (tank, actuator): used to restore state."""
        return self._q(
            """SELECT e.* FROM actuator_events e
               JOIN (SELECT MAX(id) AS id FROM actuator_events
                     GROUP BY tank_id, actuator) m ON e.id = m.id""")

    def runtime_totals(self, tank_id: str) -> dict[str, dict]:
        """Completed ON time and number of switch-ONs per actuator."""
        rows = self._q(
            """SELECT actuator,
                      COALESCE(SUM(CASE WHEN action = 'OFF' THEN duration_s END), 0) AS runtime_s,
                      SUM(CASE WHEN action = 'ON' THEN 1 ELSE 0 END) AS switch_ons
               FROM actuator_events WHERE tank_id = ? GROUP BY actuator""", (tank_id,))
        return {r["actuator"]: r for r in rows}

    # ------------------------------------------------------------------- modes
    def get_modes(self) -> dict[str, str]:
        return {r["tank_id"]: r["mode"] for r in self._q("SELECT * FROM tank_modes")}

    def set_mode(self, tank_id: str, mode: str) -> None:
        self._x("INSERT INTO tank_modes (tank_id, mode) VALUES (?, ?) "
                "ON CONFLICT(tank_id) DO UPDATE SET mode = excluded.mode", (tank_id, mode))
