import {
  codeOf,
  decoders as d,
  detailsOf,
  isError,
  isKnown,
  knownErrorCode,
  outcomeUnknown,
  type ApiError,
} from "@/api";
import { plural } from "@/ui";
import { planErrorText } from "./errors.ts";
import { dayLabel } from "./lifecycle.ts";
import { when } from "./plan-history.ts";
import { planState, type PlanState } from "./plans-api.ts";

const pastReview: ReadonlySet<PlanState> = new Set([
  "approved",
  "executing",
  "interrupted",
  "partially_reserved",
  "reserved",
  "failed",
  "unconfirmed",
]);

/**
 * U97 (#257): the words for a plan's Submit and Approve, from api's codes. Every approve refusal
 * says the approval wasn't recorded; a success line comes only from the answer (U20).
 */
export type Because = "submitted" | "edited";
export type Refusal = Readonly<{
  /** The whole line the sheet shows. */
  text: string;
  /** The first sentence after "Not approved:", R41 as "it", for the one act's partial line. */
  reason: string;
  /** A code this console doesn't know, for Technical details; null for every known one. */
  code: string | null;
  /** A self-approval refusal: Approve is then disabled with `selfReason(because)` (A6). */
  because: Because | null;
  /** No clear answer: the approval may or may not have been recorded (qa #19). */
  unclear: boolean;
}>;
type Who = Readonly<{ version: number; userId: string; day: string }>;

const person = d.nullable(
  d.object({ id: d.optional(d.nullable(d.string)), name: d.nullable(d.string) }),
);
const selfDetails = d.object({ because: d.knownText(["submitted", "edited"] as const) });
const notPendingDetails = d.object({
  state: d.optional(d.nullable(planState)),
  decided_by: d.optional(person),
  decided_at: d.optional(d.nullable(d.timestamp)),
});
const submittedDetails = d.object({
  submitted_by: d.optional(person),
  submitted_at: d.optional(d.nullable(d.timestamp)),
});

const SELF: Readonly<Record<Because, string>> = {
  submitted: "you submitted this plan, so another org admin approves it",
  edited: "you drafted this version of the plan, so another org admin approves it",
};
/** A self-approval refusal's `because`, or null for any other error (or an unknown because). */
export function selfBecause(error: ApiError): Because | null {
  if (!isError(error, "contact_plan_self_approval_forbidden")) return null;
  const because = detailsOf(error, selfDetails)?.because;
  return because !== undefined && isKnown(because) ? because : null;
}
/** A6: the reason Approve is disabled after a self-approval refusal (muted; Send back stays). */
export const selfReason = (because: Because) => `${upper(SELF[because])}.`;

const upper = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const lower = (s: string) => s.charAt(0).toLowerCase() + s.slice(1);
const firstSentence = (s: string) => s.split(/(?<=\.)\s/)[0]?.replace(/\.$/, "") ?? s;

const refusal = (
  text: string,
  reason: string,
  extra: Partial<Pick<Refusal, "code" | "because" | "unclear">> = {},
): Refusal => ({ text, reason, code: null, because: null, unclear: false, ...extra });

/** Who decided and when, both or neither (U29); a name, never an id (U25). */
function decided(error: ApiError, w: Who, r: string): Refusal {
  const x = detailsOf(error, notPendingDetails);
  const by = x?.decided_by ?? null;
  const at = x?.decided_at ?? null;
  const state = x?.state ?? null;
  // A plan back in draft was sent back; any state past review was approved; others name no one.
  const verb = state === "draft" ? "sent back" : state && pastReview.has(state) ? "approved" : null;
  if (verb && by && at && by.id === w.userId)
    return refusal(
      `You already ${verb} ${r} at ${when(at)}. Reload to see it.`,
      `you already ${verb} it at ${when(at)}`,
    );
  if (verb && by?.name && at)
    return refusal(
      `${r} was already ${verb} by ${by.name} at ${when(at)}, so your approval wasn't recorded. Reload to see it.`,
      `it was already ${verb} by ${by.name} at ${when(at)}`,
    );
  return refusal(
    `Not approved: ${r} isn't waiting for approval any more, so your approval wasn't recorded. Reload to see it.`,
    "it isn't waiting for approval any more",
  );
}

/** U97: an approve refusal (the sheet's line, and the reason for the one act's partial line). */
export function approveRefusal(error: ApiError, w: Who): Refusal {
  const r = `R${w.version}`;
  if (outcomeUnknown(error)) {
    const text = planErrorText(error);
    return refusal(text, lower(firstSentence(text)), { unclear: true });
  }
  const because = selfBecause(error);
  if (because)
    return refusal(
      `Not approved: ${SELF[because]}. Your approval wasn't recorded and nothing was booked.`,
      SELF[because],
      { because },
    );
  if (isError(error, "forbidden"))
    return refusal(
      "Not approved: only an org admin approves contact plans. Your approval wasn't recorded.",
      "only an org admin approves contact plans",
    );
  if (isError(error, "plan_not_pending")) return decided(error, w, r);
  if (isError(error, "plan_changed"))
    return refusal(
      `Not approved: ${r} changed after you opened it, so it isn't what you reviewed. Your approval wasn't recorded. Reload to review it again.`,
      "it changed after you opened it, so it isn't what you reviewed",
    );
  if (isError(error, "plan_not_found"))
    return refusal(
      `Not approved: Cadence can't find this plan any more. Reload to see ${dayLabel(w.day)}'s plans.`,
      "Cadence can't find this plan any more",
    );
  if (isError(error, "duplicate_operation")) return duplicate;
  const code = knownErrorCode(error);
  if (
    code === "plan_not_ready" ||
    code === "acknowledgements_required" ||
    code === "plan_superseded" ||
    code === "invalid_params"
  ) {
    // U36's lines, opening "Not approved:".
    const text = planErrorText(error);
    return refusal(`Not approved: ${lower(text)}`, lower(firstSentence(text)).replaceAll(r, "it"));
  }
  return refusal(
    "Not approved: Cadence refused this approval. Your approval wasn't recorded.",
    "Cadence refused this approval",
    { code: codeOf(error) },
  );
}

const duplicate = refusal(
  "Not sent: Cadence matched this to an earlier, different request, so nothing changed. Reload and try again.",
  "Cadence matched this to an earlier, different request",
);

/** U97: a submit refusal; anything not #257's own keeps U36's line (planErrorText). */
export function submitRefusalText(error: ApiError, w: Who): string {
  const r = `R${w.version}`;
  if (isError(error, "duplicate_operation")) return duplicate.text;
  if (!isError(error, "plan_already_submitted")) return planErrorText(error);
  const x = detailsOf(error, submittedDetails);
  const by = x?.submitted_by ?? null;
  const at = x?.submitted_at ?? null;
  if (by && at && by.id === w.userId)
    return `Not sent: you already sent ${r} for approval at ${when(at)}, so nothing changed.`;
  if (by?.name && at)
    return `Not sent: ${r} was already sent for approval by ${by.name} at ${when(at)}, so nothing changed. Reload to see it.`;
  return `Not sent: ${r} is already waiting for approval, so nothing changed. Reload to see it.`;
}

export const SENT = "Sent for approval.";
export const approvedLine = (passes: number) =>
  `Approved. Booking ${plural(passes, "pass", "passes")}.`;
/** U20: a success answer that isn't outcome approved. */
export const noApprovalLine = (version: number) =>
  `Cadence didn't record an approval for R${version}. Reload to see the plan; if it's still waiting, try again or tell the team that runs Cadence for you.`;
/** The one act: the submit landed and the approve was refused (U97). */
export const sentNotApprovedLine = (version: number, reason: string) =>
  `R${version} was sent for approval, but not approved: ${reason}. It's waiting for approval.`;
/** U97: the one act's muted line under the footer's button. */
export const DIRECT_NOTE =
  "No second person's approval is needed, as this mission's setting allows. Sending and approving are both recorded.";
