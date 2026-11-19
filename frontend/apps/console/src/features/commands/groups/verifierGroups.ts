import type { CatalogRevision, Preflight, VerifierGroup } from "./api.ts";

/**
 * U51 "When targets differ" (CommandFlow.md C1 B; api's preflight shape): group by what's
 * actually different, the verifiers, not just the revision number. It informs and never gates.
 */

/** `rev 4`, or the label when there's no number. */
export const revisionText = (r: CatalogRevision | null | undefined): string | null =>
  r ? (r.number !== null ? `rev ${r.number}` : r.label) : null;

/** `rev 3 · 4` from several revisions: distinct, by number, labels after. */
export function revisionsText(
  revs: readonly (CatalogRevision | null | undefined)[],
): string | null {
  const numbers = [
    ...new Set(revs.flatMap((r) => (r && r.number !== null ? [r.number] : []))),
  ].sort((a, b) => a - b);
  const labels = [
    ...new Set(revs.flatMap((r) => (r && r.number === null && r.label ? [r.label] : []))),
  ];
  const parts = [numbers.length ? `rev ${numbers.join(" · ")}` : null, ...labels].filter(
    (t): t is string => t !== null,
  );
  return parts.length ? parts.join(" · ") : null;
}

/** The verifier groups for the stack's command at `position` (api: one entry per command). */
export function groupsAt(
  p: Preflight | null | undefined,
  position: number,
): readonly VerifierGroup[] {
  return p?.commands?.find((c) => c.position === position)?.verifier_groups ?? [];
}

/** Verifiers differ when more than one group checks the command differently. */
export const verifiersDiffer = (groups: readonly VerifierGroup[]) => groups.length > 1;

/**
 * A group's verifier words (ux U51): its whole set by name, then the longest wait, so two groups
 * that share a completion verifier still read differently. No verifier: "can't turn green".
 */
export function groupVerifierText(
  g: VerifierGroup,
): Readonly<{ text: string; verifiable: boolean }> {
  if (g.verifiers.length === 0) return { text: "No verifier: can't turn green", verifiable: false };
  const longest = Math.max(...g.verifiers.map((v) => v.timeout_ms ?? 0));
  const names = g.verifiers.map((v) => v.name);
  return {
    text: [...names, longest > 0 ? `within ${Math.round(longest / 1000)} s` : null]
      .filter(Boolean)
      .join(" · "),
    verifiable: true,
  };
}

/** Up to 3 targets by name; above that, a count (the row offers Show). */
export const NAMED_TARGETS = 3;
export function groupTargetsText(
  g: VerifierGroup,
  nameOf: (spacecraftId: string) => string,
): Readonly<{ text: string; more: boolean }> {
  const n = g.spacecraft_ids.length;
  if (n <= NAMED_TARGETS) return { text: g.spacecraft_ids.map(nameOf).join(", "), more: false };
  return { text: `${n} targets`, more: true };
}

/** One group row's right side: `499 targets · rev 3` / `EARENDIL-001 · rev 4`. */
export function groupMeta(g: VerifierGroup, nameOf: (id: string) => string): string {
  return [groupTargetsText(g, nameOf).text, revisionsText(g.catalog_revisions)]
    .filter(Boolean)
    .join(" · ");
}

export const DIFFER_LEAD = "Not every target checks this command the same way.";

/** The targets' revisions when they span more than one (D Targets adds `rev n` per target). */
export function targetRevisions(
  p: Preflight | null | undefined,
): ReadonlyMap<string, string> | null {
  if (!p) return null;
  const byId = new Map<string, string>();
  for (const t of p.targets) {
    const text = revisionText(t.catalog_revision);
    if (text) byId.set(t.spacecraft_id, text);
  }
  return new Set(byId.values()).size > 1 ? byId : null;
}

/** `rev 14 · 15` for the stack's meta when targets span revisions (verifiers the same or not). */
export function spanText(p: Preflight | null | undefined): string | null {
  const revs = targetRevisions(p);
  return revs ? revisionsText(p?.targets.map((t) => t.catalog_revision) ?? []) : null;
}
