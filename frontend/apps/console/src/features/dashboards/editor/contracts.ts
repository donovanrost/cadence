import { decoders as d, type Decoded, type Reader, actor } from "@/api";
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
  // A library item's version placed by reference (domain a594da7ec; the library plan).
  add_library_widget: command(
    "add_library_widget",
    d.object({ placement_id: id, library_item_id: id, version: d.integer, section_id: d.string }),
  ),
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
      // domain 73e5f126e (api passes it through): null for embedded placements.
      library: d.nullable(d.object({ item_id: id, version: d.integer, retired: d.boolean })),
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
  // add_library_widget (domain a594da7ec): retired or unknown item; a version it doesn't have.
  "library_item_unavailable",
  "library_version_unavailable",
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
  "add_library_widget",
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

/**
 * A source's health, as a save's readiness saw it (api a7bba3ca0, contract dashboards.md). Only
 * facts about the source block a save; health from reads only warns (lead 11-14).
 */
export const LOGICAL_SOURCES = [
  "telemetry",
  "events",
  "limits",
  "operational_observables",
] as const;
export const REALMS = ["flight", "rehearsal", "replay", "simulation"] as const;
export const SOURCE_REASONS = [
  "source_unavailable",
  "source_degraded",
  "source_health_unknown",
  "connection_test_failed",
  "connection_test_blocked",
] as const;
const sourceFacts = {
  logical_source: d.knownText(LOGICAL_SOURCES),
  realm: d.nullable(d.knownText(REALMS)),
  reasons: d.array(d.knownText(SOURCE_REASONS), 16),
  observed_at: d.nullable(d.timestamp),
};
/** One per (code, source, realm): a slow source behind ten widgets warns once. */
export const sourceWarning = d.object({
  code: d.knownText(["source_unavailable", "source_degraded"] as const),
  ...sourceFacts,
  placement_ids: d.array(id, 1024),
  // free-text: the server's sentence, a fallback only; the console words it from the fields.
  message: d.string,
});
export type SourceWarning = Decoded<typeof sourceWarning>;
// [] when none (api c16236516, live since restart 5).
const warnings = d.array(sourceWarning, 64);

export const savedReply = d.object({ version: d.integer, warnings });
export type Saved = Decoded<typeof savedReply>;
export const copiedReply = d.object({ id, version: d.integer, warnings });

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
  // null: an item retired between the check and the save (Q10) names no command.
  index: d.nullable(d.integer),
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
    d.object({
      placement_id: d.nullable(id),
      // free-text: readiness codes are open (domain PublishReadiness grows them); the UI shows `message`.
      code: d.string,
      message: d.string,
      // A source issue's facts, else null (api a7bba3ca0).
      details: d.nullable(d.object(sourceFacts)),
    }),
    1024,
  ),
});
