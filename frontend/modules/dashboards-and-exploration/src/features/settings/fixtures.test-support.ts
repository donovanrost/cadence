import type { SettingsModel, SettingsState } from "./contracts";
export const settingsContext = {
  organizationId: "org-1",
  missionId: "mission-1",
  resourceId: "dashboard-1",
};
export function settingsModel(): SettingsModel {
  return {
    version: 1,
    organization_id: "org-1",
    mission_id: "mission-1",
    dashboard_id: "dashboard-1",
    document_version: 2,
    revision: 3,
    published_version: 1,
    lifecycle: "active",
    name: "Power",
    description: "",
    tags: ["power"],
    defaults_json: '{"extension":{"retained":true}}',
    loaded_at: "2026-09-07T12:00:00Z",
    query: { after_share: null, after_snapshot: null, after_deployment: null },
    shares: {
      rows: [
        {
          id: "share-1",
          data_visibility: "authorized_runtime_data",
          state: "active",
          expires_at: null,
          created_at: "2026-09-07T11:00:00Z",
        },
      ],
      next: null,
    },
    snapshots: {
      rows: [
        {
          id: "snapshot-1",
          document_version: 1,
          data_visibility: "definition_only",
          data_semantics: "definition_at_version_current_data",
          created_at: "2026-09-07T11:00:00Z",
        },
      ],
      next: null,
    },
    deployments: {
      rows: [
        {
          id: "deployment-1",
          document_version: 1,
          environment: "flight",
          digest_prefix: "abcdef123456",
          status: "exported",
          created_at: "2026-09-07T11:00:00Z",
        },
      ],
      next: null,
    },
  };
}

export function settingsFixture(): SettingsState {
  return { sequence: 0, phase: "ready", model: settingsModel() };
}
