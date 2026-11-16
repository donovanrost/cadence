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
 * #320 (four-eyes up front, U97): whether this viewer can't review the set, from the server's
 * `viewer` only (api changes.md §Permissions: the same test the review applies). Never inferred
 * from the authors list. null when they can, or when the server doesn't say (its refusal is the
 * backstop).
 */
export function reviewBlocked(set: ChangeSet): ReviewBlock | null {
  const viewer = set.viewer;
  if (!viewer || viewer.can_review) return null;
  const reason = viewer.review_blocked_reason ?? null;
  if (reason === "reviewer_is_author")
    return { line: set.legacy_conversion ? CONVERSION_STAGER : AUTHOR, code: null };
  return { line: UNKNOWN, code: reason === null ? null : reason.unrecognized };
}

/** ux U79 (TEMPORARY): who staged a conversion batch; a nameless stager is left out, never an id. */
export function conversionStager(set: ChangeSet): string | null {
  if (!set.legacy_conversion) return null;
  const name = set.authors[0]?.name;
  // 'Mira K.' already ends the sentence: don't add a second period.
  const by = name ? `Staged by ${name.endsWith(".") ? name : `${name}.`}` : "Staged earlier.";
  return `${by} Someone else reviews and applies it.`;
}
