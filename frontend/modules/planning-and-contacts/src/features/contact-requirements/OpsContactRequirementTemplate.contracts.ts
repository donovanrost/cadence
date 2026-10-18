export type Option = { label: string; value: string };

export type FormField = {
  id: string;
  name: string;
  type: "text" | "number" | "select" | "textarea" | "datetime-local" | "time";
  label: string;
  required: boolean;
  min: number | null;
  step: string | null;
  options: Option[];
  value: string;
  errors: string[];
};

export type TemplateField =
  | "spacecraft_id"
  | "schedule_type"
  | "anchor_at"
  | "time_utc"
  | "interval_minutes"
  | "window_offset_minutes"
  | "window_duration_minutes"
  | "contact_intent"
  | "success_measure"
  | "minimum_duration_seconds"
  | "preferred_duration_seconds"
  | "minimum_data_volume_bytes"
  | "contact_count"
  | "minimum_separation_seconds"
  | "priority"
  | "approval_mode"
  | "maximum_occurrences_per_run"
  | "maximum_lookback_hours"
  | "rationale";

export type TemplateValues = Record<TemplateField, string>;

export type TemplateForm = {
  panel_id: string;
  id: string;
  header: { eyebrow: string; copy: string };
  fields: Record<TemplateField, FormField>;
  outcome_details: { id: string; summary: string };
  catchup_details: { id: string; summary: string };
  submit: { id: string; label: string };
};

export type LifecycleAction = { id: string; label: string; class: string };

export type RequirementTemplate = {
  id: string;
  __dom_id: string;
  lifecycle: { state: string; class: string };
  version_label: string;
  title: string;
  schedule: string;
  content_sha256: string;
  actions?: {
    pause: LifecycleAction | null;
    activate: LifecycleAction | null;
    close: LifecycleAction | null;
  };
};

export type OpsContactRequirementTemplateProps = {
  page: {
    id: string;
    back: { href: string; icon: string; label: string };
    header: { eyebrow: string; title: string; copy: string };
  };
  ledger: {
    eyebrow: string;
    copy: string;
    count: number;
    count_label: string;
    list_id: string;
    stream_empty_id: string;
    empty: { id: string; icon: string; title: string; copy: string } | null;
  };
  authorization: {
    organization_admin: boolean;
    admin_required: { id: string; copy: string } | null;
  };
  template_form: TemplateForm | null;
  templates: RequirementTemplate[];
};

export type OpsContactRequirementTemplateEmits = {
  "validate-template": [payload: { template: TemplateValues }];
  "create-template": [payload: { template: TemplateValues }];
  "pause-template": [payload: { id: string }];
  "activate-template": [payload: { id: string }];
  "close-template": [payload: { id: string }];
};
