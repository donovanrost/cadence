import { decoders, type Decoded, type Reader } from "@/api";

/**
 * Change-set wire shapes. Requested: docs/apogee/plans/setup-shapes.md §K (a JSON passthrough
 * of Cadence.Control.Configuration, docs/apogee/api/domain.md). Final contract: api/setup.md.
 */
const { array, boolean, integer, nullable, object, oneOf, optional, string, timestamp, token } =
  decoders;

const raw: Reader<unknown> = (value) => value;

export const actor = object({ kind: token, id: token, name: string });

const revisionNumber: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 1) throw new decoders.DecodeError(path, "revision ≥ 1");
  return n;
};

export const revisionSummary = object({
  revision: revisionNumber,
  kind: oneOf(["baseline", "change_set", "rollback", "legacy_activation"]),
  live: boolean,
  applied_at: timestamp,
  applied_by: nullable(actor),
  reason: nullable(string),
  summary: nullable(string),
  entry_count: integer,
  change_set_id: nullable(token),
  rolls_back_to: nullable(revisionNumber),
  approvals: array(object({ actor, comment: nullable(string), decided_at: timestamp }), 20),
});

const op = object({
  id: token,
  kind: token,
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
  state: token,
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
const field = object({
  path: string,
  label: optional(nullable(string)),
  unit: optional(nullable(string)),
  format: optional(nullable(string)),
  before: raw,
  after: raw,
});
export const entry = object({
  revision: revisionNumber,
  kind: token,
  entity_id: nullable(token),
  entity_name: optional(nullable(string)),
  op: token,
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
export type Change = Decoded<typeof change>;
export type ChangeSet = Decoded<typeof changeSet>;
export type ConfigState = ReturnType<typeof configStateReader>;
export type RevisionDetail = ReturnType<typeof revisionDetailReader>;
export type RevisionEntry = Decoded<typeof entry>;
