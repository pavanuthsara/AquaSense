import { useCallback, useEffect, useState } from "react";
import { api } from "./api.js";
import { useLiveState, useThrottledLoad } from "./hooks.js";
import Header from "./components/Header.jsx";
import ParameterCards from "./components/ParameterCards.jsx";
import HistoryCharts from "./components/HistoryCharts.jsx";
import ActuatorPanel from "./components/ActuatorPanel.jsx";
import ActiveAlerts from "./components/ActiveAlerts.jsx";
import ForecastAlerts from "./components/ForecastAlerts.jsx";
import MetricsPanel from "./components/MetricsPanel.jsx";
import { ActuatorLog, AlertLog } from "./components/LogTables.jsx";

const TANK_KEY = "aquasense.tank";
const savedTank = () => { try { return localStorage.getItem(TANK_KEY); } catch { return null; } };

/**
 * Data flow:
 *   live state (values, actuators, active alerts) -> pushed via SSE (/api/stream)
 *   history, logs, metrics                       -> fetched, throttled to every 3 s
 *   forecast + early alerts                      -> forecasting service (:8001), same throttle
 */
export default function App() {
  const [tanks, setTanks] = useState([]);
  const [tankId, setTankId] = useState(null);
  const [rangeS, setRangeS] = useState(21600);
  const [error, setError] = useState(null);
  const { state, connected } = useLiveState(tankId);

  // tank list: load once, then refresh (a CSV replay may add a tank)
  useEffect(() => {
    const load = () => api.tanks().then((list) => {
      setTanks(list);
      setTankId((cur) => cur ?? (list.includes(savedTank()) ? savedTank() : list[0]));
    }).catch((e) => setError(e.message));
    load();
    const id = setInterval(load, 10000);
    return () => clearInterval(id);
  }, []);

  const selectTank = (t) => {
    setTankId(t);
    try { localStorage.setItem(TANK_KEY, t); } catch { /* storage unavailable */ }
  };

  const logs = useThrottledLoad(useCallback(async () => {
    const [alerts, events] = await Promise.all([api.alerts(tankId), api.events(tankId)]);
    return { alerts, events };
  }, [tankId]), state, [tankId]);
  const metrics = useThrottledLoad(useCallback(() => api.metrics(tankId), [tankId]), state, [tankId]);
  // network error (TypeError) = forecasting service not running -> null;
  // an HTTP error (e.g. no readings yet) is shown in the forecast panel
  const forecast = useThrottledLoad(useCallback(() => api.forecast(tankId).catch(
    (e) => (e instanceof TypeError ? null : { error: e.message })), [tankId]), state, [tankId]);

  const run = (promise) => promise.then(() => setError(null)).catch((e) => setError(e.message));

  return (
    <>
      <Header tanks={tanks} tankId={tankId} onTank={selectTank} state={state} connected={connected}
              onMode={(m) => run(api.setMode(tankId, m))} />
      <main>
        {error && <div className="error" role="alert">{error} <button onClick={() => setError(null)}>×</button></div>}
        {!state ? <p className="hint">Waiting for data from the controller…</p> : (
          <>
            <ParameterCards parameters={state.parameters} />
            <ForecastAlerts forecast={forecast} />
            <HistoryCharts tankId={tankId} state={state} rangeS={rangeS} onRange={setRangeS}
                           forecast={forecast} />
            <ActuatorPanel actuators={state.actuators} mode={state.mode}
                           onCommand={(name, action) => run(api.command(tankId, name, action))} />
            <section className="two-col">
              <ActiveAlerts alerts={state.active_alerts} parameters={state.parameters} now={state.now} />
              <MetricsPanel metrics={metrics} parameters={state.parameters} />
            </section>
            <section className="two-col">
              <AlertLog alerts={logs?.alerts} parameters={state.parameters} />
              <ActuatorLog events={logs?.events} />
            </section>
          </>
        )}
      </main>
    </>
  );
}
