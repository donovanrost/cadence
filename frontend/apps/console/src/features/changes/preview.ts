import { configKind, opActions } from "./shapes.ts";
import { decoders, isRecord, type Decoded } from "@/api";

/** The change-set dry run's shape. Contract: docs/apogee/api/changes.md (preview). */
const { array, boolean, integer, nullable, object, oneOf, string, token } = decoders;

const verdict = oneOf(["go", "hold", "no_go"]);

/** U42 derived_point_in_use (domain 5504322a8): the live points whose expressions read it. */
const dependentsDetails = object({
  used_by: decoders.optional(
    array(object({ point_id: string, name: nullable(string), definition_id: token }), 200),
  ),
});

// Items are diagnostics: ids and reasons may be absent or null without failing the preview (qa #18).
const previewItem = object({
  op_id: decoders.optional(nullable(token)),
  change_id: decoders.optional(nullable(token)),
  kind: configKind,
  entity_id: decoders.optional(nullable(token)),
  reason: decoders.optional(nullable(token)),
  errors: decoders.optional(array(object({ path: string, message: string }), 200)),
  // Compatibility HOLD (DECISIONS #33, domain): both values named.
  // Absent or null: framing_unverified sends null values (domain 5fc08e7c).
  spacecraft_count: decoders.optional(nullable(integer)),
  profile_value: decoders.optional(nullable(object({ path: string, value: (v: unknown) => v }))),
  transport_value: decoders.optional(
    nullable(
      object({
        transport: object({ id: token, name: string }),
        path: string,
        value: (v: unknown) => v,
      }),
    ),
  ),
  sentence: decoders.optional(nullable(string)),
  /** L17/L22 holds (api setup.md): true when it can't be acknowledged away; the sentence says what to do. */
  blocking: decoders.optional(boolean),
  // Lenient: each hold sends details of its own shape; only an object is read, for its used_by.
  details: (v: unknown, path = "") => (isRecord(v) ? dependentsDetails(v, path) : null),
  /** #65 catalog holds (catalog-generations.md): who moves from → to, and the requests involved. */
  spacecraft_ids: decoders.optional(array(token, 20_000)),
  from: decoders.optional(nullable(token)),
  to: decoders.optional(nullable(token)),
  requests: decoders.optional(array((v: unknown) => v, 5000)),
  /** Raw comparison for Technical details (api 76a66307); the sentence is the plain reading. */
  detail: decoders.optional(nullable(string)),
  cause: decoders.optional(nullable(token)),
  entity_name: decoders.optional(nullable(string)),
  // Conflict detail (api 062a73f8): what moved under a staged change, where and by whom.
  paths: decoders.optional(
    array(
      object({
        path: string,
        label: decoders.optional(nullable(string)),
        unit: decoders.optional(nullable(string)),
        format: decoders.optional(nullable(string)),
        base: (v: unknown) => (v === undefined ? null : v),
        live: (v: unknown) => (v === undefined ? null : v),
        staged: (v: unknown) => (v === undefined ? null : v),
        changed_in: (v: unknown, path = "") =>
          v === "outside" ? ("outside" as const) : integer(v, path),
        changed_by: decoders.optional(nullable(object({ name: string }))),
      }),
      200,
    ),
  ),
});
export type PreviewItem = Decoded<typeof previewItem>;

/** A staged/rolled-back field: raw path plus, when the server sends them, label and unit. */
export const diffField = object({
  path: string,
  label: decoders.optional(nullable(string)),
  unit: decoders.optional(nullable(string)),
  format: decoders.optional(nullable(string)),
  before: (v: unknown) => (v === undefined ? null : v),
  after: (v: unknown) => (v === undefined ? null : v),
});
export const diffEntry = object({
  kind: configKind,
  entity_id: decoders.optional(nullable(string)),
  entity_name: decoders.optional(nullable(string)),
  action: decoders.known(opActions),
  fields: decoders.optional(array(diffField, 2000)),
});
export type DiffEntry = Decoded<typeof diffEntry>;

export const previewReader = object({
  verdict,
  diffs: decoders.optional(array(diffEntry, 5000)),
  checks: array(
    object({
      key: token,
      verdict,
      /** #65: true when an item can't be acknowledged away (apply waits for it to clear). */
      blocking: decoders.optional(boolean),
      items: array(previewItem, 500),
    }),
    20,
  ),
  effects: array(
    object({
      op_id: token,
      changes: integer,
      keeps: array(
        object({
          spacecraft: object({ id: token, name: string }),
          // free-text: the server's sentence for why this spacecraft keeps its value.
          reason: string,
          /** domain 2ef4ca79: older_profile_version | catalog_override | framing_governed. */
          code: decoders.optional(nullable(token)),
        }),
        5000,
      ),
    }),
    500,
  ),
});
export type Preview = Decoded<typeof previewReader>;
