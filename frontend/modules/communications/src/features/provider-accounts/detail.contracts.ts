export type EmptyPayload = Record<string, never>;

export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type EmptyState = {
  id: string;
  text: string;
};

export type Page = {
  id: string;
  header: {
    title: string;
    subtitle: string;
    config_label: string;
    breadcrumbs: Breadcrumb[];
  };
  grants: {
    card_id: string;
    heading: string;
    subtitle: string;
    stream_id: string;
    empty: EmptyState;
  };
  grant_form_card: {
    id: string;
    heading: string;
    subtitle: string;
  };
  audit: {
    card_id: string;
    heading: string;
    subtitle: string;
    stream_id: string;
    empty: EmptyState;
  };
};

export type Action = {
  id: string;
  label: string;
  disabled: boolean;
  payload: EmptyPayload;
};

export type Actions = {
  validate: Action & { icon: string };
  rotate: Action & { icon: string };
  revoke: (Action & { confirm: string }) | null;
};

export type Stat = {
  id: string;
  label: string;
  value: string | number;
};

export type Option = {
  label: string;
  value: string;
  disabled: boolean;
};

export type GrantValues = {
  mission_id: string;
  allowed_services: string;
  allowed_stations: string;
  max_quota: string;
  grant_reason: string;
};

export type GrantInputValues = Record<keyof GrantValues, string | number>;

export type GrantField = {
  key: keyof GrantValues;
  id: string;
  name: string;
  type: "select" | "text" | "number";
  label: string;
  value: string;
  required: boolean;
  min: number | null;
  placeholder: string | null;
  options: Option[];
};

export type GrantForm = {
  id: string;
  values: GrantValues;
  fields: Record<keyof GrantValues, GrantField>;
  action: {
    id: string;
    label: string;
  };
};

export type Grant = {
  id: string;
  __dom_id: string;
  provider_account_grant_id: string;
  mission_name: string;
  version_label: string;
  restriction_summary: string | null;
  lifecycle: {
    status: "ready" | "blocked";
    label: string;
  };
  revoke: {
    id: string;
    label: string;
    confirm: string;
    payload: { "grant-id": string };
  } | null;
};

export type AuditEntry = {
  id: string;
  __dom_id: string;
  provider_audit_entry_id: string;
  recorded_at: string;
  action: string;
  outcome: {
    status: "ready" | "blocked";
    label: string;
  };
};

export type Detail = {
  label: string;
  value: string;
  mono: boolean;
  wrapper_id: string | null;
};

export type DetailCard = {
  id: string;
  title: string;
  rows: Detail[];
};

export type Ingestion = DetailCard & {
  description: string;
};

export type Guardrails = {
  id: string;
  title: string;
  json: string;
};

export type Diagnostics = {
  id: string;
  title: string;
  columns: Detail[][];
};

export type ProviderAccountShowProps = {
  page: Page;
  actions: Actions;
  stats: Stat[];
  grant_form: GrantForm;
  configuration: DetailCard;
  ingestion: Ingestion;
  guardrails: Guardrails;
  diagnostics: Diagnostics;
  account_grants: Grant[];
  account_audit: AuditEntry[];
  canGrant?: boolean;
  actionsDisabled?: boolean;
};
