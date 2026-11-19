import { DecodeError, decoders as d, type Decoded, type Reader } from "@/api/index.ts";

/**
 * Readers for the resolved dashboard snapshot: `Cadence.Reads.Dashboards.WorkspaceSnapshot`
 * (version 1), passed through unchanged by D5 (viewer) and D7 (preview). Ported from the module's
 * `workspace/validation.ts`, with the same bounds and relationships: aligned frame columns, unique
 * ids, sections that exist, and ready vs unavailable placements. Vocabularies use `known`
 * (typing rule 1): a value the server adds reads as `unrecognized` and degrades one widget or
 * one label instead of failing the whole dashboard.
 */

const MAX_SAFE = Number.MAX_SAFE_INTEGER;

const bounded =
  (min: number, max: number): Reader<number> =>
  (value, path = "") => {
    const n = d.integer(value, path);
    if (!Number.isSafeInteger(n) || n < min || n > max)
      throw new DecodeError(path, `integer ${min}..${max}`);
    return n;
  };

const text =
  (max: number): Reader<string> =>
  (value, path = "") => {
    const s = d.string(value, path);
    if (s.length > max) throw new DecodeError(path, `text of at most ${max} characters`);
    return s;
  };

const unique =
  <T>(read: Reader<readonly T[]>, key: (item: T) => unknown): Reader<readonly T[]> =>
  (value, path = "") => {
    const items = read(value, path);
    if (new Set(items.map(key)).size !== items.length) throw new DecodeError(path, "unique ids");
    return items;
  };

const warning = d.object({
  code: (value, path = "") => {
    const code = d.string(value, path);
    if (!/^[a-z][a-z0-9_]{0,127}$/.test(code)) throw new DecodeError(path, "warning code");
    return code;
  },
  severity: d.known(["info", "warning", "error"] as const),
});
const warnings = d.array(warning, 128);

const fieldKinds = d.known(["time", "number", "string", "boolean", "enum"] as const);
type FieldKind = Decoded<typeof fieldKinds>;
type FieldValue = number | string | boolean | null;

function cell(kind: FieldKind): Reader<FieldValue> {
  return (value, path = "") => {
    if (value === null) return null;
    switch (kind) {
      case "time":
        return bounded(-MAX_SAFE, MAX_SAFE)(value, path);
      case "number": {
        const n = d.number(value, path);
        if (Number.isInteger(n) && !Number.isSafeInteger(n))
          throw new DecodeError(path, "safe number");
        return n;
      }
      case "boolean":
        return d.boolean(value, path);
      case "string":
      case "enum":
        return text(4096)(value, path);
      case "unrecognized":
        // A column kind this console doesn't know: keep any JSON scalar, render it as text.
        if (typeof value === "string") return text(4096)(value, path);
        if (typeof value === "boolean") return value;
        return d.number(value, path);
    }
  };
}

/** First pass reads the column's kind; the second reads each cell for that kind. */
const anything: Reader<unknown> = (value) => value;
const fieldShape = d.object({
  name: d.token,
  kind: fieldKinds,
  unit: d.nullable(text(128)),
  values: d.array(anything, 10_000),
});
const field: Reader<{
  readonly name: string;
  readonly kind: FieldKind;
  readonly unit: string | null;
  readonly values: readonly FieldValue[];
}> = (value, path = "") => {
  const raw = fieldShape(value, path);
  const read = cell(raw.kind);
  return { ...raw, values: raw.values.map((v, i) => read(v, `${path}.values[${i}]`)) };
};

const frameShape = d.object({
  role: d.known(["primary", "compare", "limits", "quality", "events", "annotations"] as const),
  shape: d.known(["scalar", "wide", "long", "events", "intervals", "matrix"] as const),
  time_axis: d.nullable(d.known(["generation_time", "receipt_time", "occurred_at"] as const)),
  fields: unique(d.array(field, 64), (f) => f.name),
});
const frame: Reader<Decoded<typeof frameShape>> = (value, path = "") => {
  const f = frameShape(value, path);
  if (new Set(f.fields.map((x) => x.values.length)).size > 1)
    throw new DecodeError(`${path}.fields`, "columns of equal length");
  return f;
};

const annotation: Reader<Decoded<typeof annotationShape>> = (value, path = "") => {
  const a = annotationShape(value, path);
  const valid =
    a.kind === "point"
      ? a.ends_at_ms === null
      : a.ends_at_ms === null || a.ends_at_ms >= a.starts_at_ms;
  if (!valid) throw new DecodeError(`${path}.ends_at_ms`, "end consistent with kind");
  return a;
};
const annotationShape = d.object({
  id: d.token,
  title: text(4096),
  severity: d.known(["info", "warning", "error", "critical"] as const),
  kind: d.known(["point", "interval"] as const),
  starts_at_ms: bounded(-MAX_SAFE, MAX_SAFE),
  ends_at_ms: d.nullable(bounded(-MAX_SAFE, MAX_SAFE)),
});

export const widgetTypes = [
  "value_tile",
  "time_series",
  "status_matrix",
  "data_table",
  "state_timeline",
  "event_timeline",
  "constellation_health",
] as const;

const widget = d.object({
  type: d.known(widgetTypes),
  version: d.literal(1),
  title: text(4096),
  options: d.object({
    precision: bounded(0, 6),
    window_seconds: bounded(1, 86_400),
    show_unit: d.optional(d.boolean),
    show_min_max_band: d.optional(d.boolean),
    legend_mode: d.optional(d.known(["auto", "always", "hidden"] as const)),
    line_width: d.optional(d.known(["thin", "normal", "bold"] as const)),
    fill_opacity: d.optional(bounded(0, 30)),
    span_gaps: d.optional(d.boolean),
    show_points: d.optional(d.boolean),
    axis_mode: d.optional(d.known(["unit", "shared"] as const)),
    shared_tooltip: d.optional(d.boolean),
  }),
});

const layout = d.object({
  x: d.nullable(bounded(0, 100_000)),
  y: d.nullable(bounded(0, 100_000)),
  w: bounded(1, 48),
  h: bounded(1, 1024),
});
const placementBase = {
  id: d.token,
  authored_id: d.token,
  section_id: d.nullable(d.token),
  layout,
};

const readyPlacement = d.object({
  ...placementBase,
  status: d.literal("ready"),
  reason: nullValue,
  widget,
  frames: d.array(frame, 384),
  annotations: d.array(annotation, 1000),
  warnings,
});
const unavailablePlacement = d.object({
  ...placementBase,
  status: d.literal("unavailable"),
  reason: d.known(["unsupported_widget", "missing_result", "invalid_frame"] as const),
  widget: nullValue,
  frames: emptyList,
  annotations: emptyList,
  warnings: emptyList,
});
function nullValue(value: unknown, path = ""): null {
  if (value !== null) throw new DecodeError(path, "null");
  return null;
}
function emptyList(value: unknown, path = ""): readonly never[] {
  if (!Array.isArray(value) || value.length > 0) throw new DecodeError(path, "empty list");
  return [];
}
export const placement = d.variant("status", {
  ready: readyPlacement,
  unavailable: unavailablePlacement,
});

export const context = d.object({
  time_mode: d.known(["live", "range", "archive", "replay_run"] as const),
  time_axis: d.known(["generation_time", "receipt_time"] as const),
  from: d.nullable(text(128)),
  to: d.nullable(text(128)),
  window_seconds: d.nullable(bounded(1, 86_400)),
  relative_duration_ms: d.nullable(bounded(1, 86_400_000)),
  refresh_ms: d.nullable(bounded(0, 86_400_000)),
  realm: d.known(["flight", "rehearsal", "replay", "simulation"] as const),
  data_view: d.known(["canonical", "as_recorded", "all_revisions", "recomputed"] as const),
  limit_mode: d.known(["observed", "current", "recomputed", "compare"] as const),
  scope_kind: d.known([
    "mission",
    "spacecraft",
    "contact",
    "ground_station",
    "source_endpoint",
    "transport",
    "link",
  ] as const),
  scope_ids: unique(d.array(d.token, 1024), (id) => id),
});

const section = d.object({
  id: d.token,
  title: text(4096),
  description: d.nullable(text(16_384)),
  collapsed: d.boolean,
});

const snapshotShape = d.object({
  version: d.literal(1),
  organization_id: d.token,
  mission_id: d.token,
  dashboard_id: d.token,
  document_version: bounded(1, MAX_SAFE),
  document_mode: d.known(["published", "draft", "draft_preview", "snapshot"] as const),
  author: d.boolean,
  name: text(4096),
  description: d.nullable(text(16_384)),
  grid: d.object({
    columns: bounded(1, 48),
    row_height_px: bounded(1, 1024),
    gap_px: bounded(0, 128),
  }),
  context,
  sections: unique(d.array(section, 64), (s) => s.id),
  placements: unique(d.array(placement, 1024), (p) => p.id),
  warnings,
});

/** A snapshot whose placements only name sections it has. Staged documents need an author. */
export const workspaceSnapshot: Reader<Decoded<typeof snapshotShape>> = (value, path = "") => {
  const s = snapshotShape(value, path);
  const sections = new Set(s.sections.map((x) => x.id));
  s.placements.forEach((p, i) => {
    if (p.section_id !== null && !sections.has(p.section_id))
      throw new DecodeError(`${path}.placements[${i}].section_id`, "a section of this dashboard");
  });
  if ((s.document_mode === "draft" || s.document_mode === "draft_preview") && !s.author)
    throw new DecodeError(`${path}.author`, "author for a staged document");
  return s;
};

export type WorkspaceSnapshot = Decoded<typeof workspaceSnapshot>;
export type WorkspacePlacement = WorkspaceSnapshot["placements"][number];
export type ReadyPlacement = Extract<WorkspacePlacement, { status: "ready" }>;
export type WorkspaceWidget = ReadyPlacement["widget"];
export type WorkspaceFrame = ReadyPlacement["frames"][number];
export type WorkspaceAnnotation = ReadyPlacement["annotations"][number];
export type WorkspaceWarning = Decoded<typeof warning>;
export type WorkspaceField = Decoded<typeof field>;
export type WidgetType = (typeof widgetTypes)[number];
