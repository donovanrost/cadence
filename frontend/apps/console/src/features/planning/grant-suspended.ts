import { decoders as d, detailsOf, isError, isKnown, orNull, type ApiError } from "@/api";
import { named, serviceOf, subject, when, withCode, type Worded } from "./grant-words.ts";
import { untilText, type Grant, type Grants } from "./grants.ts";

/**
 * ux U105 "Suspended" (#499): a grant a tightening of the approval setting suspended, its row line,
 * Resume…'s up-front reasons (A6, from the server's flags only) and its refusals. A nameless
 * service reads "the service identity this grant is for", never its id (U25).
 */

const TIGHTER = "Needs a second person's approval";

/** U105: which save tightened it; an unknown or missing level claims neither. */
function whose(level: NonNullable<Grant["suspension"]>["level"]): string {
  if (level === "mission") return "the mission's approval setting";
  if (level === "organization") return "the organization's approval setting";
  return "the approval setting for this mission";
}

/**
 * The row line: who saved the tightening, when, and who resumes it now (the setting in force; an
 * unread setting gives the stricter form).
 */
export function suspendedLine(g: Grant, setting: Grants["approval_setting"]): string | null {
  if (g.state !== "suspended") return null;
  const s = g.suspension;
  const resumes =
    setting === "direct" ? "An org admin resumes it." : "A second org admin resumes it.";
  // ca-ux on #565: without a suspension record the line still says who resumes it.
  if (s === null) return `Suspended. ${resumes}`;
  const by = named(s.by);
  const what = whose(s.level);
  const head = by
    ? `Suspended when ${by} changed ${what} to ${TIGHTER} at ${when(s.at)}.`
    : `Suspended when ${what} changed to ${TIGHTER} at ${when(s.at)}.`;
  return `${head} ${resumes}`;
}

/** Resume…'s muted line (U105). */
export const resumeLine = (g: Grant) =>
  g.valid_until
    ? `It takes effect again at once. ${subject(g)} can act under it until ${untilText(g)}.`
    : "It takes effect again at once.";

/** The answer's line, claimed only on a confirmed state (U20). */
export const resumedLine = (g: Grant) =>
  g.state === "active" && g.valid_until
    ? `Resumed. ${subject(g)} can act under it until ${untilText(g)}.`
    : "Cadence didn't confirm that it resumed. Reload to see it.";

const accountable = (service: string | null) =>
  service
    ? `You're accountable for ${service}, so another org admin resumes its grant.`
    : "You're accountable for the service identity this grant is for, so another org admin resumes it.";
const authorsUnknown = (service: string | null) =>
  `${service ?? "The service identity this grant is for"} has no one recorded as accountable for it, so its grant can't be resumed yet.`;
const RECORD_AUTHORS = "An org admin records who's accountable in People › Service identities.";
const CANT = "You can't resume this grant, so another org admin resumes it.";

/**
 * Resume… on a suspended grant, from viewer_can_decide and cannot_decide_because only (A6):
 * `none` (no Resume), or Resume with its disabled reason (null: on).
 */
export type ResumeOffer =
  | Readonly<{ kind: "none" }>
  | Readonly<{ kind: "act"; blocked: Worded | null }>;

export function resumeOffer(g: Grant): ResumeOffer {
  if (g.state !== "suspended") return { kind: "none" };
  const why = g.cannot_decide_because;
  if (g.viewer_can_decide !== false || why === null) return { kind: "act", blocked: null };
  if (!isKnown(why)) return { kind: "act", blocked: { text: CANT, code: why.unrecognized } };
  const details = g.cannot_decide_details;
  switch (why) {
    case "not_admin":
    case "not_a_person":
    case "not_proposed":
      return { kind: "none" };
    case "approved":
      return {
        kind: "act",
        blocked: { text: "You approved this grant, so another org admin resumes it." },
      };
    case "proposer":
      return {
        kind: "act",
        blocked: { text: "You proposed this grant, so another org admin resumes it." },
      };
    case "accountable":
      return {
        kind: "act",
        blocked: { text: accountable(named(details?.grantee ?? null) ?? serviceOf(g)) },
      };
    case "authors_unknown":
      return {
        kind: "act",
        blocked: {
          text: `${authorsUnknown(named(details?.service ?? null) ?? serviceOf(g))} ${RECORD_AUTHORS}`,
        },
      };
    case "policy_changed":
      // ca-ux on #565: not the viewer's doing, so it doesn't read as their refusal.
      return {
        kind: "act",
        blocked: {
          text: "The approval setting for this mission changed after this grant was suspended, so who can resume it may have changed. Reload to see it.",
        },
      };
  }
}

const person = d.object({ id: d.nullable(d.string), name: d.nullable(d.string) });
const optionalPerson = (value: unknown, path?: string) =>
  value === undefined || value === null ? null : person(value, path);
const forbidden = d.object({
  because: orNull(d.knownText(["approved", "proposed", "accountable"] as const)),
  grantee: optionalPerson,
});
const authors = d.object({ service: optionalPerson });
const notSuspended = d.object({
  state: orNull(d.knownText(["expired", "active", "revoked"] as const)),
});
const NOTHING = "Nothing changed.";

/** U105's resume refusals; `disable` keeps Resume off with its up-front line afterwards. */
/** ux on #570: Resume's A6 reason while it stays off after a separation refusal. */
const REFUSED: Worded = { text: "Resume was refused. Reload to see the grant as it is now." };

export function resumeFailure(e: ApiError, g: Grant): Worded & { disable?: Worded } {
  const s = serviceOf(g);
  if (isError(e, "automation_grant_self_approval_forbidden")) {
    const f = detailsOf(e, forbidden);
    if (f?.because === "accountable") {
      const who = f.grantee?.name ?? s;
      const why = who
        ? `you're accountable for ${who}, so another org admin resumes its grant`
        : "you're accountable for the service identity this grant is for, so another org admin resumes it";
      return { text: `Not resumed: ${why}. ${NOTHING}`, disable: REFUSED };
    }
    const verb = f?.because === "approved" ? "approved" : "proposed";
    return {
      text: `Not resumed: you ${verb} this grant, so another org admin resumes it. ${NOTHING}`,
      disable: REFUSED,
    };
  }
  if (isError(e, "automation_grant_approver_authors_unknown")) {
    const who = detailsOf(e, authors)?.service?.name ?? s;
    const mid = `${who ?? "the service identity this grant is for"} has no one recorded as accountable for it, so its grant can't be resumed yet.`;
    return {
      text: `Not resumed: ${mid} ${NOTHING} ${RECORD_AUTHORS}`,
      disable: REFUSED,
    };
  }
  if (isError(e, "automation_grant_capability_required"))
    return {
      text: `Not resumed: this grant lets ${s ?? "the service identity this grant is for"} do something you can't do yourself, so you can't resume it. ${NOTHING} Ask an org admin who can do everything it allows to resume it.`,
      disable: REFUSED,
    };
  if (isError(e, "automation_grant_legacy"))
    return {
      text: `Not resumed: this grant was made before Cadence checked grants against the mission's approval setting, so it can only be revoked. ${NOTHING} To change it, propose a new grant.`,
    };
  if (isError(e, "automation_grant_not_suspended")) return { text: notSuspendedLine(e) };
  if (isError(e, "grant_changed"))
    return {
      text: `Not resumed: the grant changed after you opened it. ${NOTHING} Reload to see it, then resume it again.`,
    };
  if (isError(e, "authenticated_user_required"))
    return {
      text: `Not resumed: only a person can resume a grant, not a service identity. ${NOTHING}`,
    };
  if (isError(e, "duplicate_operation"))
    return {
      text: "Not resumed: Cadence matched this to an earlier, different request, so nothing changed. Reload and try again.",
    };
  return withCode(`Not resumed: Cadence refused this. ${NOTHING}`, e);
}

function notSuspendedLine(e: ApiError): string {
  const state = detailsOf(e, notSuspended)?.state;
  if (state === "expired")
    return `Not resumed: this grant's validity ended, so it can't be resumed. ${NOTHING} To go on, propose a new grant.`;
  if (state === "active") return `Not resumed: it's active again. ${NOTHING} Reload to see it.`;
  if (state === "revoked") return `Not resumed: it was revoked. ${NOTHING} Reload to see it.`;
  return `Not resumed: it isn't suspended any more. ${NOTHING} Reload to see it.`;
}
