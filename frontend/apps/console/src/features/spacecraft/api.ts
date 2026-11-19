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
 * Contract: docs/apogee/api/setup.md, `GET /api/console/v1/missions/:mission_id/spacecraft`.
 */
const { array, boolean, integer, nullable, object, string, timestamp, token } = decoders;

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
export type SpacecraftDirectory = Readonly<{
  spacecraft: readonly SpacecraftRow[];
  telemetry: TelemetryFreshness;
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

export const directoryReader: Reader<SpacecraftDirectory> = object({
  spacecraft: array(directoryRow, 20_000),
  telemetry: telemetryFreshness,
});

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
