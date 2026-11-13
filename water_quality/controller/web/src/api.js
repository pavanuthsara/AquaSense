// Thin wrapper around the FastAPI backend (see controller/api/routes.py).

async function request(path, options = {}) {
  const res = await fetch(path, { headers: { "Content-Type": "application/json" }, ...options });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || res.statusText);
  }
  return res.json();
}

// The forecasting service (water_quality/prediction/service.py) runs separately
// on :8001 next to the controller; override with VITE_FORECAST_URL.
const FORECAST_URL = import.meta.env.VITE_FORECAST_URL
  ?? `${window.location.protocol}//${window.location.hostname}:8001`;

const q = (params) => new URLSearchParams(
  Object.entries(params).filter(([, v]) => v != null)).toString();

export const api = {
  tanks: () => request("/api/tanks"),
  history: (tankId, parameter, since, limit = 5000) =>
    request(`/api/history?${q({ tank_id: tankId, parameter, since, limit })}`),
  alerts: (tankId, limit = 200) => request(`/api/alerts?${q({ tank_id: tankId, limit })}`),
  events: (tankId, limit = 200) => request(`/api/actuators/events?${q({ tank_id: tankId, limit })}`),
  metrics: (tankId) => request(`/api/metrics?${q({ tank_id: tankId })}`),
  setMode: (tankId, mode) =>
    request("/api/mode", { method: "POST", body: JSON.stringify({ tank_id: tankId, mode }) }),
  command: (tankId, actuator, action) =>
    request(`/api/actuators/${actuator}`, { method: "POST", body: JSON.stringify({ tank_id: tankId, action }) }),
  streamUrl: (tankId) => `/api/stream?${q({ tank_id: tankId })}`,
  forecast: (tankId) => request(`${FORECAST_URL}/forecast?${q({ tank_id: tankId })}`),
};
