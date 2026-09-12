import type { WorkspaceSnapshot } from "../../workspace";
export type SharedViewKind = "share" | "snapshot";
export type SharedView = {
  version: 1;
  organization_id: string;
  mission_id: string;
  id: string;
  kind: SharedViewKind;
  dashboard_id: string;
  data_visibility: "definition_only" | "authorized_runtime_data";
  data_semantics:
    | "published_definition_current_data"
    | "definition_at_version_current_data"
    | "frozen_time_window";
  created_at: string;
  expires_at: string | null;
  loaded_at: string;
  runtime_context: Record<string, string>;
  definition: null | {
    name: string;
    description: string;
    version: number;
    placements: number;
    sections: number;
    json: string;
  };
  canvas: WorkspaceSnapshot | null;
};
