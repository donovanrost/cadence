import type { WorkspaceSnapshot } from "../workspace/contracts";

export const widgetDefaults = {
  type: "value_tile",
  title: "",
  mode: "context",
  spacecraft_id: "",
  scope_kind: "",
  scope_id: "",
  section_id: "",
  binding_source: "telemetry",
  precision: "2",
  window_seconds: "300",
  show_unit: "true",
  show_min_max_band: "true",
  legend_mode: "auto",
  line_width: "normal",
  fill_opacity: "0",
  span_gaps: "false",
  show_points: "false",
  axis_mode: "unit",
  shared_tooltip: "true",
  repeat_over: "spacecraft",
  repeat_layout: "wrap_grid",
  repeat_max_instances: "12",
};
export type WidgetFields = typeof widgetDefaults;
export type EditorSection = {
  id: string;
  title: string;
  description: string;
  collapsed_by_default: boolean;
};
export type EditorPlacement = {
  id: string;
  section_id: string | null;
  title: string;
  editable: boolean;
  fields: WidgetFields | null;
  observables: string[];
  layout: { x: number | null; y: number | null; w: number; h: number };
  constraints: { min_w: number; min_h: number; max_w: number; max_h: number; max_y: number };
};
export type EditorModel = {
  version: 3;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  document_version: number;
  name: string;
  description: string;
  defaults: WidgetFields;
  runtime_defaults_json: string;
  grid: { columns: number; row_height_px: number; gap_px: number };
  sections: EditorSection[];
  placements: EditorPlacement[];
  preview: WorkspaceSnapshot | null;
};
export type EditorState = {
  version: 2;
  sequence: number;
  phase: "editing" | "review";
  revision: number;
  dirty: boolean;
  model: EditorModel;
};
export const editorActions = [
  "rename",
  "add_section",
  "update_section",
  "remove_section",
  "move_section",
  "add_widget",
  "update_widget",
  "remove_widget",
  "layout",
  "runtime_defaults",
  "save_draft",
  "discard_draft",
  "reload_editor",
] as const;
export type EditorAction = (typeof editorActions)[number];
