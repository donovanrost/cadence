import { producerFixture } from "../../../../../test-support/producer-fixture";
import { required } from "../../../../../test-support/required";
import { jsonFixture } from "../../../../../test-support/json-fixture";
import { oneOf } from "@cadence/plugin-sdk/admission";
import { planReviewActions } from "./plan-review";
import { test, expect, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { OpsContactPlanShow, type PlanDetailPort } from "../../contact-plans";
import { planFixture } from "./fixtures.test-support";
import { admitPlanDetail, canAct, planDecision, reviewHref } from "./plan-detail";
function harness() {
  const props = planFixture();
  const port: PlanDetailPort = {
    protocol: "remote-query" as const,
    context: { ...props.detail.context, plan_id: props.detail.plan.id },
    execute: vi.fn(),
    refresh: vi.fn(),
  };
  return {
    props,
    port,
    wrapper: mount(
      pageHeaderHarness("/missions/:mission_id/ops/plans/:contact_plan_id").stage(
        OpsContactPlanShow,
      ),
      { props: { ...props, port } },
    ),
  };
}
const receipt = (d: ReturnType<typeof planFixture>["detail"]) => ({
  receiptId: "receipt-one",
  completedAt: "2027-01-01T00:00:00Z",
  result: {
    contactPlanId: d.plan.id,
    version: d.plan.version,
    contentSha256: d.plan.content_sha256,
  },
});
test("native submission sends exact review evidence and cannot repeat while pending", async () => {
  const { props, port, wrapper } = harness();
  vi.mocked(port.execute).mockImplementation(() => new Promise(() => {}));
  await wrapper.get("#submission-reason").setValue("Reviewed proposal");
  await wrapper.get("#submission").trigger("submit");
  await wrapper.get("#submission").trigger("submit");
  expect(port.execute).toHaveBeenCalledExactlyOnceWith(
    "submit-plan",
    planDecision(props.detail, "submit-plan", "Reviewed proposal"),
  );
  expect(wrapper.get("#submit-plan").attributes("disabled")).toBeDefined();
  wrapper.unmount();
});
test("confirmed decisions refresh in place and keep approval and rejection reasons separate", async () => {
  const { props, port, wrapper } = harness();
  props.detail.plan.lifecycle_state = "pending_approval";
  await wrapper.setProps({ detail: structuredClone(props.detail) });
  await wrapper.get("#approval-reason").setValue("Approve exact selection");
  await wrapper.get("#rejection-reason").setValue("Different rejection reason");
  vi.mocked(port.execute).mockResolvedValue(receipt(props.detail));
  const fresh = structuredClone(props.detail);
  fresh.plan.lifecycle_state = "approved";
  fresh.plan.approved_version = 1;
  fresh.plan.reviewed_decision = {
    id: "approval-one",
    version: 1,
    content_sha256: fresh.plan.content_sha256,
    decision: "approved",
    reason: "Approved",
    actor_id: "admin",
    actor_kind: "user",
    decided_at: "2027-01-01T00:00:00Z",
  };
  vi.mocked(port.refresh).mockResolvedValue(fresh);
  await wrapper.get("#approval").trigger("submit");
  await flushPromises();
  expect(port.execute).toHaveBeenCalledExactlyOnceWith(
    "approve-plan",
    planDecision(props.detail, "approve-plan", "Approve exact selection"),
  );
  expect(wrapper.get("#plan-reviewed-decision").text()).toContain("Approved");
  expect(wrapper.get("#execute-plan").attributes("disabled")).toBeUndefined();
  wrapper.unmount();
});
test("uncertain outcomes preserve reasons and stay locked through read-only recovery", async () => {
  const { props, port, wrapper } = harness();
  vi.mocked(port.execute).mockRejectedValue(new Error("private-error-sentinel"));
  vi.mocked(port.refresh).mockResolvedValue(props.detail);
  await wrapper.get("#submission-reason").setValue("Keep my reason");
  await wrapper.get("#submission").trigger("submit");
  await flushPromises();
  expect(wrapper.text()).not.toContain("private-error-sentinel");
  expect((wrapper.get("#submission-reason").element as HTMLTextAreaElement).value).toBe(
    "Keep my reason",
  );
  await wrapper.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#submit-plan").attributes("disabled")).toBeDefined();
  expect(port.execute).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
test("confirmed receipts cannot unlock a stale refresh", async () => {
  const { props, port, wrapper } = harness();
  vi.mocked(port.execute).mockResolvedValue(receipt(props.detail));
  vi.mocked(port.refresh).mockResolvedValue(props.detail);
  await wrapper.get("#submission-reason").setValue("Review");
  await wrapper.get("#submission").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#submit-plan").attributes("disabled")).toBeDefined();
  wrapper.unmount();
});
test("new versions clear reasons and historical, denied and malformed reviews cannot decide", async () => {
  const { props, port, wrapper } = harness();
  await wrapper.get("#submission-reason").setValue("Reason for version one");
  const next = structuredClone(props.detail);
  next.plan.version = 2;
  next.plan.current_version = 2;
  next.query.version = 2;
  next.plan.content_sha256 = "b".repeat(64);
  await wrapper.setProps({ detail: next });
  expect((wrapper.get("#submission-reason").element as HTMLTextAreaElement).value).toBe("");
  const historical = structuredClone(props.detail);
  historical.plan.current_version = 2;
  await wrapper.setProps({ detail: historical });
  expect(wrapper.find("#plan-review-historical").exists()).toBe(true);
  for (const action of ["submit-plan", "approve-plan", "reject-plan", "execute-plan"] as const)
    expect(canAct(historical, action)).toBe(false);
  const denied = structuredClone(props.detail);
  denied.permissions.operate = false;
  await wrapper.setProps({ detail: denied });
  expect(wrapper.get("#submit-plan").attributes("disabled")).toBeDefined();
  await wrapper.setProps({ detail: { contract_version: 2 } });
  expect(wrapper.find("#plan-detail-unavailable").exists()).toBe(true);
  expect(port.execute).not.toHaveBeenCalled();
  wrapper.unmount();
});
test("departed pages ignore late completions", async () => {
  const { props, port, wrapper } = harness();
  let finish: ((v: unknown) => void) | undefined;
  vi.mocked(port.execute).mockImplementation(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  await wrapper.get("#submission-reason").setValue("Review");
  await wrapper.get("#submission").trigger("submit");
  wrapper.unmount();
  required(finish)(receipt(props.detail));
  await flushPromises();
  expect(port.refresh).not.toHaveBeenCalled();
});
test("admission rejects scope substitution, mismatched approval hashes and execution versions", () => {
  const { detail } = planFixture();
  expect(admitPlanDetail(detail)).toEqual(detail);
  expect(admitPlanDetail(detail, { ...detail.context, plan_id: "different" })).toBeNull();
  const bad = structuredClone(detail);
  bad.plan.reviewed_decision = {
    id: "a",
    version: 1,
    content_sha256: "b".repeat(64),
    decision: "approved",
    actor_id: "admin",
    actor_kind: "user",
    reason: "Review",
    decided_at: detail.plan.created_at,
  };
  expect(admitPlanDetail(bad)).toBeNull();
  bad.plan.reviewed_decision = null;
  bad.execution.entries = [
    { id: "e", version: 2, snapshot_id: "s", state: "pending", attempts: 0, reservation_id: null },
  ];
  expect(admitPlanDetail(bad)).toBeNull();
  bad.execution.entries = [];
  bad.query.opportunities_page = 2;
  expect(admitPlanDetail(bad)).toBeNull();
});
test("page links retain reviewed version and independent evidence pages", () => {
  const { detail } = planFixture();
  detail.query.approvals_page = 2;
  expect(reviewHref(detail, 1, "opportunities_page", 3)).toBe(
    "/missions/mission-plan/ops/plans/plan-one?version=1&approvals_page=2&opportunities_page=3",
  );
  expect(reviewHref(detail, 2)).toBe("/missions/mission-plan/ops/plans/plan-one?version=2");
});
const producer = producerFixture("CADENCE_PLAN_REVIEW_MODEL", import.meta.url);
test.skipIf(!producer.available)(
  "producer-supplied plan review emits native decision evidence",
  async () => {
    const props = jsonFixture(producer.read()),
      action = process.env.CADENCE_PLAN_REVIEW_ACTION ?? "submit-plan";
    if (!oneOf(planReviewActions, action)) throw Error("Unknown producer action");
    const detail = required(admitPlanDetail(props.detail));
    expect(detail).not.toBeNull();
    const port: PlanDetailPort = {
      protocol: "remote-query" as const,
      context: { ...required(detail).context, plan_id: required(detail).plan.id },
      refresh: vi.fn(),
      execute: vi.fn(() => new Promise(() => {})),
    };
    const wrapper = mount(
      pageHeaderHarness("/missions/:mission_id/ops/plans/:contact_plan_id").stage(
        OpsContactPlanShow,
      ),
      { props: { detail, port } },
    );
    if (action === "execute-plan") await wrapper.get("#execute-plan").trigger("click");
    else {
      const form =
        action === "submit-plan"
          ? "submission"
          : action === "approve-plan"
            ? "approval"
            : "rejection";
      await wrapper.get("#" + form + "-reason").setValue("Reviewed actual producer evidence");
      await wrapper.get("#" + form).trigger("submit");
    }
    expect(port.execute).toHaveBeenCalledTimes(1);
    process.stdout.write(
      "PLAN_PAYLOAD=" + JSON.stringify(required(vi.mocked(port.execute).mock.calls[0])[1]) + "\n",
    );
    wrapper.unmount();
  },
);

test("a prior confirmed submission cannot unlock a later uncertain approval", async () => {
  const { props, port, wrapper } = harness();
  const submitted = structuredClone(props.detail);
  submitted.plan.lifecycle_state = "pending_approval";
  vi.mocked(port.execute)
    .mockResolvedValueOnce(receipt(props.detail))
    .mockRejectedValueOnce(new Error("uncertain"));
  vi.mocked(port.refresh).mockResolvedValue(submitted);
  await wrapper.get("#submission-reason").setValue("Submit review");
  await wrapper.get("#submission").trigger("submit");
  await flushPromises();
  await wrapper.get("#approval-reason").setValue("Approve review");
  await wrapper.get("#approval").trigger("submit");
  await flushPromises();
  await wrapper.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#approve-plan").attributes("disabled")).toBeDefined();
  expect(port.execute).toHaveBeenCalledTimes(2);
  expect((wrapper.get("#approval-reason").element as HTMLTextAreaElement).value).toBe(
    "Approve review",
  );
  wrapper.unmount();
});

test("a confirmed decision can recover from a failed refresh without repeating the mutation", async () => {
  const { props, port, wrapper } = harness();
  const submitted = structuredClone(props.detail);
  submitted.plan.lifecycle_state = "pending_approval";
  vi.mocked(port.execute).mockResolvedValue(receipt(props.detail));
  vi.mocked(port.refresh)
    .mockRejectedValueOnce(new Error("unavailable"))
    .mockResolvedValueOnce(submitted);
  await wrapper.get("#submission-reason").setValue("Review");
  await wrapper.get("#submission").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#approval-reason").attributes("disabled")).toBeDefined();
  await wrapper.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#approval-reason").attributes("disabled")).toBeUndefined();
  expect(port.execute).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
