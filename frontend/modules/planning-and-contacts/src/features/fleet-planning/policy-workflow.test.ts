import { record } from "./policy-native-fixture.test-support";
import { required, deferred } from "./policy-test-helpers";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { fleetPolicyContribution } from "./policy.contribution";
import { admitPolicyPage, type PolicyPage } from "./fleet-policy";
import {
  policyPageFixture,
  policyOperationFixture,
  policyAfterOperation,
} from "./policy-workflow.test-support";
const wrappers: { unmount(): void }[] = [];
afterEach(() => wrappers.splice(0).forEach((w) => w.unmount()));
function harness(page: PolicyPage = policyPageFixture()) {
  let server = structuredClone(page);
  const execute = vi.fn(
    async (action: string, input: Record<string, unknown>): Promise<unknown> => {
      const op = policyOperationFixture(server, action, input);
      server = policyAfterOperation(server, op);
      return op;
    },
  );
  const read = vi.fn(async () => structuredClone(server));
  const wrapper = mount(fleetPolicyContribution.component, {
    props: { page, port: { execute, navigate: vi.fn() }, readPort: { read } },
  });
  wrappers.push(wrapper);
  return {
    wrapper,
    execute,
    read,
    get server() {
      return server;
    },
  };
}
test("semantic policy admission rejects impossible dates and unsafe identity text", () => {
  const page = policyPageFixture();
  const invalidDate = structuredClone(page);
  required(invalidDate.model.grants.entries[0]).valid_until = "2026-02-30T00:00:00Z";
  expect(admitPolicyPage(invalidDate)).toBeNull();
  const invalidId = structuredClone(page);
  required(invalidId.model.identities.entries[0]).id = String.fromCharCode(0xd800);
  expect(admitPolicyPage(invalidId)).toBeNull();
});
test("native saves wait for validation, retain the exact base and accept a real-shaped receipt", async () => {
  const h = harness();
  const { promise, resolve: settle } = deferred<unknown>();
  h.execute.mockImplementationOnce(() => promise);
  await h.wrapper.get("#policy-requirement-concurrency").setValue("5");
  expect(h.execute).toHaveBeenCalledTimes(1);
  await h.wrapper.get("#fleet-policy-form").trigger("submit");
  expect(h.execute).toHaveBeenCalledTimes(1);
  const [action, command] = required(h.execute.mock.calls[0]);
  settle(policyOperationFixture(h.server, action, command));
  await flushPromises();
  expect(h.execute.mock.calls.map((c) => c[0])).toEqual(["validate-policy", "save-policy"]);
  expect(required(h.execute.mock.calls[1])[1]).toMatchObject({
    sequence: 2,
    payload: {
      policy: { requirement_concurrency: "5" },
      edit_reference: { base: { policy_version: 2 } },
    },
  });
  expect(h.wrapper.find("#fleet-policy-operation-receipt").exists()).toBe(true);
  expect(h.wrapper.find("#fleet-policy-edit-unavailable").exists()).toBe(false);
  expect(h.wrapper.get("#policy-requirement-concurrency").element.getAttribute("type")).toBe(
    "number",
  );
  expect(h.read).toHaveBeenCalledOnce();
  expect(h.wrapper.get("#fleet-policy-workflow-notice").text()).toContain("evidence refreshed");
});
test("refresh retains policy, grant and revocation drafts and rejects malformed or foreign models", async () => {
  const h = harness();
  await h.wrapper.get("#policy-requirement-concurrency").setValue("5");
  await flushPromises();
  await h.wrapper.get("#grant-approval-reason").setValue("Keep this reason");
  await flushPromises();
  await h.wrapper.get("#revoke-automation-grant-reason").setValue("Keep revocation reason");
  await h.wrapper.get("#fleet-policy-refresh").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#policy-requirement-concurrency").element as HTMLInputElement).value).toBe(
    "5",
  );
  expect((h.wrapper.get("#grant-approval-reason").element as HTMLInputElement).value).toBe(
    "Keep this reason",
  );
  expect((h.wrapper.get("#revoke-automation-grant-reason").element as HTMLInputElement).value).toBe(
    "Keep revocation reason",
  );
  h.read.mockResolvedValueOnce({
    ...h.server,
    model: { ...h.server.model, context: { ...h.server.model.context, mission_id: "foreign" } },
  });
  await h.wrapper.get("#fleet-policy-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.get("#fleet-policy-workflow-notice").text()).toContain("retained");
  expect(h.wrapper.find("#fleet-policy-form").exists()).toBe(true);
});
test("lost mutation responses recover their matching server receipt through a read without resubmission", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = policyOperationFixture(h.server, action, input);
    h.read.mockResolvedValueOnce(policyAfterOperation(h.server, op));
    throw Error("Lost response");
  });
  await h.wrapper.get("#fleet-policy-approval-reason").setValue("Exact draft");
  await h.wrapper.get("#fleet-policy-approval-form").trigger("submit");
  await flushPromises();
  expect(h.wrapper.find("#fleet-policy-unconfirmed").exists()).toBe(true);
  await h.wrapper.get("#fleet-policy-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#fleet-policy-unconfirmed").exists()).toBe(false);
  expect(h.wrapper.find("#fleet-policy-operation-receipt").exists()).toBe(true);
  expect(h.execute).toHaveBeenCalledOnce();
});
test("unknown effects stay locked and revocation carries the displayed immutable grant reference", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = {
      ...policyOperationFixture(h.server, action, input),
      status: "unconfirmed" as const,
      receipt: null,
    };
    h.read.mockResolvedValue(policyAfterOperation(h.server, op));
    return op;
  });
  await h.wrapper.get("#revoke-automation-grant-reason").setValue("Reviewed grant");
  await h.wrapper.get("#automation-grant-revocation-form").trigger("submit");
  await flushPromises();
  expect(required(h.execute.mock.calls[0])[1]).toMatchObject({
    payload: { grant_evidence: required(h.server.model.grants.entries[0]).reference },
  });
  await h.wrapper.get("#fleet-policy-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#fleet-policy-unconfirmed").exists()).toBe(true);
  expect(h.wrapper.get("fieldset").attributes("disabled")).toBeDefined();
  expect(h.execute).toHaveBeenCalledOnce();
});
test("policy and grant receipt admission rejects a substituted outcome", () => {
  const page = policyPageFixture();
  expect(admitPolicyPage(page)).not.toBeNull();
  const payload = {
    decision: { reason: "Reviewed", policy_evidence: required(page.model.current).reference },
  };
  const op = policyOperationFixture(page, "approve-policy", { sequence: 1, payload });
  expect(admitPolicyPage(policyAfterOperation(page, op))).not.toBeNull();
  if (op.action !== "approve-policy") throw Error("Expected approval fixture");
  const substituted = {
    ...op,
    receipt: { ...op.receipt, result: { ...op.receipt.result, contentSha256: "f".repeat(64) } },
  };
  expect(admitPolicyPage(policyAfterOperation(page, substituted))).toBeNull();
  expect(() =>
    fleetPolicyContribution.read(page, {
      organizationId: "foreign",
      missionId: page.model.context.mission_id,
    }),
  ).toThrow();
});
test("producer-supplied policy contribution sends native payloads and admits completed receipts", async () => {
  if (!process.env.CADENCE_POLICY_WORKFLOW) return;
  const supplied = record(JSON.parse(process.env.CADENCE_POLICY_WORKFLOW));
  const snapshot = record(supplied.snapshot);
  const page = required(admitPolicyPage(snapshot.data));
  const context = record(snapshot.context);
  if (
    typeof context.organizationId !== "string" ||
    typeof context.missionId !== "string" ||
    context.resourceId !== undefined
  )
    throw Error("Invalid producer context");
  expect(
    fleetPolicyContribution.read(page, {
      organizationId: context.organizationId,
      missionId: context.missionId,
    }),
  ).toHaveProperty("page");
  if (typeof supplied.action !== "string") throw Error("Missing producer action");
  const h = harness(page);
  h.execute.mockImplementation(async (action, input) => {
    if (action.startsWith("validate-")) return policyOperationFixture(page, action, input);
    if (supplied.operation) return supplied.operation;
    throw Error("Captured payload");
  });
  const selectors: Record<string, [string, string]> = {
    "save-policy": ["#policy-requirement-concurrency", "#fleet-policy-form"],
    "approve-policy": ["#fleet-policy-approval-reason", "#fleet-policy-approval-form"],
    "issue-grant": ["#grant-approval-reason", "#automation-grant-form"],
    "revoke-grant": ["#revoke-automation-grant-reason", "#automation-grant-revocation-form"],
  };
  const [field, form] = required(selectors[supplied.action]);
  await h.wrapper
    .get(field)
    .setValue(supplied.action === "save-policy" ? "5" : "Reviewed exact producer evidence");
  await flushPromises();
  await h.wrapper.get(form).trigger("submit");
  await flushPromises();
  const call = h.execute.mock.calls.find((c) => c[0] === supplied.action);
  expect(call).toBeDefined();
  if (supplied.operation)
    expect(h.wrapper.find("#fleet-policy-operation-receipt").exists()).toBe(true);
  process.stdout.write(`POLICY_CONTRIBUTION_COMMANDS=${JSON.stringify(h.execute.mock.calls)}\n`);
  process.stdout.write(`POLICY_CONTRIBUTION_INPUT=${JSON.stringify(required(call)[1])}\n`);
});
