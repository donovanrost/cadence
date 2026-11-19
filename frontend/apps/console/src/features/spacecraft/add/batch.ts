import type { ServerScids, SpacecraftRow } from "../api.ts";
import type { ManifestRow } from "./manifest.ts";
import { expandName, type NamingPattern } from "./naming.ts";

/** One proposed spacecraft in the batch, before the server's batch validation. */
export type ProposedSpacecraft = Readonly<{
  key: string;
  name: string;
  scid: number | null;
  norad: number | null;
  plane: number | null;
  slot: number | null;
  /** Profile named by a manifest row (by name); null means the batch default. */
  profileName: string | null;
  problems: readonly string[];
}>;

export type PlaneFill = Readonly<{ firstPlane: number; perPlane: number }>;

export const MAX_BATCH = 500;
/** CCSDS TC spacecraft id is 10 bits; the server rejects anything above (spacecraft config kind). */
export const MAX_SCID = 1023;

/** Rows generated from a profile: names from the pattern, consecutive SCIDs, optional plane fill. */
export function generateRows(
  pattern: NamingPattern,
  count: number,
  scidStart: number,
  planes: PlaneFill | null,
  /** One per row, in order; null = add later. */
  norads: readonly (number | null)[] = [],
): readonly ProposedSpacecraft[] {
  return Array.from({ length: count }, (_, i) => {
    const scid = scidStart + i;
    return {
      key: `gen-${i}`,
      name: expandName(pattern, { scid, n: i + 1 }),
      scid,
      norad: norads[i] ?? null,
      plane: planes ? planes.firstPlane + Math.floor(i / planes.perPlane) : null,
      slot: planes ? (i % planes.perPlane) + 1 : null,
      profileName: null,
      problems: [],
    };
  });
}

export function manifestRows(rows: readonly ManifestRow[]): readonly ProposedSpacecraft[] {
  return rows.map((row) => ({
    key: `line-${row.line}`,
    name: row.name ?? "",
    scid: row.scid,
    norad: row.norad,
    plane: row.plane,
    slot: row.slot,
    profileName: row.profile,
    problems: row.problems.map((p) => `Line ${row.line}: ${p.message}`),
  }));
}

/** Smallest SCID above every SCID already in the mission (the server re-checks at review). */
/**
 * The SCID to suggest. S9 (#313, U20): the server's when it sends one (null: none is free). Without
 * it, the old guess from the directory, which can't see archived or staged SCIDs, never past
 * MAX_SCID.
 */
export function nextFreeScid(
  existing: readonly SpacecraftRow[],
  server: ServerScids | null = null,
): number | null {
  if (server) return server.next;
  const guess = existing.reduce(
    (max, row) => (row.scid !== null && row.scid >= max ? row.scid + 1 : max),
    1,
  );
  return guess > MAX_SCID ? null : guess;
}

export type ClashReport = Readonly<{
  rows: readonly ProposedSpacecraft[];
  clashCount: number;
  missingScid: number;
  missingNorad: number;
}>;

/**
 * Adds clash problems: names and SCIDs unique within the batch and against the mission. S9 (#313):
 * `inUse` is the server's SCIDs in use; one with no live craft in the directory (archived, or
 * staged) can't be named, so it reads as the server's own stage-time words.
 */
export function checkClashes(
  proposed: readonly ProposedSpacecraft[],
  existing: readonly SpacecraftRow[],
  inUse: readonly number[] = [],
): ClashReport {
  const takenNames = new Map(existing.map((row) => [row.name.toLowerCase(), row.name]));
  const takenScids = new Map<number, string | null>(inUse.map((scid) => [scid, null]));
  for (const row of existing) if (row.scid !== null) takenScids.set(row.scid, row.name);
  const seenNames = new Map<string, number>();
  const seenScids = new Map<number, number>();
  for (const row of proposed) {
    const name = row.name.toLowerCase();
    if (name) seenNames.set(name, (seenNames.get(name) ?? 0) + 1);
    if (row.scid !== null) seenScids.set(row.scid, (seenScids.get(row.scid) ?? 0) + 1);
  }

  let clashCount = 0;
  const rows = proposed.map((row) => {
    const problems = [...row.problems];
    const name = row.name.toLowerCase();
    if (!name) problems.push("Name is empty");
    const owner = takenNames.get(name);
    if (owner) problems.push(`Name ${owner} already exists in this mission`);
    if ((seenNames.get(name) ?? 0) > 1) problems.push(`Name ${row.name} repeats in this batch`);
    if (row.scid !== null) {
      const scidOwner = takenScids.get(row.scid);
      if (scidOwner) problems.push(`SCID ${row.scid} is already ${scidOwner}`);
      else if (scidOwner === null)
        problems.push(`SCID ${row.scid} is already used in this mission`);
      if ((seenScids.get(row.scid) ?? 0) > 1)
        problems.push(`SCID ${row.scid} repeats in this batch`);
    }
    if (problems.length > row.problems.length) clashCount += 1;
    return problems.length === row.problems.length ? row : { ...row, problems };
  });
  return {
    rows,
    clashCount,
    missingScid: rows.filter((row) => row.scid === null).length,
    missingNorad: rows.filter((row) => row.norad === null).length,
  };
}

/** "EARENDIL-509 to EARENDIL-550" for the rows after the preview. */
export function rangeLabel(rows: readonly ProposedSpacecraft[]): string | null {
  const first = rows[0];
  const last = rows.at(-1);
  if (!first || !last) return null;
  return first === last ? first.name : `${first.name} to ${last.name}`;
}
