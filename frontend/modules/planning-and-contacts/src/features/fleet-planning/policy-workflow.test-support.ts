import type { PolicyAction, PolicyPage, PolicyOperation, PolicyGrant } from "./fleet-policy";
import { evidenceFixture } from "./policy-decisions.test-support";
export function policyPageFixture(): PolicyPage {
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
    grants: { page: 1, more: false, active_count: 1, entries: [] as PolicyGrant[] },
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
  action: PolicyAction,
  command: any,
): PolicyOperation {
  const input = JSON.parse(JSON.stringify(command.payload));
  let result: any;
  const reference = page.model.current?.reference;
  if (action === "validate-policy" || action === "validate-grant")
    result = { valid: true, errors: [], surfaceId: "fleet_planning_policy", actionId: action };
  if (action === "save-policy")
    result = {
      fleetPlanningPolicyId: reference?.policy_id ?? "policy-1",
      fleetPlanningPolicyVersion: (input.edit_reference.base?.policy_version ?? 0) + 1,
      currentVersion: (input.edit_reference.base?.policy_version ?? 0) + 1,
      activeVersion: page.model.active?.reference.policy_version ?? null,
      lifecycleState: page.model.state === "unconfigured" ? "draft" : page.model.state,
      contentSha256: "a".repeat(64),
    };
  if (action === "approve-policy")
    result = {
      fleetPlanningPolicyId: reference!.policy_id,
      fleetPlanningPolicyVersion: reference!.policy_version,
      currentVersion: reference!.policy_version,
      activeVersion: reference!.policy_version,
      lifecycleState: "active",
      contentSha256: reference!.content_sha256,
    };
  if (action === "issue-grant")
    result = {
      automationGrantId: "grant-new",
      serviceIdentityId: input.grant.service_identity_id,
      lifecycleState: "active",
      fleetPlanningPolicyVersion: input.policy_evidence.policy_version,
    };
  if (action === "revoke-grant")
    result = { automationGrantId: input.grant_evidence.grant_id, lifecycleState: "revoked" };
  return {
    sequence: command.sequence,
    action,
    input,
    status: "completed",
    receipt: {
      receiptId: `receipt-${command.sequence}`,
      completedAt: "2026-09-09T04:00:00Z",
      result,
    },
  };
}
export function policyAfterOperation(page: PolicyPage, op: PolicyOperation): PolicyPage {
  const next: PolicyPage = JSON.parse(JSON.stringify(page));
  next.sequence = op.sequence;
  next.operation = op;
  if (op.status !== "completed") return next;
  const r = op.receipt!.result;
  if (op.action === "save-policy") {
    next.model.current = {
      reference: {
        ...next.model.context,
        contract_version: 1,
        policy_id: r.fleetPlanningPolicyId,
        policy_version: r.fleetPlanningPolicyVersion,
        content_sha256: r.contentSha256,
      },
      values: {
        ...(next.model.current?.values ?? next.model.defaults),
        requirement_concurrency: Number(op.input.policy.requirement_concurrency),
      },
    };
    if (next.model.state === "unconfigured") next.model.state = "draft";
  }
  if (op.action === "approve-policy") {
    next.model.active = next.model.current;
    next.model.state = "active";
  }
  if (op.action === "revoke-grant") {
    const grant = next.model.grants.entries.find(
      (g) => g.reference.grant_id === r.automationGrantId,
    )!;
    grant.state = "revoked";
    grant.revoked_at = op.receipt!.completedAt;
    grant.revocation_reason = op.input.revocation.reason;
    next.model.grants.active_count--;
  }
  return next;
}
