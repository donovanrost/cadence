export const fixedFieldKeys = [
  "provider_account_id",
  "credential_ref",
  "display_name",
  "provider_type",
  "backend_type",
  "backend_key",
  "allowed_services",
  "allowed_directions",
  "allowed_stations",
  "max_quota",
] as const;
export type FixedFieldKey = (typeof fixedFieldKeys)[number];
export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type Page = {
  id: string;
  heading: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

export type Option = {
  label: string;
  value: string;
  disabled: boolean;
};

export type BackendPresentation = {
  label: string;
  placeholder: string;
};

export type Visibility = {
  field: string;
  equals: string;
} | null;

export type Reference = {
  provider_id: string;
  version: number;
  mode: string;
  result_limit: number;
} | null;

export type Field = {
  key: string;
  id: string;
  name: string;
  type: "hidden" | "text" | "textarea" | "number" | "url" | "select";
  label: string | null;
  required: boolean;
  placeholder: string | null;
  min: number | null;
  max: number | null;
  step: string | null;
  options: Option[];
  presentations?: Record<string, BackendPresentation>;
  value: string;
  wrapper_id?: string;
  help?: string | null;
  default?: string;
  reference?: Reference;
  visible_when?: Visibility;
};

export type Section = {
  id: string;
  number: string;
  title: string;
  field_keys: FixedFieldKey[];
};

export type ConfigurationSection = {
  id: string;
  fields_id: string;
  number: string;
  title: string;
  description: string | null;
  fields: Field[];
};

export type Connector = {
  options: Option[];
  selected: {
    id: string;
    form_value: string;
    provider_type: string;
    client_key: string;
    label: string;
    description: string;
  };
  configuration: {
    id: string;
    kind: string;
    description: string | null;
    sections: ConfigurationSection[];
  };
  boundary: { id: string; text: string };
};

export type ProviderAccountForm = {
  id: string;
  hidden_field_keys: FixedFieldKey[];
  sections: {
    network_identity: Section;
    credential_registry: Section;
    organization_guardrails: Section;
  };
  fields: Record<FixedFieldKey, Field>;
  connector: Connector;
  credential_note: { id: string; text: string };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

export type ProviderAccountValues = Record<string, string>;
export type ProviderAccountPayload = { provider_account: ProviderAccountValues };
