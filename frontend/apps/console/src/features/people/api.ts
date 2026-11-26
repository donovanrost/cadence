import type { OrganizationId } from "@/api/index.ts";
import {
  decoders,
  invitationState,
  invitedBy,
  request,
  role,
  roleText,
  type ApiResult,
  type Decoded,
  type Role,
} from "@/api";

/** Requested shapes: docs/apogee/plans/setup-shapes.md §O (final contract in api/setup.md). */
const { array, nullable, object, oneOf, string, timestamp, token } = decoders;

/** Roles are the shared entity vocabulary (typing §12 A5); re-exported for People's own callers. */
export { roles, type Role } from "@/api";

const member = object({
  user_id: token,
  display_name: nullable(string),
  email: string,
  role,
  capabilities: array(token, 100),
  joined_at: nullable(timestamp),
});
const invitation = object({
  id: token,
  email: string,
  role,
  invited_by: invitedBy,
  sent_at: timestamp,
  expires_at: nullable(timestamp),
  /** api-ops L5/L21: `declined` when the invitee turns it down. */
  /** Shared vocabulary (typing §12 A5); People lists pending, expired and declined ones. */
  status: invitationState,
});

export const peopleReader = object({
  members: array(member, 10000),
  invitations: array(invitation, 10000),
  permissions: array(token, 50),
});
export type People = Decoded<typeof peopleReader>;
export type Member = Decoded<typeof member>;
export type Invitation = Decoded<typeof invitation>;

const base = (organizationId: OrganizationId) =>
  `/organizations/${encodeURIComponent(organizationId)}`;

export function fetchPeople(
  organizationId: OrganizationId,
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
  organizationId: OrganizationId,
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

/** `Org admin` / `Member`, or the server's word for a role the console doesn't know. */
export const roleLabel = roleText;

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
  organizationId: OrganizationId,
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

/**
 * An invitation's status as a tag (qa: accepted and withdrawn read "Pending"). Exhaustive: a new
 * status won't compile until it has words. `revoked` is an admin's withdraw (U32 "Withdrawn").
 */
export function invitationTag(status: Invitation["status"]): {
  state: "neutral" | "nominal" | "caution" | "off";
  label: string;
} {
  if (typeof status !== "string") return { state: "off", label: status.unrecognized };
  switch (status) {
    case "pending":
      return { state: "neutral", label: "Pending" };
    case "accepted":
      return { state: "nominal", label: "Accepted" };
    case "expired":
      return { state: "caution", label: "Expired" };
    case "declined":
      return { state: "off", label: "Declined" };
    case "revoked":
    case "withdrawn":
      return { state: "off", label: "Withdrawn" };
    default: {
      const never: never = status;
      return never;
    }
  }
}
