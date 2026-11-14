# Platform admin area (L7, DECISIONS #75)

A console area behind admin mode (Auth.md, L6) for platform admins. Owners: api (endpoints, after L6/L5) and
fe-setup (screens). It replaces the LiveView `/admin/**`.

## Shell
Route `/console/admin/**`, outside org and mission scope.
- **Top bar:** brand · mono `PLATFORM ADMIN` in place of the org/mission switcher · the admin-mode chip · UTC ·
  account.
- **Rail:** `Organizations` · `Service identities` · `Runtime`.
- **Layout:** reading layout. Outside admin mode every route shows the step-up form inline (Auth.md); nothing
  renders behind it.
- **Footer caption** (api-ops): on an organization's page, "Changes to Acme Space's members and invitations are
  recorded in its audit log (Access)." with a link to that org's Audit filtered to Access. On the platform pages,
  "Recorded in Admin › Audit; organization changes also appear in that organization's Audit." (api-ops, built in
  0698ba78f). **Admin › Audit** (`GET /admin/audit`, api/admin.md AD5) lists platform actions: organizations
  created, service identities issued, rotated and revoked, admin mode entered and left, and, once api-ops adds
  them, platform-wide binding switches (U53).

## Organizations (`/console/admin/organizations`)
- h1 `12 organizations`. ApTable: Name (link) · Slug (mono) · Members · Missions · Created (by, when). There's a
  filter box. Primary `Create organization`.
- **Create** (ApSheet): Name · Slug (mono; filled from the name, editable, live check "acme-space is taken") ·
  First admin email (required; they're invited as org admin). Primary `Create and invite`. Result: nominal callout
  "Created Acme Space. Invitation sent to ana@acme.space."
- **Organization page** (`…/organizations/:orgId`):
  - Header: name, slug, created.
  - Panels: Members (name, email, role; read-only) · Invitations (email, role, invited by and when, state;
    `Withdraw`) · Missions (name, created; read-only).
  - Primary `Invite into Acme Space` (email + role). This is the cross-org invite. People in the org see the
    same invitation on their People › Invitations tab.

## Service identities (`/console/admin/service-identities`)
- ApTable: Name · Organization · Created (by, when) · Last used · `Revoke` (danger; it confirms: "Revoke
  pipeline-ingest? Anything using its token stops working now.").
- **Issue** (ApSheet): Organization (select) · Name · what it may do, as the server's capability list in words
  (not keys).
- **After issuing:** the token is shown once, in a mono box with `Copy`, and a caution callout "Copy this token
  now. Cadence won't show it again." `Done` stays disabled until the checkbox "I've stored the token" is ticked.
  The sheet can't be closed by clicking outside it while the token is showing.

## Runtime (`/console/admin/runtime`)
Read-only diagnostics.
- One row per mission: Organization · Mission (link into its console) · Runtime (the U38 state: `■ APPLIED gen 8`
  / `◆ NOT APPLIED since 23:10Z: <reason words>`, same words as U38) · Telemetry last received (age) · anything
  else the server's read adds, as columns with plain labels.
- Sorted worst first. `Refresh` with `Updated 23:55:03Z`.
- No actions unless the server offers one. A section the read can't fill shows `—` with the reason (U13), never a
  zero.
- Node or process details go in a `Technical details` disclosure per row.

## States
Loading per panel. A 403 in admin mode (the capability was lost): crit callout "Your account can't use platform
administration any more." and the admin chip ends. Errors follow U20.
