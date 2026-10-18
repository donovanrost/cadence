import { expect, test, vi } from "vite-plus/test";
import { createPolicyActionPort } from "./policy-action-port";
import type { PolicyCommand, PolicyInputs } from "./fleet-policy";
import { admitPolicyOperation } from "./fleet-policy";
import { policyOperationFixture, policyPageFixture } from "./policy-workflow.test-support";
import { required } from "./policy-test-helpers";

const page = policyPageFixture();
const evidence = required(page.model.current).reference;
const grant = {
  service_identity_id: "service-one",
  maximum_horizon_duration: "1h 1s",
  maximum_contacts: "10",
  maximum_execution_concurrency: "2",
  valid_days: "7",
  approval_reason: "Reviewed bounds",
};
const policy: PolicyInputs["save-policy"]["policy"] = {
  max_horizon_duration: "1d",
  requirement_concurrency: "8",
  provider_search_concurrency: "4",
  reuse_freshness_seconds: "300",
  max_contacts: "",
  max_estimated_cost_micros: "",
  currency: "USD",
  critical_contact_reserve: "0",
  automation_mode: "advisory",
  execution_concurrency: "4",
  max_repair_attempts: "3",
  repair_horizon_duration: "1h 1s",
  automatic_submission: "false",
  distinct_provider_required: "false",
  distinct_station_required: "false",
  distinct_service_pool_required: "false",
};
const edit_reference = { contract_version: 1 as const, ...page.model.context, base: evidence };
const commands = [
  { action: "validate-policy", input: { policy, edit_reference } },
  { action: "save-policy", input: { policy, edit_reference } },
  {
    action: "approve-policy",
    input: { decision: { reason: "Reviewed draft", policy_evidence: evidence } },
  },
  { action: "validate-grant", input: { grant } },
  { action: "issue-grant", input: { grant, policy_evidence: evidence } },
  {
    action: "revoke-grant",
    input: {
      revocation: { automation_grant_id: "grant-one", reason: "Reviewed revocation" },
      grant_evidence: required(page.model.grants.entries[0]).reference,
    },
  },
] satisfies PolicyCommand[];

test.each(commands)("admits the exact native $action request and receipt", async (command) => {
  const request = { ...command, sequence: 3 };
  const operation = policyOperationFixture(page, command.action, {
    sequence: 3,
    payload: command.input,
  });
  const execute = vi.fn(async () => operation);
  const port = createPolicyActionPort({ execute }, page.model.context);
  await expect(port.execute(request)).resolves.toEqual(operation);
  expect(execute).toHaveBeenCalledExactlyOnceWith(command.action, {
    sequence: 3,
    payload: command.input,
  });
  expect(admitPolicyOperation({ ...operation, receipt: null }, page.model.context)).toBeNull();
  expect(
    admitPolicyOperation(
      { ...operation, status: "unconfirmed", receipt: null },
      page.model.context,
    ),
  ).toMatchObject({ status: "unconfirmed", receipt: null });
});

test("the transport rejects substituted sequence, draft, context, and receipt result", async () => {
  const command = required(commands.find((command) => command.action === "approve-policy"));
  const operation = policyOperationFixture(page, command.action, {
    sequence: 3,
    payload: command.input,
  });
  const request = { ...command, sequence: 3 };
  for (const response of [
    { ...operation, sequence: 4 },
    { ...operation, input: { decision: { ...command.input.decision, reason: "Another draft" } } },
    {
      ...operation,
      input: {
        decision: {
          ...command.input.decision,
          policy_evidence: { ...evidence, mission_id: "foreign" },
        },
      },
    },
    {
      ...operation,
      receipt: {
        ...operation.receipt,
        result: { automationGrantId: "wrong-result", lifecycleState: "active" },
      },
    },
  ]) {
    const port = createPolicyActionPort({ execute: async () => response }, page.model.context);
    await expect(port.execute(request)).rejects.toThrow(
      "Different or unavailable policy operation",
    );
  }
});
