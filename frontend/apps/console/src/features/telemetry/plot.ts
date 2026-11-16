import {
  limitSegments,
  toSeries,
  type ComparisonSeries,
  type LimitSegment,
  type SeriesPoint,
  type TimeWindow,
} from "@/features/investigate/index.ts";
import { STYLES } from "./selection.ts";

type LimitIntervals = Parameters<typeof limitSegments>[0];
type Style = Omit<ComparisonSeries, "points">;
const FALLBACK: Style = { tone: "text-4", dash: "solid" };
const styleAt = (i: number): Style => STYLES[i] ?? FALLBACK;
import type { SeriesData } from "./useSeries.ts";

/** Chart inputs from the series data: first series primary (band), others gray/dashed lines. */
export type PlotView = Readonly<{
  window: TimeWindow;
  primary: readonly SeriesPoint[];
  comparison: readonly ComparisonSeries[];
  limits: readonly LimitSegment[];
  stepMs: number;
  legend: readonly { label: string; style: Style }[];
}>;

export const seriesLabel = (d: SeriesData) =>
  `${d.sc.name} › ${d.key.pointId}${d.history.unit ? ` (${d.history.unit})` : ""}`;

export function plotView(
  data: readonly SeriesData[],
  intervals: LimitIntervals | null,
): PlotView | null {
  const first = data[0];
  if (!first) return null;
  const window = { from: Date.parse(first.history.from), to: Date.parse(first.history.to) };
  return {
    window,
    primary: toSeries(first.history),
    comparison: data.slice(1).map((d, i) => ({ points: toSeries(d.history), ...styleAt(i + 1) })),
    // Limits only when exactly one point is plotted (OpsLists §Telemetry).
    limits: data.length === 1 ? limitSegments(intervals, window, null) : [],
    stepMs: first.history.bucket_width_ms,
    legend: data.map((d, i) => ({ label: seriesLabel(d), style: styleAt(i) })),
  };
}

/** Latest bucket per series for T3 (mean of the newest bucket; honest about being a bucket). */
export function latestRows(data: readonly SeriesData[]) {
  return data.map((d) => {
    const last = d.history.buckets.at(-1) ?? null;
    return {
      key: `${d.sc.id}|${d.key.pointId}`,
      label: seriesLabel(d),
      sc: d.sc,
      pointId: d.key.pointId,
      unit: d.history.unit,
      last,
    };
  });
}

/**
 * D11 (ux, §11c(D)): a capped history read (api: the fallback store keeps the EARLIEST 20,000 raw
 * samples) covers the read's start to its last bucket's end. With several series cut, the plot is
 * complete only up to the earliest such end. Null when no series was cut.
 */
export function cappedLine(rows: readonly SeriesData[]): string | null {
  const cut = rows.filter((r) => r.history.truncated);
  if (cut.length === 0) return null;
  const from = Math.min(...cut.map((r) => Date.parse(r.history.from)));
  const end = Math.min(
    ...cut.map((r) => {
      const last = r.history.buckets.at(-1);
      return last ? Date.parse(last.t_end) : Date.parse(r.history.from);
    }),
  );
  const iso = (t: number) => new Date(t).toISOString();
  const days = iso(from).slice(0, 10) !== iso(end).slice(0, 10);
  const at = (t: number) => `${days ? `${iso(t).slice(5, 10)} ` : ""}${iso(t).slice(11, 16)}Z`;
  const endTime = `${iso(end).slice(11, 16)}Z`;
  return `This range has more samples than one read returns (20,000). The plot shows ${at(from)} to ${at(end)}; samples after ${days ? at(end) : endTime} weren't read. Pick a shorter or later range to see the rest.`;
}
