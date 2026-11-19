import {
  actor,
  decisionKind,
  decisionRecordFields,
  decoders,
  type Decoded,
  type Reader,
  type Unrecognized,
} from "@/api";

/**
 * Change-set wire shapes. Requested: docs/apogee/plans/setup-shapes.md §K (a JSON passthrough
 * of Cadence.Control.Configuration, docs/apogee/api/domain.md). Final contract: api/setup.md.
 */
const {
  array,
  boolean,
  integer,
  known,
  nullable,
  object,
  oneOf,
  optional,
  string,
  timestamp,
  token,
} = decoders;

/** Change-set kinds the server registers (config.exs `configuration_kinds`). */
export const configKinds = [
  "ground_station",
  "transport",
  "spacecraft",
  "spacecraft_profile",
  "spacecraft_override",
  "spacecraft_routes",
  "spacecraft_route",
  "framing_compatibility",
  "catalog_compatibility",
  "switch_compatibility",
  "derived_telemetry",
  "limit_definition",
  // U79 (director): an older route set up on the old routing page, removed through the set (domain).
  "legacy_routing_rule",
] as const;
export type ConfigKind = (typeof configKinds)[number];
const configKindWords: Readonly<Record<ConfigKind, string>> = {
  ground_station: "Ground station",
  transport: "Transport",
  spacecraft: "Spacecraft",
  spacecraft_profile: "Profile",
  spacecraft_override: "Override",
  spacecraft_routes: "Spacecraft routes",
  // U79: one spacecraft's own route (domain 774471695).
  spacecraft_route: "Extra route",
  framing_compatibility: "Framing compatibility",
  catalog_compatibility: "Catalog compatibility",
  switch_compatibility: "Commanding and telemetry switches",
  derived_telemetry: "Derived point",
  limit_definition: "Limits",
  legacy_routing_rule: "Older route",
};
export const configKind = decoders.knownText(configKinds);
/** A kind in words, or the server's word for a kind the console doesn't know yet. */
export const configKindText = (k: ConfigKind | Unrecognized) =>
  decoders.vocabularyText(k, configKindWords);
export const opActions = ["create", "update", "delete"] as const;
/** A revision entry's op: the staged actions (Configuration.Staging) plus archive (older ledgers). */
export const entryOps = [...opActions, "archive"] as const;
export type EntryOp = (typeof entryOps)[number];

const raw: Reader<unknown> = (value) => value;

/** The shared entity (typing §12 A5). */
export { actor };

const revisionNumber: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 1) throw new decoders.DecodeError(path, "revision ≥ 1");
  return n;
};

/**
 * One decision on the revision's change set. P3 (#227) adds the record's fields, optional until
 * the dev reset; an entry without `decision` is an approval (the only kind sent before P3).
 */
export const revisionApproval = object({
  actor,
  // free-text: the approver's comment.
  comment: nullable(string),
  decided_at: timestamp,
  decision: optional(nullable(decisionKind)),
  ...decisionRecordFields,
});

export const revisionSummary = object({
  revision: revisionNumber,
  kind: oneOf(["baseline", "change_set", "rollback", "legacy_activation"]),
  live: boolean,
  applied_at: timestamp,
  /** P3: whoever's request ran the apply, on every row (DECISIONS #112). */
  applied_by: nullable(actor),
  /** P3 (#227): who submitted the change set. TIGHTEN to required with the dev reset. */
  submitted_by: optional(nullable(actor)),
  // free-text: the reason a person gave for the revision.
  reason: nullable(string),
  summary: nullable(string),
  entry_count: integer,
  change_set_id: nullable(token),
  rolls_back_to: nullable(revisionNumber),
  approvals: array(revisionApproval, 20),
});

const op = object({
  id: token,
  kind: configKind,
  entity_id: nullable(token),
  action: oneOf(["create", "update", "delete"]),
  paths: array(string, 500),
  payload: raw,
});

export const change = object({
  id: token,
  summary: string,
  author: actor,
  staged_at: timestamp,
  source: raw,
  state: known(["staged", "withdrawn"] as const),
  ops: array(op, 1000),
});

export const changeSetStates = ["open", "in_review", "applied", "discarded"] as const;

export const changeSet = object({
  id: token,
  version: integer,
  state: oneOf(changeSetStates),
  base_revision: revisionNumber,
  opened_at: timestamp,
  opened_by: actor,
  staged_count: integer,
  changes: array(change, 500),
  withdrawn: array(change, 500),
  authors: array(actor, 100),
  submitted_by: nullable(actor),
  submitted_at: nullable(timestamp),
  // free-text: the reason given when submitting the change set.
  reason: nullable(string),
  approval_required: nullable(boolean),
  reviews: array(
    object({
      decision: oneOf(["approved", "sent_back"]),
      actor,
      comment: nullable(string),
      decided_at: timestamp,
    }),
    50,
  ),
  failure: nullable(raw),
  applied_revision: nullable(revisionNumber),
  /**
   * api changes.md §Permissions: whether this viewer may review (approve or send back), the
   * server's own reviewer_is_author test computed up front. Absent on an older server.
   */
  viewer: optional(
    nullable(
      object({
        can_review: boolean,
        review_blocked_reason: optional(nullable(decoders.knownText(["reviewer_is_author"]))),
      }),
    ),
  ),
});

export const configCapabilities = [
  "config.stage",
  "config.apply",
  "config.review",
  "config.rollback",
  "config.discard_any",
] as const;
export type ConfigCapability = (typeof configCapabilities)[number];

/** Unknown capability strings are dropped: the server may add some before the client knows them. */
const capabilities: Reader<ReadonlySet<ConfigCapability>> = (value, path = "") =>
  new Set(
    array(string, 64)(value, path).flatMap((c) =>
      configCapabilities.flatMap((known) => (known === c ? [known] : [])),
    ),
  );

export const configStateReader = (value: unknown, path = "") => {
  const state = object({
    head: revisionSummary,
    change_set: nullable(changeSet),
    permissions: capabilities,
  })(value, path);
  // The open set is the mission's one shared set; an applied or discarded set is never "current".
  const set = state.change_set;
  if (set && (set.state === "applied" || set.state === "discarded"))
    throw new decoders.DecodeError(
      `${path ? `${path}.` : ""}change_set.state`,
      "open or in_review",
    );
  if (set && set.staged_count !== set.changes.length)
    throw new decoders.DecodeError(
      `${path ? `${path}.` : ""}change_set.staged_count`,
      "changes.length",
    );
  return state;
};

export const revisionsReader = object({ revisions: array(revisionSummary, 200) });

/** label/unit/entity_name arrive from the server with the readable-diff work (ux review #3). */
export const field = object({
  path: string,
  label: optional(nullable(string)),
  unit: optional(nullable(string)),
  format: optional(nullable(string)),
  before: raw,
  after: raw,
  /** U83 (api): the option's words beside the raw value, and the row's reason. */
  before_label: optional(nullable(string)),
  after_label: optional(nullable(string)),
  note: optional(nullable(string)),
});
export const entry = object({
  revision: revisionNumber,
  kind: configKind,
  entity_id: nullable(token),
  entity_name: optional(nullable(string)),
  op: decoders.knownText(entryOps),
  paths: array(string, 500),
  fields: array(field, 2000),
});

/** revision_summary + entries (GET /config/revisions/:n). */
export const revisionDetailReader = (value: unknown, path = "") => ({
  ...revisionSummary(value, path),
  entries: object({ entries: array(entry, 5000) })(value, path).entries,
});

export type Actor = Decoded<typeof actor>;
export type RevisionSummary = Decoded<typeof revisionSummary>;
export type RevisionApproval = Decoded<typeof revisionApproval>;
export type Change = Decoded<typeof change>;
export type ChangeSet = Decoded<typeof changeSet>;
export type ConfigState = ReturnType<typeof configStateReader>;
export type RevisionDetail = ReturnType<typeof revisionDetailReader>;
export type RevisionEntry = Decoded<typeof entry>;
