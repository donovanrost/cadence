import { decoders, isKnown, request, type ApiResult, type Decoded, type Unrecognized } from "@/api";
import type { HoldReason, Preview, StageOp } from "@/features/changes/index.ts";
import { overrideOp } from "@/features/profiles/index.ts";
import { plural } from "@/ui";

const { array, integer, nullable, object, string, token } = decoders;
const revisionRef = object({ id: token, number: integer, label: nullable(string) });

/** api 34b8cc27 (setup.md "…/rollout"): what staging this revision on each profile would move. */
export const rolloutReader = object({
  revision: revisionRef,
  profiles: array(
    object({
      id: token,
      name: string,
      current_revision: nullable(revisionRef),
      spacecraft_count: integer,
      on_current_version: integer,
      on_older_versions: integer,
      override_pinned: integer,
      already_on_revision: integer,
      moves_default: integer,
      moves_all: integer,
    }),
    1000,
  ),
  unprofiled_count: integer,
});
export type Rollout = Decoded<typeof rolloutReader>;
export type RolloutProfile = Rollout["profiles"][number];

export function fetchRollout(
  key: Readonly<{ missionId: string; revisionId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<Rollout>> {
  const mission = encodeURIComponent(key.missionId);
  const revision = encodeURIComponent(key.revisionId);
  return request(`/missions/${mission}/catalog/revisions/${revision}/rollout`, rolloutReader, {
    signal,
  });
}

/** "Earendil Block 1 · 500 spacecraft · rev 14" (ux C3; U102, never "SC"). */
export const profileCard = (p: RolloutProfile) =>
  `${p.name} · ${p.spacecraft_count} spacecraft · ${p.current_revision?.label ?? "catalog set per spacecraft"}`;

/**
 * C3 Roll out to (Catalog.md, #65): a rollout is a change set. By profile, one
 * `spacecraft_profile` op per profile pinning the revision's composition; a few spacecraft first,
 * one composition override per spacecraft (P3's op). The whole set applies as one generation.
 */
export type RolloutChoice =
  | Readonly<{
      kind: "profiles";
      /** allVersions: also move spacecraft pinned to older profile versions (domain; ux: off by default). */
      profiles: readonly Readonly<{ id: string; allVersions: boolean }>[];
    }>
  | Readonly<{ kind: "spacecraft"; ids: readonly string[]; reason: string }>;

/**
 * What C3 rolls out: the catalog revision (its number, and the id the dry run's catalog moves name)
 * and its one-layer composition, which is what the ops pin (D3, #544: Cadence derives the catalog
 * revision from it).
 */
export type RolloutTarget = Readonly<{ id: string; number: number; compositionId: string }>;

export function rolloutOps(target: RolloutTarget, choice: RolloutChoice): StageOp[] {
  if (choice.kind === "spacecraft")
    return choice.ids.map((id) =>
      overrideOp(id, "composition_id", { value: target.compositionId, reason: choice.reason }),
    );
  return choice.profiles.map((p) => ({
    kind: "spacecraft_profile",
    action: "update",
    entity_id: p.id,
    changes: [{ path: "composition_id", value: target.compositionId }],
    // domain 2ef4ca79: expanded when the set applies, so api's moves_all is what moves.
    ...(p.allVersions ? { options: { rollout: "all_versions" } } : {}),
  }));
}

/** The compatibility check's items with this reason. */
const catalogItems = (p: Preview, reason: HoldReason) =>
  p.checks.flatMap((c) => c.items).filter((i) => i.reason === reason);

/** Spacecraft the dry run moves onto this revision (catalog_change items, `to` = the revision). */
export const rolloutMoves = (p: Preview, revisionId: string): number =>
  catalogItems(p, "catalog_change")
    .filter((i) => i.to === revisionId)
    .reduce((n, i) => n + (i.spacecraft_count ?? 0), 0);

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

const keepCode = (code: Exclude<KeepCode, "other"> | Unrecognized | null | undefined): KeepCode =>
  code !== null && code !== undefined && isKnown(code) ? code : "other";

/** "Stage rev 15 for Earendil Block 1" / "for 2 profiles" / "for 3 spacecraft" (ux C3). */
export function stageLabel(revision: number, choice: RolloutChoice, names: readonly string[]) {
  const target =
    choice.kind === "spacecraft"
      ? plural(choice.ids.length, "spacecraft", "spacecraft")
      : choice.profiles.length === 1
        ? (names[0] ?? "1 profile")
        : plural(choice.profiles.length, "profile");
  return `Stage rev ${revision} for ${target}`;
}

export type DryRunLine = Readonly<{ tone: "nominal" | "caution"; text: string }>;

/**
 * ux C3: the dry run's counts, and nothing inferred. `from` names the catalog the older-version
 * spacecraft keep when one profile is chosen ("rev 14"); `unprofiled` only for the profile option.
 */
export function dryRunLines(
  p: Preview,
  revision: Readonly<{ id: string; number: number }>,
  from: string | null,
  unprofiled: number,
): DryRunLine[] {
  const lines: DryRunLine[] = [];
  const moves = rolloutMoves(p, revision.id);
  lines.push({
    tone: "nominal",
    text: `Moves ${plural(moves, "spacecraft", "spacecraft")} to rev ${revision.number}.`,
  });
  const keeps = rolloutKeeps(p);
  const older = keeps.get("older_profile_version") ?? 0;
  if (older > 0)
    lines.push({
      tone: "nominal",
      text: `${older} ${older === 1 ? "keeps" : "keep"} ${from ?? "their catalog"}: ${older === 1 ? "it's" : "they're"} on an older version of the profile.`,
    });
  const own = keeps.get("catalog_override") ?? 0;
  if (own > 0)
    lines.push({
      tone: "nominal",
      text: `${own} ${own === 1 ? "keeps its" : "keep their"} own catalog (override).`,
    });
  const other = (keeps.get("framing_governed") ?? 0) + (keeps.get("other") ?? 0);
  if (other > 0)
    lines.push({
      tone: "nominal",
      text: other === 1 ? "1 stays as it is." : `${other} stay as they are.`,
    });
  if (unprofiled > 0)
    lines.push({
      tone: "nominal",
      text: `${unprofiled} ${unprofiled === 1 ? "has" : "have"} no profile, so this doesn't reach ${unprofiled === 1 ? "it" : "them"}.`,
    });
  const cancels = rolloutCancels(p);
  if (cancels > 0)
    lines.push({ tone: "caution", text: `Cancels ${plural(cancels, "queued command")}.` });
  return lines;
}
