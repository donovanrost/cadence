import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";

/**
 * ux U65 · catalog revision approval (domain's model approval gate, DECISIONS #92 a; api's wire
 * 11-15). A catalog revision's compiled mission model must be approved, against a comparison
 * report, before a change set can move spacecraft onto it.
 */

const person = d.object({ id: d.token, name: d.string });

/** The declaration kinds a report groups its changes by (ux's section words). */
export const declarationKinds = [
  "command",
  "command_argument",
  "command_argument_type",
  "command_encoding",
  "command_constraint",
  "command_verifier",
  "parameter",
  "parameter_type",
  "container",
  "calibrator",
  "algorithm",
  "monitoring_policy",
  "stream",
  "service",
  "extension",
  "unit",
  "space_system",
] as const;
export type DeclarationKind = (typeof declarationKinds)[number];

const counts = { added: d.integer, removed: d.integer, changed: d.integer };

export const comparisonReader = d.object({
  report_id: d.token,
  passed: d.boolean,
  /** The revision it would replace; null when there's none (everything counts as added). */
  against: d.nullable(d.object({ revision_id: d.token, catalog_revision_number: d.integer })),
  replay: d.object({
    /** not_required: low risk, replay skipped (the report still passes). */
    status: d.knownText(["not_required", "not_run", "passed", "failed"] as const),
    reason: d.nullable(d.knownText(["qualification_corpus_required"] as const)),
    cases: d.integer,
    failed_cases: d.array(
      d.object({
        name: d.string,
        // free-text: the replay's own explanation of a failed case, shown as said
        reason: d.nullable(d.string),
      }),
      500,
    ),
  }),
  risk: d.knownText(["low", "medium", "high"] as const),
  totals: d.object(counts),
  sections: d.array(d.object({ kind: d.knownText(declarationKinds), ...counts }), 100),
  affected_kinds: d.array(d.knownText(declarationKinds), 100),
  // free-text: runtime plan target names, shown in Technical details only, never branched on
  changed_targets: d.array(d.string, 500),
  generated_at: d.timestamp,
});
export type Comparison = Decoded<typeof comparisonReader>;

export const modelRevisionReader = d.object({
  id: d.token,
  status: d.knownText(["candidate", "approved", "rejected", "retired"] as const),
  imported_at: d.nullable(d.timestamp),
  /** null: Cadence doesn't know who imported it (ux: "Importer not recorded"). */
  imported_by: d.nullable(person),
  catalog_revision: d.nullable(
    d.object({
      id: d.token,
      number: d.integer,
      label: d.nullable(d.string),
      database_id: d.token,
    }),
  ),
  decision: d.nullable(
    d.object({
      kind: d.knownText(["approved", "rejected"] as const),
      by: person,
      at: d.timestamp,
      report_id: d.nullable(d.token),
      // free-text: the rejecting admin's own words, shown quoted
      reason: d.nullable(d.string),
    }),
  ),
  viewer_can_decide: d.boolean,
  viewer_is_importer: d.boolean,
  cannot_decide_because: d.nullable(
    d.knownText(["not_admin", "self_approval", "plans_not_ready", "not_approvable"] as const),
  ),
  /**
   * U88 (api, 11-18): Approve only; Reject stays allowed, so an orphan clears from the queue.
   * Optional until api ships it.
   */
  cannot_approve_because: d.optional(d.nullable(d.knownText(["not_in_catalog"] as const))),
  plans_ready: d.boolean,
  comparison: d.nullable(comparisonReader),
});
export type ModelRevision = Decoded<typeof modelRevisionReader>;

export type ModelKey = Readonly<{ missionId: MissionId; revisionId: string }>;

const path = (k: ModelKey, rest = "") =>
  `/missions/${encodeURIComponent(k.missionId)}/mission-model-revisions/${encodeURIComponent(k.revisionId)}${rest}`;

export function fetchModelRevision(
  key: ModelKey,
  signal: AbortSignal,
): Promise<ApiResult<ModelRevision>> {
  return request(path(key), modelRevisionReader, { signal });
}

/** Runs the comparison against the revision it would replace (synchronous; reports dedupe). */
export function runComparison(key: ModelKey): Promise<ApiResult<Comparison>> {
  return request(path(key, "/comparison"), comparisonReader, { method: "POST", body: {} });
}

export function approveRevision(
  key: ModelKey,
  reportId: string,
): Promise<ApiResult<ModelRevision>> {
  return request(path(key, "/approve"), modelRevisionReader, {
    method: "POST",
    body: { comparison_report_id: reportId },
  });
}

export function rejectRevision(key: ModelKey, reason: string): Promise<ApiResult<ModelRevision>> {
  return request(path(key, "/reject"), modelRevisionReader, {
    method: "POST",
    body: { reason },
  });
}
