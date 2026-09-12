export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type Page = {
  id: string;
  title: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

export type Option = {
  label: string;
  value: string;
  disabled: boolean;
};

export type Section = {
  id: string;
  number: string;
  title: string;
};

export type FormValue = string | number | boolean;

export type Field = {
  key: string;
  id: string;
  name: string;
  type: "hidden" | "text" | "number" | "select" | "checkbox";
  label: string;
  required: boolean;
  placeholder: string | null;
  options: Option[];
  value: string;
  provider_managed_id: string | null;
};

export type Visibility = {
  field: string;
  equals: string;
} | null;

export type ConfigurationField = {
  key: string;
  wrapper_id: string;
  id: string;
  name: string;
  type: "text" | "number" | "select" | "checkbox";
  label: string;
  required: boolean;
  placeholder: string | null;
  help: string | null;
  step: string | number | null;
  min: number | null;
  max: number | null;
  default: string;
  value: string;
  options: Option[];
  visible: boolean;
  visible_when: Visibility;
};

export type ConfigurationSection = Section & {
  fields_id: string;
  description: string | null;
  fields: ConfigurationField[];
};

export type DirectConfiguration = {
  id: string;
  kind: string;
  description: string | null;
  active: boolean;
  sections: ConfigurationSection[];
};

export type Provider = {
  active: boolean;
  profile_fields_id: string;
  ready_count: number;
  versions: { id: string; version: number }[];
  selected: {
    display_name: string;
    version: number;
    status: "ready";
    status_label: string;
  } | null;
  empty_state: {
    id: string;
    visible: boolean;
    message: string;
    action: { label: string; href: string };
  };
  operator_summary: {
    id: string;
    label: string;
    text: string;
    endpoint: string;
  } | null;
  derivation_error: string | null;
};

export type Detail = {
  label: string;
  value: string;
  mono: boolean;
};

export type ProviderDerived = {
  active: boolean;
  id: string;
  number: string;
  title: string;
  description: string;
  configuration: {
    id: string;
    rows: Detail[];
    empty_text: string | null;
  };
};

export type Review = {
  configuration_summary_id: string;
  ownership: { label: string; value: string; source: string };
  readiness: {
    label: string;
    status: "ready" | "attention";
    value: string;
    endpoint: string;
  };
  error: string | null;
  error_id: string;
  diagnostics: { id: string; label: string; json_id: string; json: string };
};

export type TransportForm = {
  id: string;
  selected_origin: "direct" | "provider_managed";
  can_submit: boolean;
  sections: {
    identity: Section;
    origin: Section;
    source: Section;
    provider_capability: Section;
    review: Section;
  };
  fields: Record<string, Field>;
  origin_cards: { value: string; label: string; description: string }[];
  direct_configuration: DirectConfiguration;
  provider: Provider;
  provider_derived: ProviderDerived;
  review: Review;
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

export type TransportValues = Record<string, string>;
export type TransportPayload = { transport: TransportValues };
