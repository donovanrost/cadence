# L12 mission providers + L13 provider-account grants and credential revoke: shape proposal (fe-setup → api-ops, cc lead)

fe-setup, 2026-11-13. BACKLOG §11 L12, L13. ux: `screens/SettingsAuditProviders.md` (Provider accounts), U4 (Ground
stations › Providers tab). Replaces the LiveView writes in `Applications.Comms.ActionProvider` (mission providers)
and `Applications.OrganizationAdminAction` → `GroundNetworks.ProviderAccountOperations` (account grants, credential
revoke). Reads to extend: `GET /missions/:id/providers` (`Reads.CommsDirectory.providers/2`) and the org
`provider-accounts` endpoints (`ProviderAccountController`).

## What exists (read, 2026-11-13)
- **Mission provider** (`GroundNetworks.MissionProvider`): versioned, append-only; `lifecycle_state: active | archived`.
  Health lives in `metadata.control_plane` / `metadata.sync` (`{status: healthy | failed, checked_at, error}`) plus
  `last_validated_at` / `last_synced_at`. Created by binding an **account grant** (`provider_account_grant_id`):
  type, URL, credential and environment come from the granted account version, not input.
  `policy_mode: approval_required | bounded_automatic`; `bounded_automatic` adds station substitutions and
  shift/retention seconds.
- **Validate / sync** (`Control.Providers.validate_current/4`, `sync_current/4`) call the provider **inline**
  (no queue); a failure writes `status: "failed"` and returns the error. Sync rewrites station availability.
- **Archive** inserts an archived version; reservations keep their pinned version; the grant isn't touched.
- **Account grant** (`ProviderAccountGrants`): `active | revoked`, versioned; restrictions `allowed_services`,
  `allowed_stations`, `max_quota`. Revoking flags open reservations that carry the grant for operator review and
  publishes `contacts_changed`.
- **Credential** (`ProviderCredentials.revoke/4`): revokes the account's current reference (external backends too);
  missions aren't cascaded: their providers then fail at credential resolve.
- Every account write passes `ProviderAccountOperations.admit/3`: `:manage_provider_accounts` (org admin) and
  `expected_account_version` + `credential_ref` + `expected_credential_version`, else `:stale_provider_account`.

### Defects found while reading (please fix with the endpoints)
1. **Archive needs an active grant.** `archive_provider` goes through `persist_provider` → `validate_account_binding`,
   so a provider whose grant was revoked can't be archived (`provider_account_grant_revoked`). That's the main reason
   to archive one.
2. **Sync can crash.** `ground_networks.ex:179` matches `{:ok, _} = ProviderReports.sync(…)`.
3. **Grant on an archived account reads as the wrong error.** `grant_for_system`'s active-account check falls into
   `:provider_account_grant_widens_guardrails`.
4. **Revoke reason is hardcoded** ("Revoked by organization administrator"); the console will send the person's.
5. **Credential revoke doesn't show.** Nothing sets `ProviderAccount.credential_status = :revoked`, so the directory's
   status never says so.

## L13 · provider-account grants and credential (`/api/console/v1/organizations/:organization_id/provider-accounts/:id`)
Who: `:manage_provider_accounts` (org admins), as today. **todo(authz):** granting an account to a mission checks
only that the mission exists in the org; nobody on the mission side agrees. Fine while only org admins grant; note
it for Cedar.

```
GET  /                         (PA2, the detail) → {account: <PA1 row> + {version,
                                  credential: {ref (masked), version, status: active | revoked},
                                  guardrails: {allowed_services: [..], allowed_stations: [..]}},
                                grants: [{id, version, mission {id, name}, state: active | revoked,
                                  allowed_services: [..] | null, allowed_stations: [..] | null, max_quota|null,
                                  reason|null, granted_by {id, name}|null, granted_at,
                                  revoked_by {id, name}|null, revoked_at|null, revoke_reason|null}],
                                permissions: ["provider_accounts.manage"]}
POST /grants {mission_id, allowed_services?: [..], allowed_stations?: [..], max_quota?: int, reason?,
              expected_account_version}
  → 201 {grant}
  409 account_changed {version}            (replaces the evidence map: the server rebuilds credential_ref and
                                            the credential version from the account version)
  409 account_archived                     (defect 3)
  422 invalid_params {allowed_services | allowed_stations | max_quota: msg}   (widens the account's guardrails)
POST /grants/:grant_id/revoke {reason, expected_grant_version}
  → 200 {grant, flagged_reservations: int}  (how many open reservations now need an operator's review)
  409 grant_changed {version} · 409 grant_already_revoked · 422 {reason: "Say why."}
POST /credential/revoke {reason, expected_credential_version}
  → 200 {account}                           (with the credential's status revoked, and the PA1 status saying so)
  409 credential_changed {version} · 409 credential_already_revoked
```
- PA1 `status` gains `credential_revoked` (defect 5), worded "Credential revoked" (crit).
- Console (`org.provider-accounts/:accountId`): a **Missions** panel turns into **Grants** (mission, restrictions,
  granted by/when, state) with `Grant to a mission…` (sheet: mission select from the org's missions, optional
  stations/services within the account's guardrails, quota, reason) and a row `Revoke…` (confirm with a required
  reason; the result says "3 open bookings now need an operator's review" from `flagged_reservations`). The
  credential line gets `Revoke credential…` (danger, required reason): "Every mission provider on this account
  stops working until you point the account at a new reference."

## L12 · mission providers (`/api/console/v1/missions/:mission_id/providers`)
Who: `:manage_mission` (mission admins) for every write, as today (create also checks `:operate_mission`).

```
GET  /                → {providers: [<today's row> + {version, policy_mode,
                           grant: {id, version, state: active | revoked},
                           health: {validate: {status: healthy | failed | null, checked_at|null, error|null},
                                    sync:     {status: healthy | failed | null, checked_at|null, error|null}}}],
                         permissions: ["providers.manage"]}
GET  /options         → {grants: [{id, version, account {id, name, provider {key, label}},
                           allowed_stations: [..] | null, allowed_services: [..] | null}],   (this mission's active grants)
                         policy_modes: [{key, label}], deadline_behaviors: [{key, label}]}
POST / {grant_id, display_name, policy_mode, deadline_behavior?, permitted_resource_refs?: [..],
        bounded?: {approved_station_substitutions: [..], minimum_retained_duration_seconds, <the four *_shift_seconds>}}
  → 201 {provider}
  409 grant_revoked · 409 grant_changed {version}
  422 invalid_params {field: msg}           (widens_account_guardrails on permitted_resource_refs; bounded fields)
POST /:id/validate    → 200 {provider, result: {ok: bool, message|null}}
POST /:id/sync        → 200 {provider, result: {ok: bool, stations: int|null, message|null}}
POST /:id/archive {reason}  → 200 {provider}   (defect 1: works with a revoked grant)
  404 provider_not_found (also for an archived one)
```
- Validate and sync are **results, not errors**: a provider that refuses or is unreachable is `200` with
  `ok: false` and the provider's message (and the row's health says `failed`), so the console says what happened
  instead of a generic failure. `unsupported_capability` is `ok: false` with that message. Both run inline; say if
  they can take more than ~10 s and the console will show "Contacting the provider…".
- Console (`setup.stations.providers`): the Providers table gains Health (validate/sync, with when) and a row
  action menu: `Validate`, `Sync stations`, `Archive…` (confirm, required reason: "Bookings already made keep this
  provider's version; no new ones can use it."). Primary `Add provider` (sheet: grant select from `/options`, name,
  policy mode; `bounded_automatic` opens the substitutions and shift fields in an Advanced disclosure). Without
  `providers.manage` the tab reads as text with "Mission admins change providers."
