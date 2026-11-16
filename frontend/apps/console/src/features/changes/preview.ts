import { configKind, opActions } from "./shapes.ts";
import { decoders, isKnown, isRecord, type Decoded, type Unrecognized } from "@/api";

/** The change-set dry run's shape. Contract: docs/apogee/api/changes.md (preview). */
const { array, boolean, integer, nullable, object, oneOf, string, token } = decoders;

const verdict = oneOf(["go", "hold", "no_go"]);

/**
 * HOLD details the console reads: U42 derived_point_in_use's dependents (domain 5504322a8) and U43
 * limit_alarm_active's point (its alarms link).
 */
/**
 * HOLD and NO-GO reasons the console words or links (holds.ts placeholders, alarm and app links,
 * actions.ts framing, dependents.ts, U65's model approval). Items are diagnostics: any other reason
 * still renders through `blocking` and the server's sentence (typing rule B).
 */
export const holdReasons = [
  "spacecraft_passes_booked",
  "spacecraft_has_traffic",
  "commanding_disabled_cancels_commands",
  "telemetry_disabled",
  "handled_apids_change",
  "limit_alarm_active",
  "telemetry_app_not_installed",
  "derived_point_in_use",
  "framing_unverified",
  "framing_mismatch",
  "mission_model_not_approved",
  // #65 catalog generations: blocking holds (actions.ts blockingNext) and C3's dry-run counts
  // (catalog/rollout.ts).
  "catalog_command_in_flight",
  "catalog_configuration_pending",
  "catalog_change",
  "catalog_cancels_commands",
  // U81 §1 (domain fbc2ae00c, api setup.md): another mission of the org flies this SCID.
  "scid_shared_in_organization",
] as const;
export type HoldReason = (typeof holdReasons)[number];
/** A reason as text: its key, or the server's own (an item is a diagnostic either way). */
export const reasonText = (reason: HoldReason | Unrecognized): string =>
  isKnown(reason) ? reason : reason.unrecognized;

const holdDetails = object({
  point_id: decoders.optional(nullable(string)),
  /** U63 telemetry_app_not_installed (domain e587668da): the app to install, and its display name. */
  app_key: decoders.optional(nullable(token)),
  app_name: decoders.optional(nullable(string)),
  /** U65 mission_model_not_approved (domain + api): the catalog revision to approve, and its model. */
  catalog_database_id: decoders.optional(nullable(token)),
  catalog_revision_id: decoders.optional(nullable(token)),
  catalog_revision_number: decoders.optional(nullable(integer)),
  mission_model_revision_id: decoders.optional(nullable(token)),
  used_by: decoders.optional(
    array(object({ point_id: string, name: nullable(string), definition_id: token }), 200),
  ),
  /**
   * U81 §1 scid_shared_in_organization (api setup.md): the shared SCID, the shared provider accounts
   * (sorted by name), the other mission (null when folded: the ones the viewer can't open), and how
   * many missions the item stands for.
   */
  scid: decoders.optional(nullable(integer)),
  provider_accounts: decoders.optional(array(object({ id: token, name: nullable(string) }), 200)),
  mission: decoders.optional(nullable(object({ id: token, name: nullable(string) }))),
  mission_count: decoders.optional(nullable(integer)),
});

// Items are diagnostics: ids and reasons may be absent or null without failing the preview (qa #18).
const previewItem = object({
  op_id: decoders.optional(nullable(token)),
  change_id: decoders.optional(nullable(token)),
  kind: configKind,
  entity_id: decoders.optional(nullable(token)),
  reason: decoders.optional(nullable(decoders.knownText(holdReasons))),
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
  details: (v: unknown, path = "") => (isRecord(v) ? holdDetails(v, path) : null),
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
  /** U83 (api): the option's words beside the raw value, and the row's reason. */
  before_label: decoders.optional(nullable(string)),
  after_label: decoders.optional(nullable(string)),
  note: decoders.optional(nullable(string)),
});
export const diffEntry = object({
  kind: configKind,
  entity_id: decoders.optional(nullable(string)),
  entity_name: decoders.optional(nullable(string)),
  action: decoders.known(opActions),
  fields: decoders.optional(array(diffField, 2000)),
});
export type DiffEntry = Decoded<typeof diffEntry>;

/** Why an effect's spacecraft keeps its value (domain 2ef4ca79). */
const keepCodes = ["older_profile_version", "catalog_override", "framing_governed"] as const;

/** The preview's checks (Cadence.Configuration.Preview.summarize/1); a new one reads as its key. */
export const checkKeys = ["validation", "conflicts", "compatibility"] as const;
export type CheckKey = (typeof checkKeys)[number];
const CHECK_LABELS: Readonly<Record<CheckKey, string>> = {
  validation: "Validation",
  conflicts: "Conflicts",
  compatibility: "Compatibility",
};
/** A check's row label; an unknown check reads as its key in words. */
export const checkLabel = (key: CheckKey | Unrecognized): string =>
  isKnown(key) ? CHECK_LABELS[key] : humanizeKey(key.unrecognized);
/** The check's key as text (row keys). */
export const checkKeyText = (key: CheckKey | Unrecognized): string =>
  isKnown(key) ? key : key.unrecognized;
const humanizeKey = (key: string) => {
  const words = key
    .replace(/[_.:-]+/g, " ")
    .trim()
    .toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
};

export const previewReader = object({
  verdict,
  /** U93 (api): false = no activation exists, so applying starts nothing. Optional until shipped. */
  has_active_configuration: decoders.optional(boolean),
  diffs: decoders.optional(array(diffEntry, 5000)),
  checks: array(
    object({
      key: decoders.knownText(checkKeys),
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
          code: decoders.optional(nullable(decoders.knownText(keepCodes))),
        }),
        5000,
      ),
    }),
    500,
  ),
});
export type Preview = Decoded<typeof previewReader>;
