import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  pointId as pointIdReader,
  requestPageMeta,
  vocabularyText,
  type Decoded,
} from "@/api/index.ts";
import { engineeringValue, formatValue, withUnit } from "@/features/alarms/index.ts";

/**
 * Investigate › Points (#143): the current condition of every point of one spacecraft from both
 * stores, one row per (point, source). Contract: docs/apogee/api/ops.md,
 * `GET …/spacecraft/:spacecraft_id/point-conditions`.
 */
export const sources = ["ground_limit", "catalog_monitoring"] as const;
export const conditions = ["critical", "caution", "nominal"] as const;
/** The ground-limit evaluator's states. */
export const limitStates = [
  "green",
  "blue",
  "yellow_low",
  "yellow_high",
  "red_low",
  "red_high",
] as const;
export const freshnesses = ["fresh", "stale", "unknown"] as const;

const rowReader = d.object({
  point_id: pointIdReader,
  point_name: d.string,
  unit: d.nullable(d.string),
  source: d.knownText(sources),
  /** The monitoring rule, for a live row; null for a ground limit. */
  policy_id: d.nullable(d.string),
  condition: d.knownText(conditions),
  /** The ground-limit vocabulary (`yellow_high`, …); null for a live row. */
  raw_limit_state: d.nullable(d.knownText(limitStates)),
  /** false: an active ground limit and a sample, but no job has evaluated it yet. */
  evaluated: d.boolean,
  /** When the ground-limit job ran; null for a live row (live by definition). */
  evaluated_at: d.nullable(d.timestamp),
  entered_at: d.nullable(d.timestamp),
  /** The newest 200 evaluations were searched and none changed state: it entered before that. */
  entered_at_is_lower_bound: d.boolean,
  value: d.nullable(engineeringValue),
  last_sample_at: d.nullable(d.timestamp),
  freshness: d.known(freshnesses),
});
export type PointCondition = Decoded<typeof rowReader>;

const metaReader = d.object({
  observed_at: d.timestamp,
  stale_after_s: d.integer,
  /** degraded: the history store did not answer, so a point this node has not heard is unknown. */
  telemetry: d.known(["ok", "degraded"] as const),
  counts: d.object({
    total: d.integer,
    critical: d.integer,
    caution: d.integer,
    stale: d.integer,
    unknown: d.integer,
    not_evaluated: d.integer,
  }),
});
export type PointsMeta = Decoded<typeof metaReader>;

export const pointsReader = d.array(rowReader, 200);

export type PointsQuery = Readonly<{
  /** `attention`: the critical, caution, stale and unknown points only. */
  state: "all" | "attention";
}>;

/** One page, worst point first (the server's order); `cursor` is the previous page's next. */
export function fetchPointConditionPage(
  missionId: MissionId,
  spacecraftId: string,
  query: PointsQuery,
  cursor: string | null,
  signal?: AbortSignal,
) {
  const params = new URLSearchParams({ state: query.state, limit: "100" });
  if (cursor) params.set("cursor", cursor);
  return requestPageMeta(
    `/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/point-conditions?${params.toString()}`,
    pointsReader,
    metaReader,
    signal ? { signal } : {},
  );
}

const SOURCE_WORDS: Readonly<Record<(typeof sources)[number], string>> = {
  ground_limit: "Ground limits",
  catalog_monitoring: "Monitoring",
};

/** "Ground limits" / "Monitoring"; the server's text for a source this console doesn't know. */
export const sourceWords = (row: PointCondition) => vocabularyText(row.source, SOURCE_WORDS);

const CONDITION_WORDS: Readonly<Record<(typeof conditions)[number], string>> = {
  critical: "Critical",
  caution: "Caution",
  nominal: "Nominal",
};

/** The condition's word; a condition this console doesn't know shows the server's text. */
export const conditionText = (row: PointCondition) =>
  vocabularyText(row.condition, CONDITION_WORDS);

/** The state a row's mark shows: its condition, but a stale or unknown point never reads healthy. */
export function markState(row: PointCondition): "crit" | "caution" | "stale" | "nominal" | "off" {
  if (row.condition === "critical") return "crit";
  if (row.condition === "caution") return "caution";
  if (row.freshness === "stale") return "stale";
  if (row.freshness === "unknown") return "off";
  if (!row.evaluated) return "off";
  return "nominal";
}

/** "STALE", "NO SAMPLE KNOWN" or null: said in words beside the condition, not by colour alone. */
export function freshnessWord(row: PointCondition): string | null {
  if (row.freshness === "stale") return row.last_sample_at === null ? "NEVER SAMPLED" : "STALE";
  if (row.freshness === "unknown") return "SAMPLE TIME UNKNOWN";
  return null;
}

const LIMIT_WORDS: Readonly<Record<(typeof limitStates)[number], string>> = {
  red_low: "below red limit",
  red_high: "above red limit",
  yellow_low: "below yellow limit",
  yellow_high: "above yellow limit",
  green: "within limits",
  blue: "informational",
};

/** "Not evaluated yet", the ground limit in words ("above yellow limit"), or "Monitoring rule". */
export function detailWords(row: PointCondition): string {
  if (!row.evaluated) return "Not evaluated yet";
  // The rule's id is not shown (ids belong in technical details); the source column says which store.
  if (row.source === "catalog_monitoring") return "Monitoring rule";
  return row.raw_limit_state === null ? "" : vocabularyText(row.raw_limit_state, LIMIT_WORDS);
}

export const valueText = (row: PointCondition): string =>
  row.value === null ? "—" : (withUnit(formatValue(row.value), row.unit) ?? "—");
