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
| O5 | `PUT`/`DELETE /people/:user_id`, `POST /invitations/:id/resend`, `DELETE /invitations/:id` | **implemented** |
| O6 | `POST /service-identities`, `POST /service-identities/:id/rotate`, `DELETE /service-identities/:id` | **implemented** |
| O4 | command policies (as text) | with api-ops (commanding policy, D7) |
| G1, T1, T2 | `GET /missions/:mission_id/ground-stations`, `/transports`, `/routing-rules` | **implemented** |
| kind schema | `GET /missions/:mission_id/config/kinds/:kind/schema` | **implemented** |
| catalog APIDs | `GET /missions/:mission_id/catalog/revisions/:revision_id/apids` | **implemented** (L17) |

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
- `telemetry` (top level, on the list and on spacecraft detail): `"ok"`, or `"degraded"` when the
  durable telemetry history didn't answer in time (3 s). Then `last_received_at` comes from live
  values only and is `null` for spacecraft not heard since the last server restart: say "last
  received may be incomplete" rather than "never heard".
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
   "catalog_revision": {"id": "catalog_revision_…", "number": 4, "label": "rev 4"},
   "spacecraft_count": 500, "spacecraft_on_older_versions": 3, "override_count": 12,
   "last_change": {"version": 4, "revision": null, "at": "2026-11-12T10:00:00Z", "actor": null}}
]}}
```

- `spacecraft_count`: spacecraft pinned to any version of this profile. `spacecraft_on_older_versions`
  is the subset pinned below `version`.
- `catalog_revision`: the catalog the profile's latest version sets (`SpacecraftType.catalog_revision_id`),
  `{id, number, label}` with `label` "rev N" ("rN" is a change-set revision), or `null` when the
  profile sets none. `number`/`label` are `null` if the revision can't be found.
- `override_count`: per-spacecraft override entries (spacecraft × path) across the spacecraft
  pinned to the profile, as the detail's `override_count`. `last_change`: the detail's
  `profile.last_change` (`{version, revision: null, at, actor: null}`: when the latest version was
  made), or `null` if its history row is missing.

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
     "transport": {"id": "…", "name": "Svalbard X-band"}}
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
- `routing_rules[].transport` has no `version`: a route names its transport and the current
  version resolves at apply (DECISIONS, routing drop (a), 11-16; the field was removed).
- `routing_rules[].direction`: `inbound | outbound | bidirectional`. These are the model's values
  (inbound = downlink, outbound = uplink), not the `downlink | uplink | both` that was requested.
  `role`: `primary | candidate | contributing`. Archived rules appear with `active: false`, active
  ones first.
- `routing_rules[].origin` (ux U79): `legacy | profile | spacecraft` (a future value: decode as
  unrecognized, no tag). `route_id`: the extra route's id (the `spacecraft_route` entity) when
  `origin` is `spacecraft`, else `null`; an extra route's two legs are two rows with the same
  `route_id`. `station`: `{id, code, name}` (code and name `null` when the station is gone), or
  `null` when the rule has none. Edit and Remove key on `route_id`; Remove stages
  `{kind: "spacecraft_route", action: "delete", entity_id: route_id}`. Older (`legacy`) rows are
  removed through `legacy_routing_rule` (below).
- `GET …/spacecraft/:spacecraft_id/routes/:route_id` → `{id, document}`: the extra route as staged,
  for the editor (an empty transport stays empty, a name template stays a template). `404
  spacecraft_route_not_found` when it isn't an extra route of that spacecraft.
- `readiness.checks[].status`: `ready | blocker | caution | not_set_up`. `ready` is true when
  `identity`, `profile` and `routing` are not blockers (`telemetry` is informational), the same rule
  as the directory's `ready`.
- `configuration`: `null` in v1, for the same reason as the directory (DECISIONS #1 change sets).
- `commanding_enabled`, `telemetry_enabled` (top level, §11 L17): what the active configuration
  does now, `true | false`, or `null` when the mission has no active configuration for it. Show
  these as the switches' current values in the edit form.

Errors: `404 mission_not_found`, `404 spacecraft_not_found`.

## Spacecraft edits (§11 L17, L22): the `spacecraft` change-set kind

Staged through change sets (changes.md) with `kind: "spacecraft"`. The form comes from
`GET …/config/kinds/spacecraft/schema`: `display_name`, `scid` (0–1023), `spacecraft_type_id`
(enum of the mission's shared profiles, by name), `spacecraft_type_version` (section
`identity`), then `commanding_enabled` and `telemetry_enabled` (booleans, section `switches`, with
ux's U40 help).

- **Create**: `{kind: "spacecraft", action: "create", document: {display_name, scid?,
  spacecraft_type_id?, spacecraft_type_version?, commanding_enabled?, telemetry_enabled?}}`.
- **Update**: `{kind, action: "update", entity_id, changes: [{path, value}]}`. **Unchanged means
  absent**: send only the paths that change. An explicit `null` for a switch is `422
  invalid_params` with `details["ops.<i>.changes.<switch>"]` (create:
  `details["ops.<i>.document.<switch>"]`), on both preview and stage.
- **Profile without a version** means that profile's latest version: the server fills
  `spacecraft_type_version` before validating. A version without a profile stays `422` ("Choose a
  profile and its version together"). To keep the current pin, leave both out. Sending
  `spacecraft_type_id` alone re-pins to the latest even if it's the current profile.
- **An unchanged pin passes** even when that profile version is no longer active (the domain's
  `same_pin?`). The form shows the current value as `<name> (inactive)` from this detail read's
  `profile`.
- **Archive** is `action: "delete"` on the wire. The console says "Archive". It leaves the
  mission's lists, fleet and planning when applied; its id, SCID and history stay.

HOLDs on the preview's `compatibility` check (`items[]`: `{kind: "spacecraft", entity_id,
reason, blocking, sentence, details?}`; sentences are ux's U40):

| reason | blocking | when | details |
|---|---|---|---|
| `spacecraft_commands_waiting` | **yes** | archiving one with command requests still waiting to release | `{waiting_requests, booked_passes, earliest_pass_at}` |
| `spacecraft_passes_booked` | no (acknowledge) | archiving one with passes still booked to start later | same |
| `spacecraft_has_traffic` | no (acknowledge) | archiving one that has ever had passes booked or commands requested | none |
| `commanding_disabled_cancels_commands` | no | turning commanding off with commands waiting | `requests` |
| `commanding_command_in_flight` | **yes** | turning commanding off while one is being sent | `requests` |
| `telemetry_disabled` | no | turning telemetry off | none |
| `telemetry_packet_inputs_required` | **yes** | turning telemetry on without handled APIDs | none |
| `telemetry_app_not_installed` | **yes** | turning telemetry on for spacecraft without the telemetry app (ux U63; domain e587668da) | `{app_key, app_name}` (`app_name` null without a registry display name); ONE item for all such spacecraft: `entity_id` the first, `spacecraft_ids` all. The console titles it "Telemetry app not installed" and links "Open Setup › Apps" to `/setup/apps/<app_key>` |
| `scid_shared_in_organization` | no (acknowledge) | a spacecraft create, or an update changing its SCID, when another mission in the same organization has a non-archived spacecraft with that SCID and the two missions' non-archived providers share a provider account (ux U81 §1; never across organizations). One item per other mission the viewer can open, plus at most one folded item for the rest | `{scid, provider_accounts: [{id, name}], mission: {id, name} \| null, mission_count}`: all four keys always; `provider_accounts` ≥ 1, sorted by name, `name` nullable (the union on the folded item); `mission` null on the folded item; `mission_count` 1 when named, ≥ 1 when folded |

`earliest_pass_at` is ISO 8601 UTC or null. The sentences already carry the counts and the §4
short time. A blocking item can't be acknowledged away: submit answers `409 holds_blocking`,
and so does approve if one appeared after the submit; checks that can't run answer
`503 preview_failed` ([changes.md](changes.md) Errors, #262).
If an apply still meets one of the telemetry conditions (applied anyway, or a race after the
preview), it answers in words, never a generic failure (ux U63): `409 telemetry_app_not_installed`
or `409 telemetry_packet_inputs_required`, `details: {spacecraft_ids}`, `message` naming up to three
spacecraft in full, else "12 spacecraft" ("Not applied: the telemetry app isn't installed on
EARENDIL-312. Install the app in Setup › Apps first." / "Not applied: telemetry can't be turned on
for EARENDIL-312 until its packet inputs are set up.").

Defence in depth: a request whose spacecraft was archived anyway (queued between preview and
apply) is never sent. At release it's canceled with `end_reason: spacecraft_archived`
(commanding.md) and its lane moves on.

## The model approval gate (U65, DECISIONS #92 a)

A catalog import makes a mission-model revision; a generation can't introduce it until an
organization administrator approves it against a comparison report. The console names a model
by its catalog revision ("catalog rev 4"); the model revision id is Technical details. Base
`/api/console/v1/missions/:mission_id/mission-model-revisions`.

- `GET ?status=candidate|approved|rejected|retired` (default `candidate`) → `{revisions: [{id,
  status, imported_at, imported_by {id, name} | null, catalog_revision {id, number, label,
  database_id} | null, latest_comparison_status: passed|failed|null}]}`, newest first.
- `GET /:id` → `{id, status, imported_at, imported_by, catalog_revision, decision {kind:
  approved|rejected, by {id, name}, at, report_id | null, reason | null, retroactive} | null,
  viewer_can_decide, viewer_is_importer, cannot_decide_because: not_admin | not_approvable |
  self_approval | authors_unknown | plans_not_ready | null, cannot_decide_details: {via_service:
  {id, name} | null} | {service: {id, name} | null} | null, cannot_approve_because: not_in_catalog | null,
  plans_ready, comparison: <cmp> | null}`. `imported_by`
  null reads "Importer not recorded". `imported_by` names a person only while they hold an
  active membership in the mission's organization, never by email (#366, #146's rule). Anyone
  else is `{id: null, name: null}`: recorded, but not named, and their id isn't sent. `cannot_approve_because` (11-17, ux U88) is
  `not_in_catalog` when no catalog revision names the model revision (a second run of a file
  makes one): Approve is refused (`409 mission_model_revision_not_in_catalog`), Reject stays;
  `cannot_decide_because` wins when both are set. `self_approval` and `authors_unknown` (#280) come
  from the same check the approve path makes; `cannot_decide_details` carries the approve refusal's
  details for them (null otherwise). Importers (11-17) are the people recorded on the catalog
  revisions naming the model revision plus the people who ran a completed import run that made
  it (every run makes its own model revision, so a reimport's has only its runner);
  `imported_by` is the first. A service or Cadence's own seed never counts as one.
- **On `GET /:id` only** (#195, ux U102; additive, read as optional), `catalog_revision` also has:
  `import_run_id` (the run that made that catalog revision; always present and never null when
  `catalog_revision` is: both come from one row), `breaking: integer | null` and
  `breaking_base: {catalog_revision_id, revision} | null`.
  - The base is the revision before it in the same catalog database: the highest `revision_number`
    below its own. It's the same function as C3's `base_revision`, so `breaking` always equals the
    `diff.summary.breaking` that the import page showed for `import_run_id`. Catalog revisions are
    always numbered (`revision` is never null), immutable and never deleted, so a revision's base
    and count don't change when later revisions are imported. Only a release that changes what
    counts as breaking (C3's rules below) can change the count. It's computed per read, not stored.
  - `breaking_base` null: the database's first revision, with nothing earlier to compare
    (`breaking` null). `breaking_base` set with `breaking` null: the diff couldn't be read, as C3's
    `diff` below (no model, a model revision not stored for this mission, or a failed query; #367).
    Both set: the count. `0` means nothing breaks; an unknown count is never sent as `0`.
  - The list (`GET ?status=`) doesn't carry these fields (one diff per row would read every model).
- `POST /:id/comparison {}` → `201 <cmp>`, synchronous, against the mission's active binding set
  and the revision this one replaces (the previous catalog revision's model in the same
  database, else none). Reports dedupe on content.
- `<cmp>` = `{report_id, passed, against {revision_id, catalog_revision_number} | null, replay
  {status: not_required|not_run|passed|failed, reason: qualification_corpus_required | null,
  cases, failed_cases [{name, reason}]}, risk: low|medium|high, totals {added, removed, changed},
  sections [{kind, added, removed, changed}], affected_kinds [kind], changed_targets [target],
  generated_at}`. `kind` and `target` are known vocabularies (read as known text). `not_run` is
  "Replay: not run…" (a caution, never shown as passed); `not_required` is "Replay: not needed for
  a low-risk change."
- `POST /:id/approve {comparison_report_id}` and `POST /:id/reject {reason}` (reason required;
  only a candidate) → `200` the read. Refusals, worded per ux U65: `403 forbidden` (not an org
  admin), `403 human_mission_model_approver_required`, `403 mission_model_self_approval_forbidden`
  (the importer, under 'independent'; `details: {via_service: {id, name} | null}`, #280: a service
  identity you're accountable for imported it), `403 mission_model_approver_authors_unknown`
  (`details: {service: {id, name} | null}`, #280: a service identity with nobody recorded as
  accountable imported it, so nobody can approve it yet), `409 mission_model_comparison_not_passed`, `409
  mission_model_comparison_mismatch` (another revision's report: run it again), `409
  mission_model_runtime_plans_not_ready`, `409 mission_model_revision_not_approvable`, `404
  mission_model_revision_not_found` / `mission_model_comparison_report_not_found`, `422
  mission_model_decision_reason_required` ("Give a reason first."), `422
  mission_model_decision_reason_too_long` (over 2,000 bytes), `422 invalid_params`. Approving an
  already approved revision returns it unchanged (the first approver stays).
- The catalog read's revision rows (`GET /catalog?database_id=`) carry `model {revision_id,
  status} | null` for the row tag (NEEDS APPROVAL / APPROVED / REJECTED).
- Preview HOLD `mission_model_not_approved` (blocking; compatibility check): `details
  {catalog_revision_id, catalog_revision_number, catalog_database_id, mission_model_revision_id}`.
- Apply refusals: `409 mission_model_revision_not_approved {mission_model_revision_ids,
  catalog_revision_numbers}` ("Not applied: catalog rev 4 isn't approved yet.") and `409
  mission_model_comparison_failed {mission_model_revision_id, comparison_report_id,
  catalog_revision_number}` ("Not applied: catalog rev 4's comparison didn't pass.").
- Audit (kind `config`, target `{kind: mission_model_revision, id, label: "catalog rev 4"}`):
  "Approved catalog rev 4 (comparison passed against rev 3; replay not run)" / "Rejected catalog
  rev 4" with the reason. An approval of a revision some spacecraft already run (grandfathered;
  domain 71ce7d850) is retroactive: `decision.retroactive: true`, and the audit line reads
  "(retroactive; comparison passed against rev 3; replay not run)".

## Spacecraft configuration workspace ((B), owner: api)

A spacecraft's configuration in the console (director 11-17; ux U94): the host's workspace, over
the same read model, Drafts and `Control.SpacecraftConfiguration`. Base:
`/api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id/configuration/workspace`.
Approve and reject stay on L10 (activation requests of kind `spacecraft_configuration`).

**DECISIONS #109.** Change sets are the only writer of a spacecraft's Telemetry and Commanding
switches. The editable `document` never carries them; they're read-only in `switches`.

### `GET …/workspace?section=overview|catalog|communications|changes`

`{data: snapshot}`. `section` defaults to `overview`; anything else is `422 invalid_params
{section}`.

- `spacecraft_id`, `name`, `scid` (nullable), `section`.
- `token`: opaque; send it back on save and submit.
- `saved_version`: per craft (1, 2…); null when never saved (the document is derived).
- `document`: `{catalog_revision_id|null, telemetry_source_endpoint_id|null, handled_apids: [int],
  protocol: {downlink, uplink, frame_size, secondary_header_length, insert_zone_length,
  ocf_length, truncated_primary_header} | null}`. No switch keys.
- `external_changes`: bool.
- `switches`: `{telemetry_enabled: SWITCH, commanding_enabled: SWITCH}`, where SWITCH is `{value:
  bool, set: bool, revision: int|null}`. `set` false means no change set has set it (the value
  reads false). `revision` is the change-set revision that last set it; it's null until it's
  stored (null reads "set through Setup, Changes").
- `active`: `{version, generation, document}` (the same document shape), or null when nothing runs
  for the craft.
- `review`: `{id, state: approval_pending|approved|rejected|withdrawn|superseded|stale|active,
  requester_id, version|null}` or null. From the dev reset (DECISIONS #112) it also carries the
  decision record's `subject`, `separated_from`, `admin_mode` and `applied_by`. Read them as
  optional until then.
- `approval`: `{requirement: direct|independent, policy_token, source:
  organization|inherited|overridden|enforced, can_request, can_review}`. Send `policy_token` back
  on submit.
- `catalogs` (≤100): `{id, name, label, number, declarations, packets, commands}`, where `number`
  is the catalog revision number (U65's "catalog rev 14").
- `fleet` (≤100, this craft first): `{id, name, scid, active_catalog_id, has_changes}`, plus
  `fleet_total`.
- `sources`: `{id, name}` (this craft's packet sources). `presets`: `{id, version, name,
  protocol}` (profiles' framing).

### `PUT …/workspace/draft` `{token, document}`

Saves a draft; the active configuration stays in use. Answers the fresh snapshot (a new token).
`?section=` works as on GET.

- A switch key anywhere in `document`: `422 invalid_params`, message "Not saved: Telemetry and
  Commanding are changed with a change set, not in a spacecraft's configuration.", with
  `details["document.telemetry_enabled"]` / `details["document.commanding_enabled"]`: "Change this
  with a change set, from the spacecraft's Operation panel." Nothing is saved. (Drafts.save also
  ignores switch input, as the domain's backstop.)
- A malformed document: `422 invalid_params {document}`.

### `POST …/workspace/submit` `{token, policy_token, intent: review|activate}`

- `review`: `{state: approval_pending, request_id}`. It lists on L10.
- `activate` (a direct mission): `{state: active, execution_id}`, or `{state: needs_review}` when it
  was approved but the application couldn't be confirmed.
- A bad `intent`, or a missing token: `422 invalid_params`.

### `GET …/workspace/catalogs/:catalog_revision_id/packets`

`{data: {catalog_id, packets: [{apid, name, definitions}]}}` (≤2048). An unknown catalog
revision: `404 catalog_revision_not_found`.

### Errors (the console envelope; messages are ux's U94 words on these routes only)

The messages name the spacecraft and the catalog revision ("catalog rev 14"), never an id ("this
spacecraft" / "that catalog revision" when it can't be known). The host's page keeps its own copy.
Someone outside the mission's organization gets `404 mission_not_found` on every route (the
console's mission scope), so the mission's existence doesn't leak.

| Code | Status | When |
|---|---|---|
| `spacecraft_configuration_changed` | 409 | The token is stale (save) |
| `spacecraft_configuration_review_unavailable` | 409 | Submit before a save, or with external changes |
| `spacecraft_configuration_review_stale` | 409 | The active fleet configuration moved |
| `activation_policy_changed` | 409 | The policy changed since the snapshot |
| `spacecraft_switch_set_by_change_set` | 409 | (submit) A change set turned a switch on or off after the draft was saved; save again |
| `spacecraft_catalog_set_by_profile` | 409 | The catalog is the profile's (a change set sets it) |
| `spacecraft_catalog_required` | 422 | Submit with no catalog |
| `spacecraft_packet_inputs_required` | 422 | Telemetry on without a source and packets |
| `spacecraft_catalog_unavailable` | 422 | The catalog revision isn't this mission's |
| `spacecraft_packet_input_unavailable` | 422 | The source isn't this craft's |
| `spacecraft_source_limit_exceeded` | 422 | Too many sources |
| `mission_model_revision_not_approved` | 409 | The catalog's model isn't approved (U65). `details {mission_model_revision_ids, catalog_revision_numbers}`: one number per id, in the same order; an entry is `null` when that catalog revision has no number, so read it as "a catalog revision" (U65, #272) |
| `activation_self_approval_forbidden` | 403 | (L10 approve) A different person must review |
| `forbidden` | 403 | No operate access |
| `spacecraft_not_found` | 404 | Also when the craft is removed between the access check and the read (#272) |

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
  "recent_changes": [{"at": "…", "kind": "change_set", "version_label": "r3", "summary": "Rename",
                      "actor": {"name": "Alice"}}]
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
- `recent_changes` (R2): the mission's last 5 configuration revisions, newest first:
  `[{at, kind: "change_set" | "rollback" | "legacy_activation", version_label: "r3", summary,
  actor: {name} | null}]`. `[]` when nothing has been applied yet (show the panel empty, or omit
  it). `version_label` is the revision number; open `GET /config/revisions/:n` for the detail.
  It's `null` only if the revisions can't be read.

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
  "versions": [{"version": 4, "created_at": "2026-10-19T02:29:00Z", "actor": null,
                "spacecraft_count": 497}]
}}
```

- Fields are exactly the model-backed ones from profile-routing §3: framing (TM/TC/packet
  protocol, frame length, secondary header, insert zone, OCF, FECF, truncated primary header) and catalog.
  `versions[].spacecraft_count` is how many spacecraft pin that version ("12 spacecraft on v5"). The
  field diffs per revision come from `GET /config/revisions?entity_kind=spacecraft_profile&entity_id=`.
  `type` is `integer | boolean | enum | string | reference`; `runtime_impact` is
  `generation | routes | none`. Enum options come as `[{value, label}]`.
- `rules` and `overrides` come from domain's profile routing (DECISIONS #3, shapes in domain.md
  "P2 additions"). `routing_model` is `"profile"` when the profile has rules, else
  `"per_spacecraft"` (legacy per-spacecraft rules not yet lifted). `override_count` and each
  field's `overridden_by` count the spacecraft overriding that path.
- `extra_routes` (ux U79), beside `overrides`: one entry per extra route a spacecraft on this
  profile has of its own, `[{spacecraft: {id, name}, route_id, name, station: {id, code, name} |
  null, legs: [{direction: "downlink" | "uplink", role}]}]`, sorted by spacecraft name then route
  name. `legs` use the profile rules' words, not the detail's inbound/outbound.
- The catalog field's `enum` lists the mission's catalog revisions, newest first, as `[{value:
  <catalog revision id>, label: "r3 · demo_spacecraft.yaml"}]` (render a select), or `null` when
  the mission has none.
- `catalog_revision` is `{id, number, label: "rev N"}` (or `null`), as the profile list sends it
  (#246). `number` and `label` are `null` when the profile's catalog revision id names none of the
  mission's catalog revisions (the id has no foreign key: another mission's, or one left over after
  a reset); read it as an unnumbered catalog revision. The catalog field's `value` is the profile's
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
- `revisions[].declaration_count` comes from the producing import run. `current_revision`
  also has `command_count` and `telemetry_count` (commands and telemetry parameters in its
  declarations); they're `null` only when the revision's model can't be read. Revisions in the
  list carry `null` for both (counting every revision would read every model).
- `revisions[].spacecraft_count`: spacecraft whose latest saved configuration references the
  revision.
- `revisions[].artifact.size_bytes` is `null` in the index (sizes would mean loading every file).
  C3 has the real size. `format_label` is the importer's display name.
- `revisions[].actor`: the importer of record, `{kind, name} | null`, by the same rule as `requested_by` below (#366; it was `{name}` from the stored name or email). `null` when none was recorded.
- `import_runs[].status`: `running | succeeded | failed`. There is no separate `pending` state: a
  queued import is `running`. `file_name` is known for runs that produced a revision, otherwise
  `null`.
- `import_runs[].requested_by` (#146, ux U103; additive, read as optional): who started the run,
  `{kind: user | service | system, name: string | null} | null`. Also on C3's run detail and the
  source-file page's runs. `null` when the run recorded no actor. Two batched name queries per
  table, whatever its length. The name follows mms-security's rule (11-19); the console's words
  decide what shows:
  - `user`: the person's current display name, only while they hold an active membership in the
    mission's organization, checked at read time. A person from another organization (a platform
    admin acting as support), someone who has since left, or a member without a display name reads
    `name: null`, and the kind stays `user`: the act is never shown as Cadence's. There's no
    fallback to email or id; neither is ever sent. The name stored on the run at import isn't used.
  - `service`: the service identity's display name, only when it belongs to the mission's
    organization; otherwise `null`.
  - `system`: Cadence itself (a seed or a task), with the stored system name, which is never a
    person.

## `GET /api/console/v1/missions/:mission_id/catalog/imports/:import_run_id` (C3)

The shape is setup-shapes.md §C3, plus `declaration_count`.

- `file.size_bytes` is the uploaded artifact's byte size.
- `diagnostics[]`: `{severity: error|warning|info, code, message, path}`, where `path` is a
  " / "-joined XTCE path or `null`. A run can succeed with error diagnostics (unsupported items
  are skipped).
- `base_revision`: the revision before this run's revision in the same database (the highest
  `revision_number` below its own), or `null` (first revision, or no revision produced). It's the
  same base as the revision read's `breaking_base` (the model approval gate above).
- `requested_by`: as the index's run row (C1 above).
- `diff` (DECISIONS #9 v1, from the two revisions alone): `null` when there's no base or either
  revision can't be read: it has no model, its model revision isn't stored for this mission, or its
  declarations can't be queried (#367: a missing model is never read as an empty one, which would
  show every item added and 0 breaking). Otherwise `{summary: {commands: {before, after, added, changed,
  removed}, telemetry: {…}, unchanged, total_before, breaking}, changes: [{op, kind, name, change,
  breaking}], truncated}`.
  - `total_before` counts the base revision's commands plus telemetry parameters; `unchanged` is
    how many of those didn't change. `other` declarations aren't in either count. They're not
    `declaration_count`, which is the importer's figure for this run (what it read from the file).
  - Items are what operators know: a **command** (with its arguments, argument types, encoding
    and verifiers) or a **telemetry** parameter (with its type and calibrator). Declarations no
    command or parameter references or names (containers, units, monitoring policies) are
    `kind: "other"`. `name` is the qualified name (`/commands/SET_MODE`).
  - `change` describes the first change, for example `arguments/duration/type: size_in_bits 8 →
    16`, `verifiers/Accepted on board: added (+1 more)` or `units degC → V`. It's `null` for added
    and removed items.
  - **Breaking**: a command or parameter removed; a command whose argument, argument type or
    encoding changed; a parameter whose type changed. Additions, descriptions, verifiers,
    calibrators and units aren't breaking. `changes` lists breaking first, at most 500
    (`truncated: true` beyond that).
- Errors: `404 import_run_not_found`.
- Live: refetch on `invalidate` with `catalog`.

## `GET /api/console/v1/missions/:mission_id/catalog/revisions/:revision_id/rollout` (C3 "Roll out to")

What staging this catalog revision on each profile would move, so the options can show
server-computed effect counts.

```json
{"data": {
  "revision": {"id": "catalog_revision_…", "number": 4, "label": "rev 4"},
  "profiles": [{
    "id": "profile-…", "name": "Earendil Block 1",
    "current_revision": {"id": "…", "number": 3, "label": "rev 3"},
    "spacecraft_count": 500, "on_current_version": 1, "on_older_versions": 499,
    "override_pinned": 0, "already_on_revision": 1, "moves_default": 0, "moves_all": 499
  }],
  "unprofiled_count": 0
}}
```

- Spacecraft: every non-archived spacecraft pinned to the profile, at any version. Each counts in
  exactly one of three buckets, checked in this order:
  1. `override_pinned`: its override sets its own `catalog_revision_id`, so it keeps it either way.
  2. `already_on_revision`: its configured catalog (latest configuration) is this revision.
  3. Movable.
  `override_pinned + already_on_revision + moves_all = spacecraft_count`.
- `moves_default`: movable spacecraft on the profile's current version. A profile op with the
  default rollout moves only those.
- `moves_all`: movable spacecraft at any version. A profile op with `options: {"rollout":
  "all_versions"}` (domain, 2ef4ca79) re-pins every spacecraft on the profile. Override-pinned ones
  keep their catalog, so this is what it moves catalog-wise.
- `on_current_version + on_older_versions = spacecraft_count`.
- `current_revision`: the catalog the profile sets today (`null` if none). `unprofiled_count`:
  spacecraft with no profile; a profile op never moves them.
- Profiles: active ones, sorted by name. Spacecraft pinned to a deleted profile aren't counted.
- Errors: `404 catalog_revision_not_found`.
- Live: refetch on `invalidate` with `catalog` or `spacecraft`.

## `GET /api/console/v1/missions/:mission_id/catalog/revisions/:revision_id/apids` (§11 L17)

The APIDs the revision defines, with their packets: the choices for `handled_apids`.

```json
{"data": {"revision_id": "catalog_revision_…", "available": true,
  "apids": [{"apid": 100, "packets": ["HK_FAST", "HK_SLOW"]}]}}
```

- Sorted by APID, packets by name. Read from the revision's executable telemetry plan, so it's
  exactly what decode can handle.
- `available: false` (with `apids: []`) when the revision has no telemetry plan yet. Say "not
  compiled yet", not "no APIDs".
- Errors: `404 catalog_revision_not_found`.

## Source files (§11 L18: K1-K3)

Under `/api/console/v1/missions/:mission_id/catalog/artifacts/:artifact_id`.

- **K1** `GET` → `{artifact: {id, file_name, format_label, format_version, media_type, size_bytes,
  sha256, uploaded_at, uploaded_by {kind, name} | null, database {id, name}, download_url}, revisions:
  [{id, number, label, imported_at}] (made from this file), import_runs: [<the index's run row>]
  (newest first, 50), permissions: ["catalog.import"] | []}`. `404 artifact_not_found`. `uploaded_by` follows the same rule as `requested_by` (C1, #366).
- **K2** `POST /reimport` (empty body) → `202 {import_run: {id}}`: the importer runs again on the
  stored file and makes a new candidate revision. `409 import_running {import_run_id}` while a run
  on this file is still going, `403 forbidden`, `404 artifact_not_found`. todo(authz): any mission
  operator, like an upload.
- **K3** `GET /download` → the stored bytes as an attachment (`content-disposition` with the file
  name). It's a plain link: the session cookie is enough. `404 artifact_not_found`.
- `download_url` also appears on the catalog index's `revision.artifact` and on the import run's
  `file.artifact {id, download_url}` (null when the run's file is gone).

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

### Mission create (§11 L4; organization admins and platform admins)

Under `/organizations/:organization_id`, in the organization the path names:

- **M1** `GET /missions/slug?slug=` → `{slug, available, suggestion | null}`. A slug is unique within
  its organization; when it's taken, `suggestion` is a free variant (`earendil-2`).
- **M2** `POST /missions {name, slug}` → `201 {mission: {id, name, slug}}`. `name` 1–120
  characters; `slug` lowercase letters, numbers and hyphens, starting with a letter or digit, at
  most 64. Errors: `422 invalid_params` with **flat** field details, as AD1's (`{name: msg}`,
  `{slug: msg, suggestion}` for a clash, including one that loses a race); `403 forbidden` for
  anyone else (Policy `:create_missions`, todo(authz)). The new mission joins the session's
  missions on the next bootstrap. Creation isn't in the organization Audit yet (no store for it).

### Provider accounts (PA1, organization admins)

- `GET /provider-accounts` → `{accounts: [{id, name, provider: {key, label}, event_ingestion_mode, status: "connected" |
  "credential_revoked" | "not_checked", status_detail, expires_at: null, last_success_at, missions: [{id,
  name}], added_at, added_by: {name} | null}], adapters: [{key, label}], permissions:
  ["provider_accounts.manage"]}`.
  - `missions` lists the missions whose ground-network providers use the account.
  - `status` is `credential_revoked` when the account's credential is revoked (L13; older
    servers sent `auth_failed`), and `not_checked` before a first successful test.
  - There's no `expiring`: credentials carry no expiry yet.
- `GET /provider-accounts/:id/versions` → `{id, name, current_version, versions: [{version,
  created_at, actor: {kind: "user" | "system", id, name} | null, changes: [{field, label, before,
  after}]}]}`, newest first. `changes` compares with the version before (`[]` for version 1).
  Fields: endpoint, region, environment, client key, credential **reference** (never a secret),
  event ingestion and its settings, request policy, guardrails, provider settings. A rename
  changes the account's name without a new version, so it isn't listed. Errors: `404
  provider_account_not_found`, `403 forbidden`.
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
  `environment_ref`, `region_ref`, `event_ingestion_mode` (enum `polling` | `disabled`, default
  `polling`), `credential.backend`, `credential.key`. There's no secret-value field. `404
  provider_adapter_not_found`.
- `POST /provider-accounts` `{provider_key, name, settings: {base_url, environment_ref, region_ref?,
  event_ingestion_mode?}, credential: {backend, key}}` → `201 {id, version: 1}`. It registers the
  reference without calling the provider; use Test afterwards.
- `settings.event_ingestion_mode` (qa L12/L13, 11-16): whether Cadence fetches the provider's
  contact events. `polling` | `webhook` | `hybrid` | `disabled`; omitted on create, `polling`. An
  account that is `disabled` (or `webhook`) is never polled. The console offers `polling` and
  `disabled` only (the schema's enum): webhook and hybrid need the provider set up to post to
  Cadence, which the console doesn't configure. Anything else: `422
  details["settings.event_ingestion_mode"]`, before anything is registered. The account row in
  `GET /provider-accounts` carries `event_ingestion_mode`.
- `PUT /provider-accounts/:id` `{name?, settings?, credential?}` → `201 {id, version}`. Settings and
  credential make a new account version (a sent `credential` registers a new reference). Sent
  settings **merge** onto the current version: `{settings: {event_ingestion_mode: "disabled"}}`
  alone changes only the mode. A rename alone writes no version (`version: null`); it's
  presentation, and it's audited. A blank name or one over 120 bytes: `422 details.name`.
- `DELETE /provider-accounts/:id` (optional `reason`) → `{id, state: "archived"}`. The account
  drops out of the list. While missions use it: `409 in_use` with `details.missions: [{id,
  name}]`. `409 already_retired`.
- Writes need `provider_accounts.manage` (organization admin). Errors: `422 invalid_params`
  (`provider_key`, `credential`, `settings`), `403 forbidden`.

### Provider-account grants and credential (L13, organization admins; owner: api-ops)

Under `/organizations/:organization_id/provider-accounts/:id`. Every route needs
`provider_accounts.manage`, else `403 forbidden`; an unknown account is `404
provider_account_not_found`. A stale view answers which thing changed, with its current version in
`details.version`, so the console can reload just that.

- `GET /` (PA2) → `{account: <PA1 row> + {version, credential: {ref, version: int | null, status:
  "active" | "revoked" | "missing"}, guardrails: {allowed_services: [..] | null, allowed_stations:
  [..] | null}}, grants: [<grant>], permissions}`.
  - `credential.status` is `missing` (and `version` `null`, only then) when no credential is
    registered under the account's reference (older accounts). There's nothing to revoke.
  - `credential.ref` is masked (`"…"` and the last 6 characters). The reference isn't a secret,
    but the console only needs to recognise it.
  - `grants` is every grant of the account (active and revoked; the latest version of each),
    newest first.
  - `<grant>`: `{id, version, mission: {id, name}, state: "active" | "revoked", allowed_services:
    [..] | null, allowed_stations: [..] | null, max_quota: int | null, reason: string | null,
    granted_by: {id, name} | null, granted_at, revoked_by: {id, name} | null, revoked_at | null,
    revoke_reason | null}`. A `null` restriction means the account's own guardrail applies.
    `mission.name` is always a string: a mission with no name on record reads as its id.
- `POST /grants` `{mission_id, allowed_services?, allowed_stations?, max_quota?, reason?,
  expected_account_version}` → `201 {grant}`.
  - The server rebuilds the credential reference and its version from the account version.
  - `409 account_changed {version}`, `409 account_archived`.
  - `422 invalid_params` with the field:
    - a restriction that widens the account's guardrails: `allowed_services`,
      `allowed_stations` or `max_quota`;
    - a malformed value;
    - `mission_id` (missing, or not this organization's);
    - `expected_account_version` missing.
- `POST /grants/:grant_id/revoke` `{reason, expected_grant_version}` → `200 {grant,
  flagged_reservations}`. `flagged_reservations` is how many open bookings that carry the grant
  now wait for an operator's review.
  - `422 invalid_params {reason: "Say why."}`; `422 invalid_params {expected_grant_version}`
    when it's missing.
  - `409 grant_changed {version}`, `409 grant_already_revoked`.
  - `404 account_grant_not_found` (also for another account's grant).
- `POST /credential/revoke` `{reason, expected_credential_version}` → `200 {account: <PA1 row>}`.
  - The row's `status` is `credential_revoked`.
  - The reason is recorded in the credential's audit entry.
  - Every mission provider on the account fails at credential resolve until the account points
    at a new reference.
  - `422 invalid_params {reason}`, or `{expected_credential_version}` when it's missing; `409
    credential_changed {version}`; `409 credential_already_revoked`.

### `GET /audit` (AU1, organization admins)

Query: `from`, `to` (ISO; default the last 7 days), `actor_id`, `mission_id`, `kinds` (comma
list of `config, commanding, access, alarms, contacts, data, provider_accounts, account,
platform`), `limit` (default 100; clamped to 1–200), and `cursor` (from `next_cursor`).
`mission_id` narrows the per-mission sources; organization-level events (organization settings,
access, provider accounts, account, platform) are always included.

`{events: [{id, at, actor: {kind, id, name} | null, kind, action, target: {kind, id, label} |
null, mission: {id, name} | null, reason}], sources: {included, missing}, next_cursor}`, newest
first.

- There's no single audit store yet, so this merges each domain's own records:
  - `config`: applied configuration revisions ("Applied r6 · 2 changes", "Rolled back to r4") and
    settings changes ("Changed Governance settings");
  - `commanding` (director 11-15, ux U59): a command group is ONE entry per decision, never one
    per member, target `{kind: "command_group", id: <command_group_id>, label: "SET_MODE and 2
    more for 12 spacecraft"}` (the console opens it at `ops.commands.request`, whose param is
    the group id): "Submitted <label>" (" · needs a second GO", " · 3 spacecraft have their own
    values"), or "Resent <label> (sent back at 13:02Z: “<original title>”)"; "Gave GO on
    <label>" (", excluding 2 spacecraft"), "Gave NO-GO on <label>", "Sent back <label>" (the
    note is the `reason`); "Aborted <label>: 40 uplinks canceled, 8 already sent" (the abort
    reason); "Released 2 uplinks of <label> into the SVL 14:05Z pass" (or "into a contact that
    wasn't a booked pass (SVL 14:05Z)", plus " · then stopped, 1 uplink still queued");
    "Acknowledged the Contact HOLD on <label>" (the note); "Canceled SET_MODE on EARENDIL-004 from
    <label>" (an operator canceling one member; the reason). Cadence's own cancels (expiry,
    fail-closed, a catalog change) fold to one entry per group and reason, actor `{kind:
    "service", id, name: "Cadence"}`, `reason: null`: "Canceled 12 uplinks of <label>: they
    expired before release" / ": what they were approved against changed" / ": the catalog
    changed" / ": EARENDIL-004 was archived" ("3 of its spacecraft were archived") / ":
    commanding was turned off for EARENDIL-004" ("for 3 of its spacecraft"), else
    "Canceled 12 uplinks of <label>." Notes and members' outcomes (failed, completed) aren't
    audit entries. A standalone request (no group) keeps "Requested X" and "Approved X" /
    "Rejected X", target `{kind: "command_request", …}`, and adds "Canceled X" (an operator, with
    the reason) or "Canceled X on <spacecraft>: it expired before release" (Cadence). The window
    is applied in SQL and each part is capped at 200 per mission, so a 1,000-target group is a
    handful of rows;
  - `access`: invitations sent, accepted (by the new member) and revoked; members joining
    without an invitation; role changes and removals (by the admin who made them). Each carries
    its actor, so `actor_id` finds a person's own access events;
  - `alarms`: people acknowledging, assigning, handing off and annotating episodes (the note is
    the `reason`);
  - `contacts`: contact plan approval decisions ("Approved contact plan v1"; the 100 newest plans
    per mission), and planning policy changes ("Proposed planning policy v4" with the saver's
    `reason`, "Approved planning policy v4" / "Rejected …" with the decision's), target `{kind:
    "planning_policy", id, label: "Planning policy"}`;
  - `data`: data-source definition changes.
  - `provider_accounts`: account added, settings changed (a new version), renamed, retired;
    credential reference set / rotated / revoked; mission access granted / removed. Named by the
    account's current name (a rename says both names); the credential only as its reference.
  - `config` also carries dashboards created, archived and restored (dashboards.md §D3), target
    `{kind: "dashboard", id, label}`.
  - `account`: members changing their own password and signing out sessions (session.md
    §Account, Audit). The actor is the member; `target` is `null`.
- `sources.missing` is empty now. Keep handling it generically.
- Actions are server-made sentences.
- Settings entries: `{kind: "config", action: "Changed <Section> settings", target: {kind:
  "settings", id: <section key>, label}}`, with " (organization default)" and `mission: null` for
  the organization's own.
- An approval setting change (#233; ux U96) says which way it went, and adds `change: {before,
  after}` with raw values: on a mission `{approval_requirement, override: bool}` (the effective
  value, and whether the mission set its own); for the organization `{approval_requirement,
  allow_override}`. Sentences: "Loosened approval on EARENDIL: Needs a second person's approval →
  Applies without approval" / "Tightened approval on EARENDIL: …" (plus " (the organization's
  setting)" when the mission hands back to it); only the override changed: "EARENDIL now uses
  the organization's approval setting (…); what applies doesn't change." / "EARENDIL now sets its
  own approval setting (…); what applies doesn't change."; organization: "Loosened approval
  (organization default): …" / "Tightened …", and "Missions may now set their own approval
  setting." / "Missions can no longer set their own approval setting." (both in one save: two
  sentences, the value first). A change saved before #233 has no `change` and keeps "Changed
  Governance settings". Settings history carries only the actor's name, so `actor` is `{kind:
  "user", id: null, name}` and `actor_id` doesn't find a person's settings changes. The log holds
  each section's 10 most recent changes per scope, for the Governance, Commanding, Configuration
  and Pass review sections.
- The per-field settings migration shows as one entry per mission it rewrote: `actor: null`,
  `target: null`, action "Settings now follow the organization except the fields set for this
  mission." (plus " Approval settings stay set for this mission, even where they match the
  organization." when it kept approval fields equal to the organization's).
- `platform` events (platform admin actions on the organization) also carry `organization`.
- `403 forbidden` for non-admins; `422 invalid_params` (`kinds`, `from`/`to`, `limit`, `cursor`).

### `GET /people` (O1)

```json
{"data": {
  "members": [{"user_id": "user_…", "display_name": "Mira K.", "email": "mira@…",
               "role": "member", "capabilities": [],
               "joined_at": "2026-10-19T02:29:00Z"}],
  "invitations": [{"id": "…", "email": "ana@…", "role": "member", "invited_by": {"name": "Ada Admin"},
                   "sent_at": "…", "expires_at": "…", "status": "pending", "decided_at": null}],
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
- `invitations` holds the pending, unexpired ones **and** those decided or lapsed in the last 30
  days, so the inviter sees what happened: `status` is `pending | accepted | declined | revoked |
  expired` (a pending one past `expires_at` reads `expired`; a resend revokes the old one).
  `decided_at` is when it left pending (`null` while pending). Count only `pending` for the header.
  Members are sorted by name; invitations newest first. There is no presence or last-seen yet.

### `POST /invitations` (O2)

Body `{email, role: "member" | "organization_admin"}` (default `member`). Requires
`org.invite` (organization admin). It sends the invitation email when mail is configured.

- `201` returns the invitation (same shape as above) plus `delivery: "submitted" | "unavailable"`.
- Errors: `422 invalid_params` (`details.email` / `details.role`), `409 already_member`,
  `409 already_invited`, `403 forbidden`.

### People administration (O5)

All require `org.manage_members` (organization admin). An organization always keeps at least
one active admin.

- `PUT /people/:user_id {role: "member" | "organization_admin"}` → `200 {user_id, role, state:
  "active"}`. Errors: `422 invalid_params` (`details.role`), `404 member_not_found`, `409
  last_admin` (demoting the last admin), `403 forbidden`.
- `DELETE /people/:user_id` → `200 {user_id, role, state: "revoked"}`. The membership is revoked,
  not deleted (history keeps pointing at it); the person loses access to the organization on
  their next request (the organization reads as `404 organization_not_found` to them). Inviting
  them again restores the membership when they accept. Errors: `404 member_not_found`, `409
  last_admin`, `403 forbidden`.
- `POST /invitations/:invitation_id/resend` → `201` a fresh invitation (same shape as O2, new
  `id`): same email and role, a new link (the old one stops working), delivered again. Errors:
  `404 invitation_not_found` (not pending: accepted, revoked or expired), `403 forbidden`.
- `DELETE /invitations/:invitation_id` → `204`; the link stops working. Errors: `404
  invitation_not_found`, `403 forbidden`.
- **Per-person activity**: the organization audit read filtered to them, `GET /audit?actor_id=<user_id>`
  (AU1 below).

### Service identity writes (O6)

All require an organization admin (the same access as the O3 read; offer them where O3 succeeds). The API token appears in the
response **once** (create and rotate); Cadence stores only its digest and can't show it again.
Responses carry `cache-control: no-store`.

- `POST /service-identities {name, capabilities: ["organization_admin"] | ["mission_admin"],
  mission_id?}` → `201 {service_identity: {id, name, capabilities, mission_id}, api_token}`.
  `organization_admin` covers all missions (no `mission_id`); `mission_admin` needs a `mission_id`
  of this organization. Errors: `422 invalid_params` (`name` 1-120 characters, `capabilities`,
  `mission_id`), `403 forbidden`.
- `POST /service-identities/:id/rotate` → `200 {service_identity, api_token}`. The old token
  stops working immediately; the directory's `key_created_at` becomes the rotation time. Errors:
  `404 service_identity_not_found` (not active), `403 forbidden`.
- `DELETE /service-identities/:id` → `204`. The identity is disabled: its token stops working and
  it leaves the directory (O3). Errors: `404 service_identity_not_found`, `403 forbidden`.
- `POST /service-identities/:id/accountable {user_ids: [user_id]}` → `204` (#280). Records people
  as accountable for the identity, for approvals. Use it for an identity issued before #280 with
  nobody on record. The acting admin is recorded too. Errors: `422 invalid_params` (`user_ids`: each
  must be a person in this organization), `404 service_identity_not_found`, `403 forbidden` (not an
  org admin, or not a person).
- **Accountability (#280, ux U100):** whoever creates an identity, and whoever rotates its key, is
  recorded as accountable for it, from the session, in the same transaction. Its acts then count as
  theirs wherever an approval kind refuses approving your own work: catalog imports, activation
  requests, contact plans (including approvals under an automation grant), command requests and
  change sets. An identity issued by another service counts as that service's people,
  transitively. If anyone in the chain is unknown, nobody can approve its work (`*_approver_authors_unknown`).
  The directory's `created_by` comes from this record, never from identity metadata.

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
- **L11 additions (api-ops):**
  - Row fields:
    - `state: enabled | disabled` (the word form of `status`);
    - `shared`: `true` for a platform-shared source, which is read-only unless you're a
      platform admin in admin mode;
    - `logical_source: {key, label} | null`, `isolation_level`, `storage | null`;
    - `credentials_ref`: the reference with its middle elided, never material, or `null`.
  - `kind` is a closed set: `managed_tsdb | byo_tsdb | postgres | object_archive | projection`.
  - `permissions: ["data_sources.manage"]` (top level) when the caller passes the check the
    writes use (`operate_mission` today), else `[]`.

### Data sources (L11): writes, and the reads behind them

All under `/missions/:mission_id`. They wrap the legacy page's `OpsConsole.Actions.DataSources`,
so the validation and authorization are the same. Only the organization's own sources and
bindings can be written. A platform-shared one needs a platform admin in admin mode, otherwise
`403 platform_source`. Each write answers with the source's D1 row as `source`.

- `GET /data-sources/options` → `{logical_sources: [{key, label}], kinds: [{key, label,
  requires_credentials}], isolation_levels: {<kind>: [{key, label}]}, storages: [{key, label}]}`.
  Registration offers `byo_tsdb` and `managed_tsdb`.
- `GET /data-sources/:id` → `{source, bindings: [{id, logical_source, data_source_id, status:
  active | disabled | superseded}], runs: [{job_id, kind: provision | deprovision | reconcile,
  status: queued | running | completed | failed | outcome_unknown, started_at, error | null,
  actions: [] | ["retry"] | ["requeue"]}]}`. Runs are the newest 20. `404 data_source_not_found`.
  - `source.tsdb_actions` (also on D1 rows): `[]` or `["provision", "reconcile",
    "deprovision"]`, the backend operations this source takes. Only a `byo_tsdb` source with an
    `org_isolated` or `mission_isolated` backend takes them. The page offers only these.
  - A run's `error` is `{code, message}` (since 11-14; it was a string). `code` is one of
    `tsdb_executor_not_configured`, `credentials_unavailable`, `worker_failed`, `requeued`,
    `outcome_unknown` and `run_failed` (the fallback); `message` is a sentence to show as is.
  - `outcome_unknown`: the run's real outcome was lost (it ran before the 11-14 jobs fix). It
    has no actions: nobody re-runs it from here.
- `POST /data-sources {display_name, logical_source, kind, isolation_level, storage,
  credentials_ref?, credential_provider?, endpoint_ref?, material_env_profile?,
  http_endpoint_env?}` → `201 {source}`.
  - The server makes the id from the name (`Bus history` → `bus_history`, then `bus_history_2`
    and so on).
  - `credentials_ref` is required for `byo_tsdb`.
  - `422 invalid_params` with `details.field`.
- `POST /data-sources/:id/disable` and `/enable` → `{source}`. `409 data_source_state {state}`
  when it's already in that state.
- `GET /data-source-bindings` → `{bindings: [{id, logical_source, realm, data_source: {id,
  display_name}, status, shared}]}`: the mission's own bindings first, then the platform-wide ones
  it falls back to (only for a logical source and realm it has none of its own for). Every binding
  view (`bindings[]` of a source, W3's `binding`) also carries `shared`: true for a platform-wide
  binding (no organization), which every mission without its own reads.
- `GET /data-source-bindings/:binding_id/blast-radius` (DECISIONS #90, ux U53; a platform-wide
  binding, a platform admin in admin mode; re-read it when the sheet opens) → `{binding: {id,
  logical_source, realm, from: {id, display_name}}, affected_missions, live_passes: {total, first:
  [{spacecraft_name, station_code | null, aos}]}}`. `affected_missions` counts the platform's
  missions with no active binding of their own for that logical source and realm; `first` is up to
  3 passes live now (AOS ≤ now < LOS), earliest AOS first. `403 platform_source` outside admin
  mode, `409 binding_not_shared` for a mission's own binding, `404 binding_not_found`, `503
  blast_radius_unavailable` when counting fails (the sheet then refuses to switch).
- `GET /data-source-bindings/:binding_id/events` (actors per #146's rule, #471: on an organization's binding a person is named only while an active member, and anyone else is `{id: null, name: null}`; never an email) → `{events: [{at, actor: {id, name} | null,
  kind: switched | registered | changed | enabled | disabled | superseded, from: {id,
  display_name} | null, to: …, reason | null, affected_missions | null, live_passes_total |
  null}]}`, newest first, 50. A platform-wide switch's entry carries its reason and counts. For a
  platform-wide binding outside admin mode, `actor`, `reason`, `affected_missions` and
  `live_passes_total` are `null` (the platform admins' record; tenants see what happened and when).
- `PUT /data-source-bindings/:binding_id {data_source_id, expected_data_source_id}` → `{binding}`.
  - `expected_data_source_id` (the source the sheet showed) is required: `422 invalid_params
    {field: "expected_data_source_id"}` without it.
  - `409 binding_changed {current_data_source_id}` when it's stale, checked by the switch action
    itself (every caller, not only this endpoint) and again under a row lock at the write.
  - `422` when the source doesn't serve the binding's logical source or isn't enabled.
  - The binding must be the mission's own, or (a platform admin in admin mode) a platform-wide one.
    A mission's own binding may point at its own or a shared source; a platform-wide binding only at
    a platform-shared source: `422 platform_target_required {field: "data_source_id"}` otherwise.
  - A platform-wide binding (#90) also takes `reason` (required, 1–500 characters),
    `expected_affected_missions` and `expected_live_passes_total` (the counts the sheet showed;
    required). The server recounts: if either differs, `409 blast_radius_changed` with the fresh
    blast-radius body in `details`, and nothing is switched. `422 invalid_params {field, <field>:
    sentence}` for a missing reason or count. Success is `{binding, recorded: {affected_missions,
    live_passes_total}}`, the counts recorded in the binding's event and in the platform audit
    (Admin › Audit).
- `POST /data-sources/:id/probe` → `{source, probe: {health: {status, checked_at} | null,
  reason | null}}`.
- `POST /data-sources/:id/credential {credentials_ref}` rotates to that reference (the reference
  only) → `{source}`.
  - The source's current reference gets a new version (its material was rotated behind it).
  - A new reference is registered the way Register does it, and the source points at it.
  - `422 invalid_params {field: "credentials_ref"}` for a reference that another source or
    mission holds.
- `POST /data-sources/:id/tsdb/provision | reconcile | deprovision` → `202 {source, run | null}`.
  - `run` is `null` for `reconcile`, which is synchronous.
  - Outside `tsdb_actions`, the answer is `409 data_source_state {state}` with a sentence:
    `managed` ("This source is managed by Cadence; its storage is provisioned automatically.")
    or `customer_owned` ("This source uses your own database as is; Cadence doesn't provision
    it.").
- `POST /data-source-runs/:job_id/retry | requeue` → `202 {run}`. Retry starts a failed run again;
  requeue puts a run stuck in running back in the queue. `404 run_not_found`.
- While any run is `queued` or `running`, poll `GET /data-sources/:id` (about every 5 s). The
  mission channel's `data_sources` invalidate covers binding and health changes, not run
  progress.

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
- Rows also carry (§11 L9) `status: {state: "active" | "not_installed" | "disabled" |
  "activation_pending" | "failed", label, version}` and `surfaces: [{surface_id, label, order,
  purpose, area: "setup" | "ops", scope: "mission" | "spacecraft"}]` (by order). `active`: a
  platform app, or installed and its status loads; `activation_pending`: an approval-pending
  activation request for its binding set (telemetry decom only today); `failed`: installed but its
  status can't be loaded. `label` is the app's own status words ("Monitoring") or `null`. While
  `activation_pending`, status adds `activation_request: {requested_by: {name} | null,
  requested_at}` (the open request; ux #77). `area`
  comes from the surface placement (`application_workspace` is Setup, `ops_*` Ops); administration
  surfaces aren't listed. Spacecraft-scope apps aren't in this list yet (L19).

### `GET /missions/:mission_id/spacecraft/:spacecraft_id/apps` (§11 L19)

The apps installable on one spacecraft (today `spacecraft` and `telemetry_decom`) with **this
spacecraft's** installations: `{apps: [<A1 row>], permissions}`. `surfaces` holds only the
spacecraft-scope ones (open them with S1's `?spacecraft_id=`), and `status` is the app's status
at this spacecraft. `activation_pending` counts only a decom request that names this spacecraft
(or names none: a mission-wide composition). Installations are per spacecraft, so the A1 verbs apply under this path: `POST
…/spacecraft/:spacecraft_id/apps/:key/install | disable | uninstall` → the row. `404
spacecraft_not_found` and A1's errors.

### `GET /missions/:mission_id/apps/:key/surfaces/:surface_id/host?spacecraft_id=` (§11 L9, S1)

Everything the console needs to load one app surface (a Module Federation component) and let it
talk to the server: `{catalog, status, surfaces}`.

- `catalog` is the application-host catalog for that one app and surface, **schema unchanged**
  (`cadence.first-party-frontend-catalog.v1`; check it with plugin-sdk's
  `assertFrontendApplicationCatalog`): session id, CSRF token, bridge base URL, context, the
  app's package and release coordinates. The surface talks through the existing bridge
  (`/api/cadence/application-host/v1/…/query|actions`), same-origin, no new token.
- The one change inside: `session.context.actor.permissions` are real, from a closed vocabulary:
  `applications:view` (always), `applications:operate` (the actor passes the policy of every
  action the surface declares), `activations:request` (the surface can request activation and the
  actor may). Without `applications:operate`, render read-only. Under today's Policy whoever loads
  a surface may also operate it (todo(authz): read-only becomes real with Cedar).
- `status` and `surfaces` are the A1 row's.
- **Several scopes at once (L19b):** like the bridge's `GET /catalog`, this pins the host scope
  (mission, or one spacecraft) in the browser session, which keeps the 16 most recently loaded
  scopes. Surfaces at any of them work side by side, so you don't need to re-pin on focus.
  `host_session_mismatch` now only means this session never loaded that scope (or 16 newer ones
  pushed it out): re-request `/host` on that error, then retry once.
- Errors: `404 application_not_found | surface_not_found | spacecraft_not_found`;
  `409 application_not_installed` with `details.status` (`not_installed` or `disabled`; the host
  shows "<App> isn't installed on <mission>." with `Install` for admins); `403 forbidden`;
  `503 application_unavailable` (no release, or the catalog can't be built).
- **A mission that isn't the session organization's** (another organization's, or one that
  doesn't exist): with L4 (`51e3babb1`, director 11-14) the policy refuses it before any lookup.
  The bridge's `GET /api/cadence/application-host/v1/…/catalog` answers `404
  application_unavailable` (was `404 mission_not_found`), and the legacy REST paths that take a raw
  mission id answer `403 scope_mismatch`. Foreign and nonexistent missions get the same answer, so
  it reveals nothing. Note that the same code `application_unavailable` also appears as a 503 (no
  release); read the status.

### Settings (ST1): `GET /missions/:mission_id/settings` and `GET /organizations/:organization_id/settings`

`{sections: [{key, title, purpose, fields: [field + {value, source: "mission" | "organization",
inherited_value}], locked, version: {version, at, actor: {name}} | null}], permissions:
["settings.edit"]}`.

- Sections come from the server's settings registry (Governance, Commanding, Pass review and
  `cadence.configuration`, the profile framing generations flag). A section with no console fields
  is left out, and so is a section whose owner can't be read (logged on the server).
- Fields use the kind-schema shape, with paths inside the section's value. Shares between 0 and 1
  (Pass review) have `unit: "ratio"`. At organization level each section's `fields` ends with an
  `allow_override` field ("Missions may override", boolean, `source: "organization"`,
  `inherited_value: null`).
- **Per field** (a85b1799e): at mission level a field's `source` is `"mission"` only when the
  mission's override sets that path; every other field is `"organization"` and its `value` is the
  organization's (the override is merged over it, so unset fields follow later organization
  changes). At organization level every field is `"organization"`. Governance fields the
  per-field migration kept read `"mission"` even where they equal the organization's.
- `inherited_value` is the organization's value (mission level only). `locked: true` means the
  organization doesn't allow an override: the fields then read the organization's values, all
  `"organization"`, whatever the mission stored.
- `version` is per section: there's no single settings version (`null` before the first save).
- **Who may change the approval setting (#233, user ruling 11-18).** In `cadence.governance`,
  `approval_requirement` (and `allow_override` at organization level) carry `allowed_values`:
  the values THIS viewer may save (the enum's own values; `true`/`false` for `allow_override`),
  `[]` when none. At mission level they also carry `can_inherit`: whether the viewer may clear
  the mission's own value (send `null`). Other fields carry neither key, which means no
  field-level limit.

  | Viewer | Organization level | Mission level |
  |---|---|---|
  | Organization admin (or a platform admin in admin mode) | both values; `allow_override` both | both values; `can_inherit: true` |
  | Mission admin (its own mission) | `[]` (a mission scope can't save there) | `["independent"]` (tighten, or pin an inherited `independent` so the mission stays strict if the organization loosens; ux), `[]` once the mission sets its own `independent`; never `direct`, even while it's in effect (pinning it loosens in advance; lead); `can_inherit` only when the organization's value isn't looser |
  | Operator | `[]` | `[]`; `can_inherit: false` |
  | Anyone, while the organization doesn't allow an override (`locked`) | as above | `[]`; `can_inherit: false` (an organization admin changes the organization's value) |

  A mission admin is a service identity's capability today; people are organization admins or
  members.

`PUT …/settings/:section_key` with `{values: {path: value | null}, expected_version}` saves
directly and returns `201 {version, state: "active"}`. `expected_version` is the section's
`version.version`, or `null` (or left out) to skip the check, as on a first save.

- **Mission:** only the paths sent change. A value sets that field for the mission; `null`
  removes it, so it follows the organization again. Paths not sent keep what's stored. When no
  field is left set, the section inherits entirely.
- **Organization:** the paths sent replace the stored ones; the rest keep their values. `null`
  isn't accepted (`422 invalid_params`, `details.values`). `allow_override` is sent as a path.

Errors: `422 invalid_params` (an unknown path in `details`, or `details.values` for a value the
section refuses), `409 version_conflict` (with `details.expected_version`, the section's current
version; also when another save lands between the read and the write), `409
settings_enforced_by_organization`, `404 settings_section_not_found`, `403 forbidden`, and
`422 settings_write_unconfirmed` / `422 settings_unavailable` when the section's owner fails or
can't be read (retry). Edit needs `settings.edit` (any mission operator
today, from the enforcing check).

The approval setting adds two 403s (#233; ux U96 words, by the level saved). A refused change
writes nothing:
- `403 approval_policy_change_requires_organization_admin`: loosening a mission's setting ("Not
  saved: only an organization admin can let changes on EARENDIL apply without approval."), or
  any change to the organization's ("Not saved: only an organization admin can change the
  organization's approval setting."). A non-admin's save to the organization's governance
  section answers that second line too, with code `forbidden`.
- `403 approval_policy_change_requires_mission_admin`: an operator's tightening or no-change save
  ("Not saved: only a mission admin or an organization admin can change approval settings.").
- While the organization doesn't allow an override, every mission save, an organization admin's
  included, is `409 settings_enforced_by_organization`. A stale version is refused first
  (`409 version_conflict`).

### `GET /missions/:mission_id/routing-rules/groups` (pass-2 #10)

`{groups: [{transport: {id, name}, direction, role, enabled_count, disabled_count,
spacecraft_count}]}`: active routing rules grouped by transport, direction and role, sorted by
transport name. A thousand per-spacecraft rules read as a few lines; `GET /routing-rules` with
`transport_id` lists one group's rules.

Edits go through change sets (`ground_station` and `transport` kinds; see changes.md). Refetch on
`invalidate` with `configuration` or `spacecraft`.

- `GET .../ground-stations` → `{stations: [{id, display_name, code, provider, region,
  lifecycle_state, transport_count, routing_rule_count, health}]}`. Only active stations are
  listed, unless `?include_archived=true` (U82: archived ones follow the active ones, with
  `lifecycle_state: "archived"`). Pickers use the default. `code` is the station's short code (2–8 capitals/digits, unique per mission).
  `transport_count` and `routing_rule_count` are **`null`** because the model has no
  station↔transport link yet. `health` is `null` (not tracked; show "not reported").
- `GET .../transports` → `{transports: [{id, display_name, version, origin, transport_kind,
  direction_capability, lifecycle_state, station: null, routing_rule_count}]}`.
  `routing_rule_count` counts active rules using the transport; `station` is `null` for the same
  reason as above. Active only by default; `?include_archived=true` adds archived ones after the
  active ones (U82).
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

`{providers: [{id, name, provider_type, version, policy_mode, account: {id, name} | null, grant: {id,
version, state: "active" | "revoked"} | null, status: {lifecycle_state, last_validated_at,
last_synced_at}, health: {validate: <health>, sync: <health>}, station_count}], permissions}` for
the Stations · Providers tab, sorted by name.

- `account` is `null` exactly when `grant` is (older, direct bindings with no account).
  `account.name` is `null` for members (only organization admins can read accounts).
- `grant` is `null` only for a provider bound without an account grant (older, direct bindings).
  `grant.version` is the grant version the provider was **bound at**, not the grant's current
  version. `state` is the grant's current state: a revoked grant leaves the provider in place but
  unusable until it's archived or rebound.
- `policy_mode` is always one of the two keys: a policy recorded without a mode reads
  `approval_required`, which is how the domain applies it.
- `<health>` is `{status: "healthy" | "failed" | null, checked_at | null, error | null}`, the
  provider's own record of its last validate and sync. `null` means never checked. `error` is a
  sentence for a person, not provider evidence.
- `station_count` counts active stations whose `provider` is this provider's name.
- `permissions`: `["providers.manage"]` for mission admins (`:manage_mission`), else `[]`.

## Mission providers (L12): `/api/console/v1/missions/:mission_id/providers` (owner: api-ops)

Every write needs `providers.manage` (mission admins; organization admins qualify), else `403
forbidden`. Each answers with the provider's row as the list shows it.

- `GET /options` → `{grants: [{id, version, account: {id, name, provider: {key, label}},
  allowed_stations: [..] | null, allowed_services: [..] | null}], policy_modes: [{key, label}],
  deadline_behaviors: [{key, label}]}`. `grants` are this mission's active account grants.
- `POST /` `{grant_id, display_name, policy_mode, deadline_behavior?, permitted_resource_refs?:
  [..], bounded?: {approved_station_substitutions?: [..], minimum_retained_duration_seconds?,
  maximum_earlier_start_shift_seconds?, maximum_later_start_shift_seconds?,
  maximum_earlier_end_shift_seconds?, maximum_later_end_shift_seconds?}, expected_grant_version?}`
  → `201 {provider}`.
  - The provider's type, URL, credential and environment come from the granted account version.
  - `bounded` is read only for `policy_mode: "bounded_automatic"`.
  - `409 grant_revoked`; `409 grant_changed {version}` when `expected_grant_version` is stale.
  - `422 invalid_params` names the field: `grant_id` (unknown, or another mission's),
    `display_name` (1 to 120 bytes after trimming, so fewer characters outside ASCII),
    `policy_mode`, `deadline_behavior`,
    `permitted_resource_refs` (outside the grant's or account's stations, or malformed),
    `approved_station_substitutions`, or `bounded` (a shift limit).
- `POST /:id/validate` → `200 {provider, result: {ok, message | null}}`.
- `POST /:id/sync` → `200 {provider, result: {ok, stations: int | null, message | null}}`.
  - `stations` is how many ground stations the provider listed.
  - A successful sync also rewrites the stations' provider availability.
- Validate and sync are **results, not errors**: a provider that refuses, can't be reached or
  doesn't support the call answers `200` with `ok: false` and a sentence in `message`, and the
  row's `health` says `failed`.
  - Both call the provider inline and give up after **25 s**: `ok: false`, "The provider didn't
    answer in time." Show "Contacting the provider…" while waiting.
  - The provider's late answer, if one comes, replaces that in the row's `health`.
- `POST /:id/archive` `{reason}` → `200 {provider}` (`status.lifecycle_state: "archived"`).
  - Works when the grant was revoked.
  - Bookings already made keep the provider's version; no new ones can use it, and the provider
    leaves the list.
  - `422 invalid_params {reason: "Say why."}`.
- `404 provider_not_found` for an unknown or archived provider.

## `GET /api/console/v1/missions/:mission_id/config/kinds/:kind/schema`

`{kind, fields: [{path, label, type, unit, enum, range, default, required, help, visible_when}]}`
for generating change-set edit forms. `kind` is `ground_station`, `transport`,
`spacecraft_profile`, `spacecraft`, `derived_telemetry` or `limit_definition`; anything else gets
`422 invalid_params`.

- `ground_station`: `display_name` (required), `code` (required for new stations, `pattern`
  `^[A-Z0-9]{2,8}$`, unique per mission), `provider` (an `enum` of the mission's provider names when
  the mission has providers, otherwise free text), `region`.
- `transport`: `display_name`, `transport_kind`, plus each transport kind's configuration fields
  on the **stored document's paths** (today `tcp_socket`: `configuration.mode`,
  `configuration.direction_capability`, `configuration.host`, `configuration.port`,
  `configuration.framing.mode`, `configuration.framing.fixed_message_bytes`,
  `configuration.reconnect.policy`, `configuration.tls.enabled` (boolean)). They match the transport
  detail `document`, so stage edits to exactly these paths.
- `spacecraft_profile` (8f, New profile): `display_name` (required), then the profile detail's
  section fields on the kind's document paths: `downlink_protocol`, `uplink_protocol` (both
  required), `packet_protocol`, `frame_parameters.{frame_size, secondary_header_length,
  insert_zone_length, ocf_length, fecf, truncated_primary_header}`, `catalog_revision_id`
  (`reference`; `enum` = the mission's catalog revisions, newest first, labelled "rev 4 · imported
  11-10"; no `enum` when there are none). Each field adds `section` (`profile | framing |
  catalog`). Labels, units, ranges and help match the profile detail's. Routing rules,
  applications and metadata aren't in it (their own editors). The kind still validates on stage
  (e.g. frame lengths per protocol).
- `spacecraft` (§11 L17): `display_name` (required), `scid` (integer 0–1023), `spacecraft_type_id`
  (`enum` of the mission's shared profiles, labelled by name), `spacecraft_type_version` (integer;
  empty means the profile's latest), all with `section: "identity"`. Then `commanding_enabled`
  and `telemetry_enabled` (boolean, `section: "switches"`, `help` = ux's U40 text). See "Spacecraft
  edits" above for the staging rules.
- `limit_definition` (#77 stage 2, domain c495f6d9f; staged once it's registered at tonight's
  restart): `point_id` (required, `create_only`; a catalog point or a live derived point),
  `limit_set_name` (required, `create_only`, default `DEFAULT`), then `thresholds.red_low`,
  `thresholds.yellow_low`, `thresholds.yellow_high`, `thresholds.red_high` (**`type: "number"`**,
  new in the field shape; each optional).
  - Ordering rule: red low ≤ yellow low < yellow high ≤ red high where present. Errors come back on
    `thresholds`.
  - A create gets a deterministic `entity_id` (`limit_definition:<hash of point + set>`), so leave
    `entity_id` out. A create for a point and set that are live now is refused at staging, as a
    `point_id` field error ("Limits for BATT_V already exist. Edit them instead."; domain 63206b13d).
    If they become live after staging, apply reports the `entity_exists` conflict.
  - Delete = **retire**: evaluation stops and the history stays; re-adding continues it.
  - HOLD `limit_alarm_active` (acknowledge): `details {point_id, limit_set_name, severity:
    critical | caution, episode_id}` (U43 sentence).
- `derived_telemetry` (#77 stage 1, domain 5504322a8): `point_id` (required, 1–240, **`create_only:
  true`**: show it on create, read-only after), `point_name` (1–240), `expression` (required,
  1–8192, **`type: "text"`**: a multiline editor). `metadata` isn't in the form and is kept as it is.
  New in the field shape: `create_only` (absent elsewhere) and the `text` type. Ops: create, update
  (`changes` on `point_name` / `expression`) and delete (= **retire**). Field errors come back on
  `expression` (parse, stateless, unknown point) and `point_id`. Retiring a point another live
  point reads is the blocking HOLD `derived_point_in_use` (U42 sentence; `details {point_id,
  used_by: [{point_id, name, definition_id}]}`).
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

## Archiving transports and ground stations (ux U82)

Archive is `action: "delete"` on the `transport` or `ground_station` kind through `POST
/config/stage`, for either transport origin. Once applied the item can't be chosen for new routes
or passes; its history stays. Archiving a transport also releases the provider profile created
from it (its listen port is free again). The change list, preview and history name a station
`Inuvik · INU` (its name alone without a code).

Something still using the item refuses the archive with `409 in_use`, the same details at every
moment: at stage (nothing staged), and at submit or review when it became used after staging (the
set reopens; nothing applied):

```json
{"entity": {"kind": "transport" | "ground_station", "id": "…", "name": "INU S-band" | null},
 "uses": {
   "routes":         {"count": 1, "items": [{"routing_rule_id", "name": null, "spacecraft": {"id", "name"},
                                             "station": {"id", "code", "name"} | null, "direction": "downlink"}]},
   "profile_routes": {"count": 0, "items": [{"profile": {"id", "name"}, "rule_id", "label": null}]},
   "booked_passes":  {"count": 0, "next_at": null},
   "listening_now":  {"count": 0, "items": [{"realized_contact_id", "spacecraft": {"id", "name"},
                                             "station_code": null, "starts_at"}]},
   "transports":     {"count": 0, "items": [{"id", "name"}]}}}
```

Every kind is always present; `count` is the full number and `items` at most 3. An item is listed
only when the name its line needs exists (a route's or pass's spacecraft name, a profile's name, a
station's transport name); otherwise it is only counted. A station archived together with its
transports (one stage, or already staged in the open set) isn't refused for them.

## Legacy route conversion (TEMPORARY: removed with 9ac6dc8ee; ux U79, director 11-16)

Older per-spacecraft routing rules (`origin: legacy`) become extra routes in batches of spacecraft,
each batch alone in its change set and reviewed by someone other than its stager (approval is
forced on these sets, whatever the mission's policy).

- `GET /api/console/v1/missions/:mission_id/routes/legacy-conversion` (operate_mission) →
  `{routes_converted, routes_total, batch_size, batches_total, next_batch: int | null,
  staged_batch: {change_set_id, batch, author: {id, name | null}} | null, unmappable: {count,
  routes: [{routing_rule_id, reason: "transport_has_no_station", spacecraft: {id, name | null}}]},
  can_stage}`. `next_batch` is null while a batch is staged and when nothing is left; `routes` is
  capped at 50, sorted by spacecraft name. `can_stage`: the viewer holds `manage_mission`
  (organization admins, mission admins of that mission).
- `POST` the same path (manage_mission), body optional `{spacecraft: 1..100}` (default 50) →
  `201 {change_set_id, batch, batches_total, route_count, spacecraft_count,
  remaining_route_count, unmappable: [the same entries, this batch's craft]}`. Routes that can't be
  mapped never refuse a batch: the rest stages and they're reported. Description, server-side:
  'Converted from the old routing page: batch 2 of 10, 150 routes on 50 spacecraft.'
- Refusals: `409 conversion_already_staged {change_set_id, batch, author: {id, name}}` (one staged
  batch at a time); `409 open_change_set_not_empty {change_set_id}` (a batch is alone in its set);
  `422 nothing_to_convert`; `422 invalid_params {spacecraft}`; `409 frozen_in_review`; `403`.
- While a batch is staged, ANY other staging answers `409 conversion_in_progress {change_set_id,
  batch | null}` ([changes.md](changes.md)); applying or discarding the batch lifts it.
- The change set carries `legacy_conversion: {batch, batches_total} | null` and, like every set,
  `viewer` ([changes.md](changes.md)).

## Older route removal: the `legacy_routing_rule` kind (ux U79, director 11-16)

Delete only, through `POST /config/stage`: `{kind: "legacy_routing_rule", action: "delete",
entity_id: <routing_rule_id>}`; it archives the rule when the set is applied. Not temporary: it
stays while any legacy row can exist. The console infers 'Removal staged' per row from the open
change set (`GET /config`), so the routing read carries no flag.

- Refused at stage (`422 invalid_op`, empty path, nothing staged), in ux's words: 'This route was
  converted already. Remove it as an extra route.'; 'This rule can't be removed here.'; and for a
  create or update, 'Older routes can only be removed.'
- Named in the preview, the change list and the history (`entity_name`) as `“<name>” ·
  <spacecraft>`, `INU · <spacecraft>` without a name, without ` · …` when the spacecraft has no
  name; never an id. The console adds its verb ('Remove older route …').
- A rollback past a removal is NO-GO with a validation item: 'The older route “<name>” ·
  <spacecraft> was removed and can't be restored. To route that way again, add an extra route.'
