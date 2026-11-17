import type { MissionId } from "@/api/index.ts";
import {
  actor,
  decoders as d,
  detailsOf,
  isError,
  orNull,
  request,
  type ApiError,
  type Decoded,
} from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatShort, type OpState } from "@/ui";

/**
 * L10 app activation approvals (api activations.md, be59d4f32): a save that needs
 * activation waits for a second person; approving applies it at once.
 */
const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/activations`;

/** api serves L10 (be59d4f32); on since qa's go 11-13. */
export const ACTIVATIONS_LIVE = true;
/** Withdraw: api 6e289aa35 (domain 444c6126b), live on :4011 since 11-13. */
export const WITHDRAW_LIVE = true;

/** U41: why an approved activation didn't apply. */
export const applyCodes = [
  "activation_execution_interrupted",
  "spacecraft_configuration_review_stale",
  "approved_activation_content_mismatch",
  // U88 (domain, 11-18): not retryable; a new request is the only way on.
  "mission_model_revision_not_in_catalog",
] as const;

export const requestStates = [
  "approval_pending",
  "approved",
  "rejected",
  "withdrawn",
  "superseded",
] as const;
const row = d.object({
  id: d.token,
  // knownText: a new kind still renders its server summary (fe-ops, Now).
  // null: a mission activation that's neither (api activations.md).
  kind: d.nullable(d.knownText(["telemetry_decom", "spacecraft_configuration"] as const)),
  app: d.nullable(d.object({ key: d.token, name: d.string })),
  // free-text: the server's sentence for what the request activates.
  summary: d.string,
  binding_set: d.object({ id: d.token, version: d.integer }),
  requested_by: orNull(actor),
  requested_at: d.timestamp,
  state: d.known(requestStates),
  decision: d.nullable(
    d.object({
      state: d.known(["approved", "rejected", "withdrawn"] as const),
      by: orNull(actor),
      at: d.timestamp,
      // free-text: the reason the reviewer gave.
      reason: d.string,
    }),
  ),
  execution: d.nullable(
    d.object({
      state: d.known(["in_progress", "succeeded", "failed"] as const),
      /** Resume addition (plans/activations.md): when it failed or stalled, and why by code. */
      since: d.optional(d.nullable(d.timestamp)),
      error_code: d.optional(d.nullable(d.known(applyCodes))),
      /** U41 (domain 8f30aac21): whether Retry apply can succeed; absent reads as no. */
      retryable: d.optional(d.boolean),
      // free-text: domain's U41 sentence for a known code; never shown for an unknown one (U20).
      error: d.nullable(d.string),
    }),
  ),
  can_decide: d.boolean,
  /** domain L10 asks (11-13): the newer request that replaced this one; absent until api sends it. */
  superseded_by: d.optional(d.nullable(d.token)),
  superseded_at: d.optional(d.nullable(d.timestamp)),
});
export type ActivationRequest = Decoded<typeof row>;

const listReader = d.object({
  requests: d.array(row, 500),
  next: d.nullable(d.string),
  permissions: d.array(d.known(["activations.approve"] as const), 10),
});
export type ActivationList = Decoded<typeof listReader>;
export type ListKey = Readonly<{ missionId: MissionId; state: "pending" | "decided" }>;
export function fetchActivations(k: ListKey, signal: AbortSignal) {
  return request(`${base(k.missionId)}?state=${k.state}`, listReader, { signal });
}

const detailReader = (value: unknown, path = "") => ({
  ...row(value, path),
  ...d.object({
    details: d.array(d.object({ label: d.string, value: d.string }), 100),
    comparison: d.nullable(d.object({ report_id: d.token, label: d.string })),
    /** U41 Retry apply is for people who may approve; absent reads as no (asked of api 11-13). */
    permissions: d.optional(d.array(d.known(["activations.approve"] as const), 10)),
  })(value, path),
});
export type ActivationDetail = ReturnType<typeof detailReader>;
export type DetailKey = Readonly<{ missionId: MissionId; requestId: string }>;
export function fetchActivation(k: DetailKey, signal: AbortSignal) {
  return request(`${base(k.missionId)}/${encodeURIComponent(k.requestId)}`, detailReader, {
    signal,
  });
}

export type Verb = "approve" | "reject" | "withdraw";
const decided = d.object({
  request: row,
  outcome: d.optional(d.known(["applied", "needs_review"] as const)),
});
export function decide(k: DetailKey, verb: Verb, reason: string) {
  return request(`${base(k.missionId)}/${encodeURIComponent(k.requestId)}/${verb}`, decided, {
    method: "POST",
    body: { reason },
  });
}

/** Who is looking: the gate below needs no more than this. */
export type Viewer = Readonly<{ userId: string; orgAdmin: boolean }>;

export const isRequester = (r: ActivationRequest, viewer: Viewer) =>
  r.requested_by?.id === viewer.userId;

/**
 * THE approve gate, the only place the console decides who may approve or reject (director: the
 * approver rule is with the user). Today it follows the domain's :approve_activation through the
 * server's can_decide (any mission operator except the requester). If the ruling adds the ops-console
 * path's org-admin requirement, this becomes `… && viewer.orgAdmin`, and nothing else changes.
 */
export function mayDecide(r: ActivationRequest, viewer: Viewer): boolean {
  return r.can_decide && !isRequester(r, viewer);
}

/** After a decision: what happened, in one line. */
export function decidedLine(
  verb: Verb,
  r: Decoded<typeof decided>,
): { tone: "nominal" | "caution"; text: string } {
  if (verb === "reject") return { tone: "nominal", text: "Rejected. Nothing changes." };
  if (verb === "withdraw") return { tone: "nominal", text: "Withdrawn. Nothing changes." };
  if (r.outcome === "needs_review" || r.request.execution?.state === "failed")
    return {
      tone: "caution",
      text: `Approved, but it didn't apply. ${applySentence(r.request.execution)}`,
    };
  return { tone: "nominal", text: "Approved and applied." };
}

/** Retry apply (resume addition): re-runs a failed or stalled apply; every step is safe to repeat. */
export function resume(k: DetailKey) {
  return request(`${base(k.missionId)}/${encodeURIComponent(k.requestId)}/resume`, decided, {
    method: "POST",
    body: {},
  });
}

type Execution = ActivationRequest["execution"];
type ApplyCode = NonNullable<NonNullable<Execution>["error_code"]>;
/** U41 sentences, for when domain's own sentence is missing; any other code is "Applying failed." */
const APPLY_WORDS: Readonly<Record<ApplyCode, string>> = {
  activation_execution_interrupted:
    "Applying was cut off: Cadence lost its database connection partway.",
  spacecraft_configuration_review_stale:
    "A spacecraft's configuration changed after it was reviewed, so the reviewed version can't be applied.",
  approved_activation_content_mismatch:
    "What would be applied now differs from what was approved, so it wasn't applied.",
  mission_model_revision_not_in_catalog:
    "The catalog doesn't list the revision this request names, so it can't be applied.",
  unrecognized: "Applying failed.",
};
/**
 * U41: the standalone sentence for why it didn't apply. api's `error` is always ux's sentence (it
 * names the spacecraft), never a raw reason; the code's words stand in only when it's missing.
 */
export function applySentence(e: Execution): string {
  return e?.error ?? APPLY_WORDS[e?.error_code ?? "unrecognized"];
}

/** An approved activation whose apply failed or stalled, with what the review page says (U41). */
export function notApplied(
  r: ActivationRequest,
): { text: string; retry: boolean; next: string | null } | null {
  const e = r.execution;
  if (r.state !== "approved" || !e) return null;
  // Failed, or stalled: still in_progress, but api sets `error` once nothing is working on it.
  if (e.state !== "failed" && !(e.state === "in_progress" && e.error !== null)) return null;
  const since = e.since ? ` Since ${formatShort(new Date(e.since))}.` : "";
  // ux: unknown retryability (api hasn't sent it) offers neither Retry nor the request-again step (U20).
  const retry = e.retryable === true;
  return {
    text: `Approved, but it didn't apply. ${applySentence(e)}${since}`,
    retry,
    next: e.retryable === false ? REQUEST_AGAIN : null,
  };
}

const REQUEST_AGAIN = "Request activation again so the current version can be approved.";
const notResumable = d.object({ error_code: d.known(applyCodes) });
const nothingToResume = d.object({
  state: d.nullable(d.known(["succeeded", "in_progress", "approval_pending", "rejected"] as const)),
});
/** U41: a refused Retry apply, in words. The caller refetches either way. */
export function resumeFailure(error: ApiError): string {
  if (isError(error, "not_resumable")) {
    const code = detailsOf(error, notResumable)?.error_code ?? "unrecognized";
    return `This can't be retried: ${APPLY_WORDS[code]} ${REQUEST_AGAIN}`;
  }
  if (isError(error, "nothing_to_resume")) {
    const state = detailsOf(error, nothingToResume)?.state;
    return state === "succeeded"
      ? "It already applied."
      : state === "in_progress"
        ? "It's applying now."
        : "There's nothing to retry.";
  }
  if (isError(error, "activation_execution_in_progress")) return "It's applying now.";
  return decideFailure(error);
}

const TAGS: Readonly<Record<ActivationRequest["state"], { state: OpState; label: string }>> = {
  approval_pending: { state: "caution", label: "WAITING" },
  approved: { state: "nominal", label: "APPROVED" },
  rejected: { state: "off", label: "REJECTED" },
  withdrawn: { state: "off", label: "WITHDRAWN" },
  superseded: { state: "off", label: "SUPERSEDED" },
  unrecognized: { state: "neutral", label: "UNKNOWN" },
};
export const stateTag = (r: ActivationRequest) => TAGS[r.state];

/** "Mira K. · 11-13 02:10Z". */
export const requestedLine = (r: ActivationRequest) =>
  `${r.requested_by?.name ?? "Someone"} · ${formatShort(new Date(r.requested_at))}`;

/** "Approved by Ada L. on 11-13 02:20Z: looks right", for a decided request. */
export function decisionLine(r: ActivationRequest): string | null {
  const dcs = r.decision;
  if (!dcs) return null;
  const word = {
    approved: "Approved",
    rejected: "Rejected",
    withdrawn: "Withdrawn",
    unrecognized: "Decided",
  }[dcs.state];
  const by = dcs.by?.name ?? "someone";
  // ux U41: "Withdrawn by Mira K. at 11-13 02:20Z: <reason>." (§4 short time, one closing period).
  if (dcs.state === "withdrawn")
    return `Withdrawn by ${by} at ${formatShort(new Date(dcs.at))}: ${dcs.reason.replace(/\.$/, "")}.`;
  return `${word} by ${by} on ${formatShort(new Date(dcs.at))}: ${dcs.reason}`;
}

/** lead 11-13: a superseded request names the one that replaced it (the link is the caller's). */
export function replacedBy(r: ActivationRequest): string | null {
  return r.state === "superseded" ? (r.superseded_by ?? null) : null;
}

/** One sentence for a refused decision (U20). */
export function decideFailure(error: ApiError): string {
  if (isError(error, "self_approval_forbidden"))
    return "You requested this. Someone else approves it.";
  if (isError(error, "not_requester")) return "Only the person who requested it can withdraw it.";
  if (isError(error, "not_pending")) return "It's already decided. Reload to see how.";
  if (isError(error, "nothing_to_resume"))
    return "It isn't stuck any more. Reload to see how it ended.";
  if (isError(error, "activation_policy_changed"))
    return "The approval rules changed since it was requested. Reject it, or ask the requester to withdraw it.";
  return failureOutcome(error, "changed").sentence;
}
