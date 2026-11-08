import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";

/** Contract: docs/apogee/api/ops.md, `GET /api/console/v1/missions/:mission_id/alarms` (M9). */

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

const alarm = d.object({
  id: d.token,
  spacecraft_id: d.nullable(d.token),
  point: d.object({ id: d.token, name: d.string, subsystem: d.nullable(d.string) }),
  severity: d.oneOf(alarmSeverities),
  active: d.boolean,
  condition: d.nullable(d.token),
  value: d.nullable(engineeringValue),
  limit_set_name: d.nullable(d.string),
  thresholds: d.nullable(thresholdsReader),
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
  alarms: d.array(alarm, 20_000),
});

export type Alarms = Decoded<typeof alarmsReader>;
export type Alarm = Alarms["alarms"][number];

export type AlarmQuery = Readonly<{
  state?: "active" | "nominal" | "all";
  severity?: "critical" | "caution";
  spacecraftId?: string;
  q?: string;
}>;

export function alarmQueryString(query: AlarmQuery): string {
  const params = new URLSearchParams();
  if (query.state) params.set("state", query.state);
  if (query.severity) params.set("severity", query.severity);
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  if (query.q) params.set("q", query.q);
  const text = params.toString();
  return text ? `?${text}` : "";
}

export function fetchAlarms(
  missionId: string,
  query: AlarmQuery,
  signal?: AbortSignal,
): Promise<ApiResult<Alarms>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/alarms${alarmQueryString(query)}`,
    alarmsReader,
    signal ? { signal } : {},
  );
}

const CONDITION_WORDS: Readonly<Record<string, string>> = {
  red_low: "below red limit",
  red_high: "above red limit",
  yellow_low: "below yellow limit",
  yellow_high: "above yellow limit",
};

/** "below red limit" etc. from the raw condition; null when the condition is unknown. */
export function conditionWords(condition: string | null): string | null {
  return condition === null ? null : (CONDITION_WORDS[condition] ?? null);
}

const CROSSED_BAND = {
  red_low: "red_low",
  red_high: "red_high",
  yellow_low: "yellow_low",
  yellow_high: "yellow_high",
} as const satisfies Record<string, keyof Thresholds>;

/** The band that was crossed, for the "Red limit" readout. */
export function crossedLimit(alarm: Alarm): number | null {
  const band =
    alarm.condition !== null && Object.hasOwn(CROSSED_BAND, alarm.condition)
      ? CROSSED_BAND[alarm.condition as keyof typeof CROSSED_BAND]
      : null;
  return band === null || alarm.thresholds === null ? null : alarm.thresholds[band];
}
