import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import ActivationApprovalsPage from "./ActivationApprovalsPage.vue";
import OpsActivationRequests from "./OpsActivationRequests.vue";
import { inboxFixture } from "./fixtures.test-support";
import { admitInbox, assertDecisionResult } from "./validation";
const input = {
  activation_decision: { request_id: "request-1", reason: "Reviewed exact basis" },
  decision: "approved" as const,
};

test("real review form emits the chosen decision and preserves rationale on same-request refresh", async () => {
  const data = inboxFixture().data;
  const wrapper = mount(OpsActivationRequests, { props: data });
  await wrapper.get("#review-request-1").trigger("click");
  await wrapper.get("textarea").setValue(input.activation_decision.reason);
  await wrapper.setProps({ ...structuredClone(data) });
  expect(wrapper.get("textarea").element.value).toBe(input.activation_decision.reason);
  await wrapper
    .get("form")
    .trigger("submit", { submitter: wrapper.get("#approve-activation-request").element });
  expect(wrapper.emitted("decide")).toEqual([[input]]);
  await wrapper.setProps({ activation_requests: [] });
  expect(wrapper.find("#activation-decision-form").exists()).toBe(false);
  wrapper.unmount();
});

test("pending decisions disable repeat actions and report approval/application separately", async () => {
  const snapshot = inboxFixture();
  let complete!: (value: unknown) => void;
  const execute = vi.fn(
    () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  );
  const wrapper = mount(ActivationApprovalsPage, {
    props: { snapshot, context: snapshot.context, execute, refresh: vi.fn() },
  });
  await wrapper.get("#review-request-1").trigger("click");
  await wrapper.get("textarea").setValue(input.activation_decision.reason);
  const form = wrapper.get("form");
  const event = { submitter: wrapper.get("#approve-activation-request").element };
  await form.trigger("submit", event);
  await form.trigger("submit", event);
  expect(execute).toHaveBeenCalledTimes(1);
  expect(wrapper.get("#approve-activation-request").attributes("disabled")).toBeDefined();
  complete({
    status: "ok",
    data: {
      activationRequestId: "request-1",
      decision: "approved",
      outcome: "application_needs_review",
    },
  });
  await flushPromises();
  expect(wrapper.get("#activation-review-result").attributes("role")).toBe("alert");
  expect(wrapper.get("#activation-review-result").text()).toContain("Request approved.");
  expect(wrapper.get("#activation-review-result").text()).not.toContain("approved and applied");
  wrapper.unmount();
});

test.each(["invalid", "unavailable", "wrong-request"])(
  "contains %s decision responses",
  async (kind) => {
    const snapshot = inboxFixture();
    const result =
      kind === "invalid"
        ? { status: "invalid", message: "A different person must review this request." }
        : kind === "unavailable"
          ? { status: "unavailable" }
          : {
              status: "ok",
              data: { activationRequestId: "other", decision: "approved", outcome: "applied" },
            };
    const wrapper = mount(ActivationApprovalsPage, {
      props: {
        snapshot,
        context: snapshot.context,
        execute: vi.fn().mockResolvedValue(result),
        refresh: vi.fn(),
      },
    });
    wrapper.getComponent(OpsActivationRequests).vm.$emit("decide", input);
    await flushPromises();
    expect(wrapper.get("#activation-review-result").attributes("role")).toBe("alert");
    expect(wrapper.find("#activation-approval-inbox").exists()).toBe(true);
    wrapper.unmount();
  },
);

test("rejects wrong-scope/version/duplicate snapshots without mounting decision controls", () => {
  const original = inboxFixture();
  for (const value of [
    { ...original, version: 2 },
    { ...original, context: { ...original.context, mission_id: "other" } },
    { ...original, context: { ...original.context, organization_id: "other" } },
    {
      ...original,
      data: {
        ...original.data,
        activation_requests: [
          ...original.data.activation_requests,
          ...original.data.activation_requests,
        ],
      },
    },
    { ...original, data: { ...original.data, form: {} } },
  ]) {
    expect(admitInbox(value, original.context)).toBeNull();
    const wrapper = mount(ActivationApprovalsPage, {
      props: { snapshot: value, context: original.context, execute: vi.fn(), refresh: vi.fn() },
    });
    expect(wrapper.find("#activation-inbox-unavailable").exists()).toBe(true);
    expect(wrapper.find("#approve-activation-request").exists()).toBe(false);
    wrapper.unmount();
  }
});

test("a rejection cannot be reported as an application and an unmounted page ignores its reply", async () => {
  expect(() =>
    assertDecisionResult(
      {
        status: "ok",
        data: { activationRequestId: "request-1", decision: "rejected", outcome: "applied" },
      },
      { ...input, decision: "rejected" },
    ),
  ).toThrow();
  const snapshot = inboxFixture();
  let complete!: (value: unknown) => void;
  const wrapper = mount(ActivationApprovalsPage, {
    props: {
      snapshot,
      context: snapshot.context,
      execute: () =>
        new Promise((resolve) => {
          complete = resolve;
        }),
      refresh: vi.fn(),
    },
  });
  wrapper.getComponent(OpsActivationRequests).vm.$emit("decide", input);
  wrapper.unmount();
  complete({
    status: "ok",
    data: { activationRequestId: "request-1", decision: "approved", outcome: "applied" },
  });
  await flushPromises();
});
