// Display helpers. All timestamps from the API are epoch seconds (sensor time).

export const fmtTime = (ts) => ts == null ? "–" : new Date(ts * 1000).toLocaleString([], {
  month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit",
});

export const fmtClock = (ts) => new Date(ts * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

export const fmtNum = (v, digits = 2) => v == null ? "–" : Number(v).toFixed(digits);

export function fmtDur(s) {
  if (s == null) return "–";
  s = Math.round(s);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  if (h) return `${h}h ${String(m).padStart(2, "0")}m`;
  if (m) return `${m}m ${String(sec).padStart(2, "0")}s`;
  return `${sec}s`;
}

export const STATUS_TEXT = {
  OK: "Safe", WARNING: "Warning", CRITICAL: "Critical", FAULT: "Sensor fault", MISSING: "No data",
  ON: "ON", OFF: "OFF",
};

export const SOURCE_TEXT = { payload: "real", simulated: "simulated", derived: "derived", auto: "auto" };
