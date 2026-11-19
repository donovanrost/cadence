import type { ChangeSet } from "./shapes.ts";

/** Why this viewer can't review the set, in ux's words, and the code for Technical details. */
export type ReviewBlock = Readonly<{ line: string; code: string | null }>;

/** ux (#320, U97 family; ca-ux #322): the submitter who staged nothing is blocked too (U20). */
const AUTHOR =
  "You staged part of this change set or sent it for review, so another person reviews it.";
/** ux: a disabled action always carries a reason; an unknown one is never mapped onto AUTHOR. */
const UNKNOWN = "You can't review this change set, so another person reviews it.";
/** ux U79 (TEMPORARY, deleted with 9ac6dc8ee): a legacy conversion batch keeps its own line. */
const CONVERSION_STAGER = "You staged this batch, so someone else reviews and applies it.";

/**
 * ux U79 / #412 (TEMPORARY): the batch's stager, by the viewer's id among the set's authors. The
 * authors list only picks the words; whether anyone is blocked is the server's `viewer`.
 */
const isConversionStager = (set: ChangeSet, viewerId: string | null | undefined) =>
  !!set.legacy_conversion && !!viewerId && set.authors.some((a) => a.id === viewerId);

/**
 * #320 (four-eyes up front, U97): whether this viewer can't review the set, from the server's
 * `viewer` only (api changes.md §Permissions: the same test the review applies). Never inferred
 * from the authors list. null when they can, or when the server doesn't say (its refusal is the
 * backstop). A conversion batch's stager reads U79's own line; anyone else blocked as
 * reviewer_is_author (a submitter who staged nothing) reads #320's (#412).
 */
export function reviewBlocked(set: ChangeSet, viewerId?: string | null): ReviewBlock | null {
  const viewer = set.viewer;
  if (!viewer || viewer.can_review) return null;
  const reason = viewer.review_blocked_reason ?? null;
  if (reason === "reviewer_is_author")
    return { line: isConversionStager(set, viewerId) ? CONVERSION_STAGER : AUTHOR, code: null };
  return { line: UNKNOWN, code: reason === null ? null : reason.unrecognized };
}

/**
 * ux U79 (TEMPORARY): who staged a conversion batch; a nameless stager is left out, never an id.
 * #406: the stager, already told by the review block that someone else reviews it, reads only
 * 'Staged by Mira K.'; everyone else reads both sentences.
 */
export function conversionStager(set: ChangeSet, viewerId?: string | null): string | null {
  if (!set.legacy_conversion) return null;
  const name = set.authors[0]?.name;
  // 'Mira K.' already ends the sentence: don't add a second period.
  const by = name ? `Staged by ${name.endsWith(".") ? name : `${name}.`}` : "Staged earlier.";
  const toldByBlock = reviewBlocked(set, viewerId)?.line === CONVERSION_STAGER;
  return toldByBlock ? by : `${by} Someone else reviews and applies it.`;
}
