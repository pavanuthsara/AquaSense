import { fmtDur } from "../format.js";

/** Evaluation metrics for the baseline-vs-predictive comparison. */
export default function MetricsPanel({ metrics, parameters }) {
  const labels = Object.fromEntries(parameters.map((p) => [p.name, p.label]));
  return (
    <div>
      <h2>Metrics</h2>
      <div className="metrics">
        {!metrics ? <p className="hint">Loading…</p> : (
          <>
            <p>
              Observed {fmtDur(metrics.window.observed_s)} of {fmtDur(metrics.window.duration_s)}{" "}
              ({metrics.window.data_gaps} data gaps) · {metrics.window.samples} samples · total energy{" "}
              <b>{metrics.total_energy_wh.toFixed(1)} Wh</b>
            </p>
            <table>
              <thead>
                <tr><th>Parameter</th><th className="num">Excursions</th><th className="num">Out of range</th>
                  <th className="num">% time</th><th className="num">Faults</th></tr>
              </thead>
              <tbody>
                {Object.entries(metrics.parameters).map(([name, m]) => (
                  <tr key={name}>
                    <td>{labels[name] ?? name}</td>
                    <td className="num">{m.excursions}</td>
                    <td className="num">{fmtDur(m.time_out_of_range_s)}</td>
                    <td className="num">{m.pct_time_out_of_range}%</td>
                    <td className="num">{m.sensor_faults}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="hint">
              {Object.entries(metrics.response).map(([rule, r]) => (
                <span key={rule} className="block">
                  {rule}: {r.acted_on}/{r.excursions} acted on, mean delay{" "}
                  {r.mean_delay_s == null ? "–" : fmtDur(r.mean_delay_s)}
                </span>
              ))}
            </p>
            <p className="hint">Full export: <code>python -m controller.tools.export_metrics</code></p>
          </>
        )}
      </div>
    </div>
  );
}
