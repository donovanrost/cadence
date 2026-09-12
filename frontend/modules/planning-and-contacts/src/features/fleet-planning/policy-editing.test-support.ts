import type {
  FormField,
  OpsFleetPlanningPolicyProps,
  CheckboxField,
} from "./OpsFleetPlanningPolicy.contracts";
import { decisionFixture, evidenceFixture } from "./policy-decisions.test-support";

const field = (
  name: string,
  value: string,
  type: FormField["type"] = "number",
  required = true,
): FormField => ({
  id: "policy-" + name,
  name: "policy[" + name + "]",
  value,
  label: name.replaceAll("_", " "),
  type,
  required,
  min: 0,
  options:
    name === "automation_mode"
      ? ["advisory", "approval_required", "bounded_automatic"].map((value) => ({
          label: value,
          value,
        }))
      : [],
  errors: [],
});
const checkbox = (name: string): CheckboxField => ({
  id: "policy-" + name,
  name: "policy[" + name + "]",
  label: name,
  type: "checkbox",
  value: false,
  errors: [],
});

export function editingFixture(version: number | null = 1): OpsFleetPlanningPolicyProps {
  const props = decisionFixture(version ?? 1);
  props.approval_form = null;
  props.grant_form = null;
  props.page.policy_evidence = version === null ? null : evidenceFixture(version);
  props.policy_form = {
    edit_reference: {
      contract_version: 1,
      organization_id: "org-policy",
      mission_id: "mission-policy",
      base: props.page.policy_evidence,
    },
    panel_id: "fleet-policy-editor",
    id: "fleet-policy-form",
    open: true,
    summary: version === null ? "Create the initial policy" : "Draft a new immutable version",
    fields: {
      max_horizon_duration: field("max_horizon_duration", "1h 30m", "text"),
      requirement_concurrency: field("requirement_concurrency", "8"),
      provider_search_concurrency: field("provider_search_concurrency", "4"),
      reuse_freshness_seconds: field("reuse_freshness_seconds", "300"),
      max_contacts: field("max_contacts", "", "number", false),
      max_estimated_cost_micros: field("max_estimated_cost_micros", "", "number", false),
      currency: field("currency", "USD", "text", false),
      critical_contact_reserve: field("critical_contact_reserve", "0"),
      automation_mode: field("automation_mode", "advisory", "select"),
      execution_concurrency: field("execution_concurrency", "4"),
      max_repair_attempts: field("max_repair_attempts", "3"),
      repair_horizon_duration: field("repair_horizon_duration", "1h 1s", "text"),
      automatic_submission: checkbox("automatic_submission"),
      distinct_provider_required: checkbox("distinct_provider_required"),
      distinct_station_required: checkbox("distinct_station_required"),
      distinct_service_pool_required: checkbox("distinct_service_pool_required"),
    },
    redundancy: { id: "policy-redundancy", summary: "Redundancy constraints" },
    submit: { id: "save-fleet-policy", label: "Create draft version" },
  };
  return props;
}
