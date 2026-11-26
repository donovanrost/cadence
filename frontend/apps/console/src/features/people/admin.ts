import type { OrganizationId } from "@/api/index.ts";
import { codeOf, request, type ApiError, type ApiResult, outcomeUnknown } from "@/api";
import { decoders as d } from "@/api";
import { roles, type Role } from "./api.ts";

/** O5 people administration (api 1b4defb8, setup.md). All need org.manage_members. */
const base = (orgId: OrganizationId) => `/organizations/${encodeURIComponent(orgId)}`;

const membershipReader = d.object({
  user_id: d.token,
  role: d.oneOf(roles),
  state: d.oneOf(["active", "revoked"]),
});

export function setRole(orgId: OrganizationId, userId: string, role: Role) {
  return request(`${base(orgId)}/people/${encodeURIComponent(userId)}`, membershipReader, {
    method: "PUT",
    body: { role },
  });
}

export function removeMember(orgId: OrganizationId, userId: string) {
  return request(`${base(orgId)}/people/${encodeURIComponent(userId)}`, membershipReader, {
    method: "DELETE",
  });
}

/** 201 a fresh invitation (new id; the old link stops working). Only the new id matters here. */
export function resendInvitation(orgId: OrganizationId, invitationId: string) {
  return request(
    `${base(orgId)}/invitations/${encodeURIComponent(invitationId)}/resend`,
    d.object({ id: d.token }),
    { method: "POST", body: {} },
  );
}

export function revokeInvitation(
  orgId: OrganizationId,
  invitationId: string,
): Promise<ApiResult<null>> {
  return request(`${base(orgId)}/invitations/${encodeURIComponent(invitationId)}`, () => null, {
    method: "DELETE",
  });
}

/** O5 errors in words (U20: a dropped connection never claims it saved). */
export function adminErrorText(e: ApiError): string {
  const code = codeOf(e);
  switch (code) {
    case "last_admin":
      return "Nothing changed: the organization needs at least one admin. Make someone else an admin first.";
    case "member_not_found":
      return "They aren't a member any more. The list has been reloaded.";
    case "invitation_not_found":
      return "This invitation isn't pending any more (accepted, declined, revoked or expired). The list has been reloaded.";
    case "forbidden":
      return "Only an organization admin can manage people.";
    case null:
    default:
      break;
  }
  if (outcomeUnknown(e))
    return "No clear answer from the server, so it may or may not have changed. Reload before trying again.";
  return `Nothing changed. ${"message" in e ? e.message : ""}`.trim();
}

/** People.md Access panel: capabilities as plain sentences, grouped; unknown tokens kept as-is. */
const worded = [
  "command.request",
  "command.abort",
  "command.approve",
  "org.invite",
  "org.manage_members",
] as const;
const capabilityText: Readonly<
  Record<(typeof worded)[number], readonly [group: string, sentence: string]>
> = {
  "command.request": ["Command", "Request commands"],
  "command.abort": ["Command", "Abort commands in flight"],
  "command.approve": ["Approve", "Give a second GO on another person's command"],
  "org.invite": ["Organization", "Invite people"],
  "org.manage_members": ["Organization", "Change roles and remove people"],
};

export function accessGroups(capabilities: readonly string[]): readonly Readonly<{
  group: string;
  lines: readonly Readonly<{ text: string; yes: boolean }>[];
}>[] {
  const order = ["Operate", "Command", "Approve", "Setup", "Organization", "Other"];
  const byGroup = new Map<string, { text: string; yes: boolean }[]>();
  const add = (group: string, text: string, yes: boolean) =>
    byGroup.set(group, [...(byGroup.get(group) ?? []), { text, yes }]);
  for (const [token, [group, text]] of Object.entries(capabilityText))
    add(group, text, capabilities.includes(token));
  for (const token of capabilities) if (!(token in capabilityText)) add("Other", token, true);
  return order.flatMap((g) => (byGroup.has(g) ? [{ group: g, lines: byGroup.get(g) ?? [] }] : []));
}
