# Dashboards (owner: api-ops)

Console endpoints for dashboards (BACKLOG §11e, DECISIONS #76). The plan and the asks are in
`docs/apogee/plans/dashboards.md`.

## D0: `dashboard.author` capability

`GET /session` lists `dashboard.author` in `organizations[].capabilities` and the top-level
`capabilities` when `Policy :author_dashboards` passes for at least one of the organization's
missions (`Cadence.Dashboards.Capabilities`). Today that's any mission operator. Authoring routes
still enforce it per mission. People rows don't carry it.

## D5: `GET /api/console/v1/missions/:mission_id/dashboards/:dashboard_id`

Query: `from`, `to` (`now-6h` … `now` for a live sliding window, or ISO bounds for a frozen range
up to 31 days; both or neither) and `spacecraft_id` (one of this mission's spacecraft).

```json
{"data": {
  "dashboard": {"id": "…", "name": "Bus overview", "description": null, "tags": ["power"],
                "current_version": 12, "updated_at": "2026-11-13T02:51:00Z"},
  "can_edit": true,
  "scope_options": [{"id": "spacecraft-earendil-312", "name": "EARENDIL-312"}],
  "snapshot": {…} | null,
  "resolved_at": "2026-11-13T02:52:10Z"}}
```

- Wraps `Reads.Dashboards.DashboardPage.load/4`, with the runtime admitted by `OpsWorkspaceURL`.
  Only `from`, `to` and the spacecraft enter it.
- `snapshot` is `WorkspaceSnapshot.build/4`'s map, passed through unchanged. `null` means the
  dashboard was never made current and the viewer isn't an author: "This dashboard has no saved
  version yet."
- `current_version` is the current (published) version. `can_edit` means the viewer may author it.
  `tags` come from the document's `metadata.tags` (`[]` when absent). `scope_options` holds at
  most 1000 spacecraft.
- Reading doesn't record the dashboard as recently viewed. That's D6's record-view write.
- Errors:
  - `404 not_found`: unknown, archived, or another mission's dashboard.
  - `422 invalid_params` with `details.field`: `spacecraft_id` (not this mission's) or `range`
    (bad or one-sided `from`/`to`, or a range over 31 days).
  - `503 dashboard_unavailable`: the resolve failed.
- Invalidation: refetch on `invalidate` with `dashboards`, `telemetry`, `limits`, `alarms` or
  `events`.

## D7-D13: editing (owner: api)

Stateless on the server (DECISIONS #76; `Cadence.Dashboards.StatelessAuthoring`). The browser keeps
`{base_version, commands}`, autosaves it locally, and sends it with every call. A **command** is
`{event, input}` with the legacy draft's events: `rename`, `add_section`, `update_section`,
`remove_section`, `move_section`, `add_widget`, `update_widget`, `remove_widget`, `layout`,
`runtime_defaults`. `input` never carries `expected_version` (`base_version` is the call's). At
most 256 commands (`422 too_many_commands`: "Save to keep going"). All of these need
`dashboard.author`, and live under `/api/console/v1/missions/:mission_id/dashboards/:dashboard_id`.
`runtime` is `{from, to, spacecraft_id}`, admitted like D5's query (`422 invalid_params`
`details.field` `range` | `spacecraft_id`).

- **D7** `POST /preview {base_version, commands, runtime?}` → `{snapshot, changes, current_version,
  outline}`. Writes nothing. `snapshot` is D5's `WorkspaceSnapshot` map for the staged document,
  resolved with live data paused. `changes` are `VersionDiff` labels against `base_version` (the
  Save drawer's list). `current_version > base_version` means someone saved meanwhile.
  `outline` is the editor outline (`Reads.Dashboards.Editor.outline`: `version 3, defaults,
  sections, placements [{id, section_id, title, editable, fields, observables, layout,
  constraints}], runtime_defaults_json`). Entering edit mode = D7 with `commands: []`.
  `422 invalid_command` `details {index, code, field}` names the first command that fails (the
  rest aren't applied); `code` is the authoring vocabulary (`missing_placement`,
  `invalid_binding`, `invalid_title`, `capacity`, …).
- **D8** `POST /observables {query, base_version, fields}` → `{observables: [{id, label,
  description}], more}`. `fields` is the widget sheet's form fields exactly (the outline's
  placement `fields`, edited), so the choices fit that widget's type and binding. At most 50;
  `more` says there are more matches. `422 details.fields` when they aren't a complete widget
  form.
- **D9** `POST /save {base_version, commands, message?, defaults? {time, scope}, runtime?}` →
  `201 {version, changed, warnings}`. Replays the commands on `base_version` and saves the next current
  version (`changed: false` and no new version when nothing changed). `message` defaults to the
  change labels. `defaults.time` / `defaults.scope` = "save the current range / spacecraft as
  the default", taken from `runtime`. `409 version_conflict` `details {current_version, saved_by
  {kind, id, name}, saved_at}` when someone saved since `base_version` (then D10).
  `422 dashboard_not_ready` `details.placements [{placement_id, code, message, details}]` when
  publish readiness fails. `details` is `{logical_source, realm, reasons, observed_at}` for a
  source issue (`unready_publish_source_request`), `null` otherwise.
  - **What blocks** (lead 11-14): facts about the source itself: a missing or ambiguous binding; a
    missing, disabled or misconfigured data source; a failed connection test; an unsupported
    capability or scope; an invalid runtime context. Health a read reported (a timed-out preview
    records the source unavailable) doesn't block; it comes back in `warnings`. Health nobody has
    seen yet (unknown) is silent.
  - `warnings` (D9, D11, D13; `[]` when none, and on an unchanged save): `[{code:
    source_unavailable | source_degraded, logical_source, realm, reasons, observed_at,
    placement_ids, message}]`, one per (code, logical_source, realm), so one slow source behind
    several widgets is one entry naming them. The save went through; say the widgets may stay
    empty until the source answers. `message` is a fallback sentence.
  - Closed sets: `logical_source` `telemetry | events | limits | operational_observables`; `realm`
    `flight | rehearsal | replay | simulation` or `null`; `reasons` ⊆ `source_unavailable |
    source_degraded | source_health_unknown | connection_test_failed | connection_test_blocked`.
    `observed_at` is ISO-8601 UTC, `null` without a health row.
- **D10** `POST /rebase {commands, runtime?}` → D7's body plus `{base_version (= current),
  applied: [commands], skipped: [{index, event, reason}]}`. Replays onto the newest version; keep
  `applied` as the new command list. `reason` is the authoring code (e.g. `missing_placement`:
  "widget removed").
- **D11** `POST /copy {name, base_version, commands}` → `201 {id, version: 1, warnings}`. A new dashboard
  from the staged document, so unsaved edits survive "Save as copy"; `commands: []` copies
  `base_version` as it is.
- **D12** `GET /versions` → `{current_version, versions: [{version, kind: create | save | revert |
  migration, based_on_version, saved_by {kind, id, name} | null, saved_at, message, current}]}`,
  newest first. `current_version` is `null` for a legacy dashboard never made current. A revert's
  `based_on_version` is the version it restored ("Restored from v9").
  `GET /versions/compare?from&to` → `{from, to, changes, from_json, to_json}`.
- **D13** `POST /versions/:version/restore {expected_version}` → `201 {version, warnings}`, a new current
  version (kind `revert`). `409 version_conflict` on a stale `expected_version`. (The directory's
  `POST /restore` is un-archive.)
- Errors common to all: `403 forbidden`, `404 not_found`, `503 dashboard_unavailable`.

## D1: `GET /api/console/v1/missions/:mission_id/dashboards`

Query: `q`, `tags=a,b`, `starred=true`, `archived=true`, `sort=updated|name|name_desc`, `page=N`.

```json
{"data": {"dashboards": [row], "available_tags": ["power"], "total": 12, "page": 1, "pages": 1,
          "page_size": 50, "can_create": true,
          "shortcuts": {"starred": [row], "recent": [row]}}}
```

- `row`: `{id, name, description, tags, archived, starred, current_version, updated_at,
  updated_by: {id, name} | null, viewed_at, spacecraft}`. `recent` holds the 5 most recently
  viewed (D6).
- `spacecraft` (ux's Spacecraft column), from the current document
  (`Reads.Dashboards.BindingSummary`):
  - `{mode: "fixed", spacecraft: {id, name}}`: every widget is bound to that spacecraft, by the
    document's default scope or the widget's own;
  - `{mode: "context"}`: no widget names one; the viewer picks;
  - `{mode: "fleet"}`: every widget is `constellation_health`;
  - `{mode: "mixed"}`: anything else;
  - `null`: no widgets.

  Constellation-wide widgets don't change the answer when other widgets exist.
- `can_create`: the viewer may author dashboards in this mission.
- Errors: `422 invalid_params` (an unknown sort, more than 10 tags, a bad page).

## D2: `PUT` / `DELETE /dashboards/:id/star`

`204`. Each person's own star; any mission operator. `404 not_found` for an unknown or archived
dashboard.

## D3: `POST /dashboards/:id/archive {confirm?}` · `POST /dashboards/:id/restore`

- Archive: `200 {archived: true}`. While a playlist shows the dashboard, it's `409
  dashboard_in_use` with `details.used_by.playlists: [{id, name}]` unless `confirm: true`
  (director Q10).
- Restore: `200 {archived: false}`.
- Both need dashboard authoring (`403 forbidden`). Both appear in the organization Audit, kind
  `config`: "Archived dashboard Bus overview" / "Restored dashboard Bus overview", target `{kind:
  "dashboard", id, label}`, the actor, and the mission. Creating a dashboard (its first version)
  reads "Created dashboard …".

## D4: `POST /dashboards {name, description?, tags?, spacecraft?}` · `POST /dashboards/:id/duplicate {name}`

- `201 {id, version}`. `tags`: at most 10, each 1–64 characters.
- `spacecraft`: `{mode: "fixed", spacecraft_id}` makes that spacecraft (one of this mission's)
  the dashboard's default scope (`defaults.scope`, as the viewer's `spacecraft_id` admits it).
  `{mode: "context"}` and `{mode: "fleet"}` set no default. Absent: no default. Library templates
  come later (plan slice 8).
- Errors: `422 invalid_params` with `details.field` `name` or `spacecraft` (not this mission's,
  missing id, unknown mode); `403 forbidden` (not an author); `404 not_found` (duplicating an
  unknown dashboard).

## D6: `POST /dashboards/:id/views`

`204`. Records that the viewer opened it, for `shortcuts.recent`. The viewer sends it once per
open, not on refresh. `404 not_found` for an unknown or archived dashboard.

## D14-D19: settings, sharing, activity, diagnostics, export (owner: api)

From fe-setup's proposal (docs/apogee/plans/dashboards-settings.md). Under
`/api/console/v1/missions/:mission_id/dashboards/:dashboard_id`.

- **D14** `GET /settings?shares_after=&snapshots_after=` (author) → `{dashboard: {id, name,
  description, tags, lifecycle, current_version, published_version}, defaults: {time, scope},
  limits: {name: 120, description: 500, tags: 32, tag: 64}, shares: {rows: [share], next},
  snapshots: {rows: [snapshot], next}}`.
  - `share = {id, url, data_visibility: with_data | definition_only, state: active | expired |
    revoked, expires_at, created_at, created_by: {id, name, kind: "user"} | null, revoked_by:
    {id, name, kind: "user"} | null}`.
  - `snapshot = {id, url, version, data_visibility, window: {from, to} | null, created_at,
    created_by}`. `window` is null for snapshots taken before frozen windows (never a guess).
  - `url` is the console path (`/console/:org/:mission/telemetry/dashboards/shares/:id` or
    `…/snapshots/:id`).
  - Pages are 25 rows, in the store's id order (not by time yet); pass `next` back as
    `shares_after` / `snapshots_after`.
  - `defaults.time`: `{mode: "relative", range: "now-6h"}`, `{mode: "absolute", from, to}` or
    null. `defaults.scope`: `{mode: "fixed", spacecraft_id}` or null. Stored modes the console
    doesn't edit read as null.
- **D15** `PATCH /settings {name, description, tags, defaults, expected_version}` (author) → `200
  {version}`: a new current version, "Updated dashboard settings".
  - `defaults` absent means unchanged. Within it, `time` / `scope` absent means unchanged, and
    null clears. `scope.mode` `context` or `fleet` stores no spacecraft (reads back as null).
  - `409 version_conflict {current_version, saved_by, saved_at}` (as D9).
  - `422 invalid_params` with `details.name | description | tags | defaults`.
- **D16** (author):
  - `POST /shares {data_visibility, expires_at | null}` → `201 <share>`. `expires_at` is
    rounded up to whole hours from now. A past one, or one over 365 days, is `422
    details.expires_at`.
  - `DELETE /shares/:share_id` → `200 <share>` (state `revoked`). It's `409 share_not_active`
    when it's already revoked.
  - `POST /snapshots {data_visibility, runtime: {from, to, spacecraft_id | null}}` → `201
    <snapshot>`. The window is frozen (ISO 8601, from < to). A missing or bad one is `422` with
    `details["runtime.from" | "runtime.to" | …]`, never a silent definition-only snapshot.
  - `DELETE /snapshots/:snapshot_id` → `204`. Audited ("Deleted snapshot of <dashboard>"). Its
    link then reads `snapshot_deleted` (D20). `404` when it's unknown or already deleted.
  - `403 forbidden` for non-authors; `404 not_found` for an unknown dashboard.

## D20: shared views (owner: api)

From dashboards' slice 6 (docs/apogee/plans/dashboards-slice6.md). `GET
/api/console/v1/missions/:mission_id/dashboard-shares/:share_id` and `GET
…/dashboard-snapshots/:snapshot_id` (mission operators) → `{kind: share | snapshot, share: <D14
share> | null, snapshot_row: <D14 snapshot> | null, dashboard: {id, name, description},
definition: <editor outline, version 3> | null, snapshot: <WorkspaceSnapshot> | null}`.

- A share shows the dashboard's **current** version. `definition` is null when there isn't one
  yet. A snapshot shows its stored version over its frozen window.
- `snapshot` is null for `definition_only` links; each widget then says "Data isn't shared in this
  link."
- A share takes the viewer's `?from=&to=&spacecraft_id=` (D5-style: ISO bounds, or `now-6h` /
  `now`, resolved at each load). The share's own scope always wins, so a scoped share can't be
  widened. A bad one is `422 invalid_params` with `details["runtime.from" | "runtime.to" |
  "runtime.spacecraft_id" | "runtime"]`. Snapshots ignore them (frozen).
- Errors, all 404, each with the page's sentence as the `message`:
  - `share_revoked` "Revoked by Mira K. at 11-14 02:10Z." ("Revoked at …" when nobody's
    recorded), `details {revoked_at, revoked_by {id, name} | null}`.
  - `share_expired` "Expired 11-20 00:00Z.", `details {expires_at}`.
  - `snapshot_deleted` "Deleted by Mira K. on 11-14.", `details {deleted_by {id, name} | null,
    deleted_at}`.
  - `not_found` (unknown, or another mission's).
- `503 dashboard_unavailable` when a link that should open can't be resolved right now.

## D23/D24: playlists (owner: api)

From dashboards' slice 6. Under `/api/console/v1/missions/:mission_id/dashboard-playlists`.
Mission operators read; authors (`dashboard.author`) write. Refetch on `invalidate` with
`dashboards`.

- **D23** `GET /?q=` → `{playlists: [{id, name, description, dwell_seconds, wallboard_mode,
  dashboard_count, updated_at, updated_by {id, name} | null}], can_edit}`, by name (at most 200).
- **D23** `GET /:playlist_id` → `{playlist: {id, name, description, dwell_seconds, wallboard_mode,
  updated_at, updated_by, dashboards: [{id, name, archived}]}, can_edit}`. `dashboards` are in
  playlist order, archived ones kept and flagged (present mode skips them). Present mode reads each
  dashboard through D5.
- **D24** `POST / {name, description?, dwell_seconds, wallboard_mode, dashboard_ids}` → `201 {id}`.
- **D24** `PATCH /:playlist_id {any of those, expected_updated_at}` → `200 {id}`. Absent fields are
  unchanged, and `dashboard_ids` replaces the list. `expected_updated_at` is the row's `updated_at`
  as read (microseconds).
- **D24** `DELETE /:playlist_id` → `204` (hard; audited).
- Validation is the domain's: `name` 1–120, `dwell_seconds` **5–900**, `dashboard_ids` **1–100**,
  each an **active** dashboard of this mission. (The plan said 10–3600 and 1–50; tell domain if
  those matter.) `422 invalid_params`: `details.dashboard_ids` plus `unknown: [ids]` for
  dashboards that aren't active or aren't the mission's, else `details.playlist`.
- `409 version_conflict {current: <the D23 playlist>}` on a stale `expected_updated_at`.
- `404 playlist_not_found` ("This playlist was deleted."), `403 forbidden`.

## D21/D22: the widget library (owner: api)

From fe-ops' slice 8 (docs/apogee/plans/dashboards-library.md). Under
`/api/console/v1/missions/:mission_id/dashboard-library`. Mission operators read; authors write.
Refetch on `invalidate` with `dashboards`.

- **D21** `GET /?q=&page=` → `{items: [{id, name, description, kind, latest_version,
  used_by_count, updated_at, updated_by {id, name} | null}], total, page, pages, page_size: 25,
  can_edit}`.
  - Sorted by name. Retired items are left out, and `q` matches name and description.
  - `kind` is the latest version's `widget_type_id` (read it tolerantly).
  - `used_by_count` counts active dashboards that place it (the retire rule).
- **D21** `GET /:item_id?version=n` → `{item: <list row without used_by_count>, version: {version,
  definition_json, summary, saved_at, saved_by}, versions: [{version, summary, saved_at,
  saved_by}] (newest first, ≤ 100), used_by: {dashboards: [{id, name, placements,
  pinned_versions}]}, can_edit}`. `version` defaults to the latest. A retired item is `404
  library_item_not_found`.
- **D22** writes. A viewer gets `403 forbidden` ("Dashboard editors manage the library.").
  - `POST / {name, description, definition_json, summary}` → `201 {id, version: 1}`.
  - `POST /:item_id/versions {definition_json, summary, expected_version}` → `{version}`.
  - `PATCH /:item_id {name?, description?, expected_version, expected_updated_at?}` → the D21 item.
  - `DELETE /:item_id?expected_version=n&expected_updated_at=…` → `204`.
  - `expected_updated_at` is the item's `updated_at` exactly as read (microseconds). A rename
    doesn't add a version, so send it to catch a stale rename or retire; a mismatch on either
    guard is `409 library_item_changed`. This **retires** the item: its versions stay
    for old dashboard versions. Audited ("Retired library widget Battery tile").
  - `409 library_item_changed {latest_version}` when it moved.
  - `409 library_item_in_use {used_by: {dashboards: [{id, name, placements, pinned_versions}]},
    consumer_count}` while an active dashboard places it.
  - `422 invalid_params` with `details.definition_json` (not a valid widget), `details.request`
    (bad name or shape) or `details.expected_version`.

- **D17** `GET /activity?before=` (operator) → `{events: [{id, kind, at, actor {id, name} | null,
  version, detail}], next}`: one feed, newest first, 25 per page; pass `next` back as `before`
  (opaque; `null` on the last page; `422 details.before` for a bad one). `kind` is the closed
  `saved | restored | archived | unarchived` for now. `detail` is the save's message, or "Restored
  from v9". Share, snapshot and export rows (`share_created | share_revoked | snapshot_taken |
  exported`) join with D14-D16, once domain projects their creator and time. A `published` or
  `reverted` lifecycle event repeats its version row (every save is current), so it isn't listed.
- **D18** `GET /diagnostics` (operator) → `{version, loaded_at, widgets: [{placement_id, title,
  status, sources: [{logical_source, status, status_code, cache, cache_status, severity, retryable,
  operator_action, warning_codes: [string], duration_ms, outcome, error}], warnings: [{code,
  severity, field_name, message}]}]}` for the **current** version (the `refresh` block was
  dropped after L8c, 4bc972bbe: nothing records invalidation decisions any more), widgets worst first. `status` (widget and source) is the
  closed set `ok | degraded | failed | not_run`; `status_code` keeps the engine's outcome
  (`cache_hit`, `source_degraded`, `skipped`, …) for Technical details. `cache` is `cached | fresh
  | null` (the tab's "From cache" / "Fresh"). `duration_ms`, `outcome`, `error` and warning
  `message` are `null`: the engine doesn't record them yet. `404 not_found` when the dashboard has
  no current version.
- **D19** `GET /export` (author) → the portable bundle as an attachment
  (`<name>.cadence-dashboard.json`); the deployment is recorded (`portable_json`) as before.
  `403 forbidden`, `404 not_found`. The legacy route goes with the legacy pages.
