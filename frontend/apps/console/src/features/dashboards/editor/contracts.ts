import { decoders as d, type Decoded, type Reader } from "@/api";
import { workspaceSnapshot } from "../model/snapshot.ts";

/**
 * Editor contracts (plans/dashboards.md, D7–D13; domain `Dashboards.StatelessAuthoring`). A draft
 * is `{base_version, commands}`; each command is what `AuthoringInput.admit` accepts, without
 * `expected_version` (the call carries `base_version`). Commands are also what the browser stores,
 * so one reader serves both the wire and local storage.
 */

/** The widget form, every value in its string encoding (server `AuthoringInput` @widget_keys). */
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
} as const;
export type WidgetFieldKey = keyof typeof widgetDefaults;
export type WidgetFields = Readonly<Record<WidgetFieldKey, string>>;

const text =
  (max: number): Reader<string> =>
  (value, path = "") => {
    const s = d.string(value, path);
    if (s.length > max) throw new d.DecodeError(path, `at most ${max} characters`);
    return s;
  };
export const widgetFields: Reader<WidgetFields> = (value, path = "") => {
  const shape = Object.fromEntries(Object.keys(widgetDefaults).map((k) => [k, text(512)]));
  // A decoder adapter: the reader above read exactly the WidgetFieldKey keys, each as a string.
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- keys built from widgetDefaults (§12 A1)
  return d.object(shape)(value, path) as WidgetFields;
};

const id = d.token;
const layoutEdit = d.object({
  placement_id: id,
  x: d.integer,
  y: d.integer,
  w: d.integer,
  h: d.integer,
});
export type LayoutEdit = Decoded<typeof layoutEdit>;
const section = { title: text(512), description: text(4096), collapsed_by_default: d.boolean };
const widget = { fields: widgetFields, observables: d.array(id, 24) };

const command = <E extends string, I>(event: E, input: Reader<I>) =>
  d.object({ event: d.literal(event), input });

export const commandReader = d.variant("event", {
  rename: command("rename", d.object({ name: text(512), description: text(4096) })),
  add_section: command("add_section", d.object({ section_id: id, ...section })),
  update_section: command("update_section", d.object({ section_id: id, ...section })),
  remove_section: command("remove_section", d.object({ section_id: id })),
  move_section: command(
    "move_section",
    d.object({ section_id: id, direction: d.oneOf(["up", "down"] as const) }),
  ),
  add_widget: command("add_widget", d.object({ placement_id: id, ...widget })),
  update_widget: command("update_widget", d.object({ placement_id: id, ...widget })),
  remove_widget: command("remove_widget", d.object({ placement_id: id })),
  layout: command("layout", d.object({ layouts: d.array(layoutEdit, 1024) })),
  runtime_defaults: command("runtime_defaults", d.object({ defaults_json: text(32_768) })),
});
export type Command = Decoded<typeof commandReader>;
export type CommandEvent = Command["event"];

/** One readable difference between two versions (`VersionDiff.changes`). */
const change = d.object({
  kind: d.oneOf(["added", "removed", "changed"] as const),
  subject: d.oneOf(["dashboard", "section", "widget", "layout"] as const),
  label: d.string,
  detail: d.nullable(d.string),
});
export const changes = d.array(change, 2048);
export type VersionChange = Decoded<typeof change>;

const constraints = d.object({
  min_w: d.integer,
  min_h: d.integer,
  max_w: d.integer,
  max_h: d.integer,
  max_y: d.integer,
});
/** The staged document as an editable outline (`Reads.Dashboards.Editor.outline`, version 3). */
export const outline = d.object({
  version: d.literal(3),
  dashboard_id: id,
  document_version: d.integer,
  name: d.string,
  description: d.string,
  defaults: widgetFields,
  runtime_defaults_json: d.string,
  grid: d.object({ columns: d.integer, row_height_px: d.integer, gap_px: d.integer }),
  sections: d.array(
    d.object({ id, title: d.string, description: d.string, collapsed_by_default: d.boolean }),
    64,
  ),
  placements: d.array(
    d.object({
      id,
      section_id: d.nullable(id),
      title: d.string,
      editable: d.boolean,
      fields: d.nullable(widgetFields),
      observables: d.array(id, 24),
      layout: d.object({
        x: d.nullable(d.integer),
        y: d.nullable(d.integer),
        w: d.integer,
        h: d.integer,
      }),
      constraints,
    }),
    1024,
  ),
});
export type Outline = Decoded<typeof outline>;
export type OutlinePlacement = Outline["placements"][number];

const staged = {
  snapshot: workspaceSnapshot,
  changes,
  current_version: d.integer,
  outline,
};
export const previewReply = d.object(staged);
export type Preview = Decoded<typeof previewReply>;

/** `AuthoringErrors.normalize` codes (domain): why an edit can't apply. */
export const commandCodes = [
  "invalid_type",
  "invalid_title",
  "invalid_options",
  "invalid_binding",
  "forbidden",
  "invalid_input",
  "invalid_defaults",
  "conflict",
  "missing_section",
  "missing_placement",
  "unsupported_widget",
  "invalid_widget",
  "capacity",
  "duplicate_id",
  "unavailable",
  "unknown",
] as const;
const commandCode = d.known(commandCodes);
export type CommandCode = Decoded<typeof commandCode>;
const commandEvent = d.known([
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
] as const);
export type SkippedEvent = Decoded<typeof commandEvent>;

export const rebaseReply = d.object({
  ...staged,
  base_version: d.integer,
  applied: d.array(commandReader, 256),
  skipped: d.array(
    d.object({ index: d.integer, event: commandEvent, reason: d.nullable(commandCode) }),
    256,
  ),
});
export type Rebase = Decoded<typeof rebaseReply>;

export const savedReply = d.object({ version: d.integer });
export const copiedReply = d.object({ id, version: d.integer });

export const actor = d.object({
  kind: d.known(["user", "system"] as const),
  id: d.nullable(d.string),
  name: d.nullable(d.string),
});
export const versionsReply = d.object({
  current_version: d.integer,
  versions: d.array(
    d.object({
      version: d.integer,
      kind: d.known(["create", "save", "revert", "migration"] as const),
      based_on_version: d.nullable(d.integer),
      saved_by: d.nullable(actor),
      saved_at: d.timestamp,
      message: d.nullable(d.string),
      current: d.boolean,
    }),
    200,
  ),
});
export type Versions = Decoded<typeof versionsReply>;
export type VersionRow = Versions["versions"][number];
export const compareReply = d.object({ changes, from_json: d.string, to_json: d.string });

/** Error details the editor acts on (console envelope `details`, decoded per code). */
export const commandFailure = d.object({
  index: d.integer,
  code: commandCode,
  field: d.nullable(d.string),
});
export const versionConflict = d.object({
  current_version: d.integer,
  saved_by: d.nullable(actor),
  saved_at: d.nullable(d.timestamp),
});
export const notReady = d.object({
  // domain 124c1d6f: a dashboard-level issue has no placement.
  placements: d.array(
    // Readiness codes are open (domain PublishReadiness grows them); the UI shows `message`.
    d.object({ placement_id: d.nullable(id), code: d.string, message: d.string }),
    1024,
  ),
});
