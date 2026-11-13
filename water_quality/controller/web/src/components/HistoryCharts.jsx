import { useCallback } from "react";
import {
  CartesianGrid, Line, LineChart, ReferenceArea, ReferenceLine, ResponsiveContainer,
  Tooltip, XAxis, YAxis,
} from "recharts";
import { api } from "../api.js";
import { fmtClock, fmtTime } from "../format.js";
import { useThemeColors, useThrottledLoad } from "../hooks.js";

const RANGES = [
  { label: "1 h", s: 3600 },
  { label: "6 h", s: 21600 },
  { label: "24 h", s: 86400 },
  { label: "7 d", s: 604800 },
];
const MAX_POINTS = 800; // per chart; keeps rendering fast on long ranges

/** Keep every k-th point so long histories stay responsive. */
function thin(rows) {
  if (rows.length <= MAX_POINTS) return rows;
  const k = Math.ceil(rows.length / MAX_POINTS);
  return rows.filter((_, i) => i % k === 0 || i === rows.length - 1);
}

/**
 * y-axis with round tick values (1, 2, 2.5, 5 x 10^n) that always includes
 * the safe limits. Returns { domain, ticks, decimals }.
 */
function yAxis(points, p) {
  const ys = points.map((d) => d.y).filter((v) => v != null);
  if (p.min != null) ys.push(p.min);
  if (p.max != null) ys.push(p.max);
  let lo = ys.length ? Math.min(...ys) : 0;
  let hi = ys.length ? Math.max(...ys) : 1;
  if (hi === lo) { lo -= Math.abs(lo) * 0.1 || 1; hi += Math.abs(hi) * 0.1 || 1; }
  const raw = (hi - lo) / 4;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw);
  const start = Math.floor(lo / step) * step, end = Math.ceil(hi / step) * step;
  const ticks = [];
  for (let v = start; v <= end + step / 2; v += step) ticks.push(+v.toFixed(10));
  const decimals = Math.max(0, -Math.floor(Math.log10(step) + 1e-9) + (step / mag === 2.5 ? 1 : 0));
  return { domain: [start, end], ticks, decimals };
}

function ChartTooltip({ active, payload, param }) {
  if (!active || !payload?.length || payload[0].value == null) return null;
  const d = payload[0].payload;
  return (
    <div className="tooltip">
      <div className="tooltip-time">{fmtTime(d.x)}{d.f != null ? " · forecast" : ""}</div>
      <div><b>{d.y ?? d.f}</b> {param.unit}</div>
    </div>
  );
}

function ParamChart({ param, rows, since, now, fc, c }) {
  // sensor faults become gaps so they don't distort the axis
  const points = thin(rows ?? []).map((r) => ({ x: r.ts, y: r.status === "FAULT" ? null : r.value }));
  // forecast: starts at the last cleaned value, then one point per step
  const fcPoints = fc?.forecast?.length
    ? [{ x: fc.as_of, f: fc.current }, ...fc.forecast.map((p) => ({ x: p.ts, f: p.value }))]
    : [];
  const y = yAxis([...points, ...fcPoints.map((p) => ({ y: p.f }))], param);
  const [y0, y1] = y.domain;
  const end = fcPoints.length ? Math.max(now ?? 0, fcPoints[fcPoints.length - 1].x) : now;
  const domainX = now ? [since, end] : ["dataMin", "dataMax"];
  const tick = { fill: c["text-3"], fontSize: 11 };
  return (
    <div className="chart-card">
      <h3>{param.label} ({param.unit})</h3>
      <div className="chart-box">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={points} margin={{ top: 6, right: 12, bottom: 0, left: -12 }}>
            <CartesianGrid stroke={c.grid} vertical={false} />
            {/* safe band + dashed limits, drawn behind the data */}
            <ReferenceArea y1={param.min ?? y0} y2={param.max ?? y1} fill={c["band-fill"]}
                           fillOpacity={1} stroke="none" ifOverflow="hidden" />
            {param.min != null && <ReferenceLine y={param.min} stroke={c.limit} strokeDasharray="4 4" />}
            {param.max != null && <ReferenceLine y={param.max} stroke={c.limit} strokeDasharray="4 4" />}
            <XAxis dataKey="x" type="number" domain={domainX} allowDataOverflow
                   tickFormatter={fmtClock} tick={tick} stroke={c.border} tickCount={6} />
            <YAxis domain={y.domain} ticks={y.ticks} allowDataOverflow tick={tick} stroke={c.border}
                   tickFormatter={(v) => v.toFixed(y.decimals)} width={52} />
            <Tooltip content={<ChartTooltip param={param} />} isAnimationActive={false}
                     cursor={{ stroke: c["text-3"], strokeDasharray: "2 2" }} />
            <Line dataKey="y" stroke={c.series} strokeWidth={2} dot={false}
                  activeDot={{ r: 4 }} isAnimationActive={false} connectNulls={false} />
            {fcPoints.length > 0 && now && (
              <ReferenceLine x={now} stroke={c["text-3"]} strokeDasharray="2 3"
                             label={{ value: "now", position: "insideTopRight", fill: c["text-3"], fontSize: 11 }} />
            )}
            {fcPoints.length > 0 && (
              <Line data={fcPoints} dataKey="f" stroke={c.series} strokeWidth={2} strokeDasharray="5 4"
                    strokeOpacity={0.75} dot={false} activeDot={{ r: 4 }} isAnimationActive={false} />
            )}
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

/** One small chart per parameter (single series each, so no legend). */
export default function HistoryCharts({ tankId, state, rangeS, onRange, forecast }) {
  const colors = useThemeColors();
  const since = state?.now ? state.now - rangeS : 0;
  const params = state?.parameters ?? [];

  const load = useCallback(async () => {
    const entries = await Promise.all(params.map(async (p) =>
      [p.name, await api.history(tankId, p.name, since)]));
    return Object.fromEntries(entries);
  }, [tankId, since, params]);
  const history = useThrottledLoad(load, state, [tankId, rangeS]);

  return (
    <section>
      <div className="section-head">
        <h2>History</h2>
        <div className="range" role="group" aria-label="Time range">
          {RANGES.map((r) => (
            <button key={r.s} className={r.s === rangeS ? "active" : ""} onClick={() => onRange(r.s)}>
              {r.label}
            </button>
          ))}
        </div>
      </div>
      <p className="hint">
        Shaded band = safe range. Grey dashed lines = min / max. Blue dashed line after "now" = forecast.
        Gaps = missing data or sensor faults.
      </p>
      <div className="charts">
        {params.map((p) => (
          <ParamChart key={p.name} param={p} rows={history?.[p.name]} since={since}
                      now={state?.now} fc={forecast?.parameters?.[p.name]} c={colors} />
        ))}
      </div>
    </section>
  );
}
