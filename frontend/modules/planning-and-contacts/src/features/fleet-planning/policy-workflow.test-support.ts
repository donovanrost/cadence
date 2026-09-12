import { admitPolicyCommand } from "./fleet-policy";
import { required, type MutableFixture } from "./policy-test-helpers";
import type {
  PolicyPage,
  PolicyOperation,
  PolicyGrant,
  CompletedPolicyOperation,
} from "./fleet-policy";
import { evidenceFixture } from "./policy-decisions.test-support";
export function policyPageFixture(): MutableFixture<PolicyPage> {
  const values = {
    max_horizon_seconds: 86400,
    requirement_concurrency: 8,
    provider_search_concurrency: 4,
    reuse_freshness_seconds: 300,
    max_contacts: 100,
    max_estimated_cost_micros: null,
    currency: null,
    critical_contact_reserve: 0,
    automation_mode: "bounded_automatic" as const,
    execution_concurrency: 4,
    max_repair_attempts: 3,
    repair_horizon_seconds: 3601,
    automatic_submission: true,
    distinct_provider_required: false,
    distinct_station_required: false,
    distinct_service_pool_required: false,
    default_exclusive_capacity: 1,
  };
  const model = {
    contract_version: 1 as const,
    context: { organization_id: "org-policy", mission_id: "mission-policy" },
    query: { grants_page: 1, identities_page: 1 },
    state: "active" as const,
    current: { reference: evidenceFixture(2), values: { ...values } },
    active: { reference: evidenceFixture(1), values: { ...values } },
    defaults: { ...values },
    permissions: { edit: true, approve: true, grants: true },
    identities: {
      page: 1,
      more: false,
      entries: [{ id: "service-one", name: "Mission automation" }],
    },
    grants: { page: 1, more: false, active_count: 1, entries: [] as MutableFixture<PolicyGrant>[] },
  };
  model.grants.entries.push({
    reference: {
      contract_version: 1,
      ...model.context,
      grant_id: "grant-one",
      content_sha256: "d".repeat(64),
    },
    service_identity_id: "service-one",
    policy_id: "policy-1",
    policy_version: 1,
    state: "active",
    actions: ["plan", "repair", "submit", "execute"],
    maximum_horizon_seconds: 3601,
    maximum_contacts: 10,
    maximum_execution_concurrency: 2,
    maximum_estimated_cost_micros: null,
    currency: null,
    valid_from: "2026-09-09T00:00:00Z",
    valid_until: "2026-09-19T00:00:00Z",
    approved_at: "2026-09-09T00:00:00Z",
    approval_reason: "Reviewed bounded authority",
    revoked_at: null,
    revocation_reason: "",
  });
  return { model, sequence: 0, operation: null };
}
export function policyOperationFixture(
  page: PolicyPage,
  action: unknown,
  command: Record<string, unknown>,
): CompletedPolicyOperation {
  const request = required(admitPolicyCommand(action, command.payload, page.model.context));
  const sequence = command.sequence;
  if (typeof sequence !== "number") throw Error("Missing fixture sequence");
  const completed = { sequence, status: "completed" as const };
  const received = <const T>(result: T) => ({
    receiptId: `receipt-${sequence}`,
    completedAt: "2026-09-09T04:00:00Z",
    result,
  });
  switch (request.action) {
    case "validate-policy":
      return {
        ...request,
        ...completed,
        receipt: received({
          valid: true,
          errors: [],
          surfaceId: "fleet_planning_policy",
          actionId: "validate-policy",
        }),
      };
    case "validate-grant":
      return {
        ...request,
        ...completed,
        receipt: received({
          valid: true,
          errors: [],
          surfaceId: "fleet_planning_policy",
          actionId: "validate-grant",
        }),
      };
    case "save-policy": {
      const base = request.input.edit_reference.base;
      const version = (base?.policy_version ?? 0) + 1;
      return {
        ...request,
        ...completed,
        receipt: received({
          fleetPlanningPolicyId: base?.policy_id ?? "policy-1",
          fleetPlanningPolicyVersion: version,
          currentVersion: version,
          activeVersion: page.model.active?.reference.policy_version ?? null,
          lifecycleState: page.model.state === "active" ? "active" : "draft",
          contentSha256: "a".repeat(64),
        }),
      };
    }
    case "approve-policy": {
      const reference = request.input.decision.policy_evidence;
      return {
        ...request,
        ...completed,
        receipt: received({
          fleetPlanningPolicyId: reference.policy_id,
          fleetPlanningPolicyVersion: reference.policy_version,
          currentVersion: reference.policy_version,
          activeVersion: reference.policy_version,
          lifecycleState: "active",
          contentSha256: reference.content_sha256,
        }),
      };
    }
    case "issue-grant":
      return {
        ...request,
        ...completed,
        receipt: received({
          automationGrantId: "grant-new",
          serviceIdentityId: request.input.grant.service_identity_id,
          lifecycleState: "active",
          fleetPlanningPolicyVersion: request.input.policy_evidence.policy_version,
        }),
      };
    case "revoke-grant":
      return {
        ...request,
        ...completed,
        receipt: received({
          automationGrantId: request.input.grant_evidence.grant_id,
          lifecycleState: "revoked",
        }),
      };
  }
}
export function policyAfterOperation(page: PolicyPage, op: PolicyOperation): PolicyPage {
  let model = page.model;
  if (op.status === "completed") {
    if (op.action === "save-policy") {
      const r = op.receipt.result;
      model = {
        ...model,
        state: model.state === "unconfigured" ? "draft" : model.state,
        current: {
          reference: {
            ...model.context,
            contract_version: 1,
            policy_id: r.fleetPlanningPolicyId,
            policy_version: r.fleetPlanningPolicyVersion,
            content_sha256: r.contentSha256,
          },
          values: {
            ...(model.current?.values ?? model.defaults),
            requirement_concurrency: Number(op.input.policy.requirement_concurrency),
          },
        },
      };
    }
    if (op.action === "approve-policy")
      model = { ...model, active: model.current, state: "active" };
    if (op.action === "revoke-grant") {
      const grantId = op.receipt.result.automationGrantId;
      required(model.grants.entries.find((grant) => grant.reference.grant_id === grantId));
      model = {
        ...model,
        grants: {
          ...model.grants,
          active_count: model.grants.active_count - 1,
          entries: model.grants.entries.map((grant) =>
            grant.reference.grant_id === grantId
              ? {
                  ...grant,
                  state: "revoked",
                  revoked_at: op.receipt.completedAt,
                  revocation_reason: op.input.revocation.reason,
                }
              : grant,
          ),
        },
      };
    }
  }
  return { model, sequence: op.sequence, operation: op };
}
