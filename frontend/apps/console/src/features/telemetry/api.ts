import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import type { OpState } from "@/ui";
import { engineeringValue } from "@/features/alarms/index.ts";

/** M23 point search (docs/apogee/api/ops.md, 5939f15d): the mission's canonical point set. */

const limitStates = d.oneOf(["critical", "caution", "nominal", "no_data"] as const);
/**
 * A history-sourced latest (api, after a restart) has no live limit evaluation. If it comes as
 * null, it reads as `no_data`: unknown, never nominal.
 */
const limitState: d.Reader<Decoded<typeof limitStates>> = (value, path = "") =>
  value === null ? "no_data" : limitStates(value, path);

const point = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  unit: d.nullable(d.string),
  subsystem: d.nullable(d.string),
  // Typing rule (1), lead: a new point type mustn't fail the whole points read; it reads
  // "unrecognized", which isn't plotted (only numeric is) and lists as text.
  type: d.known(["numeric", "enum", "text"] as const),
  latest: d.optional(
    d.nullable(
      d.object({
        value: d.nullable(engineeringValue),
        received_at: d.nullable(d.timestamp),
        limit_state: limitState,
        /** b8181eb9: live | history (newest stored sample, maybe days old). */
        source: d.optional(d.known(["live", "history"] as const)),
      }),
    ),
  ),
});

export type PointLatest = NonNullable<Decoded<typeof point>["latest"]>;

const LIMIT_MARK: Readonly<Record<PointLatest["limit_state"], OpState>> = {
  critical: "crit",
  caution: "caution",
  nominal: "nominal",
  no_data: "stale",
};

/** A history value (api 551cb796) is old: stale, unless its limits are out right now. */
export const isHistorical = (l: PointLatest) => l.source === "history";

/** The status mark for a point's latest: null latest is stale (no recent value). */
export function latestMark(l: PointLatest | null | undefined): OpState {
  if (!l) return "stale";
  const mark = LIMIT_MARK[l.limit_state];
  return isHistorical(l) && mark !== "crit" && mark !== "caution" ? "stale" : mark;
}

export const pointsReader = d.object({ points: d.array(point, 200) });
export type TelemetryPoint = Decoded<typeof point>;

export function fetchPoints(
  missionId: string,
  query: Readonly<{ spacecraftId?: string; q: string; limit?: number }>,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof pointsReader>>> {
  const params = new URLSearchParams({ q: query.q, limit: String(query.limit ?? 50) });
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  return request(
    `/missions/${encodeURIComponent(missionId)}/telemetry/points?${params.toString()}`,
    pointsReader,
    signal ? { signal } : {},
  );
}
