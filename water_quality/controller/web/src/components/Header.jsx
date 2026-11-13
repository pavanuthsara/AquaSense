import { fmtTime } from "../format.js";

export default function Header({ tanks, tankId, onTank, state, connected, onMode }) {
  const mode = state?.mode;
  return (
    <>
      <header className="topbar">
        <div className="brand">
          <h1>AquaSense</h1>
          <span className="sub">Threshold baseline controller · engine <b>{state?.engine ?? "–"}</b></span>
        </div>
        <div className="controls">
          <label>
            Tank{" "}
            <select value={tankId ?? ""} onChange={(e) => onTank(e.target.value)}>
              {tanks.map((t) => <option key={t}>{t}</option>)}
            </select>
          </label>
          <div className="mode" role="group" aria-label="Control mode">
            {["AUTO", "MANUAL"].map((m) => (
              <button key={m} className={mode === m ? "active" : ""} onClick={() => onMode(m)}>{m}</button>
            ))}
          </div>
          <span className={`conn ${connected ? "live" : ""}`}>● {connected ? "live" : "connecting"}</span>
        </div>
      </header>
      <p className="clock">Sensor time: {state?.now ? fmtTime(state.now) : "no readings yet"}</p>
    </>
  );
}
