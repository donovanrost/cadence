export type StatusTone = "info" | "ready" | "attention" | "blocked";

export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type Navigation = {
  breadcrumbs: Breadcrumb[];
};

export type SummaryTile = {
  id: string;
  label: string;
  value: string | number;
};

export type Provider = {
  page_id: string;
  display_name: string;
  provider_id: string;
  simulated_badge: {
    id: string;
    label: string;
  };
  version: string;
  summary_tiles: SummaryTile[];
};

export type Action = {
  id: string;
  label: string;
  disabled: boolean;
};

export type Actions = {
  validate: Action;
  sync: Action;
  archive: Action & { confirm: string };
};

export type ProfileSection = {
  id: string;
  heading: string;
  subtitle: string;
  empty: boolean;
  empty_copy: string;
  table_id: string;
  table_body_id: string;
  columns: string[];
};

export type Profiles = {
  service: ProfileSection;
  delivery: ProfileSection;
};

export type Status = {
  tone: StatusTone;
  label: string;
};

export type ServiceProfile = {
  __dom_id: string;
  id: string;
  display_name: string;
  service_kind: string;
  direction: string;
  data_families: string;
  status: Status;
};

export type DeliveryProfile = {
  __dom_id: string;
  id: string;
  display_name: string;
  operator_summary: string;
  delivery_kind: string;
  direction: string;
  status: Status;
};

export type Detail = {
  label: string;
  value: string;
  mono: boolean;
};

export type DetailCard = {
  id: string;
  title: string;
  rows: Detail[];
};

export type Capabilities = {
  id: string;
  title: string;
  empty: boolean;
  empty_copy: string;
  items: Array<{
    label: string;
    status: Status;
  }>;
};

export type Details = {
  configuration: DetailCard;
  delivery_policy: DetailCard;
  capabilities: Capabilities;
  version_history: {
    id: string;
    title: string;
    stream_id: string;
  };
};

export type Diagnostics = {
  id: string;
  label: string;
  json_id: string;
  rows: Detail[];
  json: string;
};

export type ProviderVersion = {
  __dom_id: string;
  version: number;
  lifecycle_state: string;
};

export type ProviderDetailModel = {
  navigation: Navigation;
  provider: Provider;
  actions: Actions;
  profiles: Profiles;
  details: Details;
  diagnostics: Diagnostics;
  service_profiles: ServiceProfile[];
  delivery_profiles: DeliveryProfile[];
  provider_versions: ProviderVersion[];
};
