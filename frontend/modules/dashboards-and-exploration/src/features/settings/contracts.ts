export type Visibility = "authorized_runtime_data" | "definition_only";
export type SettingsPage<T> = { rows: T[]; next: string | null };
export type SettingsQuery = {
  after_share: string | null;
  after_snapshot: string | null;
  after_deployment: string | null;
};
export type SettingsShare = {
  id: string;
  data_visibility: Visibility;
  state: "active" | "expired" | "revoked";
  expires_at: string | null;
  created_at: string;
};
export type SettingsSnapshot = {
  id: string;
  document_version: number;
  data_visibility: Visibility;
  data_semantics: "definition_at_version_current_data" | "frozen_time_window";
  created_at: string;
};
export type SettingsDeployment = {
  id: string;
  document_version: number;
  environment: string;
  digest_prefix: string;
  status: "validated" | "exported";
  created_at: string;
};
export type SettingsModel = {
  version: 1;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  document_version: number;
  revision: number;
  published_version: number | null;
  lifecycle: "active" | "archived";
  name: string;
  description: string;
  tags: string[];
  defaults_json: string;
  loaded_at: string;
  query: SettingsQuery;
  shares: SettingsPage<SettingsShare>;
  snapshots: SettingsPage<SettingsSnapshot>;
  deployments: SettingsPage<SettingsDeployment>;
};

export type SettingsState = { sequence: number; phase: "ready" | "review"; model: SettingsModel };
export const settingsActions = [
  "save_settings",
  "create_share",
  "revoke_share",
  "create_snapshot",
  "archive_dashboard",
  "reload_settings",
  "page_settings",
] as const;
export type SettingsAction = (typeof settingsActions)[number];
export type SettingsReceipt = {
  version: 1;
  dashboard_id: string;
  event: SettingsAction;
  document_version: number;
  revision: number;
  resource_id: string | null;
};
