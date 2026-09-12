import type { PolicyEditReference, PolicyEvidence } from "./policy-evidence";

export type Option = {
  label: string;
  value: string;
};

export type FormField = {
  id: string;
  name: string;
  type: "text" | "number" | "select" | "textarea";
  label: string;
  required: boolean;
  min: number | null;
  options: Option[];
  value: string;
  errors: string[];
};

export type CheckboxField = {
  id: string;
  name: string;
  type: "checkbox";
  label: string;
  value: boolean;
  errors: string[];
};

export type PolicyForm = {
  edit_reference: PolicyEditReference;
  panel_id: string;
  id: string;
  open: boolean;
  summary: string;
  fields: {
    max_horizon_duration: FormField;
    requirement_concurrency: FormField;
    provider_search_concurrency: FormField;
    reuse_freshness_seconds: FormField;
    max_contacts: FormField;
    max_estimated_cost_micros: FormField;
    currency: FormField;
    critical_contact_reserve: FormField;
    automation_mode: FormField;
    execution_concurrency: FormField;
    max_repair_attempts: FormField;
    repair_horizon_duration: FormField;
    automatic_submission: CheckboxField;
    distinct_provider_required: CheckboxField;
    distinct_station_required: CheckboxField;
    distinct_service_pool_required: CheckboxField;
  };
  redundancy: {
    id: string;
    summary: string;
  };
  submit: {
    id: string;
    label: string;
  };
};

export type ApprovalForm = {
  policy_evidence: PolicyEvidence;
  panel_id: string;
  id: string;
  reason: FormField;
  submit: {
    id: string;
    label: string;
  };
};

export type GrantForm = {
  policy_evidence: PolicyEvidence;
  panel_id: string;
  id: string;
  fields: {
    service_identity_id: FormField;
    maximum_horizon_duration: FormField;
    maximum_contacts: FormField;
    maximum_execution_concurrency: FormField;
    valid_days: FormField;
    approval_reason: FormField;
  };
  submit: {
    id: string;
    label: string;
  };
};

export type RevocationForm = {
  panel_id: string;
  id: string;
  fields: {
    automation_grant_id: FormField;
    reason: FormField;
  };
  submit: {
    id: string;
    label: string;
  };
};

export type AutomationGrant = {
  __dom_id: string;
  automation_grant_id: string;
  service_identity_id: string;
  lifecycle_state: string;
  lifecycle_state_class: string;
  policy_evidence: string;
  boundary: string;
  expiry: string;
};

export type PolicyValues = {
  max_horizon_duration: string | number;
  requirement_concurrency: string | number;
  provider_search_concurrency: string | number;
  reuse_freshness_seconds: string | number;
  max_contacts: string | number;
  max_estimated_cost_micros: string | number;
  currency: string;
  critical_contact_reserve: string | number;
  automation_mode: string;
  execution_concurrency: string | number;
  max_repair_attempts: string | number;
  repair_horizon_duration: string | number;
  automatic_submission: boolean;
  distinct_provider_required: boolean;
  distinct_station_required: boolean;
  distinct_service_pool_required: boolean;
};

export type GrantValues = {
  service_identity_id: string;
  maximum_horizon_duration: string | number;
  maximum_contacts: string | number;
  maximum_execution_concurrency: string | number;
  valid_days: string | number;
  approval_reason: string;
};

export type PolicyFields = { [K in keyof PolicyValues]: string };
export type GrantFields = { [K in keyof GrantValues]: string };

export type OpsFleetPlanningPolicyProps = {
  confirmedPolicyEvidence?: PolicyEvidence | null;
  confirmedGrantEvidence?: PolicyEvidence | null;
  confirmedGrantSequence?: number;
  page: {
    policy_evidence: PolicyEvidence | null;
    back: {
      href: string;
      icon: string;
      label: string;
    };
    header: {
      eyebrow: string;
      title: string;
      copy: string;
    };
    state: {
      id: string;
      label: string;
      class: string;
    };
    manifest: {
      id: string;
      version_label: string;
      content_sha256: string | null;
      sections: Array<{
        title: string;
        facts: Array<{
          term: string;
          value: string;
        }>;
      }>;
      empty: {
        id: string;
        icon: string;
        title: string;
        copy: string;
      } | null;
    };
  };
  policy_form: PolicyForm | null;
  approval_form: ApprovalForm | null;
  authorization: {
    organization_admin: boolean;
    admin_required: {
      copy: string;
    } | null;
  };
  grant_ledger: {
    id: string;
    list_id: string;
    empty: {
      id: string;
      copy: string;
    };
    active_count: number;
    active_label: string;
  };
  grant_form: GrantForm | null;
  revocation_form: RevocationForm | null;
  automation_grants: AutomationGrant[];
};

export type OpsFleetPlanningPolicyEmits = {
  "validate-policy": [payload: { policy: PolicyFields; edit_reference: PolicyEditReference }];
  "save-policy": [payload: { policy: PolicyFields; edit_reference: PolicyEditReference }];
  "approve-policy": [payload: { decision: { reason: string; policy_evidence: PolicyEvidence } }];
  "validate-grant": [payload: { grant: GrantFields }];
  "issue-grant": [payload: { grant: GrantFields; policy_evidence: PolicyEvidence }];
  "revoke-grant": [payload: { revocation: { automation_grant_id: string; reason: string } }];
};
