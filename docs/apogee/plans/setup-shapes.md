# Setup endpoint shapes requested by fe-setup

Owner: **fe-setup** (request). Confirmed by api 2026-11-08; api owns the final contract in `docs/apogee/api/setup.md`. Until it
lands, the console decoders in `frontend/apps/console/src/features/{readiness,spacecraft}/api.ts`
match these shapes exactly. Conventions follow `docs/apogee/api/README.md` (snake_case, null not
omitted, server-decided staleness). Sources are in `plans/setup.md`.

## R · `GET /api/console/v1/missions/:mission_id/readiness`

```json
{"data": {
  "evaluated_at": "2026-11-08T02:41:17Z",
  "verdict": {"blockers": 0, "cautions": 1, "stale": 1, "not_set_up": 1, "optional": 1},
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
- `verdict`: counts of findings per severity (rows, not affected items).
- `recent_changes`: null when there's no unified event feed (the UI then omits panel R2), else
  `[{"at", "kind", "version_label": "v4"|null, "summary", "actor": {"name"}|null}]`, newest first,
  at most 5.
- Empty mission: `fleet` is `blocker` with count 0, plus a `blocker` finding "No spacecraft" with
  `fix.kind = spacecraft_new`. Same for no catalog (`catalog_import`).

## S · `GET /api/console/v1/missions/:mission_id/spacecraft`

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

## P · `GET /api/console/v1/missions/:mission_id/profiles`

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

## PD · `GET /api/console/v1/missions/:mission_id/profiles/:profile_id`

Shape = domain `profile_detail` (`docs/apogee/domain/profile-routing.md` §5) in snake_case. Two
things it adds:
- enum fields carry `enum: [{value, label}]`;
- `versions: [{version, created_at, actor: {name}|null}]` for the History view.

Before profile routing and overrides land, return `rules: []` and `overrides: []`, plus
`"routing_model": "per_spacecraft"`, so the UI can say routing is still per spacecraft. Don't
return them empty without that flag.

## SD · `GET /api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id`

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
