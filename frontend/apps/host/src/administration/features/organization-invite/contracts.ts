import {
  observation,
  organization,
  record,
  identifier,
  text,
  type Organization,
  type Observation,
} from "../../shared/platform-contract";
export type InvitationReceipt = {
  id: string;
  email: string;
  role: "member" | "organization_admin";
  grant_platform_admin: boolean;
  expires_at: string;
  delivery: "submitted" | "unavailable";
};
export type OrganizationInvite = Observation & {
  organization: Organization;
  submitted: InvitationReceipt | null;
};
function receipt(value: unknown): asserts value is InvitationReceipt {
  if (
    !record(value) ||
    !identifier(value.id) ||
    !text(value.email) ||
    !["member", "organization_admin"].includes(String(value.role)) ||
    typeof value.grant_platform_admin !== "boolean" ||
    typeof value.expires_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value.expires_at) ||
    !Number.isFinite(Date.parse(value.expires_at)) ||
    !["submitted", "unavailable"].includes(String(value.delivery))
  )
    throw Error("Invalid invitation receipt");
}
export function readOrganizationInvite(
  value: unknown,
  userId: unknown,
  organizationId: unknown,
): OrganizationInvite {
  observation(value, userId);
  organization(value.organization);
  if (value.organization.id !== organizationId) throw Error("Invalid invitation organization");
  if (value.submitted !== null) receipt(value.submitted);
  return value as OrganizationInvite;
}
export type Input = {
  email: string;
  display_name: string;
  membership_role: "member" | "organization_admin";
  grant_platform_admin: boolean;
};
export type Act = (event: "invite", input: Input) => Promise<unknown>;
export function readInviteResult(
  value: unknown,
):
  | { status: "invited"; invitation: InvitationReceipt }
  | { status: "invalid"; errors: Record<string, string> }
  | { status: "unavailable" } {
  if (!record(value)) throw Error("Invalid invitation result");
  if (value.status === "unavailable") return { status: "unavailable" };
  if (value.status === "invited") {
    receipt(value.invitation);
    return value as { status: "invited"; invitation: InvitationReceipt };
  }
  if (
    value.status === "invalid" &&
    record(value.errors) &&
    Object.keys(value.errors).length > 0 &&
    Object.entries(value.errors).every(
      ([k, v]) =>
        ["form", "email", "display_name", "membership_role", "grant_platform_admin"].includes(k) &&
        text(v, 200),
    )
  )
    return value as { status: "invalid"; errors: Record<string, string> };
  throw Error("Invalid invitation result");
}
