import type { MissionId } from "@/api/index.ts";
import { actor, decoders as d, isError, orNull, request, type ApiError, type Decoded } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatDuration, formatShort, plural } from "@/ui";

/**
 * L3 automation grants (plans/planning-verbs.md, api agreed 11-13): what lets a service identity
 * plan, repair or submit without a person. Cost stays hidden (DECISIONS #63); the server fills it.
 */
const base = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/contact-planning/grants`;

export const grantActions = ["plan", "repair", "execute", "submit", "approve"] as const;
const grant = d.object({
  id: d.token,
  /** name is null when the identity no longer exists (api 12562f5ca). */
  service_identity: d.object({ id: d.token, name: d.nullable(d.string) }),
  policy_version: d.integer,
  allowed_actions: d.array(d.known(grantActions), 10),
  maximum_horizon_seconds: d.integer,
  maximum_contacts: d.integer,
  maximum_execution_concurrency: d.integer,
  /** #283: null on a proposal (validity starts at approval, `validity_seconds` long). */
  valid_from: d.nullable(d.timestamp),
  valid_until: d.nullable(d.timestamp),
  /**
   * #283 (U105): proposals. `expired` is derived on read: an active grant past valid_until, or a
   * proposal undecided past proposal_expires_at. An unknown state reads as unrecognized.
   */
  state: d.known(["proposed", "active", "rejected", "revoked", "withdrawn", "expired"] as const),
  approved_by: orNull(actor),
  approved_at: d.nullable(d.timestamp),
  /**
   * #283 keys, read as null when an older server leaves them out (readers first). Person objects are
   * {id, name}, both null for a non-member.
   */
  validity_seconds: orNull(d.integer),
  proposed_by: orNull(actor),
  proposed_at: orNull(d.timestamp),
  proposal_expires_at: orNull(d.timestamp),
  rejected_by: orNull(actor),
  rejected_at: orNull(d.timestamp),
  // free-text: the reason the deciding admin gave when rejecting it.
  rejection_reason: orNull(d.string),
  withdrawn_by: orNull(actor),
  withdrawn_at: orNull(d.timestamp),
  replaces_grant_id: orNull(d.token),
  viewer_can_decide: orNull(d.boolean),
  cannot_decide_because: orNull(
    d.knownText([
      "not_admin",
      "not_a_person",
      "proposer",
      "accountable",
      "authors_unknown",
      "not_proposed",
      "policy_changed",
    ] as const),
  ),
  cannot_decide_details: orNull(d.object({ grantee: orNull(actor), service: orNull(actor) })),
  /** #497: the viewer may narrow it now (the server's flag; the console never computes it). */
  viewer_can_narrow: orNull(d.boolean),
  /** #497: issued before #283, so it can only be revoked; its proposal fields read null. */
  issued_before_two_person_approval: orNull(d.boolean),
  // free-text: the reason the admin gave when granting it.
  reason: d.nullable(d.string),
  revoked_by: orNull(actor),
  revoked_at: d.nullable(d.timestamp),
  // free-text: the reason given when revoking it.
  revocation_reason: d.nullable(d.string),
  sha256: d.string,
});
export type Grant = Decoded<typeof grant>;

export const grantsReader = d.object({
  grants: d.array(grant, 500),
  service_identities: d.array(
    d.object({ id: d.token, name: d.string, state: d.known(["active", "disabled"] as const) }),
    500,
  ),
  /** The active policy's ceilings, for the form's hints; null = the policy sets none. */
  limits: d.object({
    maximum_horizon_seconds: d.nullable(d.integer),
    maximum_contacts: d.nullable(d.integer),
    maximum_execution_concurrency: d.nullable(d.integer),
  }),
  policy_version: d.nullable(d.integer),
  permissions: d.array(d.known(["grants.manage"] as const), 10),
  /** #283: the mission's approval setting for grants; null from an older server. */
  approval_setting: orNull(d.knownText(["independent", "direct"] as const)),
});
export type Grants = Decoded<typeof grantsReader>;

export function fetchGrants(missionId: MissionId, signal: AbortSignal) {
  return request(base(missionId), grantsReader, { signal });
}

export type GrantBody = Readonly<{
  service_identity_id: string;
  maximum_horizon_seconds: number;
  maximum_contacts: number;
  maximum_execution_concurrency: number;
  valid_days: number;
  reason: string;
  policy_version: number;
}>;
export function issueGrant(missionId: MissionId, body: GrantBody) {
  return request(base(missionId), d.object({ grant }), { method: "POST", body });
}
/** #283: revoke is at once and never refused for a reason or a hash; a reason goes when given. */
export function revokeGrant(missionId: MissionId, g: Grant, reason: string) {
  const why = reason.trim();
  return request(`${base(missionId)}/${encodeURIComponent(g.id)}/revoke`, d.object({ grant }), {
    method: "POST",
    body: why ? { reason: why } : {},
  });
}

/** #283 decisions answer the grant and whether this was a replay of an earlier operation_id. */
const decided = d.object({ grant, replayed: orNull(d.boolean) });
export type Decided = Decoded<typeof decided>;
const decide = (missionId: MissionId, g: Grant, act: string, body: Record<string, unknown>) =>
  request(`${base(missionId)}/${encodeURIComponent(g.id)}/${act}`, decided, {
    method: "POST",
    body,
  });
/** Approve the proposal as read (its sha256). */
export const approveGrant = (missionId: MissionId, g: Grant, operationId: string) =>
  decide(missionId, g, "approve", { sha256: g.sha256, operation_id: operationId });
export const rejectGrant = (missionId: MissionId, g: Grant, reason: string, operationId: string) =>
  decide(missionId, g, "reject", { reason, operation_id: operationId });
export type NarrowChanges = Readonly<
  Partial<{
    allowed_actions: readonly string[];
    maximum_horizon_seconds: number;
    maximum_contacts: number;
    maximum_execution_concurrency: number;
    validity_seconds: number;
  }>
>;
export const narrowGrant = (
  missionId: MissionId,
  g: Grant,
  changes: NarrowChanges,
  operationId: string,
) => decide(missionId, g, "narrow", { changes, operation_id: operationId });

/**
 * #257's rule for operation ids (as reviewOps): a retry of the SAME request reuses its id, so the
 * server replays what already happened; a changed request is a new id.
 */
export function operationIds(newId: () => string = () => crypto.randomUUID()) {
  let last: Readonly<{ key: string; id: string }> | null = null;
  return (key: string): string => {
    if (last?.key !== key) last = { key, id: newId() };
    return last.id;
  };
}

const ACTION_WORDS: Readonly<Record<Grant["allowed_actions"][number], string>> = {
  plan: "plan",
  repair: "repair",
  execute: "book",
  submit: "submit",
  approve: "approve",
  unrecognized: "other",
};
/** "plan, repair, submit". */
export const canText = (g: Grant) => g.allowed_actions.map((a) => ACTION_WORDS[a]).join(", ");
/** "48h 00m · 40 contacts · 2 at once". */
export const limitsText = (g: Grant) =>
  `${formatDuration(g.maximum_horizon_seconds)} · ${plural(g.maximum_contacts, "contact")} · ${g.maximum_execution_concurrency} at once`;

/** U105's state tags (mark + word, B2). */
export function grantTag(g: Grant): {
  state: "nominal" | "caution" | "off" | "stale";
  label: string;
} {
  switch (g.state) {
    case "proposed":
      return { state: "caution", label: "PROPOSED" };
    case "active":
      return { state: "nominal", label: "ACTIVE" };
    case "expired":
      return { state: "stale", label: "EXPIRED" };
    case "rejected":
      return { state: "off", label: "REJECTED" };
    case "withdrawn":
      return { state: "off", label: "WITHDRAWN" };
    case "revoked":
      return { state: "off", label: "REVOKED" };
    case "unrecognized":
      return { state: "off", label: "UNKNOWN" };
  }
}
/**
 * "12-19 06:40Z". A proposal (valid_until null until approval) reads its validity from approval
 * (U105): whole days, else whole hours, else the exact span, never rounded; "Set at approval"
 * without one. A decided proposal with no valid_until (rejected, withdrawn, expired) reads "—"
 * (ca-ux, #496).
 */
export function untilText(g: Grant): string {
  if (g.valid_until !== null) return formatShort(new Date(g.valid_until));
  if (g.state !== "proposed") return "—";
  const s = g.validity_seconds;
  if (s === null) return "Set at approval";
  const span =
    s % 86_400 === 0
      ? plural(s / 86_400, "day")
      : s % 3_600 === 0
        ? plural(s / 3_600, "hour")
        : formatDuration(s);
  return `${span} from approval`;
}

/** "Night ops bot"; a null name reads "Unknown service identity", never its id (U25, U105). */
export const identityName = (g: Grant) => g.service_identity.name ?? "Unknown service identity";

/** 422 messages with no field of their own (the grant as a whole, the policy evidence). */
export const generalError = (errors: Readonly<Record<string, string>>) =>
  errors["grant"] ?? (errors["policy_version"] ? "Reload: the active policy changed." : null);

/** One sentence for a refused grant write (U20). */
export function grantFailure(error: ApiError): string {
  if (isError(error, "policy_changed"))
    return "The active policy changed since you loaded it. Reload, then grant again.";
  if (isError(error, "grant_changed"))
    return "This grant changed since you loaded it. Reload to see it.";
  return failureOutcome(error, "changed").sentence;
}

/** The Grant automation sheet's draft: numbers as typed (horizon in hours). */
export type GrantDraft = Readonly<{
  identity: string;
  hours: string;
  contacts: string;
  concurrency: string;
  days: string;
  reason: string;
}>;
export const blankGrant: GrantDraft = {
  identity: "",
  hours: "",
  contacts: "",
  concurrency: "",
  days: "30",
  reason: "",
};
const whole = (text: string) => (/^\d+$/.test(text.trim()) ? Number(text.trim()) : null);

/** The POST body, or why it can't go yet (the button's disabled reason). */
export function grantBody(
  g: GrantDraft,
  policyVersion: number | null,
): { ok: true; body: GrantBody } | { ok: false; why: string } {
  if (policyVersion === null) return { ok: false, why: "Activate a policy first." };
  if (!g.identity) return { ok: false, why: "Choose a service identity." };
  const [hours, contacts, concurrency, days] = [g.hours, g.contacts, g.concurrency, g.days].map(
    whole,
  );
  if (!hours || !contacts || !concurrency || !days)
    return { ok: false, why: "Limits and days are whole numbers above 0." };
  if (!g.reason.trim()) return { ok: false, why: "Give a reason first." };
  return {
    ok: true,
    body: {
      service_identity_id: g.identity,
      maximum_horizon_seconds: hours * 3600,
      maximum_contacts: contacts,
      maximum_execution_concurrency: concurrency,
      valid_days: days,
      reason: g.reason.trim(),
      policy_version: policyVersion,
    },
  };
}

/** "Policy allows up to 48h" etc., or undefined when the policy sets no ceiling. */
export const ceiling = (n: number | null, unit: (n: number) => string) =>
  n === null ? undefined : `The policy allows up to ${unit(n)}.`;
