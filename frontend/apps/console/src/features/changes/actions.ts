import { decoders, request, type ApiError, type ApiResult, type Decoded } from "@/api";

/** Change-set writes and the dry run. Contract: docs/apogee/api/changes.md. */
const { array, integer, nullable, object, oneOf, string, token } = decoders;

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/config`;
const verdict = oneOf(["go", "hold", "no_go"]);

const previewItem = object({
  op_id: nullable(token),
  change_id: nullable(token),
  kind: token,
  entity_id: nullable(token),
  reason: decoders.optional(token),
  errors: decoders.optional(array(object({ path: string, message: string }), 200)),
});

export const previewReader = object({
  verdict,
  checks: array(object({ key: token, verdict, items: array(previewItem, 500) }), 20),
  effects: array(
    object({
      op_id: token,
      changes: integer,
      keeps: array(
        object({ spacecraft: object({ id: token, name: string }), reason: string }),
        5000,
      ),
    }),
    500,
  ),
});
export type Preview = Decoded<typeof previewReader>;

const versionResult = object({ change_set_id: token, version: integer, state: token });

const submitReader = decoders.variant("state", {
  applied: object({
    state: decoders.literal("applied"),
    change_set_id: token,
    revision: integer,
    staged_count: integer,
    runtime: oneOf(["not_applicable", "converging", "applied", "degraded"]),
    degraded_partitions: array(string, 1000),
  }),
  in_review: object({
    state: decoders.literal("in_review"),
    change_set_id: token,
    version: integer,
  }),
  open: object({ state: decoders.literal("open"), change_set_id: token, version: integer }),
});
export type SubmitResult = Decoded<typeof submitReader>;

export function previewChangeSet(
  key: Readonly<{ missionId: string; changeSetId: string; version: number }>,
  signal: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(
    `${base(key.missionId)}/change-sets/${encodeURIComponent(key.changeSetId)}/preview`,
    previewReader,
    { method: "POST", body: {}, signal },
  );
}

export function withdrawChange(missionId: string, changeId: string) {
  return request(
    `${base(missionId)}/changes/${encodeURIComponent(changeId)}/withdraw`,
    versionResult,
    {
      method: "POST",
      body: {},
    },
  );
}

export function discardChangeSet(missionId: string, changeSetId: string, expectedVersion: number) {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/discard`,
    object({
      change_set_id: token,
      version: integer,
      state: token,
      remaining: decoders.optional(integer),
    }),
    { method: "POST", body: { expected_version: expectedVersion } },
  );
}

export function submitChangeSet(
  missionId: string,
  changeSetId: string,
  body: Readonly<{ reason: string; expected_version: number; acknowledged_holds: boolean }>,
): Promise<ApiResult<SubmitResult>> {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/submit`,
    submitReader,
    { method: "POST", body },
  );
}

export function reviewChangeSet(
  missionId: string,
  changeSetId: string,
  body: Readonly<{ decision: "approve" | "send_back"; comment: string; expected_version: number }>,
): Promise<ApiResult<SubmitResult>> {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/review`,
    submitReader,
    { method: "POST", body },
  );
}

/** The server's error tag (docs/apogee/api/changes.md § Errors), when the error carries one. */
export function errorCode(error: ApiError): string | null {
  return "code" in error && typeof error.code === "string" ? error.code : null;
}

/** People-facing sentence for a change-set rejection, keyed by the facade tag. */
export function rejectionSentence(error: ApiError): string {
  switch (errorCode(error)) {
    case "change_set_changed":
      return "Someone changed the staged set while you were looking. It has been reloaded; check it and try again.";
    case "frozen_in_review":
      return "The change set is in review, so staging is paused.";
    case "reviewer_is_author":
      return "You staged part of this set, so you can't approve it. Another person must review it.";
    case "activation_policy_changed":
      return "The approval policy changed since this was submitted. The set has reopened.";
    case "checks_failed":
      return "Checks failed: nothing changed. Fix the NO-GO items and try again.";
    case "holds_not_acknowledged":
      return "Read and acknowledge the holds before applying.";
    case "reason_required":
      return "Say why (10 characters or more).";
    case "comment_required":
      return "Add a comment for the author.";
    case "nothing_staged":
      return "Nothing is staged.";
    case null:
    default:
      return "message" in error ? error.message : "Request failed.";
  }
}

export type StageOp = Readonly<{
  kind:
    | "ground_station"
    | "transport"
    | "spacecraft"
    | "spacecraft_profile"
    | "spacecraft_override";
  action: "create" | "update" | "delete";
  entity_id?: string;
  document?: Readonly<Record<string, unknown>>;
  changes?: readonly Readonly<{ path: string; value: unknown }>[];
  options?: Readonly<Record<string, unknown>>;
}>;

const stageResult = object({
  change_set_id: token,
  change_id: token,
  version: integer,
  staged_count: integer,
  base_revision: integer,
  entity_ids: array(token, 5000),
});
export type StageResult = Decoded<typeof stageResult>;

/** Stage one change (any number of ops) into the mission's open change set. */
export function stageChange(
  missionId: string,
  body: Readonly<{
    summary: string;
    source: Readonly<Record<string, unknown>>;
    ops: readonly StageOp[];
  }>,
): Promise<ApiResult<StageResult>> {
  return request(`${base(missionId)}/stage`, stageResult, { method: "POST", body });
}

/** `invalid_op` details: which op (by index) failed, and why. */
export function invalidOpDetails(error: ApiError): Readonly<{
  index: number;
  errors: readonly Readonly<{ path: string; message: string }>[];
}> | null {
  if (errorCode(error) !== "invalid_op" || !("details" in error)) return null;
  const parsed = decoders.decode(
    object({ index: integer, errors: array(object({ path: string, message: string }), 200) }),
    error.details,
  );
  return parsed.ok ? parsed.value : null;
}

export type FailureOutcome = Readonly<{
  /** false: the server rejected it, nothing changed. null: we can't tell (reply lost or unreadable). */
  changed: false | null;
  sentence: string;
}>;

/**
 * Every stage/apply failure says whether anything changed (ux review 2026-11-09). A rejection
 * means nothing changed; an unreadable reply or a lost connection means we can't tell.
 */
export function failureOutcome(
  error: ApiError,
  verb: "staged" | "applied" | "changed",
): FailureOutcome {
  if (error.kind === "malformed")
    return {
      changed: null,
      sentence: `The server's reply wasn't understood, so it isn't clear whether anything was ${verb}. Check Staged changes before trying again.`,
    };
  if (error.kind === "unavailable" && error.status === 0)
    return {
      changed: null,
      sentence: `The connection dropped, so it isn't clear whether anything was ${verb}. Check Staged changes before trying again.`,
    };
  return { changed: false, sentence: `Nothing was ${verb}. ${rejectionSentence(error)}` };
}

/** Dry run of unstaged ops (nothing written): per-op validation and conflicts, by op index. */
export function previewOps(
  key: Readonly<{ missionId: string; ops: readonly StageOp[] }>,
  signal: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(`${base(key.missionId)}/preview`, previewReader, {
    method: "POST",
    body: { ops: key.ops },
    signal,
  });
}
