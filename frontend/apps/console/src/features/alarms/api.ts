import type { PointId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import {
  spacecraftId as spacecraftIdReader,
  decoders as d,
  request,
  requestPage,
  type ApiResult,
  type Decoded,
  pointId as pointIdReader,
} from "@/api/index.ts";

/** Contract: docs/apogee/api/ops.md, `GET /api/v1/missions/:mission_id/alarms` (M9). */

export const alarmSeverities = ["critical", "caution", "nominal"] as const;
export type AlarmSeverity = (typeof alarmSeverities)[number];

/** Engineering value exactly as sent: number, string or boolean. */
export const engineeringValue: d.Reader<number | string | boolean> = (value, path = "") => {
  if (typeof value === "string" || typeof value === "boolean") return value;
  return d.number(value, path);
};

const band = d.nullable(d.number);

export const thresholdsReader = d.object({
  red_low: band,
  yellow_low: band,
  yellow_high: band,
  red_high: band,
});
export type Thresholds = Decoded<typeof thresholdsReader>;

/** The limit evaluator's states (Cadence.Limits.Evaluator); an alarm row's `condition`. */
export const limitConditions = [
  "green",
  "yellow_low",
  "yellow_high",
  "red_low",
  "red_high",
  "blue",
] as const;
/** An episode's `source_state`: a ground limit's condition or a catalog monitoring level. */
export const sourceStates = [
  ...limitConditions,
  "normal",
  "watch",
  "warning",
  "distress",
  "critical",
  "severe",
] as const;

const alarm = d.object({
  id: d.token,
  spacecraft_id: d.nullable(spacecraftIdReader),
  point: d.object({
    id: pointIdReader,
    name: d.string,
    subsystem: d.nullable(d.string),
    unit: d.nullable(d.string),
    description: d.nullable(d.string),
  }),
  severity: d.oneOf(alarmSeverities),
  active: d.boolean,
  // #1117 (#451 T3c): a row is a live alarm state, written on a transition. It carries no value,
  // condition, limit set or thresholds (ground-limit ideas, null since); the episode carries the
  // value (last_value with last_evaluated_at). first_crossed_at is the state's received_at.
  first_crossed_at: d.nullable(d.timestamp),
  generation_time: d.nullable(d.timestamp),
  received_at: d.nullable(d.timestamp),
});

export const alarmsReader = d.object({
  observed_at: d.timestamp,
  summary: d.object({
    active: d.integer,
    critical: d.integer,
    caution: d.integer,
    latest_transition_at: d.nullable(d.timestamp),
  }),
  /** The rows matching the query, whatever the page (a count needs no more than this). */
  total: d.integer,
  alarms: d.array(alarm, 200),
});

export type Alarms = Decoded<typeof alarmsReader>;
export type Alarm = Alarms["alarms"][number];

/**
 * One page, worst first. `limit` is 1 to 200 (the server's default is 100). The sister read is
 * `pointId` + `plane` + `excludeSpacecraftId`: the server filters, so a plane's sisters or their
 * count (`total`) never need the mission's alarms in the client.
 */
export type AlarmQuery = Readonly<{
  state?: "active" | "nominal" | "all";
  severity?: "critical" | "caution";
  spacecraftId?: string;
  q?: string;
  pointId?: PointId;
  plane?: number;
  excludeSpacecraftId?: string;
  limit?: number;
  /** A previous page's next cursor. */
  cursor?: string;
}>;

export function alarmQueryString(query: AlarmQuery): string {
  const params = new URLSearchParams();
  if (query.state) params.set("state", query.state);
  if (query.severity) params.set("severity", query.severity);
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  if (query.q) params.set("q", query.q);
  if (query.pointId) params.set("point_id", query.pointId);
  if (query.plane !== undefined) params.set("plane", String(query.plane));
  if (query.excludeSpacecraftId) params.set("exclude_spacecraft_id", query.excludeSpacecraftId);
  if (query.limit !== undefined) params.set("limit", String(query.limit));
  if (query.cursor) params.set("cursor", query.cursor);
  const text = params.toString();
  return text ? `?${text}` : "";
}

export function fetchAlarms(
  missionId: MissionId,
  query: AlarmQuery,
  signal?: AbortSignal,
): Promise<ApiResult<Alarms>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/alarms${alarmQueryString(query)}`,
    alarmsReader,
    signal ? { signal } : {},
  );
}

/** One page of alarms and its next cursor (null on the last page). */
export function fetchAlarmPage(
  missionId: MissionId,
  query: AlarmQuery,
  cursor: string | null,
  signal?: AbortSignal,
) {
  return requestPage(
    `/missions/${encodeURIComponent(missionId)}/alarms${alarmQueryString(cursor ? { ...query, cursor } : query)}`,
    alarmsReader,
    signal ? { signal } : {},
  );
}

const conditions = ["red_low", "red_high", "yellow_low", "yellow_high"] as const;
const CONDITION_WORDS: Readonly<Record<(typeof conditions)[number], string>> = {
  red_low: "below red limit",
  red_high: "above red limit",
  yellow_low: "below yellow limit",
  yellow_high: "above yellow limit",
};

/** "below red limit" etc. from the raw condition; null when the condition is unknown. */
export function conditionWords(condition: string | null): string | null {
  const known = conditions.find((c) => c === condition);
  return known ? CONDITION_WORDS[known] : null;
}

const CROSSED_BAND = {
  red_low: "red_low",
  red_high: "red_high",
  yellow_low: "yellow_low",
  yellow_high: "yellow_high",
} as const satisfies Record<string, keyof Thresholds>;

const isCrossedBand = (c: string): c is keyof typeof CROSSED_BAND => Object.hasOwn(CROSSED_BAND, c);

/** The threshold for a raw condition (`red_low` → thresholds.red_low); null when unknown. */
export function bandFor(thresholds: Thresholds | null, condition: string | null): number | null {
  const band = condition !== null && isCrossedBand(condition) ? CROSSED_BAND[condition] : null;
  return band === null || thresholds === null ? null : thresholds[band];
}
