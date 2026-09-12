import type {
  OpsFleetPlanningPolicyProps,
  PolicyForm,
  FormField,
  CheckboxField,
} from "./OpsFleetPlanningPolicy.contracts";
import { duration, type PolicyModel, type PolicyValues } from "./fleet-policy";
const modes = ["advisory", "approval_required", "bounded_automatic"].map((value) => ({
  label: value.replaceAll("_", " "),
  value,
}));
function field(
  group: string,
  name: string,
  id: string,
  label: string,
  value: string,
  type: FormField["type"] = "number",
  required = true,
  min: number | null = 1,
): FormField {
  return {
    id,
    name: `${group}[${name}]`,
    label,
    value,
    type,
    required,
    min: type === "number" ? min : null,
    options: [],
    errors: [],
  };
}
const string = (v: string | number | null | undefined) => (v == null ? "" : String(v));
const flag = (name: string, id: string, label: string, value: boolean): CheckboxField => ({
  id,
  name: `policy[${name}]`,
  label,
  type: "checkbox",
  value,
  errors: [],
});
function fields(v: PolicyValues): PolicyForm["fields"] {
  const f = (
    name: string,
    id: string,
    label: string,
    value: string | number | null | undefined,
    type: FormField["type"] = "number",
    required = true,
    min: number | null = 1,
  ) => field("policy", name, id, label, string(value), type, required, min);
  return {
    max_horizon_duration: f(
      "max_horizon_duration",
      "policy-max-horizon-duration",
      "Maximum horizon",
      duration(v.max_horizon_seconds),
      "text",
    ),
    requirement_concurrency: f(
      "requirement_concurrency",
      "policy-requirement-concurrency",
      "Requirement workers",
      v.requirement_concurrency,
    ),
    provider_search_concurrency: f(
      "provider_search_concurrency",
      "policy-provider-concurrency",
      "Provider workers",
      v.provider_search_concurrency,
    ),
    reuse_freshness_seconds: f(
      "reuse_freshness_seconds",
      "policy-reuse-seconds",
      "Reuse seconds",
      v.reuse_freshness_seconds,
      "number",
      true,
      0,
    ),
    max_contacts: f(
      "max_contacts",
      "policy-max-contacts",
      "Contact ceiling (optional)",
      v.max_contacts,
      "number",
      false,
    ),
    max_estimated_cost_micros: f(
      "max_estimated_cost_micros",
      "policy-max-cost",
      "Cost micros (optional)",
      v.max_estimated_cost_micros,
      "number",
      false,
      0,
    ),
    currency: f("currency", "policy-currency", "Currency", v.currency, "text", false),
    critical_contact_reserve: f(
      "critical_contact_reserve",
      "policy-critical-reserve",
      "Critical reserve",
      v.critical_contact_reserve,
      "number",
      true,
      0,
    ),
    automation_mode: {
      ...f("automation_mode", "policy-automation-mode", "Mode", v.automation_mode, "select"),
      options: modes,
    },
    execution_concurrency: f(
      "execution_concurrency",
      "policy-execution-concurrency",
      "Execution workers",
      v.execution_concurrency,
    ),
    max_repair_attempts: f(
      "max_repair_attempts",
      "policy-repair-attempts",
      "Repair attempts",
      v.max_repair_attempts,
      "number",
      true,
      0,
    ),
    repair_horizon_duration: f(
      "repair_horizon_duration",
      "policy-repair-horizon-duration",
      "Repair horizon",
      duration(v.repair_horizon_seconds),
      "text",
    ),
    automatic_submission: flag(
      "automatic_submission",
      "policy-automatic-submission",
      "Allow exact candidate Plans to be submitted automatically",
      v.automatic_submission,
    ),
    distinct_provider_required: flag(
      "distinct_provider_required",
      "policy-distinct-provider",
      "Distinct providers",
      v.distinct_provider_required,
    ),
    distinct_station_required: flag(
      "distinct_station_required",
      "policy-distinct-station",
      "Distinct stations",
      v.distinct_station_required,
    ),
    distinct_service_pool_required: flag(
      "distinct_service_pool_required",
      "policy-distinct-pool",
      "Distinct service pools",
      v.distinct_service_pool_required,
    ),
  };
}
function sections(v: PolicyValues) {
  const fact = (term: string, value: string | number | null | undefined) => ({
      term,
      value: string(value),
    }),
    yes = (b: boolean) => (b ? "yes" : "no");
  return [
    {
      title: "Horizon & search",
      facts: [
        fact("Maximum horizon", duration(v.max_horizon_seconds)),
        fact("Requirement workers", v.requirement_concurrency),
        fact("Provider workers", v.provider_search_concurrency),
        fact("Evidence reuse", `${v.reuse_freshness_seconds} sec`),
      ],
    },
    {
      title: "Quota & budget",
      facts: [
        fact("Contact ceiling", v.max_contacts ?? "none"),
        fact(
          "Cost ceiling",
          v.max_estimated_cost_micros === null
            ? "none"
            : `${v.max_estimated_cost_micros} ${v.currency} micros`,
        ),
        fact("Critical reserve", v.critical_contact_reserve),
        fact("Default capacity", v.default_exclusive_capacity),
      ],
    },
    {
      title: "Automation",
      facts: [
        fact("Mode", v.automation_mode.replaceAll("_", " ")),
        fact("Automatic submission", yes(v.automatic_submission)),
        fact("Execution workers", v.execution_concurrency),
        fact("Repair attempts", v.max_repair_attempts),
      ],
    },
    {
      title: "Redundancy",
      facts: [
        fact("Distinct provider", yes(v.distinct_provider_required)),
        fact("Distinct station", yes(v.distinct_station_required)),
        fact("Distinct pool", yes(v.distinct_service_pool_required)),
        fact("Repair horizon", duration(v.repair_horizon_seconds)),
      ],
    },
  ];
}
export function policyPresentation(model: PolicyModel): OpsFleetPlanningPolicyProps {
  const current = model.current,
    active = model.active,
    admin = Object.values(model.permissions).some(Boolean),
    mutable = model.state !== "retired";
  const identities = model.identities.entries.map((i) => ({ label: i.name, value: i.id }));
  const grants = model.grants.entries
    .filter((g) => g.state === "active")
    .map((g) => ({ label: g.service_identity_id, value: g.reference.grant_id }));
  const grantField = (
    name: string,
    id: string,
    label: string,
    value: string | number | null | undefined,
    type: FormField["type"] = "number",
  ) => field("grant", name, id, label, string(value), type);
  return {
    page: {
      policy_evidence: current?.reference ?? null,
      back: {
        href: `/missions/${encodeURIComponent(model.context.mission_id)}/ops/planning`,
        icon: "hero-arrow-left",
        label: "Fleet planning",
      },
      header: {
        eyebrow: "Administrative boundary",
        title: "Fleet Policy & Automation",
        copy: "Operators declare mission needs. Organization administrators approve the bounded horizon, capacity, cost, repair, and unattended authority Cadence may use.",
      },
      state: {
        id: "fleet-policy-state",
        label: model.state === "unconfigured" ? "stopped" : model.state,
        class: `border px-2 py-1 font-mono text-xs uppercase ${model.state === "active" ? "border-success/35 bg-success/10 text-success" : "border-primary/35 bg-primary/10 text-primary"}`,
      },
      manifest: {
        id: "fleet-policy-manifest",
        version_label: current ? `v${current.reference.policy_version}` : "not configured",
        content_sha256: current?.reference.content_sha256 ?? null,
        sections: current ? sections(current.values) : [],
        empty: current
          ? null
          : {
              id: "fleet-policy-empty",
              icon: "hero-adjustments-horizontal",
              title: "No scheduling boundary exists",
              copy: "Fleet runs and automation remain stopped until an administrator creates and approves a policy.",
            },
      },
    },
    policy_form:
      model.permissions.edit && mutable
        ? {
            edit_reference: {
              ...model.context,
              contract_version: 1,
              base: current?.reference ?? null,
            },
            panel_id: "fleet-policy-editor",
            id: "fleet-policy-form",
            open: !current,
            summary: current ? "Draft a new immutable version" : "Create the initial policy",
            fields: fields(current?.values ?? model.defaults),
            redundancy: {
              id: "fleet-policy-redundancy-details",
              summary: "Redundancy constraints",
            },
            submit: {
              id: "save-fleet-policy",
              label: current ? "Create draft version" : "Create draft policy",
            },
          }
        : null,
    approval_form:
      model.permissions.approve &&
      current &&
      mutable &&
      current.reference.policy_version !== active?.reference.policy_version
        ? {
            policy_evidence: current.reference,
            panel_id: "fleet-policy-approval",
            id: "fleet-policy-approval-form",
            reason: field(
              "decision",
              "reason",
              "fleet-policy-approval-reason",
              "Approval reason",
              "",
              "textarea",
            ),
            submit: {
              id: "approve-fleet-policy",
              label: `Approve exact v${current.reference.policy_version}`,
            },
          }
        : null,
    authorization: {
      organization_admin: admin,
      admin_required: admin
        ? null
        : { copy: "Organization administrator authority is required to change policy or grants." },
    },
    grant_ledger: {
      id: "automation-grant-ledger",
      list_id: "automation-grants",
      empty: { id: "automation-grants-empty", copy: "No automation authority on this page." },
      active_count: model.grants.active_count,
      active_label: `${model.grants.active_count} active`,
    },
    grant_form:
      model.permissions.grants && active && identities.length
        ? {
            panel_id: "automation-grant-issuer",
            id: "automation-grant-form",
            policy_evidence: active.reference,
            fields: {
              service_identity_id: {
                ...grantField(
                  "service_identity_id",
                  "grant-service-identity",
                  "Mission service identity",
                  identities[0]!.value,
                  "select",
                ),
                options: identities,
              },
              maximum_horizon_duration: grantField(
                "maximum_horizon_duration",
                "grant-max-horizon-duration",
                "Maximum horizon",
                duration(active.values.max_horizon_seconds),
                "text",
              ),
              maximum_contacts: grantField(
                "maximum_contacts",
                "grant-max-contacts",
                "Maximum contacts",
                active.values.max_contacts ?? 100,
              ),
              maximum_execution_concurrency: grantField(
                "maximum_execution_concurrency",
                "grant-execution-concurrency",
                "Execution workers",
                active.values.execution_concurrency,
              ),
              valid_days: grantField("valid_days", "grant-valid-days", "Valid days", "30"),
              approval_reason: grantField(
                "approval_reason",
                "grant-approval-reason",
                "Why this unattended authority is appropriate",
                "",
                "textarea",
              ),
            },
            submit: { id: "issue-automation-grant", label: "Issue exact grant" },
          }
        : null,
    revocation_form:
      model.permissions.grants && grants.length
        ? {
            panel_id: "automation-grant-revoker",
            id: "automation-grant-revocation-form",
            fields: {
              automation_grant_id: {
                ...field(
                  "revocation",
                  "automation_grant_id",
                  "revoke-automation-grant-id",
                  "Active grant",
                  grants[0]!.value,
                  "select",
                ),
                options: grants,
              },
              reason: field(
                "revocation",
                "reason",
                "revoke-automation-grant-reason",
                "Revocation reason",
                "",
                "textarea",
              ),
            },
            submit: { id: "revoke-automation-grant", label: "Revoke immediately" },
          }
        : null,
    automation_grants: model.grants.entries.map((g) => ({
      __dom_id: `automation-grant-${g.reference.grant_id}`,
      automation_grant_id: g.reference.grant_id,
      service_identity_id: g.service_identity_id,
      lifecycle_state: g.state,
      lifecycle_state_class:
        g.state === "active"
          ? "font-mono text-[0.58rem] uppercase text-success"
          : "font-mono text-[0.58rem] uppercase text-base-content/45",
      policy_evidence: `policy v${g.policy_version} · ${g.actions.join(", ")}`,
      boundary: `≤ ${g.maximum_contacts} contacts · ≤ ${duration(g.maximum_horizon_seconds)}`,
      expiry: `expires ${g.valid_until}`,
    })),
  };
}
