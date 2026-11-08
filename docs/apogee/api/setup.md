# Setup endpoints (Readiness, Spacecraft, Catalog, Profiles, People)

Conventions: [README.md](README.md). Requested shapes: `docs/apogee/plans/setup-shapes.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| S | `GET /missions/:mission_id/spacecraft` | **implemented** |
| R | `GET /missions/:mission_id/readiness` | **implemented** (v1, `Cadence.Reads.Readiness`; domain extends it for change-set preview) |
| P | `GET /missions/:mission_id/profiles` | **implemented** |
| SD | `GET /missions/:mission_id/spacecraft/:spacecraft_id` | **implemented** |
| PD | profile detail + versions | next |
| (3) | catalog databases/revisions/import runs, upload, import-run channel | planned |
| (4) | batch spacecraft validate + create | planned |
| (5) | org members, invitations, service identities | planned (`/organizations/:organization_id/...`) |

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
| catalog | `no_catalog`, `catalog_without_revision` blocker → `catalog_import` | detail "Latest rev N · label" ("rN" is reserved for mission config revisions) |
| comms | `no_transports` blocker → `comms` | |
| stations | `no_ground_stations` not_set_up → `station` | `unknown` when stations exist, because station health isn't tracked (never ready by default) |
| data_sources | `data_source_unavailable` blocker, `data_source_degraded` caution → `data_source` (id when it is just one) | `unknown` when no health has been reported |
| apps | `app_not_installed:limits` not_set_up; other missing optional apps → optional; fix `app` with the app key | optional findings never degrade an area |

- Units are singular when the count is 1.
- `affected_count` is 0 for findings that aren't about a set of items.
- Findings are sorted by severity (blocker first), then area order.
- `recent_changes` stays `null` until a unified change feed exists (mission change sets).
