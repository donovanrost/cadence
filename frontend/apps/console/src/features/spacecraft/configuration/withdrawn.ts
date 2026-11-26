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
 * `approval_withdrawn`: `{revision_id, decision: {kind, by, at, reason}}`, or null. The key is
 * optional so the console reads a server from before #924.
 */
export const approvalDecisionKinds = ["withdrawn", "rejected"] as const;

export const approvalWithdrawnReader = d.object({
  revision_id: d.token,
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

/** The optional key both reads carry. */
export const approvalWithdrawnKey = d.optional(d.nullable(approvalWithdrawnReader));

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
 * U109's way out ("Stage a new configuration to move it to …'s earlier approved version." or "Move
 * it to an approved composition.") depends on whether an earlier approved version is left, which
 * #924's wire doesn't carry yet, so the line ends before it rather than guess.
 */
export function withdrawnStateLine(
  w: ApprovalWithdrawn,
  composition: Composition | null | undefined,
  craft: string | null,
): string {
  const name = capital(compositionName(composition));
  const who = craft?.trim() ? craft : "This spacecraft";
  const stays = `${who} stays on it until a new configuration is applied.`;
  if (!isKnown(w.decision.kind))
    return `${name} is no longer approved since ${formatShort(new Date(w.decision.at))}. ${stays}`;
  return `${name} is no longer approved: ${decisionClause(w)}. ${stays}`;
}

/** Technical details (U109, until #600): the revision and the decision's time. */
export function withdrawnRecord(w: ApprovalWithdrawn): readonly (readonly [string, string])[] {
  return [
    ["Revision", w.revision_id],
    ["Decided", formatAbsolute(new Date(w.decision.at))],
  ];
}
