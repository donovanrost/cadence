import type { RouteLocationRaw } from "vue-router";
import type { MissionId } from "@/api/index.ts";
import {
  codeOf,
  isError,
  decoders,
  outcomeUnknown,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  detailsOf,
} from "@/api";
import { conversionInProgress } from "./conversion-refusal.ts";

/** Change-set writes and the dry run. Contract: docs/apogee/api/changes.md. */
const { array, integer, object, string, token } = decoders;

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/config`;
import { previewReader, type Preview } from "./preview.ts";
import { changeSetStates } from "./shapes.ts";
import { submitReader, type SubmitResult } from "./submitResult.ts";
export type { SubmitResult } from "./submitResult.ts";
export {
  diffEntry,
  diffField,
  previewReader,
  type DiffEntry,
  type Preview,
  type PreviewItem,
} from "./preview.ts";

const versionResult = object({
  change_set_id: token,
  version: integer,
  state: decoders.known(changeSetStates),
});

export function previewChangeSet(
  key: Readonly<{ missionId: MissionId; changeSetId: string; version: number }>,
  signal: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(
    `${base(key.missionId)}/change-sets/${encodeURIComponent(key.changeSetId)}/preview`,
    previewReader,
    { method: "POST", body: {}, signal },
  );
}

export function withdrawChange(missionId: MissionId, changeId: string) {
  return request(
    `${base(missionId)}/changes/${encodeURIComponent(changeId)}/withdraw`,
    versionResult,
    {
      method: "POST",
      body: {},
    },
  );
}

export function discardChangeSet(
  missionId: MissionId,
  changeSetId: string,
  expectedVersion: number,
) {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/discard`,
    object({
      change_set_id: token,
      version: integer,
      state: decoders.known(changeSetStates),
      remaining: decoders.optional(integer),
    }),
    { method: "POST", body: { expected_version: expectedVersion } },
  );
}

export function submitChangeSet(
  missionId: MissionId,
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
  missionId: MissionId,
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
  return codeOf(error);
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
    case "holds_blocking":
      return "A blocking hold remains, so nothing was applied. It can't be acknowledged; apply once it clears (see the checks).";
    case "catalog_command_in_flight":
      return "Commands started on the affected spacecraft, so nothing was applied. Try again when they finish.";
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
    | "spacecraft_override"
    | "spacecraft_route"
    | "legacy_routing_rule";
  action: "create" | "update" | "delete";
  entity_id?: string;
  document?: Readonly<Record<string, unknown>>;
  changes?: readonly Readonly<{ path: string; value: unknown }>[];
  options?: Readonly<Record<string, unknown>>;
}>;

export const stageResultReader = object({
  change_set_id: token,
  change_id: token,
  version: integer,
  staged_count: integer,
  base_revision: integer,
  entity_ids: array(token, 5000),
});
export type StageResult = Decoded<typeof stageResultReader>;

/** Stage one change (any number of ops) into the mission's open change set. */
export function stageChange(
  missionId: MissionId,
  body: Readonly<{
    summary: string;
    source: Readonly<Record<string, unknown>>;
    ops: readonly StageOp[];
  }>,
): Promise<ApiResult<StageResult>> {
  return request(`${base(missionId)}/stage`, stageResultReader, { method: "POST", body });
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
  /** U65: where to go about it ('Open the report' on a failed model comparison). */
  link?: Readonly<{ label: string; to: RouteLocationRaw }>;
}>;

const comparisonFailed = decoders.object({ mission_model_revision_id: decoders.token });

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
  // qa #19: a 500 can arrive after the write committed; it's unclear, never "nothing changed".
  if (error.kind === "unavailable" && outcomeUnknown(error))
    return {
      changed: null,
      sentence: `The server failed while answering, so it isn't clear whether anything was ${verb}. Check Staged changes and Revisions now, before trying again.`,
    };
  const converting = conversionInProgress(error);
  if (converting) return converting;
  // Field-level rejections (e.g. DECISIONS #36 catalog refusal) name the field and the route.
  const fields = invalidOpDetails(error);
  if (fields && fields.errors.length > 0)
    return {
      changed: false,
      sentence: `Nothing was ${verb}. ${fields.errors.map((e) => (e.path ? `${e.path}: ${e.message}` : e.message)).join(" · ")}`,
    };
  // invalid_params: details keyed by field (`{comment: "is required"}` or a list of messages).
  if (errorCode(error) === "invalid_params" && "details" in error) {
    const d = error.details;
    if (d !== null && typeof d === "object" && !Array.isArray(d)) {
      const parts = Object.entries(d).flatMap(([field, v]) =>
        typeof v === "string"
          ? [`${field}: ${v}`]
          : Array.isArray(v)
            ? v.filter((m): m is string => typeof m === "string").map((m) => `${field}: ${m}`)
            : [],
      );
      if (parts.length > 0)
        return { changed: false, sentence: `Nothing was ${verb}. ${parts.join(" · ")}` };
    }
  }
  // U63/U65: the server's sentence already says "Not applied: …" and names what (ux).
  if (
    (isError(error, "telemetry_app_not_installed") ||
      isError(error, "telemetry_packet_inputs_required") ||
      isError(error, "mission_model_revision_not_approved") ||
      isError(error, "mission_model_comparison_failed")) &&
    "message" in error &&
    error.message
  ) {
    const report = isError(error, "mission_model_comparison_failed")
      ? detailsOf(error, comparisonFailed)
      : null;
    return {
      changed: false,
      sentence: error.message,
      ...(report
        ? {
            link: {
              label: "Open the report",
              to: {
                name: "setup.catalog.model",
                params: { revisionId: report.mission_model_revision_id },
              },
            },
          }
        : {}),
    };
  }
  return { changed: false, sentence: `Nothing was ${verb}. ${rejectionSentence(error)}` };
}

/** Dry run of unstaged ops (nothing written): per-op validation and conflicts, by op index. */
export function previewOps(
  key: Readonly<{ missionId: MissionId; ops: readonly StageOp[] }>,
  signal: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(`${base(key.missionId)}/preview`, previewReader, {
    method: "POST",
    body: { ops: key.ops },
    signal,
  });
}
