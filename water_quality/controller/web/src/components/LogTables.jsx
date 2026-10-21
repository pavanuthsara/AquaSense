import { fmtDur, fmtNum, fmtTime } from "../format.js";
import StatusPill from "./StatusPill.jsx";

export function AlertLog({ alerts, parameters }) {
  const labels = Object.fromEntries(parameters.map((p) => [p.name, p.label]));
  return (
    <div>
      <h2>Alert log</h2>
      <div className="table-wrap">
        <table>
          <thead>
            <tr><th>Raised</th><th>Parameter</th><th>Severity</th><th className="num">Value / peak</th>
              <th className="num">Limit</th><th className="num">Duration</th></tr>
          </thead>
          <tbody>
            {!alerts?.length && <tr><td colSpan={6}>No alerts yet.</td></tr>}
            {alerts?.map((a) => (
              <tr key={a.id}>
                <td>{fmtTime(a.raised_at)}</td>
                <td>{labels[a.parameter] ?? a.parameter}</td>
                <td><StatusPill status={a.severity} /></td>
                <td className="num">{fmtNum(a.value, 3)} / {fmtNum(a.peak_value, 3)}</td>
                <td className="num">{a.threshold ?? "–"}</td>
                <td className="num">{a.cleared_at ? fmtDur(a.cleared_at - a.raised_at) : "active"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function ActuatorLog({ events }) {
  return (
    <div>
      <h2>Actuator log</h2>
      <div className="table-wrap">
        <table>
          <thead>
            <tr><th>Time</th><th>Actuator</th><th>Action</th><th>By</th><th>Reason</th>
              <th className="num">Ran</th></tr>
          </thead>
          <tbody>
            {!events?.length && <tr><td colSpan={6}>No actuator activity yet.</td></tr>}
            {events?.map((e) => (
              <tr key={e.id}>
                <td>{fmtTime(e.ts)}</td>
                <td>{e.actuator}</td>
                <td><StatusPill status={e.action} /></td>
                <td>{e.source}</td>
                <td className="reason">{e.reason}</td>
                <td className="num">{e.duration_s != null ? fmtDur(e.duration_s) : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
