import type { OpState } from "@/ui";
import { isHistorical, latestMark, type TelemetryPoint } from "@/features/telemetry/index.ts";

/**
 * Investigate › Telemetry (Investigate.md §Telemetry): every value on this spacecraft now (M23),
 * up to 3 plotted (M10/M11, M8 live tail). URL: ?points=a,b,c&range=6h.
 */
export const MAX_PLOTTED = 3;

export type PointFilter = "out" | "stale" | "all";

/** T1 mark: crit / caution / stale / nominal, or off for a point without limits. */
export function pointMark(p: TelemetryPoint): OpState {
  if (!p.latest) return "stale";
  // limit_state is a closed vocabulary (telemetry api), so every latest has a mark.
  return latestMark(p.latest);
}

const isOut = (p: TelemetryPoint) =>
  p.latest?.limit_state === "critical" || p.latest?.limit_state === "caution";
const isStale = (p: TelemetryPoint) =>
  !p.latest || p.latest.limit_state === "no_data" || isHistorical(p.latest);

export function filterCounts(points: readonly TelemetryPoint[]) {
  return { out: points.filter(isOut).length, stale: points.filter(isStale).length };
}

/** Filtered, out-of-limits first (critical before caution), then by subsystem and label. */
export function visiblePoints(
  points: readonly TelemetryPoint[],
  filter: PointFilter,
  q: string,
): TelemetryPoint[] {
  const term = q.trim().toLowerCase();
  const rank = (p: TelemetryPoint) =>
    p.latest?.limit_state === "critical" ? 0 : p.latest?.limit_state === "caution" ? 1 : 2;
  return points
    .filter((p) => (filter === "out" ? isOut(p) : filter === "stale" ? isStale(p) : true))
    .filter(
      (p) => !term || p.name.toLowerCase().includes(term) || p.id.toLowerCase().includes(term),
    )
    .sort(
      (a, b) =>
        rank(a) - rank(b) ||
        (a.subsystem ?? "").localeCompare(b.subsystem ?? "") ||
        a.name.localeCompare(b.name),
    );
}

/** ?points=a,b,c → at most 3 ids. */
export const pointsFrom = (value: unknown): string[] =>
  typeof value === "string" && value ? value.split(",").filter(Boolean).slice(0, MAX_PLOTTED) : [];

/** CSV of the focused point's buckets, newest first (T3 Export CSV). */
export function toCsv(
  pointId: string,
  rows: readonly Readonly<{ t: number; min: number; mean: number; max: number }>[],
): string {
  const lines = [...rows]
    .sort((a, b) => b.t - a.t)
    .map((r) => `${new Date(r.t).toISOString()},${pointId},${r.min},${r.mean},${r.max}`);
  return ["time,point,min,mean,max", ...lines].join("\n");
}
