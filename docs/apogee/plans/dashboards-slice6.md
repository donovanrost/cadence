# Dashboards slice 6: shared views, snapshots, playlists, present (D20, D23, D24 proposal)

Owner: dashboards. For: api (endpoints), domain (playlist update/delete, Q6; snapshot delete, queued by lead), cc
lead. Spec: ux `screens/Dashboards.md` §§ Snapshots and shares, Playlists and present. Plan: `plans/dashboards.md`;
DECISIONS #76 (Q5 frozen snapshot window, Q6 update/delete, Q10 delete rules + audit). Slice 5's rows
(`settings/api.ts` `shareRow` / `snapshotRow`, fe-setup) are reused, so each reader exists once.

## What exists (domain)
- **Shares / snapshots:** `SharedViews.load(scope, m, kind, id)` → `{kind, dashboard_id, data_visibility,
  data_semantics, created_at, expires_at, runtime_context, definition {name, description, version, placements,
  sections, json}, canvas}`. `canvas` (a `WorkspaceSnapshot`) only for `authorized_runtime_data`. Shares resolve the
  **current** version live (`:published`); snapshots resolve their stored document (`:draft_preview`).
- **Playlists:** `dashboard_playlists {name, description, dashboard_ids [], dwell_seconds (30), wallboard_mode,
  created_by, updated_by}`; `Playlists.directory/present`; `PlaylistAuthoring.create` only. **No update or delete**
  (Q6: add both).

## Paths
Top-level siblings, like the legacy URLs, so nothing collides with `/dashboards/:dashboard_id/*`:
`/missions/:m/dashboard-shares/:id`, `/missions/:m/dashboard-snapshots/:id`, `/missions/:m/dashboard-playlists[/:id]`.
Mission operators (`operate_mission`) read; `dashboard.author` writes playlists.

## D20 shared views (read)
```
GET /dashboard-shares/:share_id?from&to&spacecraft_id
GET /dashboard-snapshots/:snapshot_id
→ {kind: "share" | "snapshot",
   share: <D14 share row> | null,          // kind share
   snapshot_row: <D14 snapshot row> | null, // kind snapshot (window, version, created_by)
   dashboard: {id, name, description},
   definition: <Editor.outline, version 3>, // always: layout + titles, also for definition_only
   snapshot: <WorkspaceSnapshot> | null}    // null for definition_only
```
- `definition` uses the editor's outline shape, so a definition-only link still draws the grid. Each widget then
  says "Data isn't shared in this link." (ux).
- A share is live on the current version: the same runtime params as D5 and the same invalidations
  (`dashboards`, `telemetry`, `limits`, `alarms`, `events`).
- A snapshot is fixed: its stored document over its frozen window. It has no runtime params and nothing to
  refresh.
- **Errors:**
  - 404 `not_found` (unknown or other mission);
  - 404 `share_revoked` / `share_expired`, whose **message** is the sentence the page shows, e.g. "Revoked by Mira K.
    at 11-14 02:10Z." / "Expired 11-20 00:00Z.". The console's 404 keeps code and message only, no details;
  - 404 `snapshot_deleted` (Q6 final, lead 11-14): `details {deleted_by, deleted_at}`, and the **message** is the
    sentence the page shows, as with the share codes (a 410 would read as a retryable `unavailable`);
  - 503 `dashboard_unavailable`.
- **Snapshot delete** (lead queued it with domain): `DELETE /dashboards/:id/snapshots/:snapshot_id` → 204. It's
  audited ("Deleted snapshot of <dashboard>"). It belongs with fe-setup's Sharing tab (D16), but is listed here so the
  shape is agreed once. Domain keeps a tombstone (`deleted_at/by`), so the old link reads `snapshot_deleted`. Shares
  never point at snapshots, so there's nothing to revoke.

## D23 playlists (read)
```
GET /dashboard-playlists?q
→ {playlists: [{id, name, description, dwell_seconds, wallboard_mode, dashboard_count,
                updated_at, updated_by {id, name} | null}], can_edit}
GET /dashboard-playlists/:playlist_id
→ {playlist: {id, name, description, dwell_seconds, wallboard_mode, updated_at,
              dashboards: [{id, name, archived}]}}   // in playlist order; archived ones kept and flagged
```
- **Present mode needs no endpoint of its own.** The console walks `playlist.dashboards`, skips archived ones and
  says so (Q10), and reads each dashboard through **D5**. That gives the same snapshot, decoders and live path as
  the viewer. So `Playlists.present` isn't wrapped.
- The editor's dashboard picker reuses **D1** (`?q`).
- Invalidation: playlist changes fire `dashboards` (no new resource).

## D24 playlists (write, `dashboard.author`)
```
POST   /dashboard-playlists      {name, description?, dwell_seconds, wallboard_mode, dashboard_ids}  → 201 {id}
PATCH  /dashboard-playlists/:id  {name, description?, dwell_seconds, wallboard_mode, dashboard_ids}  → 200 {id}
DELETE /dashboard-playlists/:id                                                                       → 204
```
- **Validation (422 `invalid_params`, `details.field`):** `name` 1–120; `dwell_seconds` 10–3600; `dashboard_ids` 1–50,
  unique, and each a dashboard of this mission. Archived dashboards are allowed, since present skips them.
- **Stale edit (Q6 final):** PATCH carries `expected_updated_at` (the row's `updated_at`, microsecond precision);
  a stale one is `409 version_conflict` with `details {current}` (the current playlist row). The sheet offers
  reload-and-reapply.
- **Deleted while presenting:** the next D23 read is `404 playlist_not_found`; present mode says "This playlist
  was deleted." with a way back to Playlists.
- **Delete (Q10):** a hard delete after the console's confirm; nothing references a playlist. It's audited (`config`
  kind): "Deleted playlist Ops wall". Create and update are audited too: "Created / Updated playlist …".
- **New domain functions (Q6):** `PlaylistAuthoring.update/4` and `PlaylistAuthoring.delete/3`, with
  `PlaylistStore` lookups for D3's `used_by.playlists` (api-ops asked for that one).

## Console (dashboards)
| Route | Screen |
| --- | --- |
| `M/telemetry/dashboards/shares/:shareId` · `ops.dashboards.share` | takeover; header `SHARED · live · expires 11-20` (or `no expiry`), the viewer grid, no Edit. Revoked/expired: an empty state saying which and when |
| `M/telemetry/dashboards/snapshots/:snapshotId` · `ops.dashboards.snapshot` | takeover; header `SNAPSHOT · 11-12 21:00Z–23:00Z · v7 · taken by Mira K. at 23:02Z`, no range picker, no live data |
| `M/telemetry/dashboards/playlists` · `ops.dashboards.playlists` | reading page: ApTable Name · Dashboards · Dwell · Updated · `Present`; editor in a wide ApSheet (name, dwell, wallboard, ordered list with add / ↑ ↓ / remove); Delete confirms |
| `M/telemetry/dashboards/playlists/:playlistId/present` · `ops.dashboards.present` | takeover, kiosk by default: 24px line `PLAYLIST · Ops wall · 2 of 5 · next in 0:18` + health + UTC; ←/→, Space pauses (`PAUSED`), Esc leaves; a dashboard that fails shows its error for one dwell and moves on |

Built against fixtures from these shapes until api ships, unrouted until the endpoints land.
