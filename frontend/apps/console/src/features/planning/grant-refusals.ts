import { decoders as d, detailsOf, isError, isKnown, orNull, type ApiError } from "@/api";
import {
  accountableLine,
  authorsUnknownLine,
  POLICY_CHANGED,
  serviceOf,
  when,
  withCode,
  type Worded,
} from "./grant-words.ts";
import type { Grant } from "./grants.ts";

/**
 * ux U105's refusals for automation-grant acts (#283): approve, reject, narrow, revoke and issue.
 * Each opens with its act ("Not approved:"), says nothing was recorded, and puts a code the
 * console doesn't word in Technical details, never on the line.
 */

const personRef = d.object({ id: d.nullable(d.string), name: d.nullable(d.string) });
const decidedBy = (value: unknown, path?: string) =>
  value === undefined || value === null
    ? null
    : typeof value === "string"
      ? { id: value, name: null }
      : personRef(value, path);
const notProposed = d.object({
  state: d.knownText([
    "proposed",
    "active",
    "rejected",
    "revoked",
    "withdrawn",
    "expired",
  ] as const),
  decided_by: decidedBy,
  decided_at: (value: unknown, path?: string) =>
    value === undefined || value === null ? null : d.timestamp(value, path),
});
const forbidden = d.object({
  because: orNull(d.knownText(["proposed", "accountable"] as const)),
  grantee: (value: unknown, path?: string) =>
    value === undefined || value === null ? null : personRef(value, path),
});
const authors = d.object({
  service: (value: unknown, path?: string) =>
    value === undefined || value === null ? null : personRef(value, path),
});

const NOT_RECORDED = "Your approval wasn't recorded.";
const DUPLICATE = "Cadence matched this to an earlier, different request";
const LEGACY_WHY =
  "this grant was made before Cadence checked grants against the mission's approval setting, so it can only be revoked";

/** U105 (U97): 409 automation_grant_not_proposed for approve. */
function approveNotProposed(e: ApiError, viewerId: string | null): string {
  const n = detailsOf(e, notProposed);
  const verb = n?.state === "rejected" ? "rejected" : "approved";
  if (n?.decided_at && (n.state === "active" || n.state === "rejected")) {
    const at = when(n.decided_at);
    if (viewerId !== null && n.decided_by?.id === viewerId)
      return `You already ${verb} this grant at ${at}. Reload to see it.`;
    const by = n.decided_by?.name ? ` by ${n.decided_by.name}` : "";
    return `This grant was already ${verb}${by} at ${at}, so your approval wasn't recorded. Reload to see it.`;
  }
  const state = n?.state;
  const refusedNow = `Not approved: Cadence refused this approval. ${NOT_RECORDED}`;
  if (state === undefined || !isKnown(state)) return refusedNow;
  switch (state) {
    case "expired":
      return `Not approved: no one decided this grant in time, so it expired. ${NOT_RECORDED} It has to be proposed again.`;
    case "rejected":
    case "active":
      return `Not approved: this grant was already ${verb}, so your approval wasn't recorded. Reload to see it.`;
    case "revoked":
      return "Not approved: this grant was revoked, so your approval wasn't recorded. Reload to see it.";
    case "withdrawn":
      return "Not approved: this proposal was withdrawn when the grant it would replace was revoked, so your approval wasn't recorded. Reload to see it.";
    case "proposed":
      return refusedNow;
  }
}

/** U105's approve refusals; `disable` keeps Approve off with the up-front line afterwards. */
export function approveFailure(
  e: ApiError,
  g: Grant,
  viewerId: string | null,
): Worded & { disable?: Worded } {
  const s = serviceOf(g);
  if (isError(e, "automation_grant_self_approval_forbidden")) {
    const f = detailsOf(e, forbidden);
    if (f?.because === "accountable") {
      const who = f.grantee?.name ?? s;
      const text = who
        ? `Not approved: you're accountable for ${who}, so another org admin approves its grant. ${NOT_RECORDED}`
        : `Not approved: you're accountable for the service identity this grant is for, so another org admin approves it. ${NOT_RECORDED}`;
      return { text, disable: { text: accountableLine(who) } };
    }
    return {
      text: `Not approved: you proposed this grant, so another org admin approves it. ${NOT_RECORDED}`,
      disable: { text: "You proposed this grant, so another org admin approves it." },
    };
  }
  if (isError(e, "automation_grant_approver_authors_unknown")) {
    const who = detailsOf(e, authors)?.service?.name ?? s;
    return {
      text: `Not approved: ${authorsUnknownLine(who)} ${NOT_RECORDED}`,
      disable: { text: authorsUnknownLine(who) },
    };
  }
  if (isError(e, "automation_grant_not_proposed")) return { text: approveNotProposed(e, viewerId) };
  if (isError(e, "approval_policy_changed"))
    return {
      text: `Not approved: the mission's approval setting changed after this grant was proposed. ${NOT_RECORDED} It has to be proposed again.`,
      disable: { text: POLICY_CHANGED },
    };
  if (isError(e, "grant_changed"))
    return {
      text: `Not approved: this grant changed since you loaded it. ${NOT_RECORDED} Reload to see it.`,
    };
  if (isError(e, "authenticated_user_required"))
    return {
      text: `Not approved: only a person can approve a grant, not a service identity. ${NOT_RECORDED}`,
    };
  if (isError(e, "automation_grant_capability_required"))
    return {
      text: `Not approved: this grant lets ${s ?? "the service identity this grant is for"} do something you can't do yourself, so you can't approve it. An org admin who can do everything it allows approves it. ${NOT_RECORDED}`,
    };
  if (isError(e, "duplicate_operation"))
    return {
      text: `Not approved: ${DUPLICATE}, so your approval wasn't recorded. Reload and try again.`,
    };
  if (isError(e, "automation_grant_legacy"))
    return { text: `Not approved: ${LEGACY_WHY}. ${NOT_RECORDED}` };
  return withCode(`Not approved: Cadence refused this approval. ${NOT_RECORDED}`, e);
}

/** Reject's refusals (U105 where it words them; the rest follow its "Not rejected: …" lines). */
export function rejectFailure(e: ApiError): Worded {
  if (isError(e, "automation_grant_not_proposed")) {
    const state = detailsOf(e, notProposed)?.state;
    if (state === "expired")
      return {
        text: "Not rejected: no one decided this grant in time, so it expired. Nothing changed.",
      };
    if (state === "withdrawn")
      return {
        text: "Not rejected: this proposal was withdrawn when the grant it would replace was revoked, so nothing changed. Reload to see it.",
      };
    if (state === "active" || state === "rejected" || state === "revoked")
      return {
        text: `Not rejected: this grant was already ${state === "active" ? "approved" : state}, so nothing changed. Reload to see it.`,
      };
  }
  if (isError(e, "authenticated_user_required"))
    return {
      text: "Not rejected: only a person can reject a grant, not a service identity. Nothing changed.",
    };
  if (isError(e, "automation_grant_legacy"))
    return { text: `Not rejected: ${LEGACY_WHY}. Nothing changed.` };
  if (isError(e, "duplicate_operation"))
    return { text: `Not rejected: ${DUPLICATE}, so nothing changed. Reload and try again.` };
  return withCode("Not rejected: Cadence refused this rejection, so nothing changed.", e);
}

const narrowFields = [
  "allowed_actions",
  "maximum_horizon_seconds",
  "maximum_contacts",
  "maximum_execution_concurrency",
  "validity_seconds",
] as const;
/** U105: the sheet's labels name the widening fields; an unknown one is a code only. */
const NARROW_FIELD_LABELS: Readonly<Record<(typeof narrowFields)[number], string>> = {
  allowed_actions: "Can",
  maximum_horizon_seconds: "Plans ahead up to",
  maximum_contacts: "Contacts per plan, at most",
  maximum_execution_concurrency: "At once, at most",
  validity_seconds: "Valid for",
};
const widening = d.object({ fields: orNull(d.array(d.knownText(narrowFields), 20)) });

/** Narrow's refusals (U105). */
export function narrowFailure(e: ApiError, g: Grant): Worded {
  const s = serviceOf(g) ?? "the service identity this grant is for";
  if (isError(e, "automation_grant_not_narrower")) {
    const fields = detailsOf(e, widening)?.fields ?? [];
    const labels = fields.flatMap((f) => (isKnown(f) ? [NARROW_FIELD_LABELS[f]] : []));
    const unknown = fields.flatMap((f) => (isKnown(f) ? [] : [f.unrecognized]));
    const bracket = labels.length ? ` (${labels.join(", ")})` : "";
    const text = `Not narrowed: this change gives ${s} more than it has now${bracket}, so it needs approval. Propose it as a new grant instead.`;
    return unknown.length ? { text, code: unknown.join(", ") } : { text };
  }
  if (isError(e, "automation_grant_narrow_unchanged"))
    return {
      text: "Not narrowed: these values are the ones the grant has now, so nothing changed. Choose less than it allows, or cancel.",
    };
  if (isError(e, "automation_grant_legacy"))
    return {
      text: `Not narrowed: ${LEGACY_WHY}. Nothing changed. To change it, propose a new grant.`,
    };
  if (isError(e, "authenticated_user_required"))
    return {
      text: "Not narrowed: only a person can narrow a grant, not a service identity. Nothing changed.",
    };
  if (isError(e, "duplicate_operation"))
    return { text: `Not narrowed: ${DUPLICATE}, so nothing changed. Reload and try again.` };
  if (isError(e, "automation_grant_not_active"))
    return {
      text: "Not narrowed: this grant isn't active any more, so nothing changed. Reload to see it.",
    };
  return withCode("Not narrowed: Cadence refused this change, so nothing changed.", e);
}

/** Revoke's refusals the console words itself; the rest are the grant write's U20 sentence. */
export function revokeFailure(e: ApiError): string | null {
  if (isError(e, "authenticated_user_required"))
    return "Not revoked: only a person can revoke a grant, not a service identity. Nothing changed.";
  if (isError(e, "automation_grant_not_active"))
    return "Not revoked: this grant isn't active any more, so nothing changed. Reload to see it.";
  return null;
}

/** Issue's person-only and #281 refusals (U105); null: the grant write's U20 sentence. */
export function issueFailure(e: ApiError, direct: boolean, service: string | null): string | null {
  if (isError(e, "authenticated_user_required"))
    return direct
      ? "Not granted: only a person can grant automation, not a service identity."
      : "Not proposed: only a person can propose a grant, not a service identity.";
  if (isError(e, "automation_grant_capability_required")) {
    const s = service ?? "the service identity this grant is for";
    return direct
      ? `Not granted: this grant would let ${s} do something you can't do yourself, so you can't grant it. Ask an org admin who can do everything it allows to grant it.`
      : `Not proposed: this grant would let ${s} do something you can't do yourself, so you can't propose it. Ask an org admin who can do everything it allows to propose it.`;
  }
  return null;
}
