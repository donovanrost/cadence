export type WorkspaceWarning = { code: string; severity: "info" | "warning" | "error" };
export type WorkspaceField = {
  name: string;
  kind: "time" | "number" | "string" | "boolean" | "enum";
  unit: string | null;
  values: Array<number | string | boolean | null>;
};
export type WorkspaceFrame = {
  role: "primary" | "compare" | "limits" | "quality" | "events" | "annotations";
  shape: "scalar" | "wide" | "long" | "events" | "intervals" | "matrix";
  time_axis: "generation_time" | "receipt_time" | "occurred_at" | null;
  fields: WorkspaceField[];
};
export type WorkspaceAnnotation = {
  id: string;
  title: string;
  severity: "info" | "warning" | "error" | "critical";
  kind: "point" | "interval";
  starts_at_ms: number;
  ends_at_ms: number | null;
};
export type WorkspaceWidget = {
  type:
    | "value_tile"
    | "time_series"
    | "status_matrix"
    | "data_table"
    | "state_timeline"
    | "event_timeline"
    | "constellation_health";
  version: 1;
  title: string;
  options: {
    precision: number;
    window_seconds: number;
    show_unit?: boolean;
    show_min_max_band?: boolean;
    legend_mode?: "auto" | "always" | "hidden";
    line_width?: "thin" | "normal" | "bold";
    fill_opacity?: number;
    span_gaps?: boolean;
    show_points?: boolean;
    axis_mode?: "unit" | "shared";
    shared_tooltip?: boolean;
  };
};
export type WorkspacePlacement = {
  id: string;
  authored_id: string;
  section_id: string | null;
  layout: { x: number | null; y: number | null; w: number; h: number };
  status: "ready" | "unavailable";
  reason: null | "unsupported_widget" | "missing_result" | "invalid_frame";
  widget: WorkspaceWidget | null;
  frames: WorkspaceFrame[];
  annotations: WorkspaceAnnotation[];
  warnings: WorkspaceWarning[];
};
export type WorkspaceSnapshot = {
  version: 1;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  document_version: number;
  document_mode: "published" | "draft" | "draft_preview" | "snapshot";
  author: boolean;
  name: string;
  description: string | null;
  grid: { columns: number; row_height_px: number; gap_px: number };
  context: {
    time_mode: "live" | "range" | "archive" | "replay_run";
    time_axis: "generation_time" | "receipt_time";
    from: string | null;
    to: string | null;
    window_seconds: number | null;
    relative_duration_ms: number | null;
    refresh_ms: number | null;
    realm: "flight" | "rehearsal" | "replay" | "simulation";
    data_view: "canonical" | "as_recorded" | "all_revisions" | "recomputed";
    limit_mode: "observed" | "current" | "recomputed" | "compare";
    scope_kind:
      | "mission"
      | "spacecraft"
      | "contact"
      | "ground_station"
      | "source_endpoint"
      | "transport"
      | "link";
    scope_ids: string[];
  };
  sections: Array<{ id: string; title: string; description: string | null; collapsed: boolean }>;
  placements: WorkspacePlacement[];
  warnings: WorkspaceWarning[];
};
