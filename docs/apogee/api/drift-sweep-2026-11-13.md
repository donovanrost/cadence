# Contract-drift sweep, 2026-11-13 (api, for lead)

Scope: `/api/console/v1` against `docs/apogee/api/*.md`, in lead's order: contacts and passes,
planning, providers, settings. Each item: what disagrees, the direction of the fix, its state.

- **server→doc** means changing the server to match the doc.
- **doc→server** means the console already reads the server's shape, so the doc changes.
- **console** means a console reader is stricter than both the doc and the server.
- **HOLD** marks items on the reservation, contact or uplink path: they are listed only, and
  wait for 01:00Z (11-14) and qa.

Exact-shape tests: before this sweep, no endpoint in these four areas had one beyond a few
sub-objects (plan `station`, `longest_gap`, `uplink_passes`, policy writes, `missed_by_owner`). They
are added below where noted.

## Settings (api): done

Commit 4d92b1f5e.
- Server: a settings section whose owner can't be read is now left out; before, the read
  returned a 500 (`{:ok, _} =` match).
- Server: a 409 from a save that lost a race now carries `details.expected_version`.
- Doc (setup.md ST1): per-field `source` and `value`, locked reads, `allow_override` as the last
  field, sparse mission PUT, organization `null` refused, `expected_version` optional, and the
  `settings_write_unconfirmed` / `settings_unavailable` 422s.
- Doc (setup.md AU1): the `platform` kind, `limit` clamped, `mission_id` scope, the settings entry
  shape, the 10-per-section window, and the migration entry.
- Tests: exact shape for a section, a field, the organization's `allow_override`, and an audit
  settings event.

## Contacts and passes

| Item | Direction | State |
| --- | --- | --- |
| Pass review `by_station[]` had no `failed`; the console's lenient count read 0 | server→doc | **fixed** 67187baea, exact-shape test |
| `POST /attention/:source/:id/resolve` answers `state: "resolved"` (doc and server agree); the console's `attentionReader` accepts only `open \| acknowledged`, so a successful resolve shows as unclear | console | **fixed** fe-ops 3aec78162 |
| `/passes` `spacecraft.name` null for a deleted spacecraft (doc and server agree); the console reads `d.string`, so the whole list fails | console | **fixed** fe-ops 3aec78162 ("Deleted spacecraft") |
| Pass review `freshness[].cursor_healthy` null without a cursor; `freshness[].provider` can be null; rows `station.ref` null without a ground station ref. The console read all three as non-null | console + doc | **fixed** fe-ops 3aec78162 (decode test on the nulls); doc 85f793df0 |
| contacts.md:198 says row `attention` carries only `pass_resolution`; it also carries `pass_release` and `provider_change` (as :148-150, :293 say) | doc→server | doc fix below |
| `cost` is `{amount, currency} \| null`; `pass_phase`, `delivery_state`, `source.provider_name`, `source.synthetic` can be null | doc→server | doc fix below |
| L14 `provider_change.expired` (boolean) undocumented; history `resolution.action` can also be `observed`, `apply_failed` | doc→server | doc fix below |
| Attention `contact_settlement` source and `POST …/retry` documented only in domain/contact-settlement.md | doc→server | doc fix below |
| `recover-uplink`: only `ready` is refused (`409 uplink_not_blocked`); `qualifying` re-qualifies | doc→server | **HOLD** (uplink) doc wording only |
| Contact findings: `overlap_s: null` and `station: null` on some kinds | doc→server | doc fix below |
| Single booking create returns a bare `Passes.fetch` row (no `replaced_by`; `attention`, `uplink_readiness` null) instead of the `/passes` row | server→doc | **HOLD** (reservation) |
| Release: unlisted `ScheduleCommands.execute` errors fall to a 500 | server | **HOLD** (reservation), unverified |
| `/spacecraft/:id/passes` stations carry `ref` too | doc→server | doc fix below |
| Pass review `provider.account_id`, `freshness[].provider_id` extra keys | doc→server | doc fix below |
| U55 `contact_ended.cause` / `by` / `at` null on a canceled contact with no action record; the console decoded non-null | shape change | **fixed** contract confirmed nullable (lead 11-14): null only without an action record; `at` from the lifecycle cancel time; `by` null, never half; fe-ops reader 68b3180b6; test that a new cancel fills all three |

## Telemetry points

| Item | Direction | State |
| --- | --- | --- |
| Points read couldn't say 'no limits defined': `limit_state: no_data` meant both 'no definition' and 'not evaluated yet' (ux T1) | shape change (additive) | **fixed**: `has_limits: boolean` on each point (ux 11-15 chose it over a `limit_state: none`); fe-ops' optional reader first |

## Planning (all on the contact path except reads): listed, server fixes HOLD

| Item | Direction | State |
| --- | --- | --- |
| Plan detail `unconfirmed.passes[].provider` null when the reservation lookup fails; the console's K1 decode failed | doc→server | **fixed**: K1 reads null (lead ce69ef978); the null is genuine (no reservation record), so documented in scheduling.md, server unchanged |
| Supersedes `day` null for a draft with no passes; the console decoded non-null | console | **fixed** by fe-setup 05cb18eb7 (nullable; the server keeps null) |
| `POST …/reject` answers the bare plan read, not plan detail (no booking/unconfirmed/execution/chain) | server→doc | **HOLD** |
| Template update stale write: `409 version_conflict` without `details.expected_version` | server→doc | **HOLD** (no template edits tonight) |
| `POST /policy` ignores `reason` (the console sends it) | server→doc | **HOLD** |
| Requirement actor `kind: "actor"` for non-users; the shared console `actor` reader doesn't know it | server→doc | **HOLD** |
| Grant revoke without `sha256`: 422 keyed `details.grant` | server→doc | **HOLD** |
| List `state` enum lacks `interrupted`, `unconfirmed` (and `?state=interrupted` is a 422) | doc→server (+ filter) | doc fix below; filter HOLD |
| `author` can lack `id` | doc→server | doc fix below |
| Draft and repair reads: `plan` is the plan read, not full plan detail | doc→server | doc fix below |
| Submit reply is `{plan_id, state, outcome}` (doc implies plan detail); `operation_id` 1–120 bytes | doc→server | doc fix below |
| Undocumented 422s the console maps: `fleet_planning_requirement_not_active`, `fleet_repair_horizon_exceeded` | doc→server | doc fix below |
| `scheduling_progress` marks `contacts` and `contact_plans` | doc→server | doc fix below |
| §3 "Proposed endpoints" is stale against §4 | doc→server | doc fix below (marked superseded) |
| Grants: `limits` is an object with null fields; `revoked_at`, `revocation_reason`, `service_identity.name`, `currency`, `maximum_estimated_cost_micros` nullable | doc→server | doc fix below |
| No HTTP shape test for `execute`, a successful repair read, or a successful resolve | tests | **HOLD** (contact path), after 01:00Z |

## Providers

| Item | Owner | Direction | State |
| --- | --- | --- | --- |
| Routing groups `transport.name` null for a rule on an archived transport; the console's groups read fails | api | server→doc | **fixed** 6956b31e5 (falls back to the id), test |
| PA2 `credential.version` / `status` null when the credential record is missing; the console's PA2 decode fails | api-ops (L13) | shape change | **fixed** api-ops 8f054515c (`status: "missing"`, `version: null`), after fe-setup's reader 377e08c79 |
| PA2 `grants[].mission.name` can be null; the console reads a string | api-ops | server→doc | **fixed** api-ops 4b203c504 (falls back to the id) |
| Mission providers `policy_mode` null without `mode` | api-ops (L12) | server→doc | **fixed** api-ops 4b203c504 (`approval_required`) |
| Mission providers `account.id` / `account.name` null for a direct provider; the console's list decode fails | api-ops (L12) | shape change | **fixed** api-ops 8f054515c (`account: null`), after fe-setup's reader 377e08c79 |
| Mission providers `grant.version` is the bound version, not the grant's current one | api-ops | doc→server | **fixed** api-ops (setup.md) |
| PA1 create: a bad `base_url` answers `422 invalid_provider_account_base_url` with no details; a blank name answers `invalid_params {settings}`. The doc says `invalid_params` naming the field; the console maps `settings.base_url` and `name` | api | server→doc | **fixed** df82d460b (fe-setup OK'd; checked before the credential is registered), exact-shape test |
| Revoke grant / credential: a missing expected version answers 422 naming it (undocumented) | api-ops | doc→server | **fixed** api-ops (setup.md) |
| `display_name` limit is 120 bytes (doc: characters); `bounded.minimum_retained_duration_seconds` optional | api-ops | doc→server | **fixed** api-ops (setup.md) |
| No exact-shape test in this area | api / api-ops | tests | routing groups and PA1 create done |
