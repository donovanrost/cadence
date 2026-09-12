import "../../../module-pages.test-support";
import type { OpsPageAction } from "@cadence/plugin-sdk/ops-pages";
import { required } from "../../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import {
  policyPageFixture,
  policyOperationFixture,
  policyAfterOperation,
} from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/policy-workflow.test-support";
import OpsModulePage from "./OpsModulePage.vue";
const token = "11111111-1111-4111-8111-111111111111";
const context = { organizationId: "org-policy", missionId: "mission-policy" };
let wrapper: ReturnType<typeof mount>;
afterEach(() => wrapper?.unmount());
function harness() {
  const initial = {
    id: "planning.fleet-policy",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token,
    context,
    data: policyPageFixture(),
  };
  const execute = vi.fn<(request: OpsPageAction) => Promise<unknown>>(),
    query = vi.fn().mockResolvedValue(initial),
    refresh = vi.fn();
  wrapper = mount(OpsModulePage, {
    props: {
      contributionId: initial.id,
      snapshot: initial,
      context,
      execute,
      query,
      refresh,
      navigate: vi.fn(),
      guardNavigation: vi.fn(() => vi.fn()),
    },
  });
  return { initial, execute, query, refresh };
}
test("host binds reviewed approval and receipt recovery to the captured policy page", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async ({ event, input }) => {
    const op = policyOperationFixture(h.initial.data, event, input);
    h.query.mockResolvedValue({ ...h.initial, data: policyAfterOperation(h.initial.data, op) });
    throw Error("Lost reply");
  });
  await wrapper.get("#fleet-policy-approval-reason").setValue("Approve reviewed version");
  await wrapper.get("#fleet-policy-approval-form").trigger("submit");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledExactlyOnceWith({
    id: h.initial.id,
    token,
    event: "approve-policy",
    input: {
      sequence: 1,
      payload: {
        decision: {
          reason: "Approve reviewed version",
          policy_evidence: required(h.initial.data.model.current).reference,
        },
      },
    },
  });
  await wrapper.get("#fleet-policy-refresh").trigger("click");
  await flushPromises();
  expect(h.query).toHaveBeenCalledExactlyOnceWith({ id: h.initial.id, token });
  expect(wrapper.find("#fleet-policy-unconfirmed").exists()).toBe(false);
  expect(wrapper.find("#fleet-policy-operation-receipt").exists()).toBe(true);
  expect(h.refresh).not.toHaveBeenCalled();
});
test("unchanged host bootstrap rerenders cannot interrupt an approval receipt", async () => {
  const h = harness();
  let settle!: (v: unknown) => void;
  h.execute.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        settle = resolve;
      }),
  );
  await wrapper.get("#fleet-policy-approval-reason").setValue("Reviewed");
  await wrapper.get("#fleet-policy-approval-form").trigger("submit");
  const command = required(h.execute.mock.calls[0])[0];
  const op = policyOperationFixture(h.initial.data, command.event, command.input);
  h.query.mockResolvedValue({ ...h.initial, data: policyAfterOperation(h.initial.data, op) });
  await wrapper.setProps({ snapshot: structuredClone(h.initial), context: { ...context } });
  settle(op);
  await flushPromises();
  expect(wrapper.find("#fleet-policy-operation-receipt").exists()).toBe(true);
  expect(wrapper.find("#fleet-policy-unconfirmed").exists()).toBe(false);
});
test("foreign resources and unsupported policy data remain inside the host unavailable boundary", async () => {
  const h = harness();
  for (const changed of [
    { context: { ...context, resourceId: "wrong" } },
    { data: { model: {} } },
    { token: "invalid" },
  ]) {
    await wrapper.setProps({ snapshot: { ...h.initial, ...changed } });
    expect(wrapper.find("#ops-module-unavailable").exists()).toBe(true);
  }
  await wrapper.get("#ops-module-retry").trigger("click");
  expect(h.refresh).toHaveBeenCalledOnce();
  expect(h.execute).not.toHaveBeenCalled();
});
