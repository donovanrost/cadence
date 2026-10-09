import type { WorkspaceSnapshot } from "../workspace/contracts";

/** Server-authored widget form values; every value is the form's string encoding. */
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

export type OutlineSection = Readonly<{
  id: string;
  title: string;
  description: string;
  collapsed_by_default: boolean;
}>;

export type OutlinePlacement = Readonly<{
  id: string;
  section_id: string | null;
  title: string;
  editable: boolean;
  fields: WidgetFields | null;
  observables: readonly string[];
  layout: Readonly<{ x: number | null; y: number | null; w: number; h: number }>;
  constraints: Readonly<{
    min_w: number;
    min_h: number;
    max_w: number;
    max_h: number;
    max_y: number;
  }>;
}>;

/** The staged document as an editable outline (the canvas shows its resolved preview). */
export type DashboardOutline = Readonly<{
  version: 3;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  document_version: number;
  name: string;
  description: string;
  defaults: WidgetFields;
  runtime_defaults_json: string;
  grid: Readonly<{ columns: number; row_height_px: number; gap_px: number }>;
  sections: readonly OutlineSection[];
  placements: readonly OutlinePlacement[];
}>;

export type EditSession = Readonly<{
  revision: number;
  dirty: boolean;
  /** Someone else saved a newer version; saving will fail until this candidate is discarded. */
  conflict: boolean;
  /** The saved version this staging transaction will replace. */
  document_version: number;
  outline: DashboardOutline;
}>;

export type Publication = Readonly<{
  latest_version: number;
  published_version: number | null;
  published_at: string | null;
  lifecycle: string;
  state: "unpublished" | "published" | "draft_ahead";
}>;

export type ScopeOption = Readonly<{ id: string; name: string }>;

type PageBase = Readonly<{
  version: 2;
  /** The last confirmed action sequence; the next action must use sequence + 1. */
  sequence: number;
  author: boolean;
  publication: Publication;
  scope_options: readonly ScopeOption[];
  live: Readonly<{ active: boolean; refresh_ms: number | null }>;
  resolved_at: string;
}>;

/**
 * A viewer page has a snapshot unless the dashboard was never published and the
 * reader is not an author. An edit page always resolves its staged candidate.
 */
export type DashboardPageData =
  | (PageBase & { mode: "view"; snapshot: WorkspaceSnapshot | null; edit: null })
  | (PageBase & { mode: "edit"; snapshot: WorkspaceSnapshot; edit: EditSession });

export const stageActions = [
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
] as const;
export type StageAction = (typeof stageActions)[number];
export const pageActions = [...stageActions, "save", "discard", "publish", "search_observables"];

export type LayoutEdit = { placement_id: string; x: number; y: number; w: number; h: number };
export type SectionInput = { title: string; description: string; collapsed_by_default: boolean };
export type WidgetInput = { fields: WidgetFields; observables: string[] };

/** Each staged action's input; the composable adds the observed version and revision. */
export type StageInputs = {
  rename: { name: string; description: string };
  add_section: SectionInput;
  update_section: SectionInput & { section_id: string };
  remove_section: { section_id: string };
  move_section: { section_id: string; direction: "up" | "down" };
  add_widget: WidgetInput;
  update_widget: WidgetInput & { placement_id: string };
  remove_widget: { placement_id: string };
  layout: { layouts: LayoutEdit[] };
  runtime_defaults: { defaults_json: string };
};

export type ActionStatus = "ok" | "invalid" | "conflict" | "rejected" | "unknown";
export type ActionOutcome =
  | { status: "ok"; page: DashboardPageData }
  | { status: "invalid"; code: string; page: DashboardPageData | null }
  | { status: "conflict" | "rejected" | "unknown"; page: DashboardPageData | null };

/** The dashboard details sheet stages a rename and/or new runtime defaults, in order. */
export type DetailsChange = {
  rename: { name: string; description: string } | null;
  defaults: string | null;
};
