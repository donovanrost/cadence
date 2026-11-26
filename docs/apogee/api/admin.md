# Platform admin area (L7, api-ops)

`/api/console/v1/admin`, for platform administrators in admin mode (L6) only. Every call checks
`Administration.Access.authorize/1`. Without admin mode, or for an account that lost the
capability: `403 admin_mode_required` (end the admin chip). Writes need `x-csrf-token` and are
recorded in the platform audit. Proposal: `docs/apogee/plans/admin.md`; screens: ux `screens/Admin.md`.

People named here (`created_by`, `invited_by`, the platform audit's `actor`) may be anyone, in any
organization, because only platform admins read this area: the read itself checks admin mode, not
only the controller (#470). They're named by display name only, never by email, and `null`
without one.

## AD1 organizations

- `GET /organizations?q=&after=` → `{organizations: [{id, name, slug, members, missions,
  created_at, created_by: {name} | null}], next | null}`. 50 per page, by slug. `q` matches name
  or slug, and `after` is the previous page's `next`. `members` counts active members.
  `created_by` is known only for organizations created since the platform audit exists.
- `GET /organizations/slug?slug=` → `{slug, available, suggestion | null}`.
- `POST /organizations {name, slug, first_admin_email}` → `201 {organization: {id, name, slug},
  invitation: {email, delivery: submitted | unavailable} | null, invitation_error | null}`. When
  the organization is created but the invitation fails, `invitation` is `null` and
  `invitation_error` says why. Errors: `422 invalid_params` with `details` per field (`slug`, plus
  `suggestion` on a clash; `display_name`; `first_admin_email`).

## AD2 one organization

- `GET /organizations/:id` → `{organization: {id, name, slug, created_at}, members: [{user_id,
  name, email, role}], invitations: [{id, email, role, invited_by: {name} | null, invited_at,
  expires_at, state: pending | expired}], missions: [{id, name, slug, created_at}]}`, up to 500
  each. `404 organization_not_found`.
- `POST /organizations/:id/invitations {email, role: member | organization_admin}` → `201
  {id, email, role, expires_at, delivery, ...}`.
- `DELETE /organizations/:id/invitations/:invitation_id` → `200 {id, state: "withdrawn"}`.
  `404 invitation_not_found`.

## AD3 service identities

The same issuance as People (O6), for any organization.

- `GET /service-identities?organization_id=` → `{service_identities: [{id, name, organization:
  {id, name}, capabilities: [{key, label}], mission: {id, name} | null, created_at, created_by:
  {name} | null, last_used_at: null}], capabilities: [{key, label, needs_mission}]}`. Active
  identities only, at most 500. `last_used_at` isn't tracked yet.
- `POST /service-identities {organization_id, name, capability: organization_admin |
  mission_admin, mission_id?}` → `201 {service_identity, token}`. `service_identity` is exactly
  the list row above (`{id, name, organization, capabilities, mission, created_at, created_by,
  last_used_at}`), never the domain record. The **token is shown once** and the reply carries
  `cache-control: no-store`. `mission_id` is required for `mission_admin`. `422 invalid_params`
  by field.
- `POST /service-identities/:id/rotate {organization_id}` → `{service_identity, token}`, the same
  list row and `no-store`. The old token stops working.
- `DELETE /service-identities/:id?organization_id=` → `200 {id, state: "revoked"}`.

## AD4 runtime

`GET /runtime` → `{observed_at, missions: [{organization: {id, name, slug}, mission: {id, name,
slug}, runtime: {...} | null, telemetry_last_received_at | null, technical: []}]}`.

- `runtime` is the same object as `/counts` `runtime` (U38).
- Both values are what this node knows. `null` means not known here, never zero.
- Telemetry receipts are read at most 4 missions at a time, 5 s each. A slow mission reads
  `null`.

## Platform audit

`GET /audit?after=` → `{events: [{id, at, actor: {kind, id, name}, kind: "platform", action,
target: {kind, id, label} | null, organization: {id, name} | null}], next | null}`, newest first,
100 per page. `target.label` is always a string: the target's name when one was recorded, else its
id (withdrawn invitations; revokes recorded before 11-13).

- What's recorded: organizations created, invitations sent and withdrawn, service identities
  issued, rotated and revoked, admin mode entered (with when it ends) and left, through the
  console or the legacy pages, and platform-wide data-source bindings switched (DECISIONS #90:
  "Switched platform binding default_flight_telemetry from Cadence managed store to Northlight
  archive · 12 missions, 3 live passes: “<reason>”"; `target` is the binding).
- `action` is a server sentence: "Created organization Nova", "Issued service identity Bot in
  Acme Space", "Entered admin mode (until 03:10Z)".
- Entries never hold a token or password.
- `actor.name` is the platform admin's display name, never their email (`null` without one, #470).
- Events tied to an organization also appear in that organization's Audit as `kind: "platform"`.
  There the actor is named by that organization's rule (setup.md C1, #470): a platform admin who
  isn't one of its members is `{kind: "user", id: null, name: null}`, with no id, name or email.
  The console reads that as "the team that runs Cadence" (ux, #523).
- Caption for the platform pages: "Recorded in Admin › Audit; organization changes also appear
  in that organization's Audit."
