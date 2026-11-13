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
  `201 {version, changed}`. Replays the commands on `base_version` and saves the next current
  version (`changed: false` and no new version when nothing changed). `message` defaults to the
  change labels. `defaults.time` / `defaults.scope` = "save the current range / spacecraft as
  the default", taken from `runtime`. `409 version_conflict` `details {current_version, saved_by
  {kind, id, name}, saved_at}` when someone saved since `base_version` (then D10).
  `422 dashboard_not_ready` `details.placements [{placement_id, code, message}]` when publish
  readiness fails (the list is empty until domain passes the report through).
- **D10** `POST /rebase {commands, runtime?}` → D7's body plus `{base_version (= current),
  applied: [commands], skipped: [{index, event, reason}]}`. Replays onto the newest version; keep
  `applied` as the new command list. `reason` is the authoring code (e.g. `missing_placement`:
  "widget removed").
- **D11** `POST /copy {name, base_version, commands}` → `201 {id, version: 1}`. A new dashboard
  from the staged document, so unsaved edits survive "Save as copy"; `commands: []` copies
  `base_version` as it is.
- **D12** `GET /versions` → `{current_version, versions: [{version, kind: create | save | revert |
  migration, based_on_version, saved_by {kind, id, name} | null, saved_at, message, current}]}`,
  newest first. `current_version` is `null` for a legacy dashboard never made current. A revert's
  `based_on_version` is the version it restored ("Restored from v9").
  `GET /versions/compare?from&to` → `{from, to, changes, from_json, to_json}`.
- **D13** `POST /versions/:version/restore {expected_version}` → `201 {version}`, a new current
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

## D4: `POST /dashboards {name, description?, tags?}` · `POST /dashboards/:id/duplicate {name}`

- `201 {id, version}`. `tags`: at most 10, each 1–64 characters. A spacecraft default and
  library templates come later (plan slice 8).
- Errors: `422 invalid_params` `details.field: "name"`, `403 forbidden` (not an author), `404
  not_found` (duplicating an unknown dashboard).

## D6: `POST /dashboards/:id/views`

`204`. Records that the viewer opened it, for `shortcuts.recent`. The viewer sends it once per
open, not on refresh. `404 not_found` for an unknown or archived dashboard.
