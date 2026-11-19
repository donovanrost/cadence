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
import { formatCount, plural } from "@/ui";
import { planErrorText } from "./errors.ts";
import { dayLabel, expiredReader, lifecycleRefusal, type Expired } from "./lifecycle.ts";
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
  /** #273: the passes whose booking window closed since the approver looked, for `Show N`. */
  items?: Expired["items"] | undefined;
}>;
type Who = Readonly<{
  version: number;
  userId: string;
  day: string;
  /** The plan's unmet requirements, to count acknowledgements_required's gaps by spacecraft (U23). */
  unmet?: readonly Readonly<{ requirement_id: string; spacecraft_id: string | null }>[] | undefined;
  /** #273: the closed set the approver was shown, to diff a changed-set refusal against. */
  shown?: Expired | null | undefined;
  /** Re-plan's proposal words ("Not applied: …") instead of the plan's. */
  proposal?: boolean | undefined;
}>;

const person = d.nullable(
  d.object({ id: d.optional(d.nullable(d.string)), name: d.nullable(d.string) }),
);
const selfDetails = d.object({ because: d.knownText(["submitted", "edited"] as const) });
const notPendingDetails = d.object({
  state: d.optional(d.nullable(planState)),
  decided_by: d.optional(person),
  decided_at: d.optional(d.nullable(d.timestamp)),
});
const missingDetails = d.object({ missing: d.optional(d.array(d.string, 5_000)) });
const notReadyDetails = d.object({
  unmet: d.optional(d.array(d.object({ spacecraft_id: d.optional(d.nullable(d.string)) }), 5_000)),
  conflicts: d.optional(
    d.array(d.object({ snapshot_ids: d.optional(d.array(d.string, 5_000)) }), 5_000),
  ),
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
const firstSentence = (s: string) => s.split(/(?<=\.)\s/)[0]?.replace(/\.$/, "") ?? s;

const refusal = (
  text: string,
  reason: string,
  extra: Partial<Pick<Refusal, "code" | "because" | "unclear" | "items">> = {},
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
  if (outcomeUnknown(error))
    return refusal(
      "Cadence didn't give a clear answer, so your approval may not have been recorded. Reload to see the plan before you try again.",
      "Cadence didn't give a clear answer about the approval",
      { unclear: true },
    );
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
      `Not approved: Cadence can't find this plan any more, so your approval wasn't recorded. Reload to see ${dayLabel(w.day)}'s plans.`,
      "Cadence can't find this plan any more",
    );
  if (isError(error, "duplicate_operation"))
    return refusal(
      "Not approved: Cadence matched this to an earlier, different request, so your approval wasn't recorded. Reload and try again.",
      "Cadence matched it to an earlier, different request",
    );
  // U61's own lines (day already planned, replaced, all expired) already open "Not approved:".
  const lifecycle = lifecycleRefusal(error);
  if (lifecycle) {
    const rest = lifecycle.text.replace(/^Not approved: /, "");
    return refusal(lifecycle.text, firstSentence(rest).replaceAll(r, "it"));
  }
  const code = knownErrorCode(error);
  if (code === "plan_superseded")
    return refusal(
      `Not approved: contact rules changed after ${r} was drafted, so it's superseded and can't be booked. Your approval wasn't recorded. Draft the day again.`,
      "it's superseded by newer contact rules",
    );
  if (code === "acknowledgements_required") {
    const gaps = gapCount(error, w);
    const need =
      gaps > 0
        ? `${plural(gaps, "gap")} ${gaps === 1 ? "needs" : "need"} a reason first`
        : "some gaps need a reason first";
    return refusal(
      `Not approved: ${need}. Your approval wasn't recorded. Give a reason for each, then approve.`,
      need,
    );
  }
  if (code === "plan_not_ready") return notReady(error, r);
  if (code === "contact_plan_expired_passes_changed") return closedSince(error, w, r);
  if (code === "contact_plan_opportunity_expired")
    return refusal(
      `Not approved: the booking window has closed for some of ${r}'s passes, so ${r} can't be booked as it is. Your approval wasn't recorded. To book the others, draft the day again without them.`,
      "the booking window has closed for some of its passes, so it can't be booked as it is",
    );
  if (code === "invalid_params") {
    // The server's own message: its case is kept (dashboards' review).
    const text = planErrorText(error);
    return refusal(`Not approved: ${text}`, firstSentence(text));
  }
  return refusal(
    "Not approved: Cadence refused this approval. Your approval wasn't recorded.",
    "Cadence refused this approval",
    { code: codeOf(error) },
  );
}

/** U23: gaps are uncovered spacecraft, so the missing requirements count by their spacecraft. */
function gapCount(error: ApiError, w: Who): number {
  const missing = new Set(detailsOf(error, missingDetails)?.missing ?? []);
  const unmet = w.unmet ?? [];
  const of = (list: typeof unmet) => new Set(list.map((u) => u.spacecraft_id ?? "—")).size;
  // Only gaps the loaded plan can name by spacecraft; otherwise 0, and the line goes countless
  // (ca-ux's #338 review: never count requirements as gaps).
  return of(unmet.filter((u) => missing.has(u.requirement_id)));
}

const changedDetails = d.object({ expired: d.optional(expiredReader) });
const capped = (e: Expired | null) => e !== null && e.count > e.items.length;

/**
 * #273 (U97, #340): the closed set changed after the approver looked. "N more" only from a diff of
 * two uncapped lists keyed by snapshot id (ca-security); otherwise the countless form. Show N lists
 * the new ones. The console never retries on its own.
 */
function closedSince(error: ApiError, w: Who, r: string): Refusal {
  const current = detailsOf(error, changedDetails)?.expired ?? null;
  const shown = w.shown ?? null;
  const ids = (e: Expired | null) => (e?.items ?? []).map((i) => i.snapshot_id);
  const keyed = [...ids(current), ...ids(shown)].every((id) => id !== undefined);
  const seen = new Set(ids(shown));
  const fresh = (current?.items ?? []).filter((i) => !seen.has(i.snapshot_id));
  const n = keyed && !capped(current) && !capped(shown) ? fresh.length : 0;
  const more = n > 0 ? `${formatCount(n)} more` : "more";
  const whose = w.proposal ? "the proposal's" : `${r}'s`;
  const closed = `the booking window closed for ${more} of ${whose} passes after you opened it`;
  const extra = n > 0 ? { items: fresh } : {};
  if (w.proposal)
    return refusal(
      `Not applied: ${closed}, so what you'd apply changed. Nothing was booked. Check the list and apply it again.`,
      `the booking window closed for ${more} of its passes after you opened it`,
      extra,
    );
  return refusal(
    `Not approved: ${closed}, so what you'd approve changed. Your approval wasn't recorded. Check the list and approve again.`,
    `the booking window closed for ${more} of its passes after you opened it`,
    extra,
  );
}

/** U97: plan_not_ready by what blocks it: conflicting passes, else uncovered spacecraft. */
function notReady(error: ApiError, r: string): Refusal {
  const x = detailsOf(error, notReadyDetails);
  const passes = new Set((x?.conflicts ?? []).flatMap((c) => c.snapshot_ids ?? [])).size;
  if (passes > 0) {
    const verb = passes === 1 ? "conflicts" : "conflict";
    return refusal(
      `Not approved: ${passes} of ${r}'s passes ${verb} with other bookings, so it can't be booked. Your approval wasn't recorded. Send it back so it can be planned again.`,
      `${passes} of its passes ${verb} with other bookings`,
    );
  }
  const craft = new Set((x?.unmet ?? []).flatMap((u) => (u.spacecraft_id ? [u.spacecraft_id] : [])))
    .size;
  if (craft > 0) {
    const uncovered = `${plural(craft, "spacecraft", "spacecraft")} ${craft === 1 ? "isn't" : "aren't"} covered`;
    return refusal(
      `Not approved: ${r} isn't ready to approve: ${uncovered}. Your approval wasn't recorded. Reload to see the gaps.`,
      `it isn't ready: ${uncovered}`,
    );
  }
  return refusal(
    `Not approved: ${r} isn't ready to approve. Your approval wasn't recorded. Reload to see what's missing.`,
    "it isn't ready to approve",
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
/** U20: a submit answer that isn't outcome pending_approval (ux). */
export const notConfirmedLine = (version: number) =>
  `Cadence didn't confirm that R${version} was sent for approval. Reload to see the plan.`;
/** U20: a success answer that isn't outcome approved. */
export const noApprovalLine = (version: number) =>
  `Cadence didn't record an approval for R${version}. Reload to see the plan; if it's still waiting, try again or tell the team that runs Cadence for you.`;
/** The one act: the submit landed and the approve found no plan (U97: no "It's waiting"). */
export const sentNotFoundLine = (version: number, day: string) =>
  `R${version} was sent for approval, but Cadence can't find it any more. Reload to see ${dayLabel(day)}'s plans.`;
/** The one act: the submit landed and the approve's answer wasn't clear (U97). */
export const sentUnclearLine = (version: number) =>
  `R${version} was sent for approval, but Cadence didn't give a clear answer about the approval. Reload to see whether it was recorded before you try again.`;
/** The one act: the submit landed and the approve was refused (U97). */
export const sentNotApprovedLine = (version: number, reason: string) =>
  `R${version} was sent for approval, but not approved: ${reason}. It's waiting for approval.`;
/** U97: the one act's muted line under the footer's button. */
export const DIRECT_NOTE =
  "No second person's approval is needed, as this mission's setting allows. Sending and approving are both recorded.";
