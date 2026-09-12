export type Option = {
  label: string;
  value: string;
};

export type FormField = {
  id: string;
  name: string;
  type: "datetime-local" | "number" | "select" | "text" | "textarea";
  label: string;
  required: boolean;
  value: string;
  options?: Option[];
  min?: string;
  placeholder?: string;
  maxlength?: string;
};

export type FieldName =
  | "spacecraft_id"
  | "contact_intent"
  | "earliest_start"
  | "latest_end"
  | "success_measure"
  | "minimum_duration_seconds"
  | "preferred_duration_seconds"
  | "minimum_data_volume_bytes"
  | "contact_count"
  | "minimum_separation_seconds"
  | "priority"
  | "allowed_providers"
  | "excluded_providers"
  | "allowed_stations"
  | "excluded_stations"
  | "rationale";

export type ContactRequirementValues = Record<FieldName, string>;

export type Page = {
  id: string;
  eyebrow: string;
  heading: string;
  description: string;
};

export type JourneySection = {
  id: string;
  step: string;
  title: string;
  copy: string;
};

export type ProgressiveSection = {
  id: string;
  visible: boolean;
  visible_for: string[];
};

export type Journey = {
  outcome: JourneySection;
  horizon: JourneySection;
  advanced: {
    id: string;
    title: string;
    copy: string;
  };
  rationale: { id: string };
  progressive: {
    minimum_data_volume: ProgressiveSection;
    minimum_duration: ProgressiveSection;
  };
};

export type ContactRequirementForm = {
  id: string;
  fields: Record<FieldName, FormField>;
  error: {
    id: string;
    message: string;
  } | null;
};

export type Actions = {
  back: {
    id: string;
    label: string;
    href: string;
    icon: string;
  };
  cancel: {
    id: string;
    label: string;
    href: string;
  };
  submit: {
    id: string;
    label: string;
  };
};

export type ContactRequirementPayload = {
  contact_requirement: ContactRequirementValues;
};

export type OpsContactRequirementNewProps = {
  page: Page;
  journey: Journey;
  form: ContactRequirementForm;
  actions: Actions;
};

export type OpsContactRequirementNewEmits = {
  validate: [payload: ContactRequirementPayload];
  save: [payload: ContactRequirementPayload];
};
