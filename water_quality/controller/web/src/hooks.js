import { useEffect, useRef, useState } from "react";
import { api } from "./api.js";

const THEME_VARS = ["--series", "--band-fill", "--limit", "--grid", "--border", "--text-3"];

/** Resolved colour tokens from styles.css; re-read when light/dark changes. */
export function useThemeColors() {
  const read = () => {
    const css = getComputedStyle(document.documentElement);
    return Object.fromEntries(THEME_VARS.map((v) => [v.slice(2), css.getPropertyValue(v).trim()]));
  };
  const [colors, setColors] = useState(read);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => setColors(read());
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);
  return colors;
}

/** Live tank state pushed by the server via Server-Sent Events. */
export function useLiveState(tankId) {
  const [state, setState] = useState(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    if (!tankId) return undefined;
    setState(null);
    const es = new EventSource(api.streamUrl(tankId));
    es.onopen = () => setConnected(true);
    es.onerror = () => setConnected(false);  // EventSource reconnects by itself
    es.onmessage = (ev) => setState(JSON.parse(ev.data));
    return () => es.close();
  }, [tankId]);

  return { state, connected };
}

/**
 * Re-run `load` whenever `trigger` changes, but at most once every `minMs`.
 * Keeps a fast CSV replay (hundreds of updates/s) from flooding the browser.
 */
export function useThrottledLoad(load, trigger, deps, minMs = 3000) {
  const [data, setData] = useState(null);
  const last = useRef(0);
  const timer = useRef(null);
  const loadRef = useRef(load);
  loadRef.current = load;

  // reset when the inputs that define the query change (e.g. tank, range)
  useEffect(() => {
    last.current = 0;
    setData(null);
  }, deps); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (trigger == null || timer.current) return;
    const wait = Math.max(0, minMs - (Date.now() - last.current));
    timer.current = setTimeout(async () => {
      timer.current = null;
      last.current = Date.now();
      try { setData(await loadRef.current()); } catch (e) { console.error(e); }
    }, wait);
  }, [trigger, ...deps]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => () => { clearTimeout(timer.current); timer.current = null; }, []);
  return data;
}
