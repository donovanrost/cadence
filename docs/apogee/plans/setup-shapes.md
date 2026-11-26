# Setup endpoint shapes requested by fe-setup

Owner: **fe-setup** (request). Confirmed by api 2026-11-08; api owns the final contract in `docs/apogee/api/setup.md`. Until it
lands, the console decoders in `frontend/apps/console/src/features/{readiness,spacecraft}/api.ts`
match these shapes exactly. Conventions follow `docs/apogee/api/README.md` (snake_case, null not
omitted, server-decided staleness). Sources are in `plans/setup.md`.

## R · `GET /api/v1/missions/:mission_id/readiness`

```json
{"data": {
  "evaluated_at": "2026-11-08T02:41:17Z",
  "verdict": {"blocker": 0, "caution": 1, "stale": 1, "not_set_up": 1, "optional": 1},
  "areas": [
    {"key": "fleet", "status": "ready", "count": 500, "unit": "spacecraft",
     "secondary_count": 2, "secondary_unit": "profiles",
     "detail": "Every spacecraft has a SCID, a profile and a routing rule"}
  ],
  "findings": [
    {"id": "routing.spacecraft_without_rule", "severity": "blocker",
     "cause": "spacecraft_without_routing_rule",
     "title": "12 spacecraft have no routing rule",
     "body": "They can't be contacted until a rule covers them.",
     "affected_count": 12,
     "fix": {"kind": "profile", "id": "type_…", "label": null}}
  ],
  "recent_changes": null
}}
```

- `areas`: exactly six, in this order of `key`: `fleet | catalog | comms | stations | data_sources | apps`.
- `areas[].status`: `ready | blocker | caution | stale | not_set_up | unknown`. Use `unknown`
  (with `count` possibly null and `detail` saying why) when the area can't be assessed. It must
  never default to `ready`.
- `areas[].count`: integer or null. `unit`: string. `secondary_count`/`secondary_unit`: both null
  or both set. `detail`: one sentence or null.
- `findings[].severity`: `blocker | caution | stale | not_set_up | optional`. Findings are
  **grouped by cause on the server** (one row per cause, with `affected_count`).
- `findings[].fix`: null (no action), or `{kind, id, label}`. `kind`: `spacecraft_list | spacecraft |
  spacecraft_new | profile | catalog | catalog_import | comms | station | data_source | app`. `id` is
  null for list/new kinds. `label` overrides the default button verb, or null.
- `verdict`: counts of findings per severity (rows, not affected items), keyed by the severity values.
- `recent_changes`: null when there's no unified event feed (the UI then omits panel R2), else
  `[{"at", "kind", "version_label": "v4"|null, "summary", "actor": {"name"}|null}]`, newest first,
  at most 5.
- Empty mission: `fleet` is `blocker` with count 0, plus a `blocker` finding "No spacecraft" with
  `fix.kind = spacecraft_new`. Same for no catalog (`catalog_import`).

## S · `GET /api/v1/missions/:mission_id/spacecraft`

The Setup spacecraft directory. It's unpaginated like `/fleet` (one mission is at most a few
thousand rows), and the client filters.

```json
{"data": {"spacecraft": [
  {"id": "spacecraft-…", "name": "EARENDIL-312", "scid": 312, "norad_id": null,
   "plane": 13, "slot": 12,
   "profile": {"id": "type_…", "name": "Earendil Block 1", "version": 4},
   "routing_rule_count": 6,
   "configuration": {"active_version": 3, "draft_status": "pending_review"},
   "ready": true,
   "last_received_at": null}
]}}
```

- `scid`, `norad_id`, `plane`, `slot`: integer or null (from metadata until domain models them).
- `profile`: null when unbound. `profile.name` may be null when the profile was deleted.
- `configuration.active_version`: integer or null (never activated). `configuration.draft_status`:
  `none | draft | pending_review | rejected`.
- `ready`: the directory readiness flag (SCID + profile + at least one enabled routing rule).
- `last_received_at`: timestamp or null (never heard: "Awaiting first AOS"). It comes from the same
  freshness read as `/fleet` (api, 2026-11-08).

## P · `GET /api/v1/missions/:mission_id/profiles`

The Profiles list (rail 03). Active profiles only. The latest version is the one shown, and the
counts cover spacecraft pinned to any version.

```json
{"data": {"profiles": [
  {"id": "type_…", "name": "Earendil Block 1", "version": 4,
   "downlink_protocol": {"value": "tm", "label": "CCSDS TM"},
   "uplink_protocol": {"value": "tc", "label": "CCSDS TC"},
   "catalog_revision": {"id": "rev_…", "number": 14, "label": "FSW 3.1.0"} ,
   "spacecraft_count": 500, "spacecraft_on_older_versions": 3,
   "updated_at": "2026-10-19T02:29:00Z"}
]}}
```

- `catalog_revision`: null when the profile names none. It may stay null until domain moves the
  catalog onto the profile (profile-routing.md §3 lists it as a profile field).
- `spacecraft_on_older_versions`: how many of `spacecraft_count` pin a version below `version`.

## PD · `GET /api/v1/missions/:mission_id/profiles/:profile_id`

Shape = domain `profile_detail` (`docs/apogee/domain/profile-routing.md` §5) in snake_case. Two
things it adds:
- enum fields carry `enum: [{value, label}]`;
- `versions: [{version, created_at, actor: {name}|null}]` for the History view.

Before profile routing and overrides land, return `rules: []` and `overrides: []`, plus
`"routing_model": "per_spacecraft"`, so the UI can say routing is still per spacecraft. Don't
return them empty without that flag.

## SD · `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id`

```json
{"data": {
  "spacecraft": {"id", "name", "scid", "norad_id", "plane", "slot", "last_received_at"},
  "profile": {"id", "name", "version", "latest_version"} | null,
  "configuration": {
    "active": {"version": 3, "catalog_revision": {"id", "number", "label"} | null,
               "telemetry_enabled": true, "commanding_enabled": true,
               "activated_at": "…", "actor": {"name"} | null} | null,
    "draft": {"version": 4, "status": "draft|pending_review|rejected",
              "submitted_at": "…" | null, "actor": {"name"} | null} | null
  },
  "routing_rules": [{"id", "name", "direction": "downlink|uplink|both", "role": "primary|candidate|contributing",
                     "enabled": true, "transport": {"id", "name"}}],
  "readiness": {"ready": true, "checks": [{"key", "status": "ready|blocker|caution|not_set_up", "title", "body"}]}
}}
```

## C · Catalog (S3, `ux/screens/Catalog.md`)

### C1 · `GET /missions/:mission_id/catalog`

The index: databases, then the selected one's revisions and recent import runs.

```json
{"data": {
  "databases": [{"id": "db_…", "name": "Earendil FSW", "slug": "earendil-fsw"}],
  "database": {
    "id": "db_…",
    "current_revision": {"id": "rev_…", "number": 14, "label": "FSW 3.1.0",
                         "declaration_count": 547, "command_count": 212, "telemetry_count": 335,
                         "spacecraft_count": 500} | null,
    "revisions": [{"id", "number", "label", "notes", "artifact": {"id", "file_name", "format_label", "size_bytes"},
                   "declaration_count", "spacecraft_count", "imported_at", "actor": {"name"}|null}],
    "import_runs": [{"id", "file_name", "status": "pending|running|succeeded|failed",
                     "diagnostic_counts": {"error": 0, "warning": 2, "info": 0},
                     "revision_number": 15|null, "started_at", "completed_at"|null}]
  } | null
}}
```
- `?database_id=` selects a database, defaulting to the first. `database` is null when the mission
  has none, which the UI shows as "No catalog yet".
- `current_revision`: the latest revision. `command_count`/`telemetry_count` may be null until the
  importer reports per-kind counts. In that case the UI shows one `Declarations` number.
- `spacecraft_count`: spacecraft whose active configuration uses that revision.
- `revisions` newest first, at most 50. `import_runs` newest first, at most 20.

### C2 · `POST /missions/:mission_id/catalog/imports` (multipart)

Fields `file` (≤ 50 MiB), `database_id` (optional; when absent, `name` creates a database),
`revision_label`, `revision_notes`. Returns `{"data": {"import_run_id": "run_…"}}` (202). Errors:
`422 invalid_params`, `422 unsupported_format` (with `details.accepted: [{format_key, label,
extensions}]`), `413 file_too_large`.

`GET /missions/:mission_id/catalog/importers` → `{"data": {"importers": [{"key": "xtce_1_3",
"label": "XTCE 1.3", "extensions": [".xml"]}], "max_bytes": 52428800}}` for the accepted-format
chips.

### C3 · `GET /missions/:mission_id/catalog/imports/:import_run_id`

```json
{"data": {
  "id", "status": "pending|running|succeeded|failed", "started_at", "completed_at"|null,
  "file": {"name", "format_label", "size_bytes"},
  "failure_reason": null | "…",
  "diagnostics": [{"severity": "error|warning|info", "code", "message", "path"|null}],
  "revision": {"id", "number", "label"} | null,
  "base_revision": {"id", "number"} | null,
  "diff": null | {
    "summary": {"commands": {"before", "after", "added", "changed", "removed"},
                "telemetry": {…same…}, "unchanged", "total_before", "breaking"},
    "changes": [{"op": "added|changed|removed", "kind": "command|telemetry|other", "name",
                 "change": "arg duration: u16 seconds → u32 milliseconds", "breaking": true}]
  }
}}
```
- `diff` is null until the diff exists (DECISIONS #9 v1: added/changed/removed/breaking from the
  two revisions, without impact). The UI then shows validation and diagnostics only.
- Live status: an `import_run` event on the `mission:<id>` channel (`{import_run_id, status}`),
  or an `invalidate` with `catalog`. Either works; the UI refetches C3.

## K · Change sets (`ux/screens/Changes.md`, facade `docs/apogee/api/domain.md`)

The facade can be passed through almost one to one. The JSON is the facade shapes in snake_case,
with these conventions:
- atoms become lowercase strings;
- `actor` is `{kind, id, name}`;
- times are ISO-8601;
- revision numbers are integers (the UI renders `rN`);
- `doc`/`payload`/`value` stay raw JSON.

All routes sit under `/api/v1/missions/:mission_id/config`.

| Route | Facade | Notes |
| --- | --- | --- |
| `GET /config` | `current/2` + `permissions/2` | `{head: revision_summary, change_set: change_set \| null, permissions: ["config.stage", …]}`. Drives the staged bar and `CONFIG rN · N STAGED`. |
| `GET /config/change-sets/:id` | `change_set/3` | |
| `POST /config/stage` | `stage/4` | body `{summary, source, ops: [op]}`, returns the stage result |
| `POST /config/changes/:change_id/withdraw` | `withdraw/3` | |
| `POST /config/change-sets/:id/discard` | `discard/4` | body `{expected_version}` |
| `POST /config/change-sets/:id/preview` | `preview/3` | |
| `POST /config/preview` | `preview(…, {:ops, ops})` | body `{ops}`; the Profile P4 aside |
| `POST /config/ops/:op_id/rebase` | `rebase/4` | body `{choice: "keep_mine" \| "take_live"}` |
| `POST /config/change-sets/:id/submit` | `submit/4` | body `{reason, expected_version, acknowledged_holds}` |
| `POST /config/change-sets/:id/review` | `review/5` | body `{decision: "approve" \| "send_back", comment, expected_version}` |
| `GET /config/revisions?before=&limit=` | `list_revisions/3` | `{revisions: [revision_summary]}` |
| `GET /config/revisions/:n` | `get_revision/3` | |
| `GET /config/compare?from=&to=` | `compare/4` | |

**Errors.** Use the README envelope, with `code` = the facade tag:
- `409`: `frozen_in_review`, `change_set_changed`, `path_already_staged` (details = the map),
  `reviewer_is_author`, `activation_policy_changed`, `entity_gone`.
- `422`: `invalid_op` (details `{index, errors: [{path, message}]}`), `reason_required`,
  `comment_required`, `nothing_staged`, `not_in_review`, `checks_failed` and
  `holds_not_acknowledged` (details = the preview).
- `403`: `forbidden`.
- `404`: `change_set_not_found`, `revision_not_found`, `change_not_found`, `op_not_found`.

The UI switches on `code`, so please keep the facade's distinct tags. Don't fold them into a
generic 409/422.

**Live, on the existing `mission:<id>` channel:**
- `invalidate` with resource `configuration` after every mutation (`configuration_changed`).
- `change_set_progress` `{change_set_id, key, label, state, at}` (relayed from
  `change-sets:<id>`).
- `config_runtime` `{revision, activation_id, generation, runtime, degraded_partitions}`.

## O · People & access (`ux/screens/People.md`), under `/api/v1/organizations/:organization_id`

### O1 · `GET /people`

```json
{"data": {
  "members": [{"user_id": "user_…", "display_name": "Mira K.", "email": "mira@…",
               "role": "organization_admin|member",
               "capabilities": ["command.request", "command.approve"],
               "joined_at": "…"}],
  "invitations": [{"id": "inv_…", "email": "ana@…", "role": "member", "invited_by": {"name"}|null,
                   "sent_at": "…", "expires_at": "…", "status": "pending|expired"}],
  "permissions": ["org.invite", "org.manage_members"]
}}
```
- `capabilities` are evaluated per user on the server (DECISIONS #2). The UI shows Command / Second
  GO from `command.request` / `command.approve` only, never from the role name.
- No presence or last-seen fields until they exist (the UI drops those columns).
- `permissions` covers the caller's org-level actions, to gate the invite panel.

### O2 · `POST /invitations` `{email, role}` → the invitation (201)

Errors: `422 invalid_params` (`details.email`), `409 already_member`, `409 already_invited`.
`POST /invitations/:id/revoke` and `POST /invitations/:id/resend` can come later.

### O3 · `GET /service-identities`

```json
{"data": {"service_identities": [{"id", "name", "scope_summary": "Telemetry write · Earendil",
  "last_used_at": "…"|null, "key_created_at": "…"|null}],
  "rotation_policy_days": null}}
```
`rotation_policy_days` stays null unless the org has a policy, so the UI never invents one.

### O4 · `GET /missions/:mission_id/command-policies` (or org-level)

`{"data": {"policies": [{"key", "title", "sentence"}]}}` gives the effective two-person and
fleet-reach policy as text (DECISIONS #7).

## G · Ground stations (rail 06) and T · Comms & routing (rail 05)

These screens edit through change sets. The `ground_station` and `transport` kinds already stage.
They only need reads.

### G1 · `GET /missions/:mission_id/ground-stations`

```json
{"data": {"stations": [{"id", "display_name", "code": "SVB"|null, "provider": "…"|null,
  "region": "…"|null, "lifecycle_state": "active|archived", "transport_count": 2,
  "routing_rule_count": 500, "health": null}]}}
```
`health` stays null until station health is tracked (the UI shows "not reported", never "ok").

### T1 · `GET /missions/:mission_id/transports`

```json
{"data": {"transports": [{"id", "display_name", "version", "origin": "direct|provider_managed",
  "transport_kind": "tcp_socket", "direction_capability": "inbound|outbound|bidirectional",
  "lifecycle_state": "active|archived", "station": {"id", "display_name"}|null,
  "routing_rule_count": 500}]}}
```

### T2 · `GET /missions/:mission_id/routing-rules?spacecraft_id=&transport_id=`

`{"data": {"rules": [{"id", "display_name", "purpose", "direction", "role", "enabled", "spacecraft":
{"id", "name"}, "transport": {"id", "display_name", "version"}}], "total": 1000}}`. This one is
paged (`limit`, `cursor`), since rules are per spacecraft today (1,000+). It goes away or changes
with DECISIONS #3.

For editing, the UI needs each kind's editable fields. Please add a `schema` (same field shape as
PD sections) to G1/T1, or a `GET /config/kinds/:kind/schema`, so the edit forms are generated.

## D · Data sources (rail 07) and A · Apps (rail 08)

### D1 · `GET /missions/:mission_id/data-sources`

```json
{"data": {"sources": [{"id", "display_name", "kind": "managed_tsdb|…", "owner": "cadence|external",
  "status": "active|disabled|…", "health": {"status": "healthy|degraded|unknown", "checked_at"}|null,
  "last_received_at": "…"|null, "expected_interval_s": 300|null, "stale": false|null,
  "credentials": {"status": "valid|expiring|expired|none", "rotated_at"}|null}]}}
```
Staleness comes from the server (U9): `stale` is null when there's no expectation to judge it by.

### A1 · `GET /missions/:mission_id/apps`

```json
{"data": {"apps": [{"key": "limits", "name": "Limits & Alarming", "description": "…",
  "installed": true, "state": "installed|disabled|not_installed",
  "version": "1.2.0"|null, "consequence_if_missing": "Ground limit checks are off."|null}],
  "permissions": ["apps.install"]}}
```
Install, disable and uninstall exist today as direct actions (`ApplicationInstallations`).
**Question:** should they become a change-set kind (stage, then apply as rN), like stations, or
stay direct? If direct: `POST /apps/:key/install|disable|uninstall` returning the app row.

## CP · Contact planning (`ux/screens/ContactPlanning.md`, DECISIONS #27)

All routes sit under `/api/v1/missions/:mission_id/contact-planning`. Field schemas use
the kind-schema field shape (`path, label, type, unit, enum, range, default, required, help,
visible_when`), plus `group` (the panel key) and `advanced: boolean`.

### CP1 · `GET /` (summary)

```json
{"data": {
  "policy": {"version": 3, "mode": "advisory", "approval_required": false,
             "activated_at": "…", "actor": {"name"}|null} | null,
  "coverage": {"spacecraft_total": 500, "covered": 488, "contacts_per_day": 1500|null,
               "uplink_passes_per_day": 500|null},
  "templates": [{"id", "name", "applies_to": "profile Earendil Block 1", "rule_summary":
                 "≥ 3 contacts / day · no gap > 10h00 · ≥ 1 uplink", "priority": "routine|high|critical",
                 "version": 2, "spacecraft_count": 500}],
  "not_covered": [{"group": "profile|plane|none", "label": "Earendil Block 2", "count": 12,
                   "suggested_target": {…query…}|null}],
  "permissions": ["planning.edit", "planning.approve"]
}}
```
`policy: null` means not set up. Rule summaries are server-made sentences, so the UI never
re-derives them. Counts are null when they can't be computed.

### CP2 · Policy

- `GET /policy`:
  `{document: {...}|null, version, schema: [field], defaults: {...}|null, pending: {version, requested_by, requested_at}|null}`
- `POST /policy` with `{document, reason}`:
  - `201 {version, state: "active"|"pending_approval"}`
  - errors: `invalid_params` (details by path), `version_conflict` (with `expected_version`), `forbidden`
- `POST /policy/:version/decision` with `{decision: "approve"|"reject", comment}`. The reviewer must
  differ from the author: `reviewer_is_author`.

### CP3 · Templates

- `GET /templates/:id`: `{id, name, version, document, target: {query}, schema: [field], versions: [{version, created_at, actor, reason}]}`
- `GET /templates/schema`: the requirement field schema, for the new-template form.
- `POST /templates` with `{name, document, target, reason}`: `201 {id, version}`.
- `POST /templates/:id` with `{document, target, reason, expected_version}`: `201 {version}`.
- `target` is the same query as Command C1 (profile / plane / spacecraft ids). For an edit, also
  return `preview: {spacecraft_count, contacts_per_day}` from `POST /templates/preview` with
  `{document, target}`, which writes nothing.

Writes follow U20. A rejection says nothing changed; an unreadable reply says the outcome is
unclear.

## ST · Settings, AU · Audit log, PA · Provider accounts (`ux/screens/SettingsAuditProviders.md`)

### ST1 · `GET /missions/:mission_id/settings` (and `GET /organizations/:org_id/settings`)

```json
{"data": {"sections": [{"key": "cadence.governance", "title": "Governance", "purpose": "…",
  "fields": [{…kind-schema field…, "value": …, "source": "mission|organization|default",
              "inherited_value": …|null}]}],
  "version": {"version": 4, "at": "…", "actor": {"name"}|null}|null,
  "permissions": ["settings.edit"]}}
```
- Sections come from the server registry. Sections with no fields are left out.
- `PUT /missions/:mission_id/settings/:section_key` with `{values: {path: value|null}, reason, expected_version}`:
  - `null` resets to inherited.
  - Returns `201 {version, state: "active"|"pending_approval"}`.
  - Errors: `invalid_params` (by path), `version_conflict`, `forbidden`.

### AU1 · `GET /organizations/:org_id/audit?from=&to=&actor_id=&mission_id=&kinds=&cursor=`

```json
{"data": {"events": [{"id", "at", "actor": {"kind": "user|service", "id", "name"},
  "kind": "config|commanding|access|alarms|contacts|data", "action": "Applied r6 · 2 changes",
  "target": {"kind", "id", "label"}|null, "mission": {"id", "name"}|null, "reason": "…"|null}],
  "sources": {"included": ["config", "commanding", "access"], "missing": ["contacts", "data"]},
  "next_cursor": null}}
```
`sources` lets the UI say which sources aren't in the log yet. Action sentences are made on the
server.

### PA1 · Provider accounts (org)

- `GET /organizations/:org_id/provider-accounts`:
  `{accounts: [{id, name, provider: {key, label}, status: "connected|expiring|auth_failed|not_checked",
  status_detail: "…"|null, expires_at|null, last_success_at|null, missions: [{id, name}],
  added_at, added_by: {name}|null}], adapters: [{key, label}], permissions}`
- `GET /provider-accounts/:id`: the account plus `schema: [field, with secret: boolean]`.
  Secret values come back as `{set: true, set_at}`, never the value.
- `POST /provider-accounts` with `{provider_key, name, credentials}`, and `PUT /provider-accounts/:id`
  with `{name, credentials}` (secrets are sent only when replaced).
- `POST /provider-accounts/:id/test`: `{ok, message}` from a real provider call.
- `DELETE /provider-accounts/:id`: `409 in_use` with `details.missions` while missions use it.
- `GET /provider-adapters/:key/schema` for the add form.
