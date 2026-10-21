import { STATUS_TEXT } from "../format.js";

/** Status colour is never used alone: dot + text label. */
export default function StatusPill({ status, label }) {
  return <span className={`pill ${status}`}>{label ?? STATUS_TEXT[status] ?? status}</span>;
}
