import { fmtTime } from "../format.js";
import StatusPill from "./StatusPill.jsx";

/** "How far to trust this warning", from the held-out evaluation. */
function reliabilityText(r) {
  if (!r || r.events == null) return null;
  if (r.events < 10) return `not yet validated (only ${r.events} breaches in test data)`;
  return `in testing, warned before ${Math.round(r.warned_pct)}% of breaches; `
    + `${Math.round(r.precision * 100)}% of warnings were right`;
}

/**
 * Early (predictive) alerts: the forecast leaves the safe range while the
 * current value is still safe. Separate from the rule engine's active alerts.
 */
export default function ForecastAlerts({ forecast }) {
  const minutes = forecast?.horizon_steps ? forecast.horizon_steps * forecast.freq_min : null;
  const ahead = minutes == null ? "" : minutes < 60 ? `${minutes} min` : `${+(minutes / 60).toFixed(1)} h`;
  const params = forecast?.parameters ? Object.entries(forecast.parameters) : [];
  const waiting = params.filter(([, p]) => p.reason);

  return (
    <section>
      <h2>Forecast{ahead ? ` — next ${ahead}` : ""}</h2>
      <ul className="alerts">
        {!forecast && <li className="none">Forecasting service offline (start it with <code>python -m prediction.service</code>).</li>}
        {forecast?.error && <li className="none">Forecast unavailable: {forecast.error}</li>}
        {forecast?.early_alerts?.length === 0 && (
          <li className="none">No new breaches forecast for the parameters that are safe now.</li>
        )}
        {forecast?.early_alerts?.map((a) => {
          const note = reliabilityText(forecast.parameters[a.parameter]?.reliability);
          return (
            <li key={a.parameter} className="early">
              <StatusPill status="WARNING" label="Early warning" /> <b>{a.message}</b>
              <div className="hint">
                now {a.current_value} · expected around {fmtTime(a.breach_ts)}{note ? ` · ${note}` : ""}
              </div>
            </li>
          );
        })}
      </ul>
      {waiting.length > 0 && (
        <p className="hint">
          No forecast yet for {waiting.map(([, p]) => `${p.label} (${p.reason})`).join(", ")}.
        </p>
      )}
    </section>
  );
}
