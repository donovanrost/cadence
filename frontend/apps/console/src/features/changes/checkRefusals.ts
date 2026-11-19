import { isError, type ApiError } from "@/api";
import type { RefusalOutcome } from "./refusals.ts";

/**
 * #262 / #374 (ux U79's amendment, ca-ux 11-19): the review and the submit run the checks again,
 * and two refusals come from that. Nothing is written either way.
 * - 409 `holds_blocking` at approve: a blocking hold stands (the stage/apply line stays in
 *   rejectionSentence). Approve then waits for a reload that shows the hold cleared.
 * - 503 `preview_failed` (approve and submit): Cadence couldn't run the checks. Its details are
 *   null and the cause is only in the server's log, so Technical details shows just the code.
 *   Trying again is the fix, so the button stays enabled.
 */
export type ChecksAct = "approve" | "apply" | "request_review";

/** U79's A6/A7 reason while a blocking hold stands, before and after a 409. */
export const HOLD_STANDS = "A blocking hold stands; see the checks.";

const TRY_AGAIN = "Try again; if it keeps happening, tell the team that runs Cadence for you.";

const PREVIEW_FAILED = {
  approve:
    "Not approved: Cadence couldn't run the checks, so nothing was applied and the change set " +
    `stays in review. Your approval wasn't recorded. ${TRY_AGAIN}`,
  apply: `Not applied: Cadence couldn't run the checks, so nothing changed. ${TRY_AGAIN}`,
  request_review: `Not sent for review: Cadence couldn't run the checks, so nothing changed. ${TRY_AGAIN}`,
} as const satisfies Record<ChecksAct, string>;

const HOLDS_BLOCKING_APPROVE =
  "Not approved: a blocking hold stands, so nothing was applied and the change set stays in " +
  "review. Your approval wasn't recorded. Approve it once the hold clears; the checks show it.";

/** The refusal's words when the checks refused it, or null for any other refusal. */
export function checksRefusal(error: ApiError, act: ChecksAct): RefusalOutcome | null {
  if (isError(error, "preview_failed"))
    return { changed: false, sentence: PREVIEW_FAILED[act], technical: "preview_failed" };
  if (act === "approve" && isError(error, "holds_blocking"))
    return { changed: false, sentence: HOLDS_BLOCKING_APPROVE };
  return null;
}
