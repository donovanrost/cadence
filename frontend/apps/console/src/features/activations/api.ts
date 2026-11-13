import { actor, decoders as d, isError, orNull, request, type ApiError, type Decoded } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatShort, type OpState } from "@/ui";

/**
 * L10 app activation approvals (plans/activations.md, proposed to api 11-13): a save that needs
 * activation waits for a second person; approving applies it at once.
 */
const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/activations`;

/** Off until api serves L10 (a 404 on Setup › Changes trips qa's e2e diagnostics guard). */
export const ACTIVATIONS_LIVE = false;

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
  kind: d.knownText(["telemetry_decom", "spacecraft_configuration"] as const),
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
      // free-text: the apply error, shown as is.
      error: d.nullable(d.string),
    }),
  ),
  can_decide: d.boolean,
});
export type ActivationRequest = Decoded<typeof row>;

const listReader = d.object({
  requests: d.array(row, 500),
  next: d.nullable(d.string),
  permissions: d.array(d.known(["activations.approve"] as const), 10),
});
export type ActivationList = Decoded<typeof listReader>;
export type ListKey = Readonly<{ missionId: string; state: "pending" | "decided" }>;
export function fetchActivations(k: ListKey, signal: AbortSignal) {
  return request(`${base(k.missionId)}?state=${k.state}`, listReader, { signal });
}

const detailReader = (value: unknown, path = "") => ({
  ...row(value, path),
  ...d.object({
    details: d.array(d.object({ label: d.string, value: d.string }), 100),
    comparison: d.nullable(d.object({ report_id: d.token, label: d.string })),
  })(value, path),
});
export type ActivationDetail = ReturnType<typeof detailReader>;
export type DetailKey = Readonly<{ missionId: string; requestId: string }>;
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
      text: `Approved, but it didn't apply: ${r.request.execution?.error ?? "no reason given"}.`,
    };
  return { tone: "nominal", text: "Approved and applied." };
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
  return `${word} by ${dcs.by?.name ?? "someone"} on ${formatShort(new Date(dcs.at))}: ${dcs.reason}`;
}

/** One sentence for a refused decision (U20). */
export function decideFailure(error: ApiError): string {
  if (isError(error, "self_approval_forbidden"))
    return "You requested this. Someone else approves it.";
  if (isError(error, "not_pending")) return "It's already decided. Reload to see how.";
  if (isError(error, "policy_changed"))
    return "The approval rules changed since it was requested. Reject it, or ask the requester to withdraw it.";
  return failureOutcome(error, "changed").sentence;
}
