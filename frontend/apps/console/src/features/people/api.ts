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

/** POST result: the invitation plus whether an email went out (`unavailable`: no mail delivery). */
const invited = (value: unknown, path = "") => ({
  invitation: invitation(value, path),
  delivery: object({ delivery: oneOf(["submitted", "unavailable"]) })(value, path).delivery,
});
export type Invited = ReturnType<typeof invited>;

export function sendInvitation(
  organizationId: string,
  body: Readonly<{ email: string; role: Role }>,
): Promise<ApiResult<Invited>> {
  return request(`${base(organizationId)}/invitations`, invited, { method: "POST", body });
}

export function inviteFailure(code: string | null, message: string): string {
  switch (code) {
    case "already_member":
      return "They're already a member of this organization.";
    case "already_invited":
      return "They already have a pending invitation.";
    case "forbidden":
      return "Only an organization admin can invite people.";
    case null:
    default:
      return message;
  }
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

const serviceIdentity = object({
  id: token,
  name: string,
  scope_summary: string,
  capabilities: array(token, 100),
  mission: nullable(object({ id: token, name: string })),
  last_used_at: nullable(timestamp),
  key_created_at: nullable(timestamp),
});
export const serviceIdentitiesReader = object({
  service_identities: array(serviceIdentity, 1000),
  rotation_policy_days: nullable(decoders.integer),
});
export type ServiceIdentities = Decoded<typeof serviceIdentitiesReader>;

export function fetchServiceIdentities(
  organizationId: string,
  signal: AbortSignal,
): Promise<ApiResult<ServiceIdentities>> {
  return request(`${base(organizationId)}/service-identities`, serviceIdentitiesReader, { signal });
}

/** Key age warning only against a real org policy; never an invented number (People.md U3). */
export function keyAgeWarning(
  keyCreatedAt: string | null,
  policyDays: number | null,
  now: Date,
): string | null {
  if (keyCreatedAt === null || policyDays === null) return null;
  const days = Math.floor((now.getTime() - Date.parse(keyCreatedAt)) / 86_400_000);
  return days > policyDays ? `Key is ${days} days old; rotation policy is ${policyDays}.` : null;
}
