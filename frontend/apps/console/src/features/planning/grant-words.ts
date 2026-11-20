import { codeOf, isKnown, type ApiError } from "@/api";
import { formatShort, plural } from "@/ui";
import { canText, untilText, type Grant, type Grants } from "./grants.ts";

/**
 * ux U105's words for automation grants (#283): row state lines, the Waiting for approval panel,
 * its up-front reasons (A6, from the server's flags only) and every refusal. A nameless service
 * reads "the service identity this grant is for", never its id (U25).
 */

export const when = (iso: string) => formatShort(new Date(iso));
export const named = (p: Readonly<{ name: string | null }> | null) => p?.name ?? null;
/** "Nightly planner", or null when the service has no name to show. */
export const serviceOf = (g: Grant) => g.service_identity.name;
/** A sentence's subject: the name, or U105's nameless form, never the id (ca-ux). */
export const subject = (g: Grant) =>
  g.service_identity.name ?? "The service identity this grant is for";

export type Worded = Readonly<{ text: string; code?: string }>;
export const withCode = (text: string, e: ApiError): Worded => {
  const code = codeOf(e);
  return code ? { text, code } : { text };
};

/** U105: the row line for a grant made before #283; it can only be revoked. */
export const LEGACY_LINE =
  "Made before Cadence checked grants against the mission's approval setting, so it can only be revoked. To change it, propose a new grant.";
/** U105: Narrow…'s disabled reason on such a grant. */
export const LEGACY_NARROW = "This grant can only be revoked. To change it, propose a new grant.";

/** "Proposed by Mira K. at 11-19 06:40Z" (the name drops when it isn't shown). */
function proposedAt(g: Grant): string | null {
  if (!g.proposed_at) return null;
  const by = named(g.proposed_by);
  return `Proposed${by ? ` by ${by}` : ""} at ${when(g.proposed_at)}`;
}

/** U105's state line under the row's tag; null when the tag and Valid until say it all. */
export function stateLine(g: Grant): string | null {
  switch (g.state) {
    case "proposed": {
      const head = proposedAt(g);
      if (!head) return null;
      return g.proposal_expires_at ? `${head} · decide by ${when(g.proposal_expires_at)}` : head;
    }
    case "expired": {
      // An undecided proposal (approved_at null); an expired active grant keeps today's line.
      if (g.approved_at !== null) return null;
      const head = proposedAt(g);
      return head ? `${head}; no one decided it in time.` : null;
    }
    case "rejected": {
      if (!g.rejected_at) return "Rejected.";
      const by = named(g.rejected_by);
      const why = g.rejection_reason?.trim();
      return `Rejected${by ? ` by ${by}` : ""} at ${when(g.rejected_at)}${why ? `: ${why}` : "."}`;
    }
    case "withdrawn": {
      if (!g.withdrawn_at) return "Withdrawn: the grant it would replace was revoked.";
      const by = named(g.withdrawn_by);
      const end = by
        ? `when ${by} revoked the grant it would replace`
        : "when the grant it would replace was revoked";
      return `Withdrawn at ${when(g.withdrawn_at)}, ${end}.`;
    }
    case "active":
    case "revoked":
    case "unrecognized":
      return null;
  }
}

/** The Waiting for approval panel's line (U105); a viewer who isn't an admin hears who decides. */
export function waitingLine(g: Grant): string {
  const head = proposedAt(g) ?? "Proposed";
  const why = g.reason?.trim().replace(/\.+$/, "");
  const expires = g.proposal_expires_at
    ? ` If no one decides by ${when(g.proposal_expires_at)}, it expires.`
    : "";
  const admins =
    g.cannot_decide_because === "not_admin" || g.cannot_decide_because === "not_a_person"
      ? " Org admins approve grants."
      : "";
  return `${head}${why ? `: ${why}` : ""}. It takes effect once another org admin approves it.${expires}${admins}`;
}

/** Approve's name (B7): "Approve grant for Nightly planner"; nameless, "Approve grant". */
export const approveLabel = (g: Grant) => {
  const s = serviceOf(g);
  return s ? `Approve grant for ${s}` : "Approve grant";
};

export const accountableLine = (service: string | null) =>
  service
    ? `You're accountable for ${service}, so another org admin approves its grant.`
    : "You're accountable for the service identity this grant is for, so another org admin approves it.";
export const authorsUnknownLine = (service: string | null) =>
  `${service ?? "The service identity this grant is for"} has no one recorded as accountable for it, so its grant can't be approved yet. An org admin records who's accountable in People › Service identities.`;
export const POLICY_CHANGED =
  "The mission's approval setting changed after this grant was proposed, so it can't be approved. It has to be proposed again.";

/**
 * What the panel offers, from viewer_can_decide and cannot_decide_because only (A6, #233's
 * pattern): `none` (no panel), `watch` (the line, no actions), or the actions with Approve's
 * disabled reason (null: Approve is on).
 */
export type DecideOffer =
  | Readonly<{ kind: "none" }>
  | Readonly<{ kind: "watch" }>
  | Readonly<{ kind: "act"; blocked: Worded | null }>;

export function decideOffer(g: Grant): DecideOffer {
  if (g.state !== "proposed") return { kind: "none" };
  const why = g.cannot_decide_because;
  // An older server sends no flags: the server stays the backstop.
  if (g.viewer_can_decide !== false || why === null) return { kind: "act", blocked: null };
  if (!isKnown(why))
    return {
      kind: "act",
      blocked: {
        text: "You can't approve this grant, so another org admin approves it.",
        code: why.unrecognized,
      },
    };
  const details = g.cannot_decide_details;
  switch (why) {
    case "not_proposed":
      return { kind: "none" };
    case "not_admin":
    case "not_a_person":
      return { kind: "watch" };
    case "proposer":
      return {
        kind: "act",
        blocked: { text: "You proposed this grant, so another org admin approves it." },
      };
    case "accountable":
      return {
        kind: "act",
        blocked: { text: accountableLine(named(details?.grantee ?? null) ?? serviceOf(g)) },
      };
    case "authors_unknown":
      return {
        kind: "act",
        blocked: { text: authorsUnknownLine(named(details?.service ?? null) ?? serviceOf(g)) },
      };
    case "policy_changed":
      return { kind: "act", blocked: { text: POLICY_CHANGED } };
  }
}

/** U105: the Grant automation sheet follows the mission's approval setting (unread: propose). */
export function sheetWords(
  setting: Grants["approval_setting"],
  service: string | null,
): Readonly<{ title: string; commit: string; busy: string; line: string; direct: boolean }> {
  if (setting === "direct")
    return {
      title: "Grant automation",
      commit: "Grant",
      busy: "Granting…",
      line: "It takes effect at once. No second person's approval is needed, as this mission's setting allows.",
      direct: true,
    };
  return {
    title: "Propose a grant",
    commit: "Propose grant",
    busy: "Proposing…",
    line: `It takes effect once another org admin approves it. Until then ${service ?? "the service identity"} can't act under it.`,
    direct: false,
  };
}

/** The issue answer's line (U105), by the state the server answered. */
export function issuedLine(g: Grant): string {
  if (g.state === "proposed")
    return `Proposed. It takes effect once another org admin approves it.${g.proposal_expires_at ? ` If no one decides by ${when(g.proposal_expires_at)}, it expires.` : ""}`;
  if (g.state === "active" && g.valid_until)
    return `Granted. ${subject(g)} can act under it until ${untilText(g)}.`;
  return "Cadence didn't confirm the grant. Reload to see it.";
}

/** "Narrowed. Nightly planner can now plan and submit, …" (the answer's grant). */
export function narrowedLine(g: Grant): string {
  const hours = g.maximum_horizon_seconds / 3600;
  const ahead = Number.isInteger(hours) ? `${hours} hours` : `${g.maximum_horizon_seconds} seconds`;
  const until = g.valid_until ? `, until ${untilText(g)}` : "";
  return `Narrowed. ${subject(g)} can now ${canText(g)}, planning up to ${ahead} ahead, ${plural(g.maximum_contacts, "contact")} per plan, ${g.maximum_execution_concurrency} at once${until}.`;
}
