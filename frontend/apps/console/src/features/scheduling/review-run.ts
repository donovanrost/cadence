import { isKnown, type ApiError, type MissionId } from "@/api";
import type { Expired } from "./lifecycle.ts";
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
  SENT,
  sentNotApprovedLine,
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
 *   U20), no approval recorded (`caution`), or the one act's submit landed but its approve was
 *   refused (`crit`; `because` disables Approve after a self-approval refusal).
 */
export type ReviewOutcome =
  | { kind: "refused"; error: ApiError }
  | {
      kind: "after";
      tone: "nominal" | "caution" | "crit";
      text: string;
      because: Because | null;
      expired: Expired | null;
    };

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

type Plan = Readonly<{ id: string; version: number; counts: Readonly<{ passes: number }> }>;
type Context = Readonly<{
  missionId: MissionId;
  ops: (key: string) => Ids;
  userId: string;
  day: string;
}>;

const after = (
  tone: "nominal" | "caution" | "crit",
  text: string,
  extra: Partial<{ because: Because | null; expired: Expired | null }> = {},
): ReviewOutcome => ({ kind: "after", tone, text, because: null, expired: null, ...extra });

/** U20: "Approved" only on outcome approved (a replay shows the original answer's result). */
function approved(value: ApproveResult, version: number, passes: number): ReviewOutcome {
  return isKnown(value.outcome) && value.outcome === "approved"
    ? after("nominal", approvedLine(passes), { expired: value.expired })
    : after("caution", noApprovalLine(version));
}

export async function runReview(
  ctx: Context,
  act: ReviewAct,
  plan: Plan,
  acks: readonly Acknowledgement[],
  note?: string,
): Promise<ReviewOutcome> {
  const ids = ctx.ops(JSON.stringify([act, plan.id, plan.version, acks, note ?? ""]));
  const ref = { id: plan.id, version: plan.version };
  const who = { userId: ctx.userId, day: ctx.day };
  if (act === "approve") {
    const a = await approvePlan(ctx.missionId, ref, ids.approve, acks, note);
    if (a.ok) return approved(a.value, plan.version, plan.counts.passes);
    // A self-approval refusal disables Approve, so it closes the sheet and says why on the screen.
    const why = approveRefusal(a.error, { version: plan.version, ...who });
    return why.because
      ? after("crit", why.text, { because: why.because })
      : { kind: "refused", error: a.error };
  }
  const s = await submitPlan(ctx.missionId, ref, ids.submit, acks, note);
  if (!s.ok) return { kind: "refused", error: s.error };
  if (act === "submit") return after("nominal", SENT, { expired: s.value.expired });
  // The one act: approve the version submit put up (a sent-back draft's resubmit cuts the next).
  const version = s.value.version ?? plan.version;
  const a = await approvePlan(ctx.missionId, { id: plan.id, version }, ids.approve, acks, note);
  if (a.ok) return approved(a.value, version, plan.counts.passes);
  const why = approveRefusal(a.error, { version, ...who });
  return why.unclear
    ? after("caution", why.text)
    : after("crit", sentNotApprovedLine(version, why.reason), { because: why.because });
}
