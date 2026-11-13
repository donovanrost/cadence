import {
  scid as scidReader,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
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
  spacecraft: d.nullable(d.object({ id: d.token, name: d.string, scid: scidReader })),
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
}>;

function params(query: EventQuery, extra: Record<string, string>) {
  const p = new URLSearchParams({
    from: query.from.toISOString(),
    to: query.to.toISOString(),
    ...extra,
  });
  if (query.spacecraftId) p.set("spacecraft_id", query.spacecraftId);
  if (query.plane !== undefined) p.set("plane", String(query.plane));
  if (query.kinds?.length) p.set("kind", query.kinds.join(","));
  return p.toString();
}

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/events`;

export function fetchEvents(
  missionId: string,
  query: EventQuery,
  signal?: AbortSignal,
): Promise<ApiResult<Events>> {
  return request(
    `${base(missionId)}?${params(query, { limit: "500" })}`,
    eventsReader,
    signal ? { signal } : {},
  );
}

export function fetchDensity(
  missionId: string,
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
