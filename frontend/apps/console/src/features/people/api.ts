import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shapes: docs/apogee/plans/setup-shapes.md §O (final contract in api/setup.md). */
const { array, nullable, object, oneOf, string, timestamp, token } = decoders;

export const roles = ["organization_admin", "member"] as const;
export type Role = (typeof roles)[number];

const member = object({
  user_id: token,
  display_name: nullable(string),
  email: string,
  role: oneOf(roles),
  capabilities: array(token, 100),
  joined_at: nullable(timestamp),
});
const invitation = object({
  id: token,
  email: string,
  role: oneOf(roles),
  invited_by: nullable(object({ name: string })),
  sent_at: timestamp,
  expires_at: nullable(timestamp),
  status: oneOf(["pending", "expired"]),
});

export const peopleReader = object({
  members: array(member, 10000),
  invitations: array(invitation, 10000),
  permissions: array(token, 50),
});
export type People = Decoded<typeof peopleReader>;
export type Member = Decoded<typeof member>;
export type Invitation = Decoded<typeof invitation>;

const base = (organizationId: string) => `/organizations/${encodeURIComponent(organizationId)}`;

export function fetchPeople(
  organizationId: string,
  signal: AbortSignal,
): Promise<ApiResult<People>> {
  return request(`${base(organizationId)}/people`, peopleReader, { signal });
}

export function sendInvitation(
  organizationId: string,
  body: Readonly<{ email: string; role: Role }>,
): Promise<ApiResult<Invitation>> {
  return request(`${base(organizationId)}/invitations`, invitation, { method: "POST", body });
}

export const roleLabel = (role: Role) => (role === "organization_admin" ? "Org admin" : "Member");

/** Command / Second GO come from server-evaluated capabilities, never the role name (DECISIONS #2). */
export const canCommand = (m: Member) => m.capabilities.includes("command.request");
export const canApprove = (m: Member) => m.capabilities.includes("command.approve");

export function matchesPerson(m: Member, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (q === "") return true;
  return [m.display_name ?? "", m.email, roleLabel(m.role)].some((t) =>
    t.toLowerCase().includes(q),
  );
}
