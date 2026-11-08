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
