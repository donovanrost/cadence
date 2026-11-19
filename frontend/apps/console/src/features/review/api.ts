import type { MissionId } from "@/api/index.ts";
import { decoders, request, spacecraftRef, type ApiResult, type Decoded, type Reader } from "@/api";

/** Contract: docs/apogee/api/contacts.md, "Pass review (S9, K3)". */
const {
  array,
  boolean,
  integer,
  known,
  nullable,
  number,
  object,
  oneOf,
  optional,
  string,
  timestamp,
  token,
} = decoders;

const count: Reader<number> = (v, path = "") =>
  v === undefined || v === null ? 0 : integer(v, path);
export const owners = ["provider", "us", "weather", "unknown"] as const;
export type Owner = (typeof owners)[number];
/** Sparse `{owner: count}` maps read as all four owners. */
const byOwner = (v: unknown, path = ""): Readonly<Record<Owner, number>> => {
  const o = object({ provider: count, us: count, weather: count, unknown: count });
  return o(v ?? {}, path);
};
const provider = object({ id: token, name: string });
const station = object({
  // null for a pass result with no ground station ref (api drift sweep 11-13).
  ref: nullable(string),
  id: nullable(token),
  // free-text: the station's short code, an identifier.
  code: nullable(string),
  name: nullable(string),
});
export type ReviewStation = Decoded<typeof station>;

const summary = object({
  from: timestamp,
  to: timestamp,
  planned: count,
  realized: count,
  partial: count,
  missed: count,
  failed: count,
  canceled: count,
  pending_count: count,
  realized_ratio: nullable(number),
  threshold: number,
  target: number,
  provisional: boolean,
  missed_by_owner: byOwner,
  partial_by_owner: byOwner,
  by_station: array(
    object({
      station,
      provider: nullable(provider),
      planned: count,
      realized: count,
      partial: count,
      missed: count,
      failed: count,
      canceled: count,
      planned_seconds: count,
      flown_seconds: count,
    }),
    1000,
  ),
  by_cause: array(
    object({
      cause: nullable(string),
      cause_source: nullable(known(["cadence", "provider"] as const)),
      owner: oneOf(owners),
      missed: count,
      partial: count,
    }),
    200,
  ),
  plans: array(object({ id: token, version: integer }), 100),
  /** Span totals; a total is null when no pass reports it (unknown, not 0). */
  volume: optional(
    object({
      provider_bytes: nullable(integer),
      received_bytes: nullable(integer),
      provider_reported_passes: count,
      received_known_passes: count,
    }),
  ),
  freshness: array(
    object({
      // Both null when the account has no provider or no event cursor (api drift sweep 11-13).
      provider: nullable(provider),
      last_report_at: nullable(timestamp),
      pending_reports: count,
      oldest_pending_los: nullable(timestamp),
      cursor_healthy: nullable(boolean),
    }),
    100,
  ),
});
export type ReviewSummary = Decoded<typeof summary>;
export type StationLine = ReviewSummary["by_station"][number];
export type CauseLine = ReviewSummary["by_cause"][number];

export const outcomes = [
  "realized",
  "partial",
  "missed",
  "failed",
  "canceled",
  "pending_report",
] as const;
export type Outcome = (typeof outcomes)[number];
const row = object({
  id: token,
  spacecraft: spacecraftRef,
  station,
  provider: nullable(provider),
  antenna_ref: nullable(string),
  plan: nullable(object({ id: token, version: integer })),
  planned_aos: timestamp,
  planned_los: timestamp,
  actual_aos: nullable(timestamp),
  actual_los: nullable(timestamp),
  planned_seconds: count,
  flown_seconds: nullable(integer),
  provider_bytes: nullable(integer),
  received_bytes: nullable(integer),
  outcome: oneOf(outcomes),
  cause: nullable(string),
  owner: nullable(oneOf(owners)),
  disputable: boolean,
  provisional: boolean,
});
export type ReviewRow = Decoded<typeof row>;
const rowsReader = object({
  rows: array(row, 500),
  total: integer,
  disputable: count,
  next_cursor: optional(nullable(string)),
});
export type ReviewRows = Decoded<typeof rowsReader>;

const daily = object({
  days: array(
    object({
      day: string,
      planned: count,
      realized: count,
      canceled: optional(count),
      pending: optional(count),
      // The doc says `ratio`; the read sends `realized_ratio`.
      ratio: optional(nullable(number)),
      realized_ratio: optional(nullable(number)),
      top_cause: nullable(string),
      top_station: nullable(string),
    }),
    400,
  ),
  target: number,
});
export type ReviewDaily = Decoded<typeof daily>;
export type ReviewDay = ReviewDaily["days"][number];

export type Span = "day" | "week" | "month";
export type ReviewKey = Readonly<{ missionId: MissionId; day: string; span: Span }>;
const path = (k: ReviewKey, tail: string, extra: Record<string, string> = {}) =>
  `/missions/${encodeURIComponent(k.missionId)}/pass-review${tail}?${new URLSearchParams({
    day: k.day,
    span: k.span,
    ...extra,
  }).toString()}`;

export function fetchSummary(k: ReviewKey, signal: AbortSignal): Promise<ApiResult<ReviewSummary>> {
  return request(path(k, ""), summary, { signal });
}

/** R4: missed, failed and partial passes, 50 a page; pass `cursor` for the next page. */
export function fetchLost(
  k: ReviewKey & Readonly<{ cursor?: string }>,
  signal: AbortSignal,
): Promise<ApiResult<ReviewRows>> {
  // keyed-by-text: a query-parameter bag, not a word map
  const extra: Record<string, string> = { outcome: "missed,failed,partial", limit: "50" };
  if (k.cursor) extra.cursor = k.cursor;
  return request(path(k, "/rows", extra), rowsReader, { signal });
}

/** R3 always reads the 30 days ending at the chosen day. */
export function fetchDaily(k: ReviewKey, signal: AbortSignal): Promise<ApiResult<ReviewDaily>> {
  return request(path({ ...k, span: "month" }, "/daily"), daily, { signal });
}
