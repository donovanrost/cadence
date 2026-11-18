import {
  decoders as d,
  detailsOf,
  invitationState,
  invitedBy,
  isError,
  isKnown,
  request,
  role,
  roleText,
  type ApiError,
  type ApiResult,
  type Decoded,
  type InvitationState,
} from "@/api";
import { formatShort } from "@/ui";

/** Contract: api cfdf79f7 (L21): the signed-in user's pending invitations to other organizations. */
const organization = d.object({ id: d.token, slug: d.token, name: d.string });
const invitation = d.object({
  id: d.token,
  organization,
  role,
  invited_by: invitedBy,
  invited_at: d.timestamp,
  expires_at: d.nullable(d.timestamp),
});
export const myInvitationsReader = d.object({ invitations: d.array(invitation, 200) });
export type MyInvitation = Decoded<typeof invitation>;

export async function fetchMyInvitations(
  _key: true,
  signal: AbortSignal,
): Promise<ApiResult<readonly MyInvitation[]>> {
  const r = await request("/account/invitations", myInvitationsReader, { signal });
  return r.ok ? { ok: true, value: r.value.invitations } : r;
}

export function acceptInvitation(id: string) {
  return request(
    `/account/invitations/${encodeURIComponent(id)}/accept`,
    d.object({ organization, role }),
    { method: "POST", body: {} },
  );
}

export function declineInvitation(id: string) {
  return request(
    `/account/invitations/${encodeURIComponent(id)}/decline`,
    d.object({ id: d.token, status: d.known(["declined"] as const) }),
    { method: "POST", body: {} },
  );
}

/** `Acme Space · Member · invited by Mira K. on 11-10` (People.md Account). */
export function invitationLine(i: MyInvitation): string {
  const roleWord = roleText(i.role);
  const by = i.invited_by?.name ? `invited by ${i.invited_by.name}` : "invited";
  return `${i.organization.name} · ${roleWord} · ${by} on ${formatShort(new Date(i.invited_at)).slice(0, 5)}`;
}

const notPendingWords: Readonly<Record<InvitationState, string>> = {
  pending: "",
  accepted: "You've already accepted it.",
  revoked: "It was withdrawn by the organization.",
  withdrawn: "It was withdrawn by the organization.",
  declined: "You've already declined it.",
  expired: "It expired.",
};

/** 404 (unknown or not yours, same answer) and 409 invitation_not_pending (by details.status). */
export function invitationFailure(e: ApiError): string | null {
  if (e.kind === "not_found") return "This invitation isn't available any more.";
  if (isError(e, "invitation_not_pending")) {
    const status = detailsOf(e, d.object({ status: invitationState }))?.status;
    const why = status && isKnown(status) ? notPendingWords[status] : "";
    return `This invitation isn't pending any more. ${why}`.trim();
  }
  return null;
}
