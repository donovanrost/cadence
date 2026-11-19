import type { ModelRevision } from "./api.ts";

/**
 * U102 "Where" (#195): a revision's page offers C3 only for a target spacecraft can move to (A6),
 * up front. The dry run's NO-GO and the apply-time model gate stay the backstops.
 * - `rollout`: C3 as built, for this catalog revision and the server's breaking count.
 * - `line`: in C3's place, why spacecraft can't move to it yet.
 * - `none`: no C3 and no line (a model revision with no catalog revision, U65; a status the
 *   console doesn't know, whose text goes in Technical details, #392).
 * Only approved is offered: every model revision starts as candidate, the approval setting never
 * approves one, and the apply-time gate refuses any other status (mms-engineer, ed9bf56b0).
 */
export type RolloutGate =
  | Readonly<{
      kind: "rollout";
      revision: Readonly<{ id: string; number: number }>;
      catalogRevision: NonNullable<ModelRevision["catalog_revision"]>;
    }>
  | Readonly<{ kind: "line"; line: string }>
  | Readonly<{ kind: "none" }>;

export function rolloutGate(r: ModelRevision): RolloutGate {
  const cr = r.catalog_revision;
  if (!cr) return { kind: "none" };
  switch (r.status) {
    case "approved":
      return { kind: "rollout", revision: { id: cr.id, number: cr.number }, catalogRevision: cr };
    case "candidate":
      return {
        kind: "line",
        line: `Spacecraft can't move to rev ${cr.number} until it's approved.`,
      };
    case "rejected":
      return {
        kind: "line",
        line:
          `Rev ${cr.number} was rejected, so spacecraft can't move to it. To try again, correct ` +
          "the catalog and import the corrected file.",
      };
    case "retired":
      return {
        kind: "line",
        line: `Rev ${cr.number} is retired, so spacecraft can't move to it. Any already on it keep it.`,
      };
    default:
      return { kind: "none" };
  }
}
