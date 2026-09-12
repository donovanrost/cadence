import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { WorkspaceSnapshot, WorkspaceWarning } from "./contracts";
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const encoder = new TextEncoder(),
  decoder = new TextDecoder();
const text = (v: unknown, max = 256): v is string =>
  typeof v === "string" &&
  encoder.encode(v).length <= max &&
  decoder.decode(encoder.encode(v)) === v;
const id = (v: unknown): v is string => text(v) && v.length > 0;
const integer = (v: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): v is number =>
  Number.isSafeInteger(v) && (v as number) >= min && (v as number) <= max;
const nullable = (v: unknown, check: (v: unknown) => boolean) => v === null || check(v);
const one = (v: unknown, values: readonly unknown[]) => values.includes(v);
const array = (v: unknown, max: number): v is unknown[] => Array.isArray(v) && v.length <= max;
const keys = (v: Record<string, unknown>, names: string[]) =>
  Object.keys(v).length === names.length && names.every((k) => Object.hasOwn(v, k));
const unique = (values: unknown[]) => new Set(values).size === values.length;
function warnings(value: unknown): value is WorkspaceWarning[] {
  return (
    array(value, 128) &&
    value.every(
      (w) =>
        record(w) &&
        keys(w, ["code", "severity"]) &&
        typeof w.code === "string" &&
        /^[a-z][a-z0-9_]{0,127}$/.test(w.code) &&
        one(w.severity, ["info", "warning", "error"]),
    )
  );
}
function frame(value: unknown): boolean {
  if (
    !record(value) ||
    !keys(value, ["role", "shape", "time_axis", "fields"]) ||
    !one(value.role, ["primary", "compare", "limits", "quality", "events", "annotations"]) ||
    !one(value.shape, ["scalar", "wide", "long", "events", "intervals", "matrix"]) ||
    !one(value.time_axis, [null, "generation_time", "receipt_time", "occurred_at"]) ||
    !array(value.fields, 64)
  )
    return false;
  const lengths: number[] = [],
    names: unknown[] = [];
  for (const f of value.fields) {
    if (
      !record(f) ||
      !keys(f, ["name", "kind", "unit", "values"]) ||
      !id(f.name) ||
      !nullable(f.unit, (v) => text(v, 128)) ||
      !one(f.kind, ["time", "number", "string", "boolean", "enum"]) ||
      !array(f.values, 10000)
    )
      return false;
    names.push(f.name);
    lengths.push(f.values.length);
    if (
      !f.values.every(
        (v) =>
          v === null ||
          (f.kind === "time"
            ? integer(v, -Number.MAX_SAFE_INTEGER)
            : f.kind === "number"
              ? typeof v === "number" &&
                Number.isFinite(v) &&
                (!Number.isInteger(v) || Number.isSafeInteger(v))
              : f.kind === "boolean"
                ? typeof v === "boolean"
                : text(v, 4096)),
      )
    )
      return false;
  }
  return unique(names) && new Set(lengths).size <= 1;
}
function widget(value: unknown): boolean {
  if (
    !record(value) ||
    !keys(value, ["type", "version", "title", "options"]) ||
    value.version !== 1 ||
    !one(value.type, [
      "value_tile",
      "time_series",
      "status_matrix",
      "data_table",
      "state_timeline",
      "event_timeline",
      "constellation_health",
    ]) ||
    !text(value.title, 4096) ||
    !record(value.options)
  )
    return false;
  const opts = value.options;
  const allowed = [
    "precision",
    "window_seconds",
    "show_unit",
    "show_min_max_band",
    "legend_mode",
    "line_width",
    "fill_opacity",
    "span_gaps",
    "show_points",
    "axis_mode",
    "shared_tooltip",
  ];
  if (
    Object.keys(opts).some((k) => !allowed.includes(k)) ||
    !integer(opts.precision, 0, 6) ||
    !integer(opts.window_seconds, 1, 86400)
  )
    return false;
  for (const key of [
    "show_unit",
    "show_min_max_band",
    "span_gaps",
    "show_points",
    "shared_tooltip",
  ]) {
    if (Object.hasOwn(opts, key) && typeof opts[key] !== "boolean") return false;
  }
  return (
    (!Object.hasOwn(opts, "legend_mode") || one(opts.legend_mode, ["auto", "always", "hidden"])) &&
    (!Object.hasOwn(opts, "line_width") || one(opts.line_width, ["thin", "normal", "bold"])) &&
    (!Object.hasOwn(opts, "fill_opacity") || integer(opts.fill_opacity, 0, 30)) &&
    (!Object.hasOwn(opts, "axis_mode") || one(opts.axis_mode, ["unit", "shared"]))
  );
}
function annotation(value: unknown): boolean {
  return (
    record(value) &&
    keys(value, ["id", "title", "severity", "kind", "starts_at_ms", "ends_at_ms"]) &&
    id(value.id) &&
    text(value.title, 4096) &&
    one(value.severity, ["info", "warning", "error", "critical"]) &&
    one(value.kind, ["point", "interval"]) &&
    integer(value.starts_at_ms, -Number.MAX_SAFE_INTEGER) &&
    (value.kind === "point"
      ? value.ends_at_ms === null
      : nullable(value.ends_at_ms, (v) => integer(v, value.starts_at_ms as number)))
  );
}
export function readWorkspaceSnapshot(value: unknown, context: OpsPageContext): WorkspaceSnapshot {
  const invalid = () => {
    throw new Error("Invalid dashboard workspace snapshot.");
  };
  if (
    !record(value) ||
    !keys(value, [
      "version",
      "organization_id",
      "mission_id",
      "dashboard_id",
      "document_version",
      "document_mode",
      "author",
      "name",
      "description",
      "grid",
      "context",
      "sections",
      "placements",
      "warnings",
    ]) ||
    value.version !== 1 ||
    !id(value.organization_id) ||
    value.organization_id !== context.organizationId ||
    !id(value.mission_id) ||
    value.mission_id !== context.missionId ||
    !id(value.dashboard_id) ||
    value.dashboard_id !== context.resourceId ||
    !integer(value.document_version, 1) ||
    !one(value.document_mode, ["published", "draft", "draft_preview", "snapshot"]) ||
    typeof value.author !== "boolean" ||
    (["draft", "draft_preview"].includes(value.document_mode as string) && !value.author) ||
    !text(value.name, 4096) ||
    !nullable(value.description, (v) => text(v, 16384)) ||
    !record(value.grid) ||
    !keys(value.grid, ["columns", "row_height_px", "gap_px"]) ||
    !integer(value.grid.columns, 1, 48) ||
    !integer(value.grid.row_height_px, 1, 1024) ||
    !integer(value.grid.gap_px, 0, 128) ||
    !record(value.context) ||
    !array(value.sections, 64) ||
    !array(value.placements, 1024) ||
    !warnings(value.warnings)
  )
    return invalid();
  const c = value.context;
  if (
    !keys(c, [
      "time_mode",
      "time_axis",
      "from",
      "to",
      "window_seconds",
      "relative_duration_ms",
      "refresh_ms",
      "realm",
      "data_view",
      "limit_mode",
      "scope_kind",
      "scope_ids",
    ]) ||
    !one(c.time_mode, ["live", "range", "archive", "replay_run"]) ||
    !one(c.time_axis, ["generation_time", "receipt_time"]) ||
    !nullable(c.from, (v) => text(v, 128)) ||
    !nullable(c.to, (v) => text(v, 128)) ||
    !nullable(c.window_seconds, (v) => integer(v, 1, 86400)) ||
    !nullable(c.relative_duration_ms, (v) => integer(v, 1, 86400000)) ||
    !nullable(c.refresh_ms, (v) => integer(v, 0, 86400000)) ||
    !one(c.realm, ["flight", "rehearsal", "replay", "simulation"]) ||
    !one(c.data_view, ["canonical", "as_recorded", "all_revisions", "recomputed"]) ||
    !one(c.limit_mode, ["observed", "current", "recomputed", "compare"]) ||
    !one(c.scope_kind, [
      "mission",
      "spacecraft",
      "contact",
      "ground_station",
      "source_endpoint",
      "transport",
      "link",
    ]) ||
    !array(c.scope_ids, 1024) ||
    !c.scope_ids.every(id) ||
    !unique(c.scope_ids)
  )
    return invalid();
  const sectionIds: unknown[] = [];
  for (const s of value.sections) {
    if (
      !record(s) ||
      !keys(s, ["id", "title", "description", "collapsed"]) ||
      !id(s.id) ||
      !text(s.title, 4096) ||
      !nullable(s.description, (v) => text(v, 16384)) ||
      typeof s.collapsed !== "boolean"
    )
      return invalid();
    sectionIds.push(s.id);
  }
  if (!unique(sectionIds)) return invalid();
  const placementIds: unknown[] = [];
  for (const p of value.placements) {
    if (
      !record(p) ||
      !keys(p, [
        "id",
        "authored_id",
        "section_id",
        "layout",
        "status",
        "reason",
        "widget",
        "frames",
        "annotations",
        "warnings",
      ]) ||
      !id(p.id) ||
      !id(p.authored_id) ||
      !(p.section_id === null || sectionIds.includes(p.section_id)) ||
      !record(p.layout) ||
      !keys(p.layout, ["x", "y", "w", "h"]) ||
      !nullable(p.layout.x, (v) => integer(v, 0, 100000)) ||
      !nullable(p.layout.y, (v) => integer(v, 0, 100000)) ||
      !integer(p.layout.w, 1, 48) ||
      !integer(p.layout.h, 1, 1024) ||
      !array(p.frames, 384) ||
      !p.frames.every(frame) ||
      !array(p.annotations, 1000) ||
      !p.annotations.every(annotation) ||
      !warnings(p.warnings)
    )
      return invalid();
    if (p.status === "ready") {
      if (p.reason !== null || !widget(p.widget)) return invalid();
    } else if (
      p.status !== "unavailable" ||
      !one(p.reason, ["unsupported_widget", "missing_result", "invalid_frame"]) ||
      p.widget !== null ||
      p.frames.length ||
      p.annotations.length ||
      p.warnings.length
    )
      return invalid();
    placementIds.push(p.id);
  }
  if (!unique(placementIds)) return invalid();
  return value as unknown as WorkspaceSnapshot;
}
