import { shallowRef } from "vue";
import type { PlanDetailPort } from "./OpsContactPlanShow.contracts";
import { usePlanPageWorkflow } from "./plan-review-state";
import { useQueryReview } from "../../shared/use-query-review";
import type { ReviewCompletion } from "./plan-review";
import {
  admitPlanDetail,
  canAct,
  completedReceipt,
  planRequest,
  reviewIdentity,
} from "./plan-detail";

export function usePlanDetail(input: () => unknown, port: PlanDetailPort | undefined) {
  if (port?.protocol === "page-snapshot") return usePlanPageWorkflow(input, port);
  const state = useQueryReview(input, port, {
    admit: (value) => admitPlanDetail(value, port?.context),
    subject: (detail) => detail.plan.id,
    identity: reviewIdentity,
    reasons: () => ({ submission: "", approval: "", rejection: "" }),
    canAct,
    reasonRequired: (action) => action !== "execute-plan",
    request: planRequest,
    completion: (value, detail, action) =>
      completedReceipt(value, detail, action)
        ? { action, version: detail.plan.version, hash: detail.plan.content_sha256 }
        : null,
    reconciled: (detail, confirmed) => {
      const plan = detail.plan;
      if (plan.version !== confirmed.version || plan.content_sha256 !== confirmed.hash)
        return false;
      if (confirmed.action === "submit-plan") return plan.lifecycle_state !== "draft";
      if (confirmed.action === "approve-plan")
        return plan.reviewed_decision?.decision === "approved";
      if (confirmed.action === "reject-plan")
        return plan.reviewed_decision?.decision === "rejected";
      return (
        plan.reviewed_decision?.decision === "approved" && plan.approved_version === plan.version
      );
    },
  });
  return { ...state, confirmed: shallowRef<ReviewCompletion | null>(null) };
}
