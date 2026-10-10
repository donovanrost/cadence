import { producerFixture } from "../../../../../test-support/producer-fixture";
import { required } from "../../../../../test-support/required";
import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import { fixtureRecord, jsonFixture } from "../../../../../test-support/json-fixture";
import { oneOf } from "@cadence/plugin-sdk/admission";
import { expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { planReviewContribution } from "../../contact-plans";
import type { PlanAction } from "./OpsContactPlanShow.contracts";
import {
  admitPlanReviewPage,
  admitReviewOperation,
  type PlanReviewPage,
  type ReviewOperation,
  planReviewActions,
} from "./plan-review";
import { planDecision } from "./plan-detail";
import { reviewFixture, reviewOperation, completedReview } from "./plan-review.test-support";

function harness(page = reviewFixture()) {
  const execute =
      vi.fn<
        (action: PlanAction, input: { sequence: number; payload: unknown }) => Promise<unknown>
      >(),
    read = vi.fn(),
    dispose = vi.fn();
  let canLeave = () => true;
  const port = {
    execute,
    navigate: vi.fn(),
    guardNavigation: (g: () => boolean) => {
      canLeave = g;
      return dispose;
    },
  };
  const context = {
    organizationId: page.detail.context.organization_id,
    missionId: page.detail.context.mission_id,
    resourceId: page.detail.plan.id,
  };
  const props = planReviewContribution.read(page, context);
  const w = mount(
    pageHeaderHarness("/missions/:mission_id/ops/plans/:contact_plan_id").stage(
      planReviewContribution.component,
    ),
    {
      props: { ...props, port, readPort: { read } },
    },
  );
  return { w, page, execute, read, dispose, canLeave: () => canLeave() };
}
async function native(
  w: ReturnType<typeof harness>["w"],
  action: PlanAction,
  reason = "Reviewed exact proposal",
) {
  if (action === "execute-plan") await w.get("#execute-plan").trigger("click");
  else {
    const key =
      action === "submit-plan"
        ? "submission"
        : action === "approve-plan"
          ? "approval"
          : "rejection";
    await w.get(`#${key}-reason`).setValue(reason);
    await w.get(`#${key}`).trigger("submit");
  }
  await flushPromises();
}
test("captured plan forms serialize native evidence and retain other decision reasons", async () => {
  const h = harness();
  h.execute.mockImplementation(async (action, input) => {
    const op = reviewOperation(h.page, action, input);
    h.page = completedReview(h.page, op);
    h.read.mockResolvedValue(h.page);
    return op;
  });
  await native(h.w, "submit-plan");
  expect(h.execute).toHaveBeenLastCalledWith("submit-plan", {
    sequence: 1,
    payload: planDecision(h.page.detail, "submit-plan", "Reviewed exact proposal"),
  });
  await h.w.get("#rejection-reason").setValue("Retain alternative rationale");
  await native(h.w, "approve-plan");
  expect((h.w.get("#rejection-reason").element as HTMLTextAreaElement).value).toBe(
    "Retain alternative rationale",
  );
  expect(h.w.get("#plan-operation-receipt").text()).toContain("approve-plan");
  expect(h.w.get("#execute-plan").attributes("disabled")).toBeUndefined();
  await native(h.w, "execute-plan");
  expect(h.execute).toHaveBeenCalledTimes(3);
  expect(h.w.get("#execute-plan").attributes("disabled")).toBeDefined();
  h.w.unmount();
});
test("lost responses recover only the exact captured operation and preserve drafts until confirmation", async () => {
  const h = harness();
  let recovered: MutableFixture<PlanReviewPage> | undefined;
  h.execute.mockImplementation(async (action, input) => {
    recovered = completedReview(h.page, reviewOperation(h.page, action, input));
    throw Error("private transport error");
  });
  await native(h.w, "submit-plan", "Keep this reason");
  h.read.mockResolvedValue(h.page);
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.get("#submit-plan").attributes("disabled")).toBeDefined();
  expect((h.w.get("#submission-reason").element as HTMLTextAreaElement).value).toBe(
    "Keep this reason",
  );
  const foreign = mutableFixture(required(recovered));
  required(required(foreign.operation).receipt).result.actor_id = "foreign";
  h.read.mockResolvedValue(foreign);
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.find("#plan-operation-receipt").exists()).toBe(false);
  h.read.mockResolvedValue(recovered);
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.get("#approve-plan").attributes("disabled")).toBeDefined(); // empty approval reason
  expect(h.w.get("#approval-reason").attributes("disabled")).toBeUndefined();
  expect(h.w.get("#plan-operation-receipt").text()).toContain("submit-plan");
  expect((h.w.get("#submission-reason").element as HTMLTextAreaElement).value).toBe("");
  expect(h.execute).toHaveBeenCalledTimes(1);
  expect(h.w.text()).not.toContain("private transport error");
  h.w.unmount();
});
test("bootstrap copies cannot cancel pending decisions and departure releases the host guard", async () => {
  const h = harness();
  let finish: ((v: unknown) => void) | undefined;
  h.execute.mockImplementation(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  await native(h.w, "submit-plan");
  expect(h.canLeave()).toBe(false);
  await h.w.setProps({ page: structuredClone(h.page) });
  await h.w.get("#submission").trigger("submit");
  expect(h.execute).toHaveBeenCalledTimes(1);
  h.w.unmount();
  required(finish)(reviewOperation(h.page, "submit-plan", required(h.execute.mock.calls[0])[1]));
  await flushPromises();
  expect(h.read).not.toHaveBeenCalled();
  expect(h.dispose).toHaveBeenCalledOnce();
});
test("known rejections preserve reasons and require a fresh admitted review", async () => {
  const h = harness();
  let op: ReviewOperation | undefined;
  h.execute.mockImplementation(async (action, input) => {
    op = {
      ...reviewOperation(h.page, action, input),
      status: "rejected",
      feedback: ["review_changed"],
      receipt: null,
    };
    return op;
  });
  h.read.mockRejectedValue(Error("unavailable"));
  await native(h.w, "submit-plan");
  expect((h.w.get("#submission-reason").element as HTMLTextAreaElement).value).toBe(
    "Reviewed exact proposal",
  );
  expect(h.w.get("#submit-plan").attributes("disabled")).toBeDefined();
  h.read.mockResolvedValue(completedReview(h.page, required(op)));
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.get("#submit-plan").attributes("disabled")).toBeUndefined();
  h.w.unmount();
});
test("failed and version-substituted reads retain prior evidence, reasons and actual receipts", async () => {
  const h = harness();
  await h.w.get("#submission-reason").setValue("Retained");
  h.read.mockResolvedValue({ detail: {} });
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.find("#plan-reviewed-hash").exists()).toBe(true);
  expect((h.w.get("#submission-reason").element as HTMLTextAreaElement).value).toBe("Retained");
  const newer = structuredClone(h.page);
  newer.detail.plan.version = 2;
  newer.detail.plan.current_version = 2;
  newer.detail.query.version = 2;
  h.read.mockResolvedValue(newer);
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.get("#plan-review-summary").text()).toContain(h.page.detail.plan.content_sha256);
  expect((h.w.get("#submission-reason").element as HTMLTextAreaElement).value).toBe("Retained");
  h.w.unmount();
});
test("operator decisions, historical evidence and oversized reasons cannot bypass controls", async () => {
  const page = reviewFixture();
  page.detail.plan.lifecycle_state = "pending_approval";
  page.detail.permissions.decide = false;
  const h = harness(page);
  await native(h.w, "approve-plan");
  expect(h.execute).not.toHaveBeenCalled();
  h.w.unmount();
  const hist = reviewFixture();
  hist.detail.plan.current_version = 2;
  const hh = harness(hist);
  await native(hh.w, "submit-plan");
  expect(hh.execute).not.toHaveBeenCalled();
  hh.w.unmount();
  const u = harness();
  await native(u.w, "submit-plan", "界".repeat(1500));
  expect(u.execute).not.toHaveBeenCalled();
  expect(u.w.get("#submission-reason").attributes("disabled")).toBeUndefined();
  u.w.unmount();
});
test("public contribution rejects foreign context and forged actual-result identities", () => {
  const p = reviewFixture(),
    input = { sequence: 1, payload: planDecision(p.detail, "submit-plan", "Reason") },
    op = reviewOperation(p, "submit-plan", input);
  expect(admitReviewOperation(op, p.detail, p.actor_id)).toEqual(op);
  for (const field of [
    "actor_id",
    "mission_id",
    "organization_id",
    "contactPlanId",
    "contentSha256",
    "action",
    "version",
  ]) {
    const bad = structuredClone(op);
    fixtureRecord(bad.receipt.result)[field] = "foreign";
    expect(admitReviewOperation(bad, p.detail, p.actor_id)).toBeNull();
  }
  expect(() =>
    planReviewContribution.read(p, {
      organizationId: "foreign",
      missionId: p.detail.context.mission_id,
      resourceId: p.detail.plan.id,
    }),
  ).toThrow();
  expect(admitPlanReviewPage({ ...p, sequence: 1 })).toBeNull();
});
const producer = producerFixture("CADENCE_PLAN_WORKFLOW", import.meta.url);
test.skipIf(!producer.available)("producer supplied native plan review contribution", async () => {
  const supplied = jsonFixture(producer.read()),
    h = harness(
      mutableFixture(required(admitPlanReviewPage(fixtureRecord(supplied.snapshot).data))),
    );
  if (!oneOf(planReviewActions, supplied.action)) throw Error("Unknown producer action");
  h.execute.mockImplementation(async () => {
    if (!supplied.operation) return new Promise(() => {});
    expect(admitReviewOperation(supplied.operation, h.page.detail, h.page.actor_id)).not.toBeNull();
    h.read.mockResolvedValue(fixtureRecord(supplied.refreshed).data);
    return supplied.operation;
  });
  await native(h.w, supplied.action, "Reviewed actual producer evidence");
  expect(h.execute).toHaveBeenCalledTimes(1);
  if (supplied.operation && fixtureRecord(supplied.operation).status === "completed")
    expect(h.w.find("#plan-operation-receipt").exists()).toBe(true);
  process.stdout.write("PLAN_CONTRIBUTION_INPUT=" + JSON.stringify(h.execute.mock.calls[0]) + "\n");
  h.w.unmount();
});

test("a completed execution waits for evidence beyond the pre-execution approved state", async () => {
  const page = reviewFixture();
  page.detail.plan.lifecycle_state = "pending_approval";
  const approval = reviewOperation(page, "approve-plan", {
    sequence: 1,
    payload: planDecision(page.detail, "approve-plan", "Approve reviewed selection"),
  });
  const h = harness(completedReview(page, approval));
  let updated: MutableFixture<PlanReviewPage> | undefined;
  h.execute.mockImplementation(async (action, input) => {
    const op = reviewOperation(h.page, action, input);
    if (op.action !== "execute-plan") throw Error("Expected execution");
    op.receipt.result.lifecycleState = "failed";
    updated = completedReview(h.page, op);
    updated.detail.plan.lifecycle_state = "failed";
    const stale = structuredClone(updated);
    stale.detail.plan.lifecycle_state = "approved";
    h.read.mockResolvedValue(stale);
    return op;
  });
  await native(h.w, "execute-plan");
  expect(h.w.get("#plan-operation-receipt").text()).toContain("execute-plan");
  expect(h.w.get("#execute-plan").attributes("disabled")).toBeDefined();
  h.read.mockResolvedValue(updated);
  await h.w.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(h.w.get("#execute-plan").attributes("disabled")).toBeUndefined();
  expect(h.execute).toHaveBeenCalledTimes(1);
  h.w.unmount();
});
