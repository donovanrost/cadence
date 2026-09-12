import { expect, test } from "vite-plus/test";
import type {
  PlanDetailPort,
  PlanInputs,
  PlanPageRequest,
  PlanRequest,
} from "./OpsContactPlanShow.contracts";
import type { ReviewOperation } from "./plan-review";
import { planDecision, planPageRequest, planRequest } from "./plan-detail";
import { reviewFixture } from "./plan-review.test-support";

function rejectedPrograms(
  remote: Extract<PlanDetailPort, { protocol: "remote-query" }>,
  page: Extract<PlanDetailPort, { protocol: "page-snapshot" }>,
  operation: ReviewOperation,
) {
  const reference = planDecision(reviewFixture().detail, "execute-plan", "");
  const submission: PlanInputs["submit-plan"] = { ...reference, submission: { reason: "Review" } };
  // @ts-expect-error Approving a plan requires decision.reason rather than submission.reason.
  const incorrect: PlanRequest = ["approve-plan", submission];
  void incorrect;
  // @ts-expect-error Execution cannot silently carry another action's reason wrapper.
  const execution: PlanRequest = ["execute-plan", submission];
  void execution;
  // @ts-expect-error Page operations carry a sequence and a payload envelope.
  const bare: PlanPageRequest = ["submit-plan", submission];
  void bare;
  // @ts-expect-error The query protocol sends bare domain input.
  void remote.execute("execute-plan", { sequence: 1, payload: reference });
  // @ts-expect-error The page protocol requires its recovery sequence.
  void page.execute("execute-plan", reference);
  if (operation.status === "completed" && operation.action === "submit-plan") {
    // @ts-expect-error Submission does not provide execution counts.
    void operation.receipt.result.executionItemCount;
  }
  // @ts-expect-error Reviewed evidence is readonly.
  operation.input.plan_evidence.plan_version = 2;
}
void rejectedPrograms;

test("both transport requests preserve the exact reviewed evidence and reason wrapper", () => {
  const { detail } = reviewFixture();
  for (const action of ["submit-plan", "approve-plan", "reject-plan", "execute-plan"] as const) {
    const request = planRequest(detail, action, "  Reviewed exact version  ");
    expect(request).toEqual([action, planDecision(detail, action, "Reviewed exact version")]);
    expect(planPageRequest(7, ...request)).toEqual([action, { sequence: 7, payload: request[1] }]);
    expect(request[1].plan_evidence).toEqual({
      contract_version: 1,
      organization_id: detail.context.organization_id,
      mission_id: detail.context.mission_id,
      plan_id: detail.plan.id,
      plan_version: detail.plan.version,
      content_sha256: detail.plan.content_sha256,
    });
    if (request[0] === "submit-plan")
      expect(request[1].submission.reason).toBe("Reviewed exact version");
    else if (request[0] !== "execute-plan")
      expect(request[1].decision.reason).toBe("Reviewed exact version");
    else expect(Object.keys(request[1])).toEqual(["contact_plan_id", "plan_evidence"]);
  }
});
