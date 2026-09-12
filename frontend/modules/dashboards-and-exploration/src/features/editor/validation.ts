import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { readWorkspaceSnapshot } from "../workspace/validation";
import { parseRuntimeDefaults } from "./runtime-defaults";
import { widgetDefaults, type EditorState, type WidgetFields } from "./contracts";
const fail = (): never => {
  throw Error("Invalid dashboard editor state");
};
export function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : fail();
}
function exact(value: unknown, keys: string[]) {
  const r = record(value);
  if (Object.keys(r).length !== keys.length || keys.some((k) => !Object.hasOwn(r, k))) fail();
  return r;
}
function text(value: unknown, max = 512): string {
  if (typeof value !== "string" || new TextEncoder().encode(value).length > max) fail();
  return value as string;
}
function id(value: unknown): string {
  const s = text(value, 256);
  return s && !/[\u0000-\u001f]/.test(s) ? s : fail();
}
function integer(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max
    ? value
    : fail();
}
function bool(value: unknown): boolean {
  return typeof value === "boolean" ? value : fail();
}
function list(value: unknown, max: number): unknown[] {
  return Array.isArray(value) && value.length <= max ? value : fail();
}
function unique(ids: string[]) {
  if (new Set(ids).size !== ids.length) fail();
}
export function readObservableChoices(
  value: unknown,
  context: OpsPageContext,
  version: number,
  query: string,
  revision: number,
) {
  const r = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "dashboard_id",
    "document_version",
    "staging_revision",
    "query",
    "options",
    "more",
  ]);
  if (
    r.version !== 2 ||
    r.staging_revision !== revision ||
    r.organization_id !== context.organizationId ||
    r.mission_id !== context.missionId ||
    r.dashboard_id !== context.resourceId ||
    r.document_version !== version ||
    r.query !== query
  )
    fail();
  const options = list(r.options, 50).map((value) => {
    const option = exact(value, ["value", "label", "description"]);
    return {
      value: id(option.value),
      label: text(option.label),
      description: text(option.description, 4096),
    };
  });
  unique(options.map((o) => o.value));
  return { options, more: bool(r.more) };
}
const enums: Partial<Record<keyof WidgetFields, string[]>> = {
  type: [
    "value_tile",
    "time_series",
    "status_matrix",
    "data_table",
    "state_timeline",
    "event_timeline",
    "constellation_health",
  ],
  mode: ["context", "fixed", "scope", "repeat"],
  binding_source: ["telemetry", "limits", "operational_observables", "events"],
  legend_mode: ["auto", "always", "hidden"],
  line_width: ["thin", "normal", "bold"],
  axis_mode: ["unit", "shared"],
  repeat_over: ["spacecraft", "contact", "ground_station", "transport", "link"],
  repeat_layout: ["wrap_grid", "row", "column"],
  scope_kind: [
    "",
    "mission",
    "spacecraft",
    "contact",
    "ground_station",
    "source_endpoint",
    "transport",
    "link",
  ],
};
function fields(value: unknown): WidgetFields {
  const f = exact(value, Object.keys(widgetDefaults));
  for (const [key, value] of Object.entries(f)) {
    text(value);
    if (
      enums[key as keyof WidgetFields] &&
      !enums[key as keyof WidgetFields]!.includes(value as string)
    )
      fail();
  }
  for (const k of ["show_unit", "show_min_max_band", "span_gaps", "show_points", "shared_tooltip"])
    if (!["true", "false"].includes(f[k] as string)) fail();
  for (const k of ["precision", "window_seconds", "fill_opacity", "repeat_max_instances"])
    if (!/^(0|[1-9][0-9]{0,4})$/.test(f[k] as string)) fail();
  return f as WidgetFields;
}
export function readEditor(value: unknown, context: OpsPageContext): EditorState {
  const s = exact(value, ["version", "sequence", "phase", "revision", "dirty", "model"]);
  if (s.version !== 2) fail();
  integer(s.revision, 0, 1_000_000);
  bool(s.dirty);
  integer(s.sequence, 0, 1_000_000);
  if (!["editing", "review"].includes(s.phase as string)) fail();
  const m = exact(s.model, [
    "version",
    "organization_id",
    "mission_id",
    "dashboard_id",
    "document_version",
    "name",
    "description",
    "defaults",
    "runtime_defaults_json",
    "grid",
    "sections",
    "placements",
    "preview",
  ]);
  if (
    m.version !== 3 ||
    id(m.organization_id) !== context.organizationId ||
    id(m.mission_id) !== context.missionId ||
    id(m.dashboard_id) !== context.resourceId
  )
    fail();
  integer(m.document_version, 1, Number.MAX_SAFE_INTEGER - 1);
  text(m.name);
  text(m.description, 4096);
  fields(m.defaults);
  parseRuntimeDefaults(m.runtime_defaults_json);
  const grid = exact(m.grid, ["columns", "row_height_px", "gap_px"]);
  integer(grid.columns, 1, 48);
  integer(grid.row_height_px, 1, 1024);
  integer(grid.gap_px, 0, 128);
  const sections = list(m.sections, 64).map((v) => {
    const r = exact(v, ["id", "title", "description", "collapsed_by_default"]);
    id(r.id);
    text(r.title);
    text(r.description, 4096);
    bool(r.collapsed_by_default);
    return r;
  });
  const sectionIds = sections.map((s) => s.id as string);
  unique(sectionIds);
  const placements = list(m.placements, 1024).map((v) => {
    const p = exact(v, [
      "id",
      "section_id",
      "title",
      "editable",
      "fields",
      "observables",
      "layout",
      "constraints",
    ]);
    id(p.id);
    text(p.title);
    bool(p.editable);
    if (p.section_id !== null && !sectionIds.includes(id(p.section_id))) fail();
    if (p.editable) {
      const f = fields(p.fields);
      if (f.section_id !== (p.section_id ?? "") || f.title !== p.title) fail();
    } else if (p.fields !== null) fail();
    const observables = list(p.observables, 24).map(id);
    unique(observables);
    if (!p.editable && observables.length) fail();
    const l = exact(p.layout, ["x", "y", "w", "h"]);
    if (l.x !== null) integer(l.x, 0, 47);
    if (l.y !== null) integer(l.y, 0, 100_000);
    integer(l.w, 1, 48);
    integer(l.h, 1, 1024);
    const bounds = exact(p.constraints, ["min_w", "min_h", "max_w", "max_h", "max_y"]);
    integer(bounds.min_w, 1, grid.columns as number);
    integer(bounds.min_h, 1, 1024);
    if (bounds.max_w !== grid.columns) fail();
    integer(bounds.max_h, bounds.min_h as number, 1024);
    integer(bounds.max_y, 0, 100000);
    return p;
  });
  unique(placements.map((p) => p.id as string));
  if (m.preview !== null) {
    const preview = readWorkspaceSnapshot(m.preview, context);
    if (preview.document_mode !== "draft" || preview.document_version !== m.document_version)
      fail();
  }
  return s as unknown as EditorState;
}
