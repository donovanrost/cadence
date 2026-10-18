import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import { record } from "@cadence/plugin-sdk/admission";
import { admitReviewOperation } from "./plan-review";
import { planFixture } from "./fixtures.test-support";
import type { PlanAction } from "./OpsContactPlanShow.contracts";
import type { PlanReviewPage, ReviewOperation } from "./plan-review";
export const reviewFixture = (): MutableFixture<PlanReviewPage> => ({
  ...planFixture(),
  actor_id: "review-actor",
  sequence: 0,
  operation: null,
});
type Completed<A extends PlanAction = PlanAction> = MutableFixture<
  Extract<ReviewOperation, { action: A; status: "completed" }>
>;
export function reviewOperation<A extends PlanAction>(
  page: PlanReviewPage,
  action: A,
  input: unknown,
): Completed<A>;
export function reviewOperation(
  page: PlanReviewPage,
  action: PlanAction,
  input: unknown,
): Completed {
  if (!record(input)) throw Error("Invalid review command fixture");
  const d = page.detail;
  const operation = admitReviewOperation(
    {
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
          ...(action === "execute-plan"
            ? { lifecycleState: "reserved", executionItemCount: 1 }
            : {}),
        },
      },
    },
    d,
    page.actor_id,
  );
  if (!operation || operation.status !== "completed" || operation.action !== action)
    throw Error("Invalid review operation fixture");
  return mutableFixture(operation);
}
export function completedReview(
  page: PlanReviewPage,
  op: ReviewOperation,
): MutableFixture<PlanReviewPage> {
  const next = mutableFixture(page);
  next.sequence = op.sequence;
  next.operation = mutableFixture(op);
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
