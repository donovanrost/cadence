import type { Series } from "./snapshot-series.ts";
import { formatTime } from "./widget-data.ts";

/** At most this many series are read out; the rest are counted. */
const READ = 4;

type Window = { live: boolean; from: string | null; to: string | null; windowSeconds: number };

function windowText(w: Window): string {
  if (w.live || !w.from || !w.to) {
    const minutes = Math.round(w.windowSeconds / 60);
    return minutes >= 120
      ? `the last ${Math.round(minutes / 60)} hours`
      : `the last ${minutes} minutes`;
  }
  return `${formatTime(Date.parse(w.from))} to ${formatTime(Date.parse(w.to))}`;
}

function latest(s: Series): string | null {
  for (let i = s.points.length - 1; i >= 0; i -= 1) {
    const value = s.points[i]?.[1];
    if (value !== null && value !== undefined && Number.isFinite(value))
      return `${s.label} ${Number(value.toPrecision(4))}${s.unit ? ` ${s.unit}` : ""}`;
  }
  return null;
}

/**
 * The time series' accessible name (ux a11y checklist B5: a chart is `role="img"` with a sentence,
 * not "chart"): what it plots, over when, and each series' latest value.
 */
export function chartSentence(title: string, series: readonly Series[], w: Window): string {
  const name = title.trim() || "Time series";
  const when = windowText(w);
  if (series.length === 0) return `${name}, ${when}: no samples in this range.`;
  const values = series.slice(0, READ).map((s) => latest(s) ?? `${s.label} no value`);
  const more = series.length > READ ? `, and ${series.length - READ} more series` : "";
  return `${name}, ${when}. Latest: ${values.join(", ")}${more}.`;
}
