import {
  decoders as d,
  request,
  spacecraftId as spacecraftIdReader,
  type ApiResult,
  type Decoded,
  type MissionId,
  type SpacecraftId,
} from "@/api/index.ts";
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
  /**
   * api 11-15 (ux Investigate.md T1): whether the point has an active limit definition; on the
   * point because limits exist without a sample. Absent on older reads (marks as today).
   */
  has_limits: d.optional(d.boolean),
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

/** A point's mark, and the words when it has no limits or hasn't been checked (ux T1). */
export type PointLimits = Readonly<{ mark: OpState; word: string | null; title: string | null }>;

/**
 * ux Investigate.md T1: no limits defined, or defined but no sample checked yet, read as a dashed
 * `off` with words, never the nominal mark (that would claim a check that didn't happen, U20).
 * Otherwise the latest's own mark. A read without has_limits marks as before.
 */
export function pointLimits(
  p: Readonly<Pick<TelemetryPoint, "has_limits" | "latest">>,
): PointLimits {
  if (p.has_limits === false)
    return { mark: "off", word: "No limits", title: "No limits are defined for this point." };
  if (p.has_limits === true && p.latest?.limit_state === "no_data")
    return {
      mark: "off",
      word: "Not checked yet",
      title: "Limits are defined, but no sample has been checked yet.",
    };
  return { mark: latestMark(p.latest), word: null, title: null };
}

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
  missionId: MissionId,
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

/**
 * POST /telemetry/latest (api, per-target values): each spacecraft's current value of a few
 * points, from the current-value cache. Values are JSON text (64-bit safe); stale per the fleet
 * rule; a spacecraft with no value yet has value_json null.
 */
export const latestValuesReader = d.object({
  values: d.array(
    d.object({
      spacecraft_id: spacecraftIdReader,
      point_id: d.token,
      value_json: d.nullable(d.string),
      received_at: d.nullable(d.timestamp),
      stale: d.boolean,
    }),
    5_000,
  ),
});
export type LatestValues = Decoded<typeof latestValuesReader>;

export function fetchLatestValues(
  missionId: MissionId,
  pointIds: readonly string[],
  spacecraftIds: readonly SpacecraftId[],
  signal?: AbortSignal,
): Promise<ApiResult<LatestValues>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/telemetry/latest`,
    latestValuesReader,
    {
      method: "POST",
      body: { point_ids: [...pointIds], spacecraft_ids: [...spacecraftIds] },
      ...(signal ? { signal } : {}),
    },
  );
}
