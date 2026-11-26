import type { MissionId } from "@/api/index.ts";
import {
  decoders,
  requestPage,
  scid as scidReader,
  spacecraftId as spacecraftIdReader,
  type ApiResult,
  type Page,
  type Reader,
  type Scid,
  type SpacecraftId,
} from "@/api/index.ts";

/**
 * The Setup spacecraft directory, a page at a time (#796).
 * Contract: docs/apogee/api/setup.md, `GET /api/v1/missions/:mission_id/spacecraft`.
 */
const { array, boolean, integer, nullable, object, optional, string, timestamp, token } = decoders;

export type ProfileRef = Readonly<{ id: string; name: string | null; version: number }>;

export type SpacecraftRow = Readonly<{
  id: SpacecraftId;
  name: string;
  scid: Scid | null;
  noradId: number | null;
  plane: number | null;
  slot: number | null;
  profile: ProfileRef | null;
  routingRuleCount: number;
  /** Has a SCID, a profile and at least one enabled routing rule (server-decided). */
  ready: boolean;
  /** null: never heard since creation ("Awaiting first AOS"). */
  lastReceivedAt: string | null;
}>;

/** api: `degraded` = the history store didn't answer, so last-received is live-only (may be incomplete). */
export type TelemetryFreshness = "ok" | "degraded";
export const telemetryFreshness = (value: unknown): TelemetryFreshness =>
  value === "degraded" ? "degraded" : "ok";
/**
 * S9 (#313, U20): the server's SCIDs for adding spacecraft. `inUse` is every SCID taken in the
 * mission (live, archived, and staged in its active change set), sorted; `next` is the lowest free
 * one in 1..1023, null when none is.
 */
export type ServerScids = Readonly<{ next: number | null; inUse: readonly number[] }>;

/** The server's whole-mission counts (the subtitle's numbers), whatever page or filter is shown. */
export type DirectorySummary = Readonly<{
  total: number;
  profiles: number;
  withoutProfile: number;
  withoutScid: number;
  withoutRoute: number;
  /** Craft with no telemetry receipt yet ("awaiting first AOS"). */
  neverHeard: number;
}>;

/** What every page carries besides its rows. */
export type DirectoryMeta = Readonly<{
  summary: DirectorySummary;
  telemetry: TelemetryFreshness;
  /** null when the server doesn't send them (before #313 S9's server half): the console guesses. */
  scids: ServerScids | null;
}>;

/** Every spacecraft, read page by page: for the pickers and Add's clash checks, not the list. */
export type SpacecraftDirectory = Readonly<{
  spacecraft: readonly SpacecraftRow[];
  telemetry: TelemetryFreshness;
  scids: ServerScids | null;
}>;

const profileRef = object({ id: token, name: nullable(string), version: integer });

const count: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0) throw new decoders.DecodeError(path, "non-negative integer");
  return n;
};

const directoryRow: Reader<SpacecraftRow> = (value, path = "") => {
  const raw = object({
    id: spacecraftIdReader,
    name: string,
    scid: nullable(scidReader),
    norad_id: nullable(integer),
    plane: nullable(integer),
    slot: nullable(integer),
    profile: nullable(profileRef),
    routing_rule_count: count,
    ready: boolean,
    last_received_at: nullable(timestamp),
  })(value, path);
  // `ready` is defined by the contract; a row claiming ready without its parts is malformed.
  if (raw.ready && (raw.scid === null || raw.profile === null || raw.routing_rule_count === 0))
    throw new decoders.DecodeError(
      `${path}.ready`,
      "false without a SCID, profile or routing rule",
    );
  return {
    id: raw.id,
    name: raw.name,
    scid: raw.scid,
    noradId: raw.norad_id,
    plane: raw.plane,
    slot: raw.slot,
    profile: raw.profile,
    routingRuleCount: raw.routing_rule_count,
    ready: raw.ready,
    lastReceivedAt: raw.last_received_at,
  };
};

const scidValue: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0 || n > 1023) throw new decoders.DecodeError(path, "SCID from 0 to 1023");
  return n;
};
const summaryReader: Reader<DirectorySummary> = (value, path = "") => {
  const raw = object({
    total: count,
    profiles: count,
    without_profile: count,
    without_scid: count,
    without_routing_rule: count,
    awaiting_first_aos: count,
  })(value, path);
  return {
    total: raw.total,
    profiles: raw.profiles,
    withoutProfile: raw.without_profile,
    withoutScid: raw.without_scid,
    withoutRoute: raw.without_routing_rule,
    neverHeard: raw.awaiting_first_aos,
  };
};

/** The most rows one page carries (the server's cap). */
export const DIRECTORY_PAGE_SIZE = 500;

const directoryFields = object({
  spacecraft: array(directoryRow, DIRECTORY_PAGE_SIZE),
  summary: summaryReader,
  telemetry: telemetryFreshness,
  next_free_scid: optional(nullable(scidValue)),
  scids_in_use: optional(array(scidValue, 1024)),
});

/** The lowest of 1..1023 not in `inUse` (0 is never suggested); null when none is free. */
export function lowestFreeScid(inUse: readonly number[]): number | null {
  const taken = new Set(inUse);
  for (let scid = 1; scid <= 1023; scid += 1) if (!taken.has(scid)) return scid;
  return null;
}

/** One page: its rows and what every page carries. */
export type DirectoryPage = Readonly<{ rows: readonly SpacecraftRow[]; meta: DirectoryMeta }>;

export const directoryPageReader: Reader<DirectoryPage> = (value, path = "") => {
  const raw = directoryFields(value, path);
  return {
    rows: raw.spacecraft,
    meta: {
      summary: raw.summary,
      telemetry: raw.telemetry,
      // Readers first: without the list the console keeps its own guess; with it, the server's next.
      scids:
        raw.scids_in_use === undefined
          ? null
          : {
              // Defined by the list (api docs); derived from it if the server ever leaves it out.
              next:
                raw.next_free_scid === undefined
                  ? lowestFreeScid(raw.scids_in_use)
                  : raw.next_free_scid,
              inUse: raw.scids_in_use,
            },
    },
  };
};

/** The directory's search and paging, as the server reads them. */
function directoryPath(
  missionId: MissionId,
  query: string,
  cursor: string | null,
  limit: number,
): string {
  const params = new URLSearchParams({ limit: String(limit) });
  const q = query.trim();
  if (q !== "") params.set("q", q);
  if (cursor !== null) params.set("cursor", cursor);
  return `/missions/${encodeURIComponent(missionId)}/spacecraft?${params.toString()}`;
}

/** One directory page for `usePagedQuery`: the key is the mission and the filter text. */
export async function fetchDirectoryPage(
  key: Readonly<{ missionId: MissionId; query: string }>,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<SpacecraftRow, DirectoryMeta>>> {
  const r = await requestPage(
    directoryPath(key.missionId, key.query, cursor, 200),
    directoryPageReader,
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.rows, next: r.value.nextCursor, meta: r.value.value.meta },
  };
}

/** At most this many pages are walked (500 each): a runaway cursor ends in a failure, not a loop. */
const MAX_PAGES = 40;

/**
 * Every active spacecraft, a bounded page at a time. For the pickers and the Add flow's clash
 * checks, which name or check against the fleet; the Setup directory itself pages with a cursor.
 */
export async function fetchSpacecraftDirectory(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<SpacecraftDirectory>> {
  const rows: SpacecraftRow[] = [];
  let first: DirectoryMeta | null = null;
  let cursor: string | null = null;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    // Typed: `cursor` feeds the request and is reassigned from its answer.
    const r: ApiResult<{ value: DirectoryPage; nextCursor: string | null }> = await requestPage(
      directoryPath(missionId, "", cursor, DIRECTORY_PAGE_SIZE),
      directoryPageReader,
      { signal },
    );
    if (!r.ok) return r;
    rows.push(...r.value.value.rows);
    first ??= r.value.value.meta;
    cursor = r.value.nextCursor;
    if (cursor === null)
      return {
        ok: true,
        value: { spacecraft: rows, telemetry: first.telemetry, scids: first.scids },
      };
  }
  return {
    ok: false,
    error: { kind: "malformed", message: "the spacecraft directory has more pages than expected" },
  };
}
