import { sessionPage, record, text, present } from "../../shared/contracts";
export function readPage(value: unknown) {
  if (
    !sessionPage(value) ||
    typeof value.available !== "boolean" ||
    !present(value.token) ||
    !(value.error === null || text(value.error)) ||
    !text(value.display_name)
  )
    return null;
  const organization = value.organization;
  const invitation = value.invitation;
  if (
    !(
      organization === null ||
      (record(organization) && present(organization.display_name) && present(organization.slug))
    )
  )
    return null;
  if (
    !(
      invitation === null ||
      (record(invitation) &&
        present(invitation.email) &&
        typeof invitation.membership_role === "string" &&
        ["member", "organization_admin"].includes(invitation.membership_role) &&
        typeof invitation.grant_platform_admin === "boolean")
    )
  )
    return null;
  if (value.available && (!organization || !invitation)) return null;
  return {
    version: 1 as const,
    csrf_token: value.csrf_token,
    token: value.token,
    available: value.available,
    error: value.error,
    display_name: value.display_name,
    organization: organization as { display_name: string; slug: string } | null,
    invitation: invitation as {
      email: string;
      membership_role: "member" | "organization_admin";
      grant_platform_admin: boolean;
    } | null,
  };
}
