import { fmtDur, fmtNum, fmtTime } from "../format.js";
import StatusPill from "./StatusPill.jsx";

export default function ActiveAlerts({ alerts, parameters, now }) {
  const byName = Object.fromEntries(parameters.map((p) => [p.name, p]));
  return (
    <div>
      <h2>Active alerts</h2>
      <ul className="alerts">
        {alerts.length === 0 && (
          <li className="none">No active alerts — all measured parameters within safe range.</li>
        )}
        {alerts.map((a) => {
          const p = byName[a.parameter] ?? { label: a.parameter, unit: "" };
          const what = a.side === "fault"
            ? "sensor reading impossible"
            : `${a.side === "low" ? "below" : "above"} ${a.threshold} ${p.unit}`;
          return (
            <li key={a.id}>
              <StatusPill status={a.severity} /> <b>{p.label}</b> {what} — worst {fmtNum(a.peak_value, 3)}
              {" · "}since {fmtTime(a.raised_at)} ({fmtDur((now ?? a.raised_at) - a.raised_at)})
            </li>
          );
        })}
      </ul>
    </div>
  );
}
