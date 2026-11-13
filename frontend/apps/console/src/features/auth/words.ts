import type { Invitation, InvitationRole } from "./api.ts";

/** Auth.md wording (L5). Actor and time only when the server gives them (U29). */

/** People's words for the roles; an unrecognized role drops the "as …" clause (U29 spirit). */
const ROLE: Readonly<Record<InvitationRole, string | null>> = {
  organization_admin: "Org admin",
  member: "Member",
  unrecognized: null,
};
export const roleWord = (role: InvitationRole | null) => (role ? ROLE[role] : null);

/** MM-DD (§4 short date). */
const day = (iso: string) => iso.slice(5, 10);

/** "Mira K. invited you to Acme Space as Member on 11-10." */
export function invitationHeader(i: Invitation): string {
  const who = i.invited_by?.name;
  const role = roleWord(i.role);
  const on = i.invited_at ? ` on ${day(i.invited_at)}` : "";
  const as = role ? ` as ${role}` : "";
  return who
    ? `${who} invited you to ${i.organization.name}${as}${on}.`
    : `You're invited to ${i.organization.name}${as}${on}.`;
}

export type InvitationView = Readonly<{
  h1: string | null;
  callout: { tone: "caution" | "off"; text: string } | null;
}>;

/** The Auth.md case table: h1 and callout per case (forms and actions live in the screen). */
export function invitationView(i: Invitation, signedInAs: string | null): InvitationView {
  const org = i.organization.name;
  const who = i.invited_by?.name;
  switch (i.case) {
    case "new_account":
      return { h1: `Join ${org}`, callout: null };
    case "existing_account":
      return { h1: `Sign in to join ${org}`, callout: null };
    case "signed_in_match":
      return { h1: `Join ${org}?`, callout: null };
    case "signed_in_other":
      return {
        h1: null,
        callout: {
          tone: "caution",
          text: `This invitation is for ${i.email}.${signedInAs ? ` You're signed in as ${signedInAs}.` : ""}`,
        },
      };
    case "expired":
      return {
        h1: null,
        callout: {
          tone: "off",
          text: `This invitation expired${i.expires_at ? ` on ${day(i.expires_at)}` : ""}.${who ? ` Ask ${who} for a new one.` : " Ask for a new one."}`,
        },
      };
    case "withdrawn": {
      const by = i.withdrawn_by?.name ?? who;
      return {
        h1: null,
        callout: {
          tone: "off",
          text: by ? `${by} withdrew this invitation.` : "This invitation was withdrawn.",
        },
      };
    }
    case "accepted":
      return { h1: null, callout: { tone: "off", text: "This invitation was already accepted." } };
    case "unrecognized":
      return {
        h1: null,
        callout: { tone: "off", text: "This invitation can't be used here. Ask for a new one." },
      };
    default: {
      const unhandled: never = i.case;
      return unhandled;
    }
  }
}

export const UNKNOWN_INVITATION = "This invitation link isn't valid.";
export const WRONG_CREDENTIALS = "That email and password don't match.";
export const UNREACHABLE = "Couldn't reach Cadence. Try again.";
