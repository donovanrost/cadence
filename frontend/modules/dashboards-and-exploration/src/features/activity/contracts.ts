export type VersionSummary = {
  version: number;
  kind: "draft_save" | "publish" | "revert" | "migration";
  parent_version: number | null;
  based_on_version: number | null;
  schema_version: number;
  summary: string;
  actor_id: string | null;
  saved_at: string | null;
};
export type ActivityModel = {
  version: 1;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  name: string;
  document_version: number;
  revision: number;
  published_version: number | null;
  archived: boolean;
  author: boolean;
  query: {
    version: number | null;
    before_version: number | null;
    before_event: string | null;
    issue_id: string | null;
  };
  versions: VersionSummary[];
  next_version: number | null;
  selected: VersionSummary & { name: string; widget_count: number; section_count: number };
  events: {
    id: string;
    event_type: string;
    document_version: number | null;
    actor_id: string | null;
    occurred_at: string | null;
  }[];
  next_event: string | null;
};
export type ActivityState = { sequence: number; phase: "ready" | "review"; model: ActivityModel };
export const activityActions = ["publish_version", "restore_version", "reload_activity"] as const;
export type ActivityAction = (typeof activityActions)[number];
