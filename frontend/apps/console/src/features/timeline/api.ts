import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  spacecraftRef,
  request,
  requestPage,
  type ApiResult,
  type Decoded,
  type Page,
} from "@/api/index.ts";

/** Contracts: docs/apogee/api/ops.md, `GET …/events` and `…/events/density` (owner api, DECISIONS #26). */

export const eventKinds = [
  "limit",
  "flight_event",
  "contact",
  "command",
  "config",
  "operator",
  "data",
] as const;
export type EventKind = (typeof eventKinds)[number];
/** Shown by default; `data` (pipeline housekeeping, e.g. source watermarks) is opt-in (ux). */
export const DEFAULT_KINDS: readonly EventKind[] = eventKinds.filter((k) => k !== "data");
export const eventSeverities = ["critical", "caution", "nominal", "info"] as const;
export type EventSeverity = (typeof eventSeverities)[number];

/** Cadence.Reads.EventSentences subject kinds; only some have a page to link to (subjectLink). */
export const subjectKinds = [
  "activation",
  "catalog_revision",
  "config_revision",
  "contact",
  "dashboard",
  "data_source",
  // L15 (api dc68a1cb4): an off-plan booking; id is the pass row (reservation) id.
  "pass",
] as const;

/**
 * The producing record's own fields, for the event detail panel (U69 A8a, api a87bee73d). Each is
 * null when that record has none. Optional so an older server's rows still decode.
 */
const record = d.object({
  // free-text: the producing store's own status word, shown as said.
  status: d.nullable(d.string),
  source_record: d.nullable(
    d.object({
      // free-text: the producing store's record kind, shown as said (Technical details).
      kind: d.string,
      id: d.string,
    }),
  ),
  source_endpoint_ref: d.nullable(d.string),
  scheduled_contact_id: d.nullable(d.string),
  realized_contact_id: d.nullable(d.string),
  path_id: d.nullable(d.string),
  capability_instance_id: d.nullable(d.string),
  activation_id: d.nullable(d.string),
  // free-text: an opaque correlation key.
  correlation_key: d.nullable(d.string),
});

const event = d.object({
  id: d.token,
  at: d.timestamp,
  kind: d.oneOf(eventKinds),
  // kindLabel words the common entry kinds and sentence-cases the rest.
  // free-text: the event log's own entry kind, an open set that grows with each producer.
  raw_kind: d.nullable(d.string),
  severity: d.oneOf(eventSeverities),
  text: d.string,
  detail: d.nullable(d.string),
  /**
   * api (11-16): name and scid are null for a craft outside the name context (an unknown or
   * foreign id); the row shows no craft name then, never the id. The id drives the filter.
   */
  spacecraft: d.nullable(spacecraftRef),
  refs: d.object({
    alarm_id: d.nullable(d.token),
    point_id: d.nullable(d.token),
    command_request_id: d.nullable(d.token),
    contact_id: d.nullable(d.token),
    /** What the sentence is about, as a link target (ux timeline review #1); null when none. */
    subject: d.optional(
      d.nullable(
        d.object({ kind: d.known(subjectKinds), id: d.token, name: d.nullable(d.string) }),
      ),
    ),
  }),
  record: d.optional(d.nullable(record)),
});

export const eventsReader = d.object({
  from: d.timestamp,
  to: d.timestamp,
  events: d.array(event, 500),
});
export type Events = Decoded<typeof eventsReader>;
export type MissionEvent = Events["events"][number];

const bucket = d.object({
  t: d.timestamp,
  critical: d.integer,
  caution: d.integer,
  nominal: d.integer,
  info: d.integer,
});
export const densityReader = d.object({
  bucket_s: d.integer,
  buckets: d.array(bucket, 2_000),
  truncated: d.boolean,
});
export type Density = Decoded<typeof densityReader>;

export type EventQuery = Readonly<{
  from: Date;
  to: Date;
  spacecraftId?: string;
  plane?: number;
  kinds?: readonly EventKind[];
  /** U69 A9b: exact raw kinds (`?raw_kind=`), ANDed with `kinds`; at most 20. */
  rawKinds?: readonly string[];
  /** U69 A9a: a severity floor (`?severity_at_least=`); absent = every severity. */
  severityAtLeast?: SeverityFloor;
}>;

/** U69 A9a: `caution` keeps caution and critical; `critical` keeps critical. */
export const severityFloors = ["caution", "critical"] as const;
export type SeverityFloor = (typeof severityFloors)[number];

function params(query: EventQuery, extra: Record<string, string>) {
  const p = new URLSearchParams({
    from: query.from.toISOString(),
    to: query.to.toISOString(),
    ...extra,
  });
  if (query.spacecraftId) p.set("spacecraft_id", query.spacecraftId);
  if (query.plane !== undefined) p.set("plane", String(query.plane));
  if (query.kinds?.length) p.set("kind", query.kinds.join(","));
  if (query.rawKinds?.length) p.set("raw_kind", query.rawKinds.join(","));
  if (query.severityAtLeast) p.set("severity_at_least", query.severityAtLeast);
  return p.toString();
}

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/events`;

export function fetchEvents(
  missionId: MissionId,
  query: EventQuery,
  signal?: AbortSignal,
): Promise<ApiResult<Events>> {
  return request(
    `${base(missionId)}?${params(query, { limit: "500" })}`,
    eventsReader,
    signal ? { signal } : {},
  );
}

/** A page's envelope besides its events: the window it read. */
export type EventsMeta = Omit<Events, "events">;

/**
 * One page of the window's events, newest first (U69 A9d): the first with no `cursor`, an older one
 * with the previous page's `meta.next_cursor`, same filters. 500 a page.
 */
export async function fetchEventPage(
  missionId: MissionId,
  query: EventQuery,
  cursor: string | null,
  signal?: AbortSignal,
): Promise<ApiResult<Page<MissionEvent, EventsMeta>>> {
  const r = await requestPage(
    `${base(missionId)}?${params(query, cursor ? { limit: "500", cursor } : { limit: "500" })}`,
    eventsReader,
    signal ? { signal } : {},
  );
  if (!r.ok) return r;
  const { events, ...meta } = r.value.value;
  return { ok: true, value: { items: events, next: r.value.nextCursor, meta } };
}

export function fetchDensity(
  missionId: MissionId,
  query: EventQuery,
  bucketS: number,
  signal?: AbortSignal,
): Promise<ApiResult<Density>> {
  return request(
    `${base(missionId)}/density?${params(query, { bucket_s: String(bucketS) })}`,
    densityReader,
    signal ? { signal } : {},
  );
}

const oneEventReader = d.object({ event });

/** A Timeline permalink: one event by id (U69 A8b). Ids contain ':', so the id is URL-encoded. */
export function fetchEvent(
  missionId: MissionId,
  eventId: string,
  signal?: AbortSignal,
): Promise<ApiResult<MissionEvent>> {
  return request(
    `${base(missionId)}/${encodeURIComponent(eventId)}`,
    oneEventReader,
    signal ? { signal } : {},
  ).then((r) => (r.ok ? { ok: true, value: r.value.event } : r));
}

/** GET …/events/raw-kinds (U69 A9b picker, api 4a2f470d8): each raw kind in the window, most first. */
export const rawKindsReader = d.object({
  raw_kinds: d.array(
    d.object({
      // free-text: the event log's own entry kind, an open set (as `raw_kind` on an event).
      raw_kind: d.string,
      kind: d.known(eventKinds),
      count: d.integer,
    }),
    500,
  ),
});
export type RawKinds = Decoded<typeof rawKindsReader>["raw_kinds"];

export function fetchRawKinds(
  missionId: MissionId,
  window: Readonly<{ from: Date; to: Date }>,
  signal?: AbortSignal,
): Promise<ApiResult<RawKinds>> {
  const p = new URLSearchParams({ from: window.from.toISOString(), to: window.to.toISOString() });
  return request(
    `${base(missionId)}/raw-kinds?${p.toString()}`,
    rawKindsReader,
    signal ? { signal } : {},
  ).then((r) => (r.ok ? { ok: true, value: r.value.raw_kinds } : r));
}
