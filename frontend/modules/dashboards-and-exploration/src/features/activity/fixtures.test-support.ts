import type { ActivityState, VersionSummary } from "./contracts";
export const activityContext = {
  organizationId: "org-1",
  missionId: "mission-1",
  resourceId: "dashboard-1",
};
export const versionFixture = (version: number): VersionSummary => ({
  version,
  kind: "draft_save",
  parent_version: version > 1 ? version - 1 : null,
  based_on_version: null,
  schema_version: 1,
  summary: `Saved version ${version}`,
  actor_id: "user-1",
  saved_at: "2026-09-07T12:00:00Z",
});
export const activityFixture = (): ActivityState => ({
  sequence: 0,
  phase: "ready",
  model: {
    version: 1,
    organization_id: "org-1",
    mission_id: "mission-1",
    dashboard_id: "dashboard-1",
    name: "Flight systems",
    document_version: 2,
    revision: 2,
    published_version: null,
    archived: false,
    author: true,
    query: { version: 1, before_version: null, before_event: null, issue_id: null },
    versions: [versionFixture(2), versionFixture(1)],
    next_version: null,
    selected: { ...versionFixture(1), name: "Flight systems", widget_count: 4, section_count: 2 },
    events: [],
    next_event: null,
  },
});
