import { decoders, request, type ApiResult, type Reader } from "@/api/index.ts";

/**
 * The Setup spacecraft directory.
 *
 * Until the Setup endpoint lands (requested shape: docs/apogee/plans/setup-shapes.md §S), rows come
 * from `GET /missions/:id/fleet` (docs/apogee/api/ops.md), reading only its identity columns. The
 * screen depends on `SpacecraftDirectory` alone, so switching endpoints stays inside this file.
 */
const { array, integer, nullable, object, string, timestamp, token } = decoders;

export type ProfileRef = Readonly<{ id: string; name: string | null; version: number }>;

export type SpacecraftRow = Readonly<{
  id: string;
  name: string;
  scid: number | null;
  plane: number | null;
  slot: number | null;
  profile: ProfileRef | null;
  /** null: never heard since creation ("Awaiting first AOS"). */
  lastReceivedAt: string | null;
}>;

export type SpacecraftDirectory = Readonly<{ spacecraft: readonly SpacecraftRow[] }>;

const profileRef = object({ id: token, name: nullable(string), version: integer });

const fleetRow: Reader<SpacecraftRow> = (value, path = "") => {
  const raw = object({
    id: token,
    name: string,
    scid: nullable(integer),
    plane: nullable(integer),
    slot: nullable(integer),
    profile: nullable(profileRef),
    last_received_at: nullable(timestamp),
  })(value, path);
  return {
    id: raw.id,
    name: raw.name,
    scid: raw.scid,
    plane: raw.plane,
    slot: raw.slot,
    profile: raw.profile,
    lastReceivedAt: raw.last_received_at,
  };
};

export const fleetDirectoryReader: Reader<SpacecraftDirectory> = object({
  spacecraft: array(fleetRow, 20_000),
});

export function fetchSpacecraftDirectory(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<SpacecraftDirectory>> {
  return request(`/missions/${encodeURIComponent(missionId)}/fleet`, fleetDirectoryReader, {
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
  neverHeard: number;
}>;

export function summarize(directory: SpacecraftDirectory): DirectorySummary {
  const profiles = new Set<string>();
  let withoutProfile = 0;
  let withoutScid = 0;
  let neverHeard = 0;
  for (const row of directory.spacecraft) {
    if (row.profile) profiles.add(row.profile.id);
    else withoutProfile += 1;
    if (row.scid === null) withoutScid += 1;
    if (row.lastReceivedAt === null) neverHeard += 1;
  }
  return {
    total: directory.spacecraft.length,
    profiles: profiles.size,
    withoutProfile,
    withoutScid,
    neverHeard,
  };
}
