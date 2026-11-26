import type { MissionId } from "@/api/index.ts";
import {
  decoders,
  request,
  scid as scidReader,
  spacecraftId as spacecraftIdReader,
  type ApiResult,
  type Reader,
  type Scid,
  type SpacecraftId,
} from "@/api/index.ts";

/**
 * The Setup spacecraft directory.
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

export type SpacecraftDirectory = Readonly<{
  spacecraft: readonly SpacecraftRow[];
  telemetry: TelemetryFreshness;
  /** null when the server doesn't send them (before #313 S9's server half): the console guesses. */
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
const directoryFields = object({
  spacecraft: array(directoryRow, 20_000),
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

export const directoryReader: Reader<SpacecraftDirectory> = (value, path = "") => {
  const raw = directoryFields(value, path);
  return {
    spacecraft: raw.spacecraft,
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
  };
};

export function fetchSpacecraftDirectory(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<SpacecraftDirectory>> {
  return request(`/missions/${encodeURIComponent(missionId)}/spacecraft`, directoryReader, {
    signal,
  });
}

/** Case-insensitive match on name, or exact-prefix match on SCID digits. */
export function matchesFilter(row: SpacecraftRow, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (q === "") return true;
  if (row.name.toLowerCase().includes(q)) return true;
  if (row.profile?.name?.toLowerCase().includes(q)) return true;
  return row.scid !== null && String(row.scid).startsWith(q);
}

export type DirectorySummary = Readonly<{
  total: number;
  profiles: number;
  withoutProfile: number;
  withoutScid: number;
  withoutRoute: number;
  neverHeard: number;
}>;

export function summarize(directory: SpacecraftDirectory): DirectorySummary {
  const profiles = new Set<string>();
  let withoutProfile = 0;
  let withoutScid = 0;
  let withoutRoute = 0;
  let neverHeard = 0;
  for (const row of directory.spacecraft) {
    if (row.profile) profiles.add(row.profile.id);
    else withoutProfile += 1;
    if (row.scid === null) withoutScid += 1;
    if (row.routingRuleCount === 0) withoutRoute += 1;
    if (row.lastReceivedAt === null) neverHeard += 1;
  }
  return {
    total: directory.spacecraft.length,
    profiles: profiles.size,
    withoutProfile,
    withoutScid,
    withoutRoute,
    neverHeard,
  };
}
