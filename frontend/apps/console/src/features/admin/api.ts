import { decoders as d, request, role, type ApiResult, type Decoded, type Role } from "@/api";

/**
 * L7 platform admin (ux screens/Admin.md): AD1–AD4 as proposed in docs/apogee/plans/admin.md
 * (api-ops reviewing; fixtures until it ships). Base `/admin`, behind admin mode (L6).
 */
const named = d.nullable(d.object({ name: d.string }));

const orgRow = d.object({
  id: d.token,
  name: d.string,
  slug: d.token,
  members: d.integer,
  missions: d.integer,
  created_at: d.nullable(d.timestamp),
  created_by: named,
});
export type AdminOrganization = Decoded<typeof orgRow>;
const orgPage = d.object({ organizations: d.array(orgRow, 500), next: d.nullable(d.string) });

export function fetchOrganizations(
  k: Readonly<{ q: string; after: string | null }>,
  signal: AbortSignal,
): Promise<ApiResult<Decoded<typeof orgPage>>> {
  const p = new URLSearchParams();
  if (k.q) p.set("q", k.q);
  if (k.after) p.set("after", k.after);
  const q = p.toString();
  return request(`/admin/organizations${q ? `?${q}` : ""}`, orgPage, { signal });
}

const slugCheck = d.object({
  slug: d.string,
  available: d.boolean,
  suggestion: d.nullable(d.string),
});
export function checkSlug(slug: string, signal: AbortSignal) {
  return request(`/admin/organizations/slug?slug=${encodeURIComponent(slug)}`, slugCheck, {
    signal,
  });
}

const delivery = d.known(["submitted", "unavailable"] as const);
const created = d.object({
  organization: d.object({ id: d.token, name: d.string, slug: d.token }),
  invitation: d.nullable(d.object({ email: d.string, delivery })),
  invitation_error: d.nullable(d.string),
});
export type Created = Decoded<typeof created>;

/** AD1 create + first-admin invite in one call; a failed invite comes back beside the new org. */
export function createOrganization(
  body: Readonly<{ name: string; slug: string; first_admin_email: string }>,
) {
  return request("/admin/organizations", created, { method: "POST", body });
}

const orgDetail = d.object({
  organization: d.object({
    id: d.token,
    name: d.string,
    slug: d.token,
    created_at: d.nullable(d.timestamp),
  }),
  members: d.array(
    d.object({
      user_id: d.token,
      name: d.nullable(d.string),
      email: d.string,
      role,
    }),
    500,
  ),
  invitations: d.array(
    d.object({
      id: d.token,
      email: d.string,
      role,
      invited_by: named,
      invited_at: d.timestamp,
      expires_at: d.nullable(d.timestamp),
      state: d.known(["pending", "expired"] as const),
    }),
    500,
  ),
  missions: d.array(
    d.object({ id: d.token, name: d.string, slug: d.token, created_at: d.nullable(d.timestamp) }),
    500,
  ),
});
export type AdminOrganizationDetail = Decoded<typeof orgDetail>;

export function fetchOrganization(
  id: string,
  signal: AbortSignal,
): Promise<ApiResult<AdminOrganizationDetail>> {
  return request(`/admin/organizations/${encodeURIComponent(id)}`, orgDetail, { signal });
}

export function inviteInto(orgId: string, body: Readonly<{ email: string; role: Role }>) {
  return request(
    `/admin/organizations/${encodeURIComponent(orgId)}/invitations`,
    d.object({ invitation: d.object({ id: d.token, email: d.string }), delivery }),
    { method: "POST", body },
  );
}

export function withdrawInvitation(orgId: string, invitationId: string) {
  return request(
    `/admin/organizations/${encodeURIComponent(orgId)}/invitations/${encodeURIComponent(invitationId)}`,
    d.object({ id: d.token, state: d.known(["withdrawn"] as const) }),
    { method: "DELETE" },
  );
}

const capabilityKey = d.known(["organization_admin", "mission_admin"] as const);
const capability = d.object({ key: capabilityKey, label: d.string });
const identity = d.object({
  id: d.token,
  name: d.string,
  organization: d.object({ id: d.token, name: d.string }),
  capabilities: d.array(capability, 20),
  mission: d.nullable(d.object({ id: d.token, name: d.string })),
  created_at: d.timestamp,
  created_by: named,
  last_used_at: d.nullable(d.timestamp),
});
export type AdminServiceIdentity = Decoded<typeof identity>;
const identities = d.object({
  service_identities: d.array(identity, 2000),
  capabilities: d.array(
    d.object({ key: capabilityKey, label: d.string, needs_mission: d.boolean }),
    20,
  ),
});
export type AdminServiceIdentities = Decoded<typeof identities>;

export function fetchServiceIdentities(
  organizationId: string | null,
  signal: AbortSignal,
): Promise<ApiResult<AdminServiceIdentities>> {
  const q = organizationId ? `?organization_id=${encodeURIComponent(organizationId)}` : "";
  return request(`/admin/service-identities${q}`, identities, { signal });
}

export function issueServiceIdentity(
  body: Readonly<{
    organization_id: string;
    name: string;
    capability: "organization_admin" | "mission_admin";
    mission_id: string | null;
  }>,
) {
  return request(
    "/admin/service-identities",
    d.object({ service_identity: identity, token: d.string }),
    {
      method: "POST",
      body,
    },
  );
}

export function revokeServiceIdentity(id: string) {
  return request(
    `/admin/service-identities/${encodeURIComponent(id)}`,
    d.object({ id: d.token, state: d.known(["revoked"] as const) }),
    { method: "DELETE" },
  );
}

/** U38's reasons (domain MissionRuntimeStatus); a new reason reads as unrecognized. */
export const runtimeReasons = [
  "apply_failed",
  "spec_mismatch",
  "reconcile_crashed",
  "runtime_not_running",
] as const;
const runtimeRow = d.object({
  organization: d.object({ id: d.token, name: d.string, slug: d.token }),
  mission: d.object({ id: d.token, name: d.string, slug: d.token }),
  runtime: d.nullable(
    d.object({
      state: d.known(["applied", "not_applied"] as const),
      reason: d.nullable(d.known(runtimeReasons)),
      failure_message: d.nullable(d.string),
      desired_generation: d.nullable(d.integer),
      applied_generation: d.nullable(d.integer),
      since: d.nullable(d.timestamp),
      applied_at: d.nullable(d.timestamp),
    }),
  ),
  telemetry_last_received_at: d.nullable(d.timestamp),
  technical: d.array(d.object({ label: d.string, value: d.string }), 50),
});
export type RuntimeRow = Decoded<typeof runtimeRow>;
const runtimePage = d.object({ observed_at: d.timestamp, missions: d.array(runtimeRow, 5000) });
export type AdminRuntime = Decoded<typeof runtimePage>;

export function fetchRuntime(_key: true, signal: AbortSignal): Promise<ApiResult<AdminRuntime>> {
  return request("/admin/runtime", runtimePage, { signal });
}
