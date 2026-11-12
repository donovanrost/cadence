import type { Preview, StageOp } from "@/features/changes/index.ts";
import { overrideOp } from "@/features/profiles/index.ts";

/**
 * C3 Roll out to (Catalog.md, #65): a rollout is a change set. By profile, one
 * `spacecraft_profile` op per profile setting its catalog revision; a few spacecraft first, one
 * catalog override per spacecraft (P3's op). The whole set applies as one generation.
 */
export type RolloutChoice =
  | Readonly<{
      kind: "profiles";
      /** allVersions: also move spacecraft pinned to older profile versions (domain; ux: off by default). */
      profiles: readonly Readonly<{ id: string; allVersions: boolean }>[];
    }>
  | Readonly<{ kind: "spacecraft"; ids: readonly string[]; reason: string }>;

export function rolloutOps(revisionId: string, choice: RolloutChoice): StageOp[] {
  if (choice.kind === "spacecraft")
    return choice.ids.map((id) =>
      overrideOp(id, "catalog_revision_id", { value: revisionId, reason: choice.reason }),
    );
  return choice.profiles.map((p) => ({
    kind: "spacecraft_profile",
    action: "update",
    entity_id: p.id,
    changes: [{ path: "catalog_revision_id", value: revisionId }],
    // domain 2ef4ca79: expanded when the set applies, so api's moves_all is what moves.
    ...(p.allVersions ? { options: { rollout: "all_versions" } } : {}),
  }));
}

/** The compatibility check's items with this reason. */
const catalogItems = (p: Preview, reason: string) =>
  p.checks.flatMap((c) => c.items).filter((i) => i.reason === reason);

/** Spacecraft the dry run moves onto this revision (catalog_change items, `to` = the revision). */
export const rolloutMoves = (p: Preview, revisionId: string): number =>
  catalogItems(p, "catalog_change")
    .filter((i) => i.to === revisionId)
    .reduce((n, i) => n + (i.spacecraft_ids?.length ?? 0), 0);

/** Queued commands the apply cancels (the catalog_cancels_commands hold, acknowledged on Changes). */
export const rolloutCancels = (p: Preview): number =>
  catalogItems(p, "catalog_cancels_commands").reduce((n, i) => n + (i.requests?.length ?? 0), 0);

export type KeepCode = "older_profile_version" | "catalog_override" | "framing_governed" | "other";

/** Spacecraft the dry run leaves alone, counted by the server's code (domain 2ef4ca79). */
export function rolloutKeeps(p: Preview): ReadonlyMap<KeepCode, number> {
  const counts = new Map<KeepCode, number>();
  for (const keep of p.effects.flatMap((e) => e.keeps)) {
    const code = keepCode(keep.code);
    counts.set(code, (counts.get(code) ?? 0) + 1);
  }
  return counts;
}

const keepCode = (code: string | null | undefined): KeepCode =>
  code === "older_profile_version" || code === "catalog_override" || code === "framing_governed"
    ? code
    : "other";
