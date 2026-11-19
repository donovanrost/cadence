import { decoders as d, type Decoded } from "@/api/index.ts";

/**
 * #119 · ux U99: an import whose content matched a mission model revision that already existed.
 * Contract: docs/apogee/api/setup.md (C3 `matched_revision`, catalog index `import_runs[].matched`).
 * Read live by the server, per viewer; every key is additive, so the readers take it as optional.
 */

/** The model revision's status now. `retired` is in the vocabulary but nothing sets it yet. */
export const matchStatus = d.knownText(["candidate", "approved", "rejected", "retired"] as const);

/** A catalog database; `name` is null when it's gone, and its id is never shown (U25). */
const databaseRef = d.object({ id: d.token, name: d.nullable(d.string) });

/** A service as a refusal names it (U100); `name` is null when its row is gone. */
const service = d.object({ id: d.token, name: d.nullable(d.string) });

export const matchedRevisionReader = d.object({
  /** Technical details and route params only, never in a sentence (U99). */
  model_revision_id: d.token,
  /** The catalog revision the model is named by ("catalog rev 4"); null when none names it. */
  revision: d.nullable(
    d.object({
      id: d.token,
      number: d.integer,
      label: d.nullable(d.string),
      database: d.optional(d.nullable(databaseRef)),
    }),
  ),
  status: matchStatus,
  /** Null unless both who and when are known (U29). */
  decision: d.nullable(
    d.object({
      kind: d.knownText(["approved", "rejected"] as const),
      by: d.object({ name: d.nullable(d.string) }),
      at: d.timestamp,
      // free-text: a person's rejection reason, rendered as text only (never HTML)
      reason: d.nullable(d.string),
    }),
  ),
  /** Why separation bars THIS viewer (the approve path's own check); null when nothing does. */
  cannot_approve: d.nullable(
    d.object({
      reason: d.knownText(["self", "authors_unknown"] as const),
      via_service: d.nullable(service),
      service: d.nullable(service),
    }),
  ),
});

export type MatchedRevision = Decoded<typeof matchedRevisionReader>;

/** The runs table's `matched` (catalog index and source-file page rows). */
export const runMatchReader = d.object({
  /** THIS database's revision naming the match; null when none does. */
  number: d.nullable(d.integer),
  status: matchStatus,
  /** A route param only (Open rev 4), never in a sentence. */
  model_revision_id: d.optional(d.token),
  /** The revision the model is first recorded under (U65), for "Same as Bus catalog rev 4". */
  first: d.optional(d.nullable(d.object({ number: d.integer, database: databaseRef }))),
});
export type RunMatch = Decoded<typeof runMatchReader>;
