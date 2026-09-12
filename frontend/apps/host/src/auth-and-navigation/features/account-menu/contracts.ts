import { record, present, text } from "../../shared/contracts";
type Organization = { organization_id: string; display_name: string };
function organization(value: unknown): value is Organization {
  return record(value) && present(value.organization_id, 512) && present(value.display_name);
}
export function readAccountContext(value: unknown) {
  if (
    !record(value) ||
    value.version !== 1 ||
    !present(value.csrf_token) ||
    typeof value.platform_admin !== "boolean" ||
    typeof value.admin_mode !== "boolean" ||
    !Array.isArray(value.organizations) ||
    !value.organizations.every(organization) ||
    !(value.organization === null || organization(value.organization))
  )
    return null;
  const user = value.user;
  if (
    !(
      user === null ||
      (record(user) &&
        present(user.user_id, 512) &&
        present(user.email) &&
        (user.display_name === null || text(user.display_name)))
    )
  )
    return null;
  if (
    new Set(value.organizations.map((row) => row.organization_id)).size !==
    value.organizations.length
  )
    return null;
  return {
    user: user as { user_id: string; email: string; display_name: string | null } | null,
    organization: value.organization,
    organizations: value.organizations,
    platform_admin: value.platform_admin,
    admin_mode: value.admin_mode,
    csrf_token: value.csrf_token,
  };
}
