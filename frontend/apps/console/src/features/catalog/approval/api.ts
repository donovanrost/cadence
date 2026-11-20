import type { MissionId } from "@/api/index.ts";
import { actor, decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import { compositionActor, compositionKey } from "../composition.ts";

/**
 * ux U65 · catalog revision approval (domain's model approval gate, DECISIONS #92 a; api's wire
 * 11-15). A catalog revision's compiled mission model must be approved, against a comparison
 * report, before a change set can move spacecraft onto it.
 */

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
  // E2 (#546): `withdrawn`, an approval taken back (final until #600).
  status: d.knownText(["candidate", "approved", "rejected", "retired", "withdrawn"] as const),
  imported_at: d.nullable(d.timestamp),
  /** null: Cadence doesn't know who imported it (ux: "Importer not recorded"). */
  imported_by: d.nullable(actor),
  catalog_revision: d.nullable(
    d.object({
      id: d.token,
      number: d.integer,
      label: d.nullable(d.string),
      database_id: d.token,
      /**
       * #195 (mms-engineer #365, U102): the run that made it, and its breaking count against the
       * revision before it in its database (null: not known; base null: the first revision).
       * Optional: absent on a server before #365 (`revisionBreaking` reads that as not known).
       */
      import_run_id: d.optional(d.token),
      breaking: d.optional(d.nullable(d.integer)),
      breaking_base: d.optional(
        d.nullable(d.object({ catalog_revision_id: d.token, revision: d.integer })),
      ),
    }),
  ),
  decision: d.nullable(
    d.object({
      kind: d.knownText(["approved", "rejected", "withdrawn"] as const),
      /** null: nobody named on record (E2's withdrawal under C1; a legacy decision). */
      by: d.nullable(actor),
      at: d.timestamp,
      report_id: d.nullable(d.token),
      // free-text: the rejecting admin's own words, shown quoted
      reason: d.nullable(d.string),
    }),
  ),
  viewer_can_decide: d.boolean,
  /** E2 (#546): shows `Withdraw approval…` on an approved revision. Optional until E2 ships. */
  viewer_can_withdraw: d.optional(d.boolean),
  viewer_is_importer: d.boolean,
  cannot_decide_because: d.nullable(
    d.knownText([
      "not_admin",
      "self_approval",
      "plans_not_ready",
      "not_approvable",
      // D2 (#581): the composition's creator, who imports none of its catalogs.
      "composer",
    ] as const),
  ),
  /** #280/D2: the service the viewer is accountable for, behind self_approval or composer. */
  cannot_decide_details: d.optional(
    d.nullable(
      d.object({
        via_service: d.optional(
          d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) })),
        ),
      }),
    ),
  ),
  /** D2 (#581; U109): the composition behind this revision. Composed only after D4. */
  composition: compositionKey,
  /** D2: per catalog, the people and services separation counts as its importers. */
  importers: d.optional(
    d.array(d.object({ layer_id: d.token, importers: d.array(compositionActor, 100) }), 64),
  ),
  /**
   * D2: what approval compares against (the gate's default baseline). A composed base reads
   * it; a one-catalog page keeps `catalog_revision.breaking_base` (U109).
   */
  breaking_base: d.optional(
    d.nullable(
      d.object({
        revision_id: d.token,
        composition: d.nullable(
          d.object({ composition_id: d.token, number: d.nullable(d.integer) }),
        ),
        catalog_revision: d.nullable(d.object({ id: d.token, number: d.integer })),
      }),
    ),
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

/**
 * #260 (#613): `operation_id` makes a retry of the same approval a replay (200, `replayed: true`)
 * rather than a 409 already-approved. The 200's `replayed` is additive and not read.
 */
export function approveRevision(
  key: ModelKey,
  reportId: string,
  operationId: string,
): Promise<ApiResult<ModelRevision>> {
  return request(path(key, "/approve"), modelRevisionReader, {
    method: "POST",
    body: { comparison_report_id: reportId, operation_id: operationId },
  });
}

/**
 * One operation id per approval request: a retry of the SAME request (this revision against this
 * report) reuses it, so the server replays what already happened; another report is a new one.
 */
export function approvalOps(newId: () => string = () => crypto.randomUUID()) {
  let last: Readonly<{ key: string; id: string }> | null = null;
  return (revisionId: string, reportId: string): string => {
    const key = `${revisionId} ${reportId}`;
    if (last?.key !== key) last = { key, id: newId() };
    return last.id;
  };
}

/**
 * E2 (#546): POST …/withdraw {reason, operation_id}. One operation id per request (this revision
 * with this reason), so a retry replays the original answer (U109: "shows as the original result").
 */
export function withdrawRevision(
  key: ModelKey,
  reason: string,
  operationId: string,
): Promise<ApiResult<ModelRevision>> {
  return request(path(key, "/withdraw"), modelRevisionReader, {
    method: "POST",
    body: { reason, operation_id: operationId },
  });
}

export function rejectRevision(key: ModelKey, reason: string): Promise<ApiResult<ModelRevision>> {
  return request(path(key, "/reject"), modelRevisionReader, {
    method: "POST",
    body: { reason },
  });
}
