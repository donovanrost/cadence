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
};

export type AccountSummary = {
  id: string;
  ownership_label: string;
  display_name: string;
  version_label: string;
  badge: { status: "ready"; label: string };
  restrictions: { label: string; summary: string }[];
};

export type Accounts = {
  empty: boolean;
  bindings: {
    grant_id: string;
    grant_version: number;
    account_id: string;
    account_version: number;
    summary: AccountSummary;
  }[];
  options: Option[];
  selected: AccountSummary | null;
  empty_state: {
    id: string;
    heading: string;
    message: string;
    action: { id: string; label: string; href: string };
  };
};

export type Notes = {
  secret_boundary: { id: string; text: string };
  resource_boundary: { id: string; text: string };
};

export type Section = {
  id: string;
  number: string;
  title: string;
  field_keys: ProviderFieldKey[];
};

export type Field = {
  key: ProviderFieldKey;
  id: string;
  name: string;
  type: "text" | "number" | "select";
  label: string;
  required: boolean;
  placeholder: string | null;
  min: number | null;
  options: Option[];
  value: string;
};

export type Visibility = {
  field: ProviderFieldKey;
  equals: string;
};

export type ProviderForm = {
  id: string;
  sections: {
    binding: Section;
    resource_scope: Section;
    delivery_policy: Section;
  };
  fields: Record<ProviderFieldKey, Field>;
  conditional: {
    approval_guidance: {
      id: string;
      active: boolean;
      visible_when: Visibility;
      text: string;
    };
    bounded_policy: {
      id: string;
      active: boolean;
      visible_when: Visibility;
      field_keys: ProviderFieldKey[];
    };
  };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

export const providerFieldKeys = [
  "display_name",
  "provider_account_grant_id",
  "permitted_resource_refs",
  "policy_mode",
  "maximum_earlier_start_shift_seconds",
  "maximum_later_start_shift_seconds",
  "maximum_earlier_end_shift_seconds",
  "maximum_later_end_shift_seconds",
  "minimum_retained_duration_seconds",
  "approved_station_substitutions",
  "deadline_behavior",
] as const;

export type ProviderFieldKey = (typeof providerFieldKeys)[number];
export type ProviderValues = Record<ProviderFieldKey, string>;
export type ProviderPayload = { provider: ProviderValues };
