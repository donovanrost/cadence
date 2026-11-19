# Dashboards slice 5: Settings, Sharing, Activity, Diagnostics, Export (D14–D19 proposal)

fe-setup, 2026-11-13, for api (cc dashboards, lead). Spec: ux `screens/Dashboards.md` § Settings, § Snapshots
and shares, § Export. Plan: `plans/dashboards.md` data table (D14–D19), DECISIONS #76 (Q1, Q5).
All paths under `/api/console/v1/missions/:mission_id/dashboards/:dashboard_id`. Errors are the console
Problem envelope (`{error: {code, message, details}}`), never LiveView statuses.

## What exists (read of the domain, 2026-11-13)
- `Reads.Dashboards.Settings.load` (author only): name, description, tags, `defaults_json`, `document_version`,
  `revision` (lock), `published_version`, `lifecycle`, and paged `shares`, `snapshots`, `deployments` (25, asc).
- `SettingsAuthoring.execute`: `save_settings`, `create_share`, `create_snapshot`, `revoke_share`,
  `archive_dashboard`, each needing `expected_version` + `expected_revision`; errors `forbidden | invalid_input |
  conflict | unavailable`.
- `Management.create_share` (visibility `authorized_runtime_data | definition_only`, `expires_in_hours` 1–8760
  or never), `revoke_share`, `create_snapshot` (`frozen_time_window` only when the runtime context has from/to).
- `Activity.load` (operator): version rows (`draft_save | publish | revert | migration`, actor_id, saved_at,
  summary) and lifecycle events (`published, archived, restored, reverted, …`) without payloads.
- `ExecutionDiagnostics.load` (operator, published document): collections `plan, requests, frames, cache,
  source_execution` as key/value rows (`refresh` and `invalidation` went with L8c, 11-14). **No durations or per-request errors.**
- Export: `dashboard_export_controller.ex` (legacy path), records a `portable_json` deployment.

## Gaps the console needs closed
1. **Snapshot window (Q5):** `SettingsAuthoring` passes `%{}` as runtime context, so no snapshot is ever
   `frozen_time_window`. D16's snapshot must take the viewer's runtime.
2. **Rows lack who and what:** share rows have no `created_by`; snapshot rows have neither `created_by` nor the
   frozen window. Actor fields everywhere are ids; the console shows names.
3. **Q1:** settings save must go through `CurrentVersions.save` (a current version, `{version}`), like D9.
4. **Snapshot delete:** dropped (ux): snapshots are immutable and the list is read-only. Shared views need
   `:operate_mission` and the only access policy is `mission_member`, so nothing opens outside the mission.
5. **Diagnostics timing:** not recorded, so no numbers (ux, U20): one row per widget, worst first, status word
   (OK / DEGRADED / NOT RUN YET), cache (Fresh / From cache), the operator action as a sentence, warnings in
   words; codes, severity and retryable under Technical details.

## Proposed shapes

### D14 `GET /settings` (author)
```
{dashboard: {id, name, description, tags: [string], lifecycle: "active"|"archived",
             current_version, published_version|null, updated_at, updated_by {id, name}|null},
 defaults: {time: {mode: "relative", range: "now-6h"} | {mode: "absolute", from, to} | null,
            scope: {mode: "context"|"fixed"|"fleet", spacecraft_id|null} | null},
 limits: {name: 120, description: 500, tags: 32, tag: 64},
 shares:    {rows: [share], next: cursor|null},
 snapshots: {rows: [snapshot], next: cursor|null}}
share    = {id, url, data_visibility: "with_data"|"definition_only", state: "active"|"expired"|"revoked",
            expires_at|null, created_at, created_by {id, name}|null}
snapshot = {id, url, version, data_visibility, window: {from, to}|null, created_at, created_by {id, name}|null}
```
- `defaults` carries the values (not `defaults_json`). D9's `defaults` are booleans (save the current range/scope
  as the default), so the two are different shapes on purpose (dashboards). `url` is the console path of the shared
  view: `/console/:org/:mission/telemetry/dashboards/shares/:share_id` and `…/snapshots/:snapshot_id` (dashboards'
  routes `ops.dashboards.share` / `.snapshot`, D20).
- `data_visibility`: the wire uses `with_data` for the domain's `authorized_runtime_data` (or keep the domain
  word; say which).
- `?shares_after=` / `?snapshots_after=` page each table (25, newest first, please: the newest share is the one
  you just made).

### D15 `PATCH` (author): General save
```
→ {name, description, tags, defaults, expected_version}
← 200 {version}        409 version_conflict {current_version, saved_by {id, name}|null, saved_at}
                       422 invalid_params {details: {name|description|tags|defaults: message}}
```
- Through `CurrentVersions.save` (Q1), summary "Updated dashboard settings". `expected_revision` stays server-side
  (the console has no lock revision to send; map a lock conflict to the same 409).
- Archive stays **D3** (`POST /archive {confirm?}`, 409 `in_use` with `used_by.playlists` unless confirmed).

### D16 shares and snapshots (author)
```
POST   /shares    {data_visibility, expires_at|null}   ← 201 {share}
DELETE /shares/:share_id                               ← 200 {share} (state "revoked"); 409 share_not_active
POST   /snapshots {data_visibility, runtime: {from, to, spacecraft_id|null}}   ← 201 {snapshot}
```
- `expires_at` is a UTC date-time (the sheet picks a date); the server turns it into the domain's hours and
  rejects past or > 365 days (`422 details.expires_at`).
- The viewer's `Snapshot` posts its current range (absolute even when the viewer shows `now-6h`), so
  `create_snapshot` gets a runtime context with string from/to and stores `frozen_time_window` (Q5). Without
  from/to → 422 (`details.runtime`), never a silent definition-only snapshot.

### D17 `GET /activity?before=cursor` (operator)
```
{events: [{id, kind, at, actor {id, name}|null, version|null, detail|null}], next: cursor|null}
kind ∈ saved | restored | published | archived | unarchived | share_created | share_revoked |
       snapshot_taken | exported
```
- One feed, newest first, 25 per page, merged by the server from version rows (saved/restored), lifecycle events,
  shares, snapshots and deployments. `detail` is a short server sentence where useful ("Updated dashboard
  settings", "With data · expires 11-20", "portable_json").

### D18 `GET /diagnostics` (operator)
```
{version, loaded_at,
 widgets: [{placement_id, title, status: "ok"|"degraded"|"failed"|"planned",
            sources: [{logical_source, status, cache: "fresh"|"cached"|null, cache_status|null,
                       severity|null, retryable|null,
                       operator_action|null, warning_codes: [string],
                       duration_ms|null, outcome: "ok"|"timed_out"|"failed"|null, error|null}],
            warnings: [{code, severity, field_name|null, message|null}]}]}
```
- `cache` is the two-word verdict the tab shows (Fresh / From cache); `message` is the warning in words. The
  console doesn't map raw codes to words itself.
- No `refresh` block: nothing records invalidation decisions any more (L8c, live 11-14).
- Grouped by widget (ux: "so you can see which widget is slow or failing"), built from `plan`, `requests`,
  `source_execution` and `plan_warning`. `duration_ms` / `outcome` / `error` stay null until recorded (gap 5).

### D19 `GET /export` (author)
- The bundle as an attachment (`<slug>.cadence-dashboard.json`), recording the deployment as today. Errors as
  Problems (403/404), not text. The legacy route goes with the legacy pages.

### D20 shared views (dashboards builds them: the viewer without Edit)
- `GET /dashboard-shares/:share_id` and `GET /dashboard-snapshots/:snapshot_id` (operator): `SharedViews.load` as
  console reads, for the viewer's `SHARED · …` / `SNAPSHOT · …` headers.
- The viewer's `⋯ › Snapshot` calls fe-setup's `postSnapshot(missionId, dashboardId, runtime)` (settings/api.ts).

## Console (fe-setup)
- `features/dashboards/settings/` with its own `api.ts` readers; route `ops.dashboard.settings`
  `telemetry/dashboards/:dashboardId/settings/:tab?` (mode ops, nav telemetry), unrouted until D5 lands.
- Built against fixtures from these shapes until api ships; dashboards reviews the diff before each commit.
