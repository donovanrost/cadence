# Setup endpoints (Readiness, Spacecraft, Catalog, Profiles, People)

Conventions: [README.md](README.md). Requested shapes: `docs/apogee/plans/setup-shapes.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| S | `GET /missions/:mission_id/spacecraft` | **implemented** |
| R | `GET /missions/:mission_id/readiness` | **implemented** (v1, `Cadence.Reads.Readiness`; domain extends it for change-set preview) |
| P | `GET /missions/:mission_id/profiles` | **implemented** |
| SD | `GET /missions/:mission_id/spacecraft/:spacecraft_id` | **implemented** |
| PD | `GET /missions/:mission_id/profiles/:profile_id` | **implemented** |
| C1 | `GET /missions/:mission_id/catalog` | **implemented** |
| C3 | `GET /missions/:mission_id/catalog/imports/:import_run_id` | **implemented** |
| C2 | `POST /missions/:mission_id/catalog/imports`, `GET …/catalog/importers` | **implemented** |
| (4) | batch spacecraft validate + create | planned |
| O1 | `GET /organizations/:organization_id/people` | **implemented** |
| O2 | `POST /organizations/:organization_id/invitations` | **implemented** |
| O3 | `GET /organizations/:organization_id/service-identities` | **implemented** |
| O4 | command policies (as text) | with api-ops (commanding policy, D7) |
| G1, T1, T2 | `GET /missions/:mission_id/ground-stations`, `/transports`, `/routing-rules` | **implemented** |
| kind schema | `GET /missions/:mission_id/config/kinds/:kind/schema` | **implemented** |

## `GET /api/console/v1/missions/:mission_id/spacecraft`

The Setup spacecraft directory. It is unpaginated (the client filters) and sorted by `scid`, then
`name`, with spacecraft lacking a SCID last. Refetch on `invalidate` with `spacecraft`.

```json
{"data": {"spacecraft": [
  {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312, "norad_id": null,
   "plane": 13, "slot": 12,
   "profile": {"id": "profile-…", "name": "Earendil Block 1", "version": 1},
   "routing_rule_count": 6,
   "ready": true,
   "last_received_at": null}
]}}
```

- `scid`: integer or null. `norad_id`, `plane` and `slot` are integers or null, read from
  spacecraft metadata (`norad_id`, `plane`, `slot`) until domain makes them first-class.
- `profile`: null when unbound. `profile.version` is the version the spacecraft is pinned to.
  `profile.name` may be null if the profile was deleted.
- `routing_rule_count`: active, enabled routing rules for this spacecraft. Under DECISIONS #3 this
  becomes the materialized count from the profile's rules.
- `ready`: has a SCID, a profile, and `routing_rule_count > 0`.
- `last_received_at`: newest telemetry or limit evaluation received, or null if never heard
  ("Awaiting first AOS"). It is the same source as `/fleet`. It replaces the requested
  `first_heard_at`, which needs a projection that doesn't exist yet.
- **Not in v1:** `configuration` (`active_version`, `draft_status`) from the requested shape. The
  configuration draft and activation model is being reworked into mission change sets
  (DECISIONS #1), so this field arrives with that seam instead of shipping a shape that is about
  to change.

Errors: `404 mission_not_found`.

## `GET /api/console/v1/missions/:mission_id/profiles`

Active spacecraft profiles, each at its latest version, sorted by name. Refetch on `invalidate`
with `spacecraft`.

```json
{"data": {"profiles": [
  {"id": "profile-…", "name": "Earendil Block 1", "version": 4,
   "downlink_protocol": {"value": "tm", "label": "CCSDS TM"},
   "uplink_protocol": {"value": "tc", "label": "CCSDS TC"},
   "packet_protocol": {"value": "space_packet", "label": "CCSDS Space Packet"},
   "catalog_revision": null,
   "spacecraft_count": 500, "spacecraft_on_older_versions": 3}
]}}
```

- `spacecraft_count`: spacecraft pinned to any version of this profile. `spacecraft_on_older_versions`
  is the subset pinned below `version`.
- `catalog_revision`: always `null` for now, because profiles don't carry a catalog yet (it moves
  onto the profile with domain's profile work, profile-routing.md §3).
- **Not in v1:** `updated_at`. The profile model has no update timestamp; the History view gets
  version timestamps from PD.

## `GET /api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id`

Refetch on `invalidate` with `spacecraft`.

```json
{"data": {
  "spacecraft": {"id": "…", "name": "EARENDIL-312", "scid": 312, "norad_id": null,
                 "plane": 13, "slot": 12, "last_received_at": null},
  "profile": {"id": "profile-…", "name": "Earendil Block 1", "version": 3, "latest_version": 4},
  "configuration": null,
  "routing_rules": [
    {"id": "…", "name": "Primary downlink", "purpose": "TM", "direction": "inbound",
     "role": "primary", "enabled": true, "active": true,
     "transport": {"id": "…", "name": "Svalbard X-band", "version": 2}}
  ],
  "readiness": {"ready": false, "checks": [
    {"key": "identity", "status": "ready", "title": "SCID 312", "body": "The spacecraft has a SCID."},
    {"key": "profile", "status": "caution", "title": "Earendil Block 1 v3", "body": "Pinned to v3; the latest is v4."},
    {"key": "routing", "status": "ready", "title": "6 routing rules", "body": "Active, enabled rules cover it."},
    {"key": "telemetry", "status": "not_set_up", "title": "Never heard", "body": "No telemetry has been received yet."}
  ]}
}}
```

- `profile`: null when unbound. `name` and `latest_version` are null if the pinned profile was
  deleted (the `profile` check is then a `blocker`).
- `routing_rules[].direction`: `inbound | outbound | bidirectional`. These are the model's values
  (inbound = downlink, outbound = uplink), not the `downlink | uplink | both` that was requested.
  `role`: `primary | candidate | contributing`. Archived rules appear with `active: false`, active
  ones first.
- `readiness.checks[].status`: `ready | blocker | caution | not_set_up`. `ready` is true when
  `identity`, `profile` and `routing` are not blockers (`telemetry` is informational), the same rule
  as the directory's `ready`.
- `configuration`: `null` in v1, for the same reason as the directory (DECISIONS #1 change sets).

Errors: `404 mission_not_found`, `404 spacecraft_not_found`.

## `GET /api/console/v1/missions/:mission_id/readiness`

The shape is setup-shapes.md §R, with **singular** verdict keys (agreed with fe-setup). Refetch on
`invalidate` with `spacecraft`, `catalog`, `data_sources` or `settings`.

```json
{"data": {
  "evaluated_at": "2026-11-08T02:41:17Z",
  "verdict": {"blocker": 1, "caution": 0, "stale": 0, "not_set_up": 2, "optional": 0},
  "areas": [
    {"key": "fleet", "status": "blocker", "count": 500, "unit": "spacecraft",
     "secondary_count": 1, "secondary_unit": "profile", "detail": null},
    {"key": "catalog", "status": "ready", "count": 3, "unit": "revisions",
     "secondary_count": 1, "secondary_unit": "catalog", "detail": "Latest rev 3 · FSW 3.1.0"},
    {"key": "comms", "status": "ready", "count": 2, "unit": "transports", "secondary_count": 500, "secondary_unit": "routing rules", "detail": null},
    {"key": "stations", "status": "unknown", "count": 4, "unit": "stations", "secondary_count": null, "secondary_unit": null, "detail": "Station health isn't tracked yet."},
    {"key": "data_sources", "status": "unknown", "count": null, "unit": "sources", "secondary_count": null, "secondary_unit": null, "detail": "No data-source health has been reported yet."},
    {"key": "apps", "status": "not_set_up", "count": 0, "unit": "installed", "secondary_count": 1, "secondary_unit": "available", "detail": null}
  ],
  "findings": [
    {"id": "fleet.spacecraft_without_routing_rule", "severity": "blocker",
     "cause": "spacecraft_without_routing_rule", "title": "12 spacecraft have no routing rule",
     "body": "They can't be contacted until a rule covers them.", "affected_count": 12,
     "fix": {"kind": "comms", "id": null, "label": null}},
    {"id": "apps.app_not_installed:limits", "severity": "not_set_up",
     "cause": "app_not_installed:limits", "title": "Limits & Alarming not installed",
     "body": "Ground limit checks are off. Alarms come only from flight events.", "affected_count": 0,
     "fix": {"kind": "app", "id": "limits", "label": null}}
  ],
  "recent_changes": null
}}
```

Rules (v1), by area:

| Area | Findings (cause → severity → fix) | Status notes |
| --- | --- | --- |
| fleet | `no_spacecraft` blocker → `spacecraft_new`; `spacecraft_missing_scid`, `spacecraft_without_profile` blocker → `spacecraft_list`; `spacecraft_without_routing_rule` blocker → `comms`; `spacecraft_on_older_profile_version` caution → `profile` (one profile) or `spacecraft_list` | |
| catalog | `no_catalog`, `catalog_without_revision` blocker → `catalog_import` | detail "rev N · used by M spacecraft", or "rev N" ("rN" is reserved for mission config revisions) |
| comms | `no_transports` blocker → `comms` | |
| stations | `no_ground_stations` not_set_up → `station` | `unknown` when stations exist, because station health isn't tracked (never ready by default) |
| data_sources | `data_source_unavailable` blocker, `data_source_degraded` caution → `data_source` (id when it is just one) | `unknown` when no health has been reported |
| planning (no tile) | `planning_not_set_up` not_set_up → `contact_planning` | from `/contact-plans/setup` |
| apps | `app_not_installed:limits` not_set_up; other missing optional apps → optional; fix `app` with the app key | optional findings never degrade an area; detail names the missing apps ("A and B aren't installed") |

- Units are singular when the count is 1.
- `affected_count` is 0 for findings that aren't about a set of items.
- Findings are sorted by severity (blocker first), then area order.
- `recent_changes` stays `null` until a unified change feed exists (mission change sets).

## `GET /api/console/v1/missions/:mission_id/profiles/:profile_id`

Profile detail with **schema-driven sections** (`Cadence.SpacecraftType.Schema`, profile-routing
§3), so the form is generated from the server. Refetch on `invalidate` with `spacecraft` or
`configuration`.

```json
{"data": {
  "profile": {"id": "…", "name": "Earendil Block 1", "version": 4, "catalog_revision": null,
              "protocols": {"downlink": {"value": "tm", "label": "CCSDS TM"},
                            "uplink": {"value": "tc", "label": "CCSDS TC"},
                            "packet": {"value": "space_packet", "label": "CCSDS Space Packet"}},
              "last_change": {"version": 4, "revision": null, "at": "2026-10-19T02:29:00Z", "actor": null}},
  "inherit_count": 500, "on_older_versions": 3, "override_count": 0,
  "sections": [
    {"key": "framing", "label": "Framing", "fields": [
      {"path": "frame_parameters.frame_size", "label": "TM frame length", "type": "integer",
       "unit": "bytes", "enum": null, "range": {"min": 1, "max": 65535}, "default": 1115,
       "overridable": true, "runtime_impact": "generation",
       "help": "TM and AOS frames are at most 2048 bytes; validated per protocol.",
       "value": 1115, "overridden_by": 0}
    ]},
    {"key": "catalog", "label": "Catalog", "fields": [{"path": "catalog_revision_id", "type": "reference", "value": null, "…": "…"}]}
  ],
  "applications": {"telemetry_decom": {}},
  "rules": [], "overrides": [], "routing_model": "per_spacecraft",
  "versions": [{"version": 4, "created_at": "2026-10-19T02:29:00Z", "actor": null}]
}}
```

- Fields are exactly the model-backed ones from profile-routing §3: framing (TM/TC/packet
  protocol, frame length, secondary header, insert zone, OCF, FECF, truncated primary header) and catalog.
  `type` is `integer | boolean | enum | string | reference`; `runtime_impact` is
  `generation | routes | none`. Enum options come as `[{value, label}]`.
- `rules` and `overrides` come from domain's profile routing (DECISIONS #3, shapes in domain.md
  "P2 additions"). `routing_model` is `"profile"` when the profile has rules, else
  `"per_spacecraft"` (legacy per-spacecraft rules not yet lifted). `override_count` and each
  field's `overridden_by` count the spacecraft overriding that path.
- `catalog_revision` is `{id}` (or `null`), and the catalog field's `value` is the profile's
  `catalog_revision_id`. `versions[].actor` and `last_change.actor` are `null` because profile versions don't
  record an author (change-set revisions do; `last_change.revision` fills in when profile edits go
  through change sets).
- `applications`: the profile's app defaults as raw JSON. A typed app-config schema needs each
  app's declared contract; that's planned.

Errors: `404 profile_not_found`.

## `GET /api/console/v1/missions/:mission_id/catalog` (C1)

The shape is setup-shapes.md §C1. `?database_id=` selects a database (default: the first by name).
`database` is `null` when the mission has none. Refetch on `invalidate` with `catalog`.

- `revisions`: newest first, at most 50. `import_runs`: newest first, at most 20.
- `revisions[].declaration_count` comes from the producing import run. `command_count` and
  `telemetry_count` are **`null`**: importers report only a total so far, so show one
  "Declarations" number.
- `revisions[].spacecraft_count`: spacecraft whose latest saved configuration references the
  revision.
- `revisions[].artifact.size_bytes` is `null` in the index (sizes would mean loading every file).
  C3 has the real size. `format_label` is the importer's display name.
- `revisions[].actor`: `{name}` from the importer of record, when recorded.
- `import_runs[].status`: `running | succeeded | failed`. There is no separate `pending` state: a
  queued import is `running`. `file_name` is known for runs that produced a revision, otherwise
  `null`.

## `GET /api/console/v1/missions/:mission_id/catalog/imports/:import_run_id` (C3)

The shape is setup-shapes.md §C3, plus `declaration_count`.

- `file.size_bytes` is the uploaded artifact's byte size.
- `diagnostics[]`: `{severity: error|warning|info, code, message, path}`, where `path` is a
  " / "-joined XTCE path or `null`. A run can succeed with error diagnostics (unsupported items
  are skipped).
- `base_revision` and `diff` are `null` until the server-side revision diff exists
  (DECISIONS #9). The UI shows validation and diagnostics only.
- Errors: `404 import_run_not_found`.
- Live: refetch on `invalidate` with `catalog`.

## `POST /api/console/v1/missions/:mission_id/catalog/imports` (C2, multipart)

Fields: `file` (at most 50 MiB), `database_id` (optional; when absent, `name` is required and creates
a database), `revision_label`, `revision_notes`. Send `x-csrf-token`. The format is detected from
the file name and extension (the browser's media type is only a hint).

- `202 {"data": {"import_run_id": "…"}}`. Then poll or refetch C3 on `invalidate` with `catalog`.
- `422 invalid_params` (details keyed by field: `name`, `revision_label`, `revision_notes`,
  `file`), `422 unsupported_format` (details `{accepted: [{key, label, extensions}]}`),
  `413 file_too_large`. A body over the server's multipart limit is also rejected with `413`
  (code `file_too_large`) before it reaches the controller.

## `GET /api/console/v1/missions/:mission_id/catalog/importers`

`{"data": {"importers": [{"key": "xtce_1_3", "label": "XTCE 1.3", "extensions": [".xtce", ".xml"]}],
"max_bytes": 52428800}}`: the accepted-format chips.

## Organization routes

Base: `/api/console/v1/organizations/:organization_id`. The organization comes from the URL, not
the session default. An actor who isn't an active member (or a platform admin in admin mode) gets
`404 organization_not_found`.

### `GET /missions` (pass-2 #11)

`{missions: [{id, slug, name, spacecraft_count, worst_state}]}`, sorted by name. `worst_state` is
the worst fleet state any of the mission's spacecraft is in (the fleet read's states, worst first:
`critical | caution | stale | nominal | never_heard`), or `null` when it has no spacecraft. Visible
to every member.

### Provider accounts (PA1, organization admins)

- `GET /provider-accounts` → `{accounts: [{id, name, provider: {key, label}, status: "connected" |
  "auth_failed" | "not_checked", status_detail, expires_at: null, last_success_at, missions: [{id,
  name}], added_at, added_by: {name} | null}], adapters: [{key, label}], permissions:
  ["provider_accounts.manage"]}`.
  - `missions` lists the missions whose ground-network providers use the account.
  - `status` is `auth_failed` when the credential is revoked, and `not_checked` before a first
    successful test.
  - There's no `expiring`: credentials carry no expiry yet.
- `POST /provider-accounts/:id/test` → `{ok, checked: ["reference"], failed: null | "reference",
  reason, message}`. It checks the credential reference exists, isn't revoked and resolves in its
  secret backend. It doesn't call the provider itself yet, so `checked` says what was verified.
  `404 provider_account_not_found`.
- **Credentials are references, never secret values** (ux SettingsAuditProviders.md). Cadence
  stores a reference into the external secret manager (`backend: "external"`, `key` such as
  `providers/<org>/<account>`), or an environment-variable name (`backend: "env"`) where local
  provider credentials are enabled (development). Elsewhere `env` is refused with
  `details["credential.backend"]`.
- `GET /provider-adapters/:key/schema` → `{key, fields}`: kind-schema fields `base_url`,
  `environment_ref`, `region_ref`, `credential.backend`, `credential.key`. There's no secret-value
  field. `404 provider_adapter_not_found`.
- `POST /provider-accounts` `{provider_key, name, settings: {base_url, environment_ref, region_ref?},
  credential: {backend, key}}` → `201 {id, version: 1}`. It registers the reference without
  calling the provider; use Test afterwards.
- `PUT /provider-accounts/:id` `{name?, settings?, credential?}` → `201 {id, version}`. Settings and
  credential make a new account version (a sent `credential` registers a new reference). A
  rename alone writes no version (`version: null`); it's presentation, and it's audited. A blank
  name or one over 120 bytes: `422 details.name`.
- `DELETE /provider-accounts/:id` (optional `reason`) → `{id, state: "archived"}`. The account
  drops out of the list. While missions use it: `409 in_use` with `details.missions: [{id,
  name}]`. `409 already_retired`.
- Writes need `provider_accounts.manage` (organization admin). Errors: `422 invalid_params`
  (`provider_key`, `credential`, `settings`), `403 forbidden`.

### `GET /audit` (AU1, organization admins)

Query: `from`, `to` (ISO; default the last 7 days), `actor_id`, `mission_id`, `kinds` (comma
list of `config, commanding, access, alarms, contacts, data`), `limit` 1–200 (default 100), and
`cursor` (from `next_cursor`).

`{events: [{id, at, actor: {kind, id, name} | null, kind, action, target: {kind, id, label} |
null, mission: {id, name} | null, reason}], sources: {included, missing}, next_cursor}`, newest
first.

- There's no single audit store yet, so this merges each domain's own records:
  - `config`: applied configuration revisions ("Applied r6 · 2 changes", "Rolled back to r4") and
    settings changes ("Changed Governance settings");
  - `commanding`: command requests and approval decisions;
  - `access`: members joining, invitations sent;
  - `alarms`: people acknowledging, assigning, handing off and annotating episodes (the note is
    the `reason`);
  - `contacts`: contact plan approval decisions ("Approved contact plan v1"; the 100 newest plans
    per mission);
  - `data`: data-source definition changes.
- `sources.missing` is empty now. Keep handling it: it names any source that isn't in the log.
- Actions are server-made sentences.
- Settings history carries only the actor's name, so its `actor.id` is `null`.
- `403 forbidden` for non-admins; `422 invalid_params` (`kinds`, `from`/`to`, `limit`, `cursor`).

### `GET /people` (O1)

```json
{"data": {
  "members": [{"user_id": "user_…", "display_name": "Mira K.", "email": "mira@…",
               "role": "member", "capabilities": [],
               "joined_at": "2026-10-19T02:29:00Z"}],
  "invitations": [{"id": "…", "email": "ana@…", "role": "member", "invited_by": {"name": "Ada Admin"},
                   "sent_at": "…", "expires_at": "…", "status": "pending"}],
  "permissions": ["org.invite", "org.manage_members"]
}}
```

- Visible to every member. `permissions` are the **caller's** org-level actions (empty for plain
  members), for gating the invite panel.
- `capabilities` are evaluated on the server per member (DECISIONS #2) by calling, for a scope
  built from that member, the same policy function that enforces each one (DECISIONS #38; the
  agreement is tested per role, never a role table):
  - `command.request`, `command.approve`, `command.abort`: the command review policy
    (`ReviewAccess`, which needs `:manage_mission`). Request authoring, review and group
    abort/cancel all enforce it. **Today that means organization admins only**; plain members get
    none of these.
    The two-person rule (D7) still forbids approving your own request.
  - `org.manage_members`, `org.invite`: `:manage_organization_members` (organization admins).

  When the server policy changes, these follow with no client change. The session reports the same
  names per organization (session.md).
- `invitations` holds only pending, unexpired ones, so `status` is always `pending`. Members are
  sorted by name; invitations newest first. There is no presence or last-seen yet.

### `POST /invitations` (O2)

Body `{email, role: "member" | "organization_admin"}` (default `member`). Requires
`org.invite` (organization admin). It sends the invitation email when mail is configured.

- `201` returns the invitation (same shape as above) plus `delivery: "submitted" | "unavailable"`.
- Errors: `422 invalid_params` (`details.email` / `details.role`), `409 already_member`,
  `409 already_invited`, `403 forbidden`.

## Comms reads (G1, T1, T2)

Stations (G1) also carry `suggested_code` (U25): a stem of the name, de-duplicated against the
mission's set codes (`Cadence.Comms.StationCode.suggest/2`). It's present only when `code` is
`null`, and the server never stores it; show it as a suggestion the operator confirms.

### `GET /missions/:mission_id/data-sources` (D1)

`{sources: [{id, display_name, kind, owner: "cadence" | "customer", status, health: {status:
"healthy" | "degraded" | "unknown", checked_at} | null, last_received_at, expected_interval_s,
stale, credentials: {status: "valid" | "expired" | "none", rotated_at} | null}]}`. Cadence-owned
sources come first, then by name.

- Sources include the platform-managed ones visible to the mission (the telemetry store and the
  projections).
- `health` is the worst current probe result across the source's logical sources. It's
  `unknown` once a probe is older than the source's max age, and `null` if the source was never
  probed.
- `last_received_at` is the newest `latest_receipt_time` across its watermarks, or `null`.
- `stale` is the server's call (U9): `null` unless the source declares
  `metadata.expected_interval_seconds` (then `expected_interval_s` carries it). No managed source
  declares one yet, so expect `null`.
- `credentials` is `null` for sources without a credential reference. There's no expiry data yet,
  so there's no `expiring`.

### `GET /missions/:mission_id/apps` (A1)

`{apps: [{key, name, description, platform, installed, state: "installed" | "disabled" |
"not_installed", version, consequence_if_missing}], permissions: ["apps.install"]}`. These are the
applications installable on a mission, platform ones first, then by name.

- `platform: true` apps are always on and can't be changed.
- `version` is the installed version, an integer (application versions are integers), or `null`
  when the app isn't installed.
- `consequence_if_missing` is always `null`: apps don't declare one yet.
- `apps.install` comes from the check the actions enforce (`:operate_mission`, so any mission
  operator today; DECISIONS #38).

Actions stay direct, not a change-set kind: an installation is a host lifecycle record with its own
audited lifecycle events.

- `POST /apps/:key/install`, `/disable`, `/uninstall` (empty body) return the app's row (same
  shape).
- Errors: `404 app_not_found`, `403 forbidden`, `422` with the domain's code (for example
  `application_dependency_missing`). Refetch on `invalidate` with `configuration`.

### Settings (ST1): `GET /missions/:mission_id/settings` and `GET /organizations/:organization_id/settings`

`{sections: [{key, title, purpose, fields: [field + {value, source: "mission" | "organization",
inherited_value}], locked, version: {version, at, actor: {name}} | null}], permissions:
["settings.edit"]}`.

- Sections come from the server's settings registry (Governance, Commanding, Pass review when
  it lands, and `cadence.configuration`, the profile framing generations flag). A section with no
  console fields is left out.
- Fields use the kind-schema shape, with paths inside the section's value. Shares between 0 and 1
  (Pass review) have `unit: "ratio"`. At organization level
  each section adds `allow_override` ("Missions may override").
- `inherited_value` is the organization's value (mission level only). `locked: true` means the
  organization doesn't allow an override.
- `version` is per section: there's no single settings version.

`PUT …/settings/:section_key` with `{values: {path: value | null}, expected_version}` saves
directly and returns `201 {version, state: "active"}`. For a mission, `null` inherits that field,
and all-`null` clears the override. Errors: `422 invalid_params` (an unknown path in `details`,
or `details.values` for a value the section refuses), `409 version_conflict` (with
`details.expected_version`), `409 settings_enforced_by_organization`, `404
settings_section_not_found`, `403 forbidden`. Edit needs `settings.edit` (any mission operator
today, from the enforcing check).

### `GET /missions/:mission_id/routing-rules/groups` (pass-2 #10)

`{groups: [{transport: {id, name}, direction, role, enabled_count, disabled_count,
spacecraft_count}]}`: active routing rules grouped by transport, direction and role, sorted by
transport name. A thousand per-spacecraft rules read as a few lines; `GET /routing-rules` with
`transport_id` lists one group's rules.

Edits go through change sets (`ground_station` and `transport` kinds; see changes.md). Refetch on
`invalidate` with `configuration` or `spacecraft`.

- `GET .../ground-stations` → `{stations: [{id, display_name, code, provider, region,
  lifecycle_state, transport_count, routing_rule_count, health}]}`. Only active stations are
  listed. `code` is the station's short code (2–8 capitals/digits, unique per mission).
  `transport_count` and `routing_rule_count` are **`null`** because the model has no
  station↔transport link yet. `health` is `null` (not tracked; show "not reported").
- `GET .../transports` → `{transports: [{id, display_name, version, origin, transport_kind,
  direction_capability, lifecycle_state, station: null, routing_rule_count}]}`.
  `routing_rule_count` counts active rules using the transport; `station` is `null` for the same
  reason as above.
- `GET .../transports/:transport_id` → `{id, version, lifecycle_state, document: {display_name,
  origin, transport_kind, direction_capability, configuration}}`. `document` is exactly what the
  `transport` change-set kind loads, so prefill the edit form from it and stage
  `changes: [{path, value}]` on the same paths. `404 transport_not_found`.
- `GET .../routing-rules?spacecraft_id=&transport_id=&limit=&cursor=` → `{rules: [{id, display_name,
  purpose, direction, role, enabled, active, spacecraft: {id, name}, transport: {id, display_name,
  version}}], total, next_cursor}`. Sorted by spacecraft name, then rule name. `limit` is 1–500
  (default 100); pass `next_cursor` back as `cursor`, and `null` means the last page. This changes with
  DECISIONS #3 (rules on the profile).

## `GET /api/console/v1/missions/:mission_id/providers`

`{providers: [{id, name, provider_type, account: {id, name}, status: {lifecycle_state,
last_validated_at, last_synced_at}, station_count}]}` for the Stations · Providers tab, sorted by
name. `account.name` is `null` for members (only organization admins can read accounts).
`station_count` counts active stations whose `provider` is this provider's name. `status` is
the provider's own record; there is no inferred health.

## `GET /api/console/v1/missions/:mission_id/config/kinds/:kind/schema`

`{kind, fields: [{path, label, type, unit, enum, range, default, required, help, visible_when}]}`
for generating change-set edit forms. `kind` is `ground_station` or `transport`; anything else
gets `422 invalid_params`.

- `ground_station`: `display_name` (required), `code` (required for new stations, `pattern`
  `^[A-Z0-9]{2,8}$`, unique per mission), `provider` (an `enum` of the mission's provider names when
  the mission has providers, otherwise free text), `region`.
- `transport`: `display_name`, `transport_kind`, plus each transport kind's configuration fields
  on the **stored document's paths** (today `tcp_socket`: `configuration.mode`,
  `configuration.direction_capability`, `configuration.host`, `configuration.port`,
  `configuration.framing.mode`, `configuration.framing.fixed_message_bytes`,
  `configuration.reconnect.policy`, `configuration.tls.enabled` (boolean)). They match the transport
  detail `document`, so stage edits to exactly these paths.
- `visible_when: {path, equals}` says when to show a field (for example `frame_size` only when
  `configuration.framing_mode` is `fixed_size`, and each kind's fields only for its
  `transport_kind`).

### `GET /service-identities` (O3)

Organization admins only (`403 forbidden` for members).

```json
{"data": {"service_identities": [{"id": "…", "name": "Ground segment ingest",
  "scope_summary": "Telemetry write · Earendil", "capabilities": ["telemetry_write"],
  "mission": {"id": "…", "name": "Earendil"}, "last_used_at": null,
  "key_created_at": "2026-10-19T02:29:00Z"}],
 "rotation_policy_days": null}}
```

Only active identities are listed. `last_used_at` is always `null` (token use isn't tracked yet),
and `rotation_policy_days` is `null` (there is no rotation policy model). `mission` is `null` for
organization-wide identities ("· all missions" in `scope_summary`).
