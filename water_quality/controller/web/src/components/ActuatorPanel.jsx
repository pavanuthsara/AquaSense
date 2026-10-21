import { fmtDur, fmtNum, fmtTime } from "../format.js";
import StatusPill from "./StatusPill.jsx";

/** Actuator states, run-time (the resource metric) and manual ON/OFF. */
export default function ActuatorPanel({ actuators, mode, onCommand }) {
  const manual = mode === "MANUAL";
  const total = actuators.reduce((t, a) => t + a.energy_wh, 0);
  return (
    <section>
      <div className="section-head">
        <h2>Actuators</h2>
        <div className="total">Total energy (proxy): <b>{total.toFixed(1)} Wh</b></div>
      </div>
      <p className="hint">
        {manual
          ? "MANUAL mode: the engine still raises alerts but does not switch actuators. Use the buttons."
          : "AUTO mode: the threshold engine switches actuators. Switch to MANUAL to use the buttons."}
      </p>
      <div className="cards">
        {actuators.map((a) => (
          <div key={a.name} className="card act">
            <div className="label">
              <span>{a.label}</span>
              <span className="tag">{a.driver === "mock" ? "simulated" : a.driver}</span>
            </div>
            <div className="state"><StatusPill status={a.is_on ? "ON" : "OFF"} /></div>
            <dl>
              <dt>Run-time</dt><dd>{fmtDur(a.runtime_s)}</dd>
              <dt>Switch-ons</dt><dd>{a.switch_ons}</dd>
              <dt>Energy</dt><dd>{fmtNum(a.energy_wh, 1)} Wh <span className="meta">@{a.power_w} W</span></dd>
              <dt>On since</dt><dd>{a.is_on ? fmtTime(a.on_since) : "–"}</dd>
            </dl>
            <div className="buttons">
              <button disabled={!manual || a.is_on} onClick={() => onCommand(a.name, "on")}>ON</button>
              <button disabled={!manual || !a.is_on} onClick={() => onCommand(a.name, "off")}>OFF</button>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
