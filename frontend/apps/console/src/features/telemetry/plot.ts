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

export const seriesLabel = (d: SeriesData) => `${d.sc.name} › ${d.key.pointId}`;

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
      last,
    };
  });
}
