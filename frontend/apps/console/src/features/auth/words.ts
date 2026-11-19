import { roleText } from "@/api";
import type { Invitation } from "./api.ts";

/** Auth.md wording (L5). Actor and time only when the server gives them (U29). */

/** The shared role words (api/entities.ts); a role the console doesn't know shows the server's word. */
export const roleWord = (role: Invitation["role"]) => (role === null ? null : roleText(role));

/** MM-DD (§4 short date). */
const day = (iso: string) => iso.slice(5, 10);

/** "Mira K. invited you to Acme Space as Member on 11-10." */
export function invitationHeader(i: Invitation): string | null {
  // `unknown` (and anything without an organization) has no header (session.md: all fields null).
  if (!i.organization) return null;
  const who = i.invited_by?.name;
  const role = roleWord(i.role);
  const on = i.invited_at ? ` on ${day(i.invited_at)}` : "";
  const as = role ? ` as ${role}` : "";
  return who
    ? `${who} invited you to ${i.organization.name}${as}${on}.`
    : `You're invited to ${i.organization.name}${as}${on}.`;
}

export type InvitationView = Readonly<{
  /** One h1 per screen (shell contract #3, qa): every case has one. */
  h1: string;
  callout: { tone: "caution" | "off"; text: string } | null;
}>;

/** The Auth.md case table: h1 and callout per case (forms and actions live in the screen). */
export function invitationView(i: Invitation, signedInAs: string | null): InvitationView {
  const org = i.organization?.name ?? "this organization";
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
        h1: "Invitation for another account",
        callout: {
          tone: "caution",
          text: `This invitation is for ${i.email ?? "another account"}.${signedInAs ? ` You're signed in as ${signedInAs}.` : ""}`,
        },
      };
    case "expired":
      return {
        h1: "Invitation expired",
        callout: {
          tone: "off",
          text: `This invitation expired${i.expires_at ? ` on ${day(i.expires_at)}` : ""}.${who ? ` Ask ${who} for a new one.` : " Ask for a new one."}`,
        },
      };
    case "withdrawn": {
      const by = i.withdrawn_by?.name ?? who;
      return {
        h1: "Invitation withdrawn",
        callout: {
          tone: "off",
          text: by ? `${by} withdrew this invitation.` : "This invitation was withdrawn.",
        },
      };
    }
    case "accepted":
    case "used":
      return {
        h1: "Already accepted",
        callout: { tone: "off", text: "This invitation was already accepted." },
      };
    case "declined":
      return {
        h1: "Invitation declined",
        callout: {
          tone: "off",
          text: "This invitation was declined. Ask for a new one if you want to join.",
        },
      };
    case "unavailable":
      return {
        h1: "Invitation unavailable",
        callout: {
          tone: "off",
          text: "This invitation isn't available any more. Ask for a new one.",
        },
      };
    case "unknown":
      return { h1: "Invitation not valid", callout: { tone: "off", text: UNKNOWN_INVITATION } };
    case "unrecognized":
      return {
        h1: "Invitation unavailable",
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
