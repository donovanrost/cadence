import type { FormField, OpsFleetPlanningPolicyProps } from "./OpsFleetPlanningPolicy.contracts";
import type { PolicyEvidence } from "./policy-evidence";

export const evidenceFixture = (version = 1): PolicyEvidence => ({
  contract_version: 1,
  organization_id: "org-policy",
  mission_id: "mission-policy",
  policy_id: "policy-1",
  policy_version: version,
  content_sha256: String(version).repeat(64),
});

const field = (name: string, value: string, type: FormField["type"] = "number"): FormField => ({
  id: "grant-" + name,
  name: "grant[" + name + "]",
  type,
  label: name.replaceAll("_", " "),
  required: true,
  min: type === "number" ? 1 : null,
  options:
    name === "service_identity_id" ? [{ label: "Mission automation", value: "service-1" }] : [],
  value,
  errors: [],
});

export const decisionFixture = (
  currentVersion = 1,
  activeVersion = 1,
): OpsFleetPlanningPolicyProps => ({
  page: {
    policy_evidence: evidenceFixture(currentVersion),
    back: {
      href: "/missions/mission-policy/ops/planning",
      icon: "hero-arrow-left",
      label: "Fleet planning",
    },
    header: {
      eyebrow: "Administrative boundary",
      title: "Fleet Policy & Automation",
      copy: "Review exact policy evidence.",
    },
    state: { id: "fleet-policy-state", label: "active", class: "text-success" },
    manifest: {
      id: "fleet-policy-manifest",
      version_label: "v" + currentVersion,
      content_sha256: evidenceFixture(currentVersion).content_sha256,
      sections: [],
      empty: null,
    },
  },
  policy_form: null,
  approval_form: {
    policy_evidence: evidenceFixture(currentVersion),
    panel_id: "fleet-policy-approval",
    id: "fleet-policy-approval-form",
    reason: {
      ...field("reason", "", "textarea"),
      id: "fleet-policy-approval-reason",
      name: "decision[reason]",
    },
    submit: { id: "approve-fleet-policy", label: "Approve exact v" + currentVersion },
  },
  authorization: { organization_admin: true, admin_required: null },
  grant_ledger: {
    id: "automation-grant-ledger",
    list_id: "automation-grants",
    empty: { id: "automation-grants-empty", copy: "No authority" },
    active_count: 0,
    active_label: "0 active",
  },
  grant_form: {
    policy_evidence: evidenceFixture(activeVersion),
    panel_id: "automation-grant-issuer",
    id: "automation-grant-form",
    fields: {
      service_identity_id: field("service_identity_id", "service-1", "select"),
      maximum_horizon_duration: field("maximum_horizon_duration", "24h", "text"),
      maximum_contacts: field("maximum_contacts", "10"),
      maximum_execution_concurrency: field("maximum_execution_concurrency", "2"),
      valid_days: field("valid_days", "7"),
      approval_reason: field("approval_reason", "", "textarea"),
    },
    submit: { id: "issue-automation-grant", label: "Issue exact grant" },
  },
  revocation_form: null,
  automation_grants: [],
});
