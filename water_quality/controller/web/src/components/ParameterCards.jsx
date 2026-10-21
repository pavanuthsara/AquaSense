import { fmtNum, SOURCE_TEXT } from "../format.js";
import StatusPill from "./StatusPill.jsx";

function rangeText(p) {
  const parts = [p.min != null && `min ${p.min}`, p.max != null && `max ${p.max}`].filter(Boolean);
  return parts.length ? parts.join(" · ") : "no limits";
}

/** Live value per parameter, coloured by safe/unsafe status. */
export default function ParameterCards({ parameters }) {
  return (
    <section>
      <h2>Current values</h2>
      <div className="cards">
        {parameters.map((p) => (
          <div key={p.name} className={`card status-${p.status}`}>
            <div className="label">
              <span>{p.label}</span>
              <span className="tag">{SOURCE_TEXT[p.source ?? p.configured_source] ?? "–"}</span>
            </div>
            <div className="value">
              {fmtNum(p.value, p.name === "nh3" ? 4 : 2)}<small>{p.unit}</small>
            </div>
            <StatusPill status={p.status} />
            <div className="meta">Safe: {rangeText(p)}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
