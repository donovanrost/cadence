import { isError, isKnown, type ApiError, type MissionId } from "@/api";
import { partialApproval, type Expired } from "./lifecycle.ts";
import {
  approvePlan,
  submitPlan,
  type Acknowledgement,
  type ApproveResult,
} from "./plan-actions-api.ts";
import {
  approvedLine,
  approveRefusal,
  noApprovalLine,
  notConfirmedLine,
  SENT,
  sentNotApprovedLine,
  sentNotFoundLine,
  sentUnclearLine,
  type Because,
} from "./review-words.ts";

/**
 * #257 (U97): what a plan's review sheet does. `submit` sends it for approval; `approve` approves a
 * plan that waits (approve only); `submit_approve` is the one act under "Applies without approval":
 * submit, then approve the version submit put up. Both are recorded.
 */
export type ReviewAct = "submit" | "approve" | "submit_approve";

/**
 * - `refused`: nothing happened (the submit, or an approve-only, was refused). The sheet stays
 *   open and says why; a self-approval refusal comes as `after` instead (Approve is then off).
 * - `after`: the sheet closes and the screen shows `text`: a success from the answer (`nominal`,
 *   U20), nothing confirmed (`caution`), or the one act's submit landed but its approve was refused
 *   (`crit`). `because` disables Approve on `version` after a self-approval refusal (A6);
 *   `keepNote` is the typed note, kept for the retry (ux).
 */
export type ReviewAfter = Readonly<{
  kind: "after";
  tone: "nominal" | "caution" | "crit";
  text: string;
  version: number;
  because: Because | null;
  expired: Expired | null;
  keepNote: string | null;
}>;
export type ReviewOutcome = { kind: "refused"; error: ApiError } | ReviewAfter;

type Ids = Readonly<{ submit: string; approve: string }>;

/**
 * domain's point 3: both operation ids come from one click, and a retry of the SAME request reuses
 * them, so the server replays what already happened. A changed note or gap reason is a new request
 * with new ids (the same id with another body is 409 duplicate_operation).
 */
export function reviewOps(newId: () => string = () => crypto.randomUUID()) {
  let last: Readonly<{ key: string; ids: Ids }> | null = null;
  return (key: string): Ids => {
    if (last?.key !== key) last = { key, ids: { submit: newId(), approve: newId() } };
    return last.ids;
  };
}

type Plan = Readonly<{
  id: string;
  version: number;
  counts: Readonly<{ passes: number }>;
  /** For acknowledgements_required's gap count (U23). */
  unmet?: readonly Readonly<{ requirement_id: string; spacecraft_id: string | null }>[];
  /** #273: the closed set the approver saw, and its digest, sent back unchanged on approve. */
  expired?: Expired | null | undefined;
  expired_digest?: string | undefined;
}>;
type Context = Readonly<{
  missionId: MissionId;
  ops: (key: string) => Ids;
  userId: string;
  day: string;
}>;

const after = (
  version: number,
  tone: ReviewAfter["tone"],
  text: string,
  extra: Partial<Pick<ReviewAfter, "because" | "expired" | "keepNote">> = {},
): ReviewOutcome => ({
  kind: "after",
  tone,
  text,
  version,
  because: null,
  expired: null,
  keepNote: null,
  ...extra,
});

/** U20: "Approved" only on outcome approved (a replay shows the original answer's result). */
function approved(value: ApproveResult, version: number, passes: number): ReviewOutcome {
  if (!isKnown(value.outcome) || value.outcome !== "approved")
    return after(version, "caution", noApprovalLine(version));
  // U61/U97: passes left out because their booking window had closed are counted from the answer.
  const expired = value.expired;
  const text = expired && expired.count > 0 ? partialApproval(expired) : approvedLine(passes);
  return after(version, "nominal", text, { expired });
}

export async function runReview(
  ctx: Context,
  act: ReviewAct,
  plan: Plan,
  acks: readonly Acknowledgement[],
  note?: string,
): Promise<ReviewOutcome> {
  // The digest is part of the request: a reloaded closed set is a new request with new ids (#273).
  const digest = plan.expired_digest;
  const ids = ctx.ops(JSON.stringify([act, plan.id, plan.version, acks, note ?? "", digest ?? ""]));
  const ref = { id: plan.id, version: plan.version };
  const who = { userId: ctx.userId, day: ctx.day, unmet: plan.unmet, shown: plan.expired ?? null };
  if (act === "approve") {
    const a = await approvePlan(ctx.missionId, ref, ids.approve, acks, note, digest);
    if (a.ok) return approved(a.value, plan.version, plan.counts.passes);
    // A self-approval refusal disables Approve, so it closes the sheet and says why on the screen.
    const why = approveRefusal(a.error, { version: plan.version, ...who });
    return why.because
      ? after(plan.version, "crit", why.text, { because: why.because })
      : { kind: "refused", error: a.error };
  }
  // ux: in the one act the note is recorded once, on the decision (decision_note), not the submission.
  const s = await submitPlan(
    ctx.missionId,
    ref,
    ids.submit,
    acks,
    act === "submit" ? note : undefined,
  );
  if (!s.ok) return { kind: "refused", error: s.error };
  const version = s.value.version ?? plan.version;
  // U20: "Sent" only on outcome pending_approval; anything else stops the one act before approve.
  if (!isKnown(s.value.outcome) || s.value.outcome !== "pending_approval")
    return after(version, "caution", notConfirmedLine(version));
  if (act === "submit") return after(version, "nominal", SENT, { expired: s.value.expired });
  // The one act: approve the version submit put up (a sent-back draft's resubmit cuts the next).
  const a = await approvePlan(
    ctx.missionId,
    { id: plan.id, version },
    ids.approve,
    acks,
    note,
    digest,
  );
  if (a.ok) return approved(a.value, version, plan.counts.passes);
  const why = approveRefusal(a.error, { version, ...who });
  const keepNote = note ?? null;
  if (isError(a.error, "plan_not_found"))
    return after(version, "crit", sentNotFoundLine(version, ctx.day), { keepNote });
  return why.unclear
    ? after(version, "caution", sentUnclearLine(version), { keepNote })
    : after(version, "crit", sentNotApprovedLine(version, why.reason), {
        because: why.because,
        keepNote,
      });
}
