import { planFixture } from "./fixtures.test-support";
import type { PlanAction } from "./OpsContactPlanShow.contracts";
import type { PlanReviewPage, ReviewOperation } from "./plan-review";
export const reviewFixture = (): PlanReviewPage => ({
  ...planFixture(),
  actor_id: "review-actor",
  sequence: 0,
  operation: null,
});
export function reviewOperation(
  page: PlanReviewPage,
  action: PlanAction,
  input: { sequence: number; payload: Record<string, any> },
): ReviewOperation {
  const d = page.detail;
  return {
    sequence: input.sequence,
    action,
    input: input.payload,
    status: "completed",
    receipt: {
      receiptId: "receipt-review",
      completedAt: "2027-01-01T00:00:00Z",
      result: {
        contract_version: 1,
        actor_id: page.actor_id,
        ...d.context,
        action,
        contactPlanId: d.plan.id,
        version: d.plan.version,
        contentSha256: d.plan.content_sha256,
        ...(action === "execute-plan" ? { lifecycleState: "reserved", executionItemCount: 1 } : {}),
      },
    },
  };
}
export function completedReview(page: PlanReviewPage, op: ReviewOperation): PlanReviewPage {
  const next = structuredClone(page);
  next.sequence = op.sequence;
  next.operation = op;
  if (op.status !== "completed") return next;
  const p = next.detail.plan;
  p.lifecycle_state =
    op.action === "submit-plan"
      ? "pending_approval"
      : op.action === "reject-plan"
        ? "draft"
        : op.action === "execute-plan"
          ? "reserved"
          : "approved";
  if (op.action === "approve-plan" || op.action === "reject-plan") {
    p.reviewed_decision = {
      id: "approval-review",
      version: p.version,
      content_sha256: p.content_sha256,
      decision: op.action === "approve-plan" ? "approved" : "rejected",
      actor_id: page.actor_id,
      actor_kind: "user",
      reason: op.input.decision.reason,
      decided_at: "2027-01-01T00:00:00Z",
    };
    p.approved_version = op.action === "approve-plan" ? p.version : null;
  }
  return next;
}
