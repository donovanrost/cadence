import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { parseRuntimeDefaults } from "../../shared/runtime-defaults";
import { readWorkspaceSnapshot } from "../workspace/validation";
import {
  widgetDefaults,
  type ActionOutcome,
  type DashboardOutline,
  type DashboardPageData,
  type EditSession,
  type OutlinePlacement,
  type OutlineSection,
  type Publication,
  type ScopeOption,
  type WidgetFields,
} from "./contracts";

function fail(): never {
  throw Error("Invalid dashboard page");
}
export function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : fail();
}
function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const r = record(value);
  if (Object.keys(r).length !== keys.length || keys.some((k) => !Object.hasOwn(r, k))) fail();
  return r;
}
function text(value: unknown, max = 512): string {
  return typeof value === "string" && new TextEncoder().encode(value).length <= max
    ? value
    : fail();
}
function id(value: unknown): string {
  const s = text(value, 256);
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
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
function oneOf<T extends string>(value: unknown, values: readonly T[]): T {
  return values.find((v) => v === value) ?? fail();
}
function unique(ids: readonly string[]) {
  if (new Set(ids).size !== ids.length) fail();
}
function timestamp(value: unknown): string {
  const s = text(value, 64);
  return Number.isNaN(Date.parse(s)) ? fail() : s;
}

const fieldEnums: Partial<Record<keyof WidgetFields, readonly string[]>> = {
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
const booleanFields = [
  "show_unit",
  "show_min_max_band",
  "span_gaps",
  "show_points",
  "shared_tooltip",
] as const;
const integerFields = [
  "precision",
  "window_seconds",
  "fill_opacity",
  "repeat_max_instances",
] as const;

export function readWidgetFields(value: unknown): WidgetFields {
  const r = exact(value, Object.keys(widgetDefaults));
  const fields = { ...widgetDefaults };
  for (const key of Object.keys(widgetDefaults) as (keyof WidgetFields)[]) {
    const decoded = text(r[key]);
    const choices = fieldEnums[key];
    if (choices && !choices.includes(decoded)) fail();
    fields[key] = decoded;
  }
  for (const key of booleanFields) if (!["true", "false"].includes(fields[key])) fail();
  for (const key of integerFields) if (!/^(0|[1-9][0-9]{0,4})$/.test(fields[key])) fail();
  return fields;
}

function readSection(value: unknown): OutlineSection {
  const r = exact(value, ["id", "title", "description", "collapsed_by_default"]);
  return {
    id: id(r.id),
    title: text(r.title),
    description: text(r.description, 4096),
    collapsed_by_default: bool(r.collapsed_by_default),
  };
}

function readPlacement(
  value: unknown,
  sections: readonly string[],
  columns: number,
): OutlinePlacement {
  const p = exact(value, [
    "id",
    "section_id",
    "title",
    "editable",
    "fields",
    "observables",
    "layout",
    "constraints",
  ]);
  const editable = bool(p.editable);
  const sectionId = p.section_id === null ? null : id(p.section_id);
  if (sectionId !== null && !sections.includes(sectionId)) fail();
  const title = text(p.title);
  const fields = editable ? readWidgetFields(p.fields) : p.fields === null ? null : fail();
  if (fields && (fields.section_id !== (sectionId ?? "") || fields.title !== title)) fail();
  const observables = list(p.observables, 24).map(id);
  unique(observables);
  if (!editable && observables.length) fail();
  const l = exact(p.layout, ["x", "y", "w", "h"]);
  const c = exact(p.constraints, ["min_w", "min_h", "max_w", "max_h", "max_y"]);
  const minH = integer(c.min_h, 1, 1024);
  if (c.max_w !== columns) fail();
  return {
    id: id(p.id),
    section_id: sectionId,
    title,
    editable,
    fields,
    observables,
    layout: {
      x: l.x === null ? null : integer(l.x, 0, 47),
      y: l.y === null ? null : integer(l.y, 0, 100_000),
      w: integer(l.w, 1, 48),
      h: integer(l.h, 1, 1024),
    },
    constraints: {
      min_w: integer(c.min_w, 1, columns),
      min_h: minH,
      max_w: columns,
      max_h: integer(c.max_h, minH, 1024),
      max_y: integer(c.max_y, 0, 100_000),
    },
  };
}

export function readOutline(value: unknown, context: OpsPageContext): DashboardOutline {
  const m = exact(value, [
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
  ]);
  if (
    m.version !== 3 ||
    id(m.organization_id) !== context.organizationId ||
    id(m.mission_id) !== context.missionId ||
    id(m.dashboard_id) !== context.resourceId
  )
    fail();
  const runtimeDefaults = text(m.runtime_defaults_json, 32 * 1024);
  parseRuntimeDefaults(runtimeDefaults);
  const g = exact(m.grid, ["columns", "row_height_px", "gap_px"]);
  const grid = {
    columns: integer(g.columns, 1, 48),
    row_height_px: integer(g.row_height_px, 1, 1024),
    gap_px: integer(g.gap_px, 0, 128),
  };
  const sections = list(m.sections, 64).map(readSection);
  const sectionIds = sections.map((s) => s.id);
  unique(sectionIds);
  const placements = list(m.placements, 1024).map((p) =>
    readPlacement(p, sectionIds, grid.columns),
  );
  unique(placements.map((p) => p.id));
  return {
    version: 3,
    organization_id: context.organizationId,
    mission_id: context.missionId,
    dashboard_id: id(m.dashboard_id),
    document_version: integer(m.document_version, 1),
    name: text(m.name),
    description: text(m.description, 4096),
    defaults: readWidgetFields(m.defaults),
    runtime_defaults_json: runtimeDefaults,
    grid,
    sections,
    placements,
  };
}

function readEdit(value: unknown, context: OpsPageContext): EditSession {
  const e = exact(value, ["revision", "dirty", "conflict", "document_version", "outline"]);
  return {
    revision: integer(e.revision, 0, 1_000_000),
    dirty: bool(e.dirty),
    conflict: bool(e.conflict),
    document_version: integer(e.document_version, 1),
    outline: readOutline(e.outline, context),
  };
}

function readPublication(value: unknown): Publication {
  const p = exact(value, [
    "latest_version",
    "published_version",
    "published_at",
    "lifecycle",
    "state",
  ]);
  const latest = integer(p.latest_version, 1);
  const published = p.published_version === null ? null : integer(p.published_version, 1, latest);
  const state = oneOf(p.state, ["unpublished", "published", "draft_ahead"] as const);
  if ((state === "unpublished") !== (published === null)) fail();
  if (state === "published" && published !== latest) fail();
  return {
    latest_version: latest,
    published_version: published,
    published_at: p.published_at === null ? null : timestamp(p.published_at),
    lifecycle: text(p.lifecycle, 64),
    state,
  };
}

function readScopeOption(value: unknown): ScopeOption {
  const o = exact(value, ["id", "name"]);
  return { id: id(o.id), name: text(o.name) };
}

export function readDashboardPage(value: unknown, context: OpsPageContext): DashboardPageData {
  const d = exact(value, [
    "version",
    "mode",
    "author",
    "publication",
    "snapshot",
    "scope_options",
    "live",
    "edit",
    "sequence",
    "resolved_at",
  ]);
  if (d.version !== 2) fail();
  const live = exact(d.live, ["active", "refresh_ms"]);
  const scopeOptions = list(d.scope_options, 1000).map(readScopeOption);
  unique(scopeOptions.map((o) => o.id));
  const base = {
    version: 2 as const,
    sequence: integer(d.sequence, 0, 1_000_000),
    author: bool(d.author),
    publication: readPublication(d.publication),
    scope_options: scopeOptions,
    live: {
      active: bool(live.active),
      refresh_ms: live.refresh_ms === null ? null : integer(live.refresh_ms, 1000, 60_000),
    },
    resolved_at: timestamp(d.resolved_at),
  };
  const snapshot = d.snapshot === null ? null : readWorkspaceSnapshot(d.snapshot, context);
  if (oneOf(d.mode, ["view", "edit"] as const) === "view") {
    if (d.edit !== null) fail();
    return { ...base, mode: "view", snapshot, edit: null };
  }
  if (!snapshot || !base.author || base.live.active) fail();
  const edit = readEdit(d.edit, context);
  return { ...base, mode: "edit", snapshot, edit };
}

export function readActionOutcome(value: unknown, context: OpsPageContext): ActionOutcome {
  const r = record(value);
  const status = oneOf(r.status, ["ok", "invalid", "conflict", "rejected", "unknown"] as const);
  const page = record(r.page ?? {}).status === "ready" ? readEnvelopeData(r.page, context) : null;
  if (status === "ok") return page ? { status, page } : fail();
  if (status === "invalid") return { status, code: text(r.code ?? "invalid_input", 64), page };
  return { status, page };
}

function readEnvelopeData(value: unknown, context: OpsPageContext): DashboardPageData {
  const envelope = record(value);
  return readDashboardPage(envelope.data, context);
}

export function readObservableChoices(
  value: unknown,
  context: OpsPageContext,
  expected: { version: number; revision: number; query: string },
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
    r.staging_revision !== expected.revision ||
    r.organization_id !== context.organizationId ||
    r.mission_id !== context.missionId ||
    r.dashboard_id !== context.resourceId ||
    r.document_version !== expected.version ||
    r.query !== expected.query
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
