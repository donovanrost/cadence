# L7 platform admin area: shape proposal (fe-setup → api-ops, cc lead)

fe-setup, 2026-11-13. Spec: ux `screens/Admin.md` (c6547f8d). DECISIONS #75. Behind lead's L6 admin mode
(`useAdminMode`). Replaces the LiveView `/admin/**` (HostPageLive + `PlatformAdministrationPage`).

## What exists (read, 2026-11-13)
- **No `/api/v1/admin` endpoints.** The LiveView pages call `PlatformOverview`, `OrganizationDirectory`,
  `OrganizationCreation`, `OrganizationDetail`, `OrganizationInvitations`, `ServiceIdentityIssuance` through a
  per-visit `action_token`. Authorization: `Cadence.Administration.Access.authorize/1` (admin mode + active user +
  platform_admin), which the console API can call as is.
- **Organizations:** the directory has only `{id, name, slug}` (50 per page by slug). `OrganizationRow.inserted_at`
  exists but isn't projected; `Accounts.count_organization_members/1` exists; no mission count helper.
  Create takes `{display_name, slug}` (no first-admin email; slug uniqueness from the constraint: "This slug is
  already in use."). Detail: members `{id, user_id, name, email, role, user_state}`, pending invitations
  `{id, email, role, grant_platform_admin, expires_at}`, services; **no missions**. Cross-org invite:
  `OrganizationInvitations.create` (email, display_name, membership_role, grant_platform_admin). **No withdraw**
  in the admin area; the org-scoped `OrganizationPeople.revoke_invitation/3` lets a platform admin through.
- **Service identities:** platform issuance is hard-coded to `[:organization_admin]` with no revoke; the
  org-scoped `ServiceIdentityAdministration` (create with `organization_admin | mission_admin` + mission, rotate,
  revoke) already admits a platform admin via `Policy`. `last_used_at` isn't tracked. No cross-org list.
- **Runtime:** today's `/admin/runtime` shows dashboard invalidation diagnostics, not mission runtime.
  `MissionRuntimeStatus` (state, reason, failure_message, desired/applied generation, since, applied_at,
  activated_at) is per node and only reachable through a mission's `/counts`. No telemetry-last-received read
  for admins; no node/process info.
- **Audit:** creating an organization, platform token issuance and admin-mode enter/leave aren't recorded.
  Invitations/memberships are (row metadata → the org's Audit, Access source).

## Proposed endpoints (`/api/v1/admin`, every one through `Administration.Access.authorize/1`)
Errors: `403 admin_mode_required` when admin mode lapsed or the capability was lost (the console ends the admin
chip and shows "Your account can't use platform administration any more."), `422 invalid_params` by field.

### AD1 organizations
```
GET  /organizations?q=&after=   → {organizations: [{id, name, slug, members, missions,
                                    created_at|null, created_by {name}|null}], next|null}
GET  /organizations/slug?slug=  → {slug, available: bool, suggestion|null}     (the sheet's live check)
POST /organizations {name, slug, first_admin_email}
     → 201 {organization {id, name, slug}, invitation {email, delivery: "submitted"|"unavailable"}|null,
            invitation_error|null}
```
- `members` from `count_organization_members/1`; `missions` needs a count helper; `created_at` from
  `inserted_at`; `created_by` once creation records it (else null).
- Create + first-admin invite in one call (spec: "Create and invite"), composed from `OrganizationCreation.create`
  and `OrganizationInvitations.create(role: organization_admin)`. If the org is created but the invite fails, 201
  with `invitation: null` and the reason in `invitation_error`, so the console says both facts (U20).

### AD2 one organization
```
GET    /organizations/:id → {organization {id, name, slug, created_at|null},
                             members:     [{user_id, name, email, role}],
                             invitations: [{id, email, role, invited_by {name}|null, invited_at, expires_at,
                                            state: "pending"|"expired"}],
                             missions:    [{id, name, slug, created_at|null}]}
POST   /organizations/:id/invitations {email, role}   → 201 {invitation, delivery}
DELETE /organizations/:id/invitations/:invitation_id  → 200 {id, state: "withdrawn"}   (revoke_invitation/3)
```
- Lists up to 500 each (the console pages client-side); a bigger org gets `{rows, next}` later.

### AD3 service identities
```
GET    /service-identities?organization_id= → {service_identities: [{id, name, organization {id, name},
          capabilities: [{key, label}], mission {id, name}|null, created_at, created_by {name}|null,
          last_used_at|null}], capabilities: [{key, label, needs_mission: bool}]}
POST   /service-identities {organization_id, name, capability, mission_id|null}
          → 201 {service_identity: <row>, token}          (token shown once)
DELETE /service-identities/:id → 200 {id, state: "revoked"}
```
- Through `ServiceIdentityAdministration` (not the platform issuance that's hard-coded to org admin), so issue,
  revoke and labels are the same as People's. `capabilities` gives the words (spec: "in words, not keys").
  `last_used_at` stays null until tracked.

### AD4 runtime
```
GET /runtime → {observed_at, missions: [{organization {id, name, slug}, mission {id, name, slug},
                 runtime: {state, reason|null, failure_message|null, desired_generation|null,
                           applied_generation|null, since|null, applied_at|null}|null,
                 telemetry_last_received_at|null,
                 technical: [{label, value}]}]}
```
- One row per mission with `MissionRuntimeStatus` (same words as U38 in the console) and the fleet read's latest
  telemetry time. `runtime: null` / `telemetry_last_received_at: null` say "not known on this node" (U13), never
  zero. `technical` is whatever node/process detail exists, as label/value pairs (spec: Technical details).

### Audit (ask, not blocking)
Record organization creation, platform token issue/revoke and admin-mode enter/leave somewhere readable, so the
footer caption on the platform pages can say where (spec: until then, no caption).

## Console (fe-setup)
`/console/admin/**` outside org/mission scope: Organizations, Service identities, Runtime, behind lead's step-up
(`useAdminMode`). Built against fixtures from these shapes until api-ops ships.
