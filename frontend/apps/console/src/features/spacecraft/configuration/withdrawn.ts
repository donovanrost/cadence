import { decoders as d, isKnown, type Decoded } from "@/api";
import {
  actorInSentence,
  compositionActor,
  compositionInSentence,
  isComposed,
  type Composition,
} from "@/features/catalog/composition.ts";
import { formatAbsolute, formatShort } from "@/ui";

/**
 * E2b (#546, #924; U109): a craft whose running revision's approval was withdrawn or rejected.
 * The workspace read carries it as `active.approval_withdrawn`, and the directory row as
 * `approval_withdrawn`: `{revision_id, earlier_approved, decision: {kind, by, at, reason}}`, or
 * null.
 */
export const approvalDecisionKinds = ["withdrawn", "rejected"] as const;

/** What the next staging would select instead (#924 follow-up), or null when nothing approved is left. */
const earlierApproved = d.object({
  revision_id: d.token,
  /** The catalog revision that introduced it; null when none is recorded (#999, ModelRevisions). */
  catalog_revision: d.nullable(
    d.object({
      id: d.token,
      number: d.integer,
      // free-text: the catalog revision's own label, shown as written.
      label: d.nullable(d.string),
      database_id: d.token,
    }),
  ),
});

export const approvalWithdrawnReader = d.object({
  revision_id: d.token,
  /**
   * The way out (U109): an earlier approved, runnable version the next staging would move to, or
   * null when none is left (#999).
   */
  earlier_approved: d.nullable(earlierApproved),
  decision: d.object({
    // Open on purpose: a decision kind this console doesn't know reads U109's neutral form.
    kind: d.knownText(approvalDecisionKinds),
    by: d.nullable(compositionActor),
    at: d.timestamp,
    // free-text: the decider's own reason, quoted as written (U65).
    reason: d.nullable(d.string),
  }),
});
export type ApprovalWithdrawn = Decoded<typeof approvalWithdrawnReader>;

/** The key both reads carry: null when the craft's revision is approved. */
export const approvalWithdrawnKey = d.nullable(approvalWithdrawnReader);

/**
 * The composition's name in U109's sentences: "composition 3", "catalog rev 4" for one catalog,
 * "this composition" with no number. Never an id.
 */
export function compositionName(c: Composition | null | undefined): string {
  if (!c) return "this composition";
  const composed: boolean = isComposed(c);
  if (composed) return compositionInSentence(c);
  const revision = c.imported_layers[0]?.catalog_revision?.number;
  return revision === undefined ? "this composition" : `catalog rev ${revision}`;
}

const capital = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** What happened, after "is no longer approved: " (U109; the reason quoted, else ends at the time). */
function decisionClause(w: ApprovalWithdrawn): string {
  const { kind, by, at, reason } = w.decision;
  const when = formatShort(new Date(at));
  const why = reason?.trim() ? `: “${reason.trim()}”` : "";
  const who = actorInSentence(by);
  if (kind === "rejected")
    return who ? `${who} rejected it at ${when}${why}` : `it was rejected at ${when}${why}`;
  return who
    ? `${who} withdrew its approval at ${when}${why}`
    : `its approval was withdrawn at ${when}${why}`;
}

/**
 * The craft's state line on its configuration (U109, caution): "Composition 3 is no longer
 * approved: Ana R. withdrew its approval at 11-20 09:12Z: “<reason>”. EARENDIL-004 stays on it
 * until a new configuration is applied." A decision kind the console doesn't know says only what's
 * known: "… is no longer approved since 11-20 09:12Z." (U20).
 *
 * Then U109's way out, by `earlier_approved`: "Stage a new configuration to move it to composition
 * 3's earlier approved version." when one is left, "Move it to an approved composition." when null.
 */
export function withdrawnStateLine(
  w: ApprovalWithdrawn,
  composition: Composition | null | undefined,
  craft: string | null,
): string {
  const named = compositionName(composition);
  const name = capital(named);
  const who = craft?.trim() ? craft : "This spacecraft";
  const stays = `${who} stays on it until a new configuration is applied.`;
  const tail = `${stays} ${wayOut(w, named)}`;
  if (!isKnown(w.decision.kind))
    return `${name} is no longer approved since ${formatShort(new Date(w.decision.at))}. ${tail}`;
  return `${name} is no longer approved: ${decisionClause(w)}. ${tail}`;
}

/** U109's way out: an earlier approved version, or none left. */
function wayOut(w: ApprovalWithdrawn, named: string): string {
  if (w.earlier_approved === null) return "Move it to an approved composition.";
  return `Stage a new configuration to move it to ${named}'s earlier approved version.`;
}

/** Technical details (U109, until #600): the revision and the decision's time. */
export function withdrawnRecord(w: ApprovalWithdrawn): readonly (readonly [string, string])[] {
  return [
    ["Revision", w.revision_id],
    ["Decided", formatAbsolute(new Date(w.decision.at))],
  ];
}
