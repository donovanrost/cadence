# Dashboards plan (L8)

Owner: dashboards (w0R:pG). Status: approved (lead), draft 3, 2026-11-13: DECISIONS #76 rulings, Q10, kit answers. Routing: BACKLOG §11e. Reports to lead; scope questions go to the director.
Binding inputs: DECISIONS #75 (reverses #11), `briefs/dashboards.md` (the user's 2026-10-08 product decisions),
ux `screens/Dashboards.md` (aed431cb). Missing server pieces are numbered **D1…** (endpoints) and **C1…**
(channel) and collected in the [ask list](#ask-list-for-api--api-ops-via-lead). Questions are in [Open questions](#open-questions).

## Rulings (director, 2026-11-13)

- **Q1:** settings save and library add-to-draft go through `CurrentVersions`, so every save is current. This is a
  domain fix, routed by lead.
- **Q2:** same-browser autosave for now. Keep the `{base_version, commands}` shape so a server-held draft can come
  later.
- **Q5:** a snapshot taken from the viewer freezes the current time window (`frozen_time_window`), so it shows
  what you saw. ux has the final say on presentation.
- **Q6:** add update and delete for playlists and library items. Delete must say where the item is used and refuse
  or warn instead of leaving dangling references. My proposal is in [Delete and references](#delete-and-references).
- **Q10 confirmed** as proposed (Delete and references). Addition: **retire, delete and archive are recorded in
  the audit log** like other config changes (see below).
- Start slice 1 once lead has routed the endpoints (done: BACKLOG §11e). Build it against fixtures until D5 lands.

## What exists today (inventory, 2026-11-13)

**Every dashboard page is LiveView-only.** There's no dashboard JSON endpoint anywhere (`/api/v1` has
none), and the application-host bridge returns real data only for directory and new. Everything goes through
`HostPageLive` `host:ops-page` events with a per-page `sequence`. The only plain route is the export download
(`DashboardExportController`).

| Area | Server today | Notes for the console |
| --- | --- | --- |
| Document | `Dashboards.Document` (schema 1): name, description, `defaults` (time, scope, data, limits), `grid` (12 cols, 64px rows, 8px gap), `sections`, `placements` (layout x/y/w/h, embedded `widget_def` or `library` ref, overrides, repeat), tags in `metadata` | Seven widget kinds: `value_tile`, `time_series`, `status_matrix`, `data_table`, `state_timeline`, `event_timeline`, `constellation_health`. Binding mode `context` / `fixed` / `scope` / `repeat` (constellation is a widget kind, not a mode) |
| Resolve | `Reads.Dashboards.DashboardPage.load/4` → `Workspace` → `Engine.resolve_hydrated`: plans source requests per placement, batches identical ones, runs adapters (4 concurrent, 5 s timeout, circuit breaker), materializes frames. ETS `RuntimeCache` keyed by watermarks | One snapshot per resolve: `{context, sections, grid, placements[{id, layout, status, widget, frames[], annotations[], warnings[]}]}`. Frames are columnar (`fields[{name, kind, unit, values[]}]`, ≤10k values). Time series come back as a decimated min/max/mean envelope at about pixel width |
| Runtime URL | `OpsWorkspaceURL.admit`: `from=now-6h&to=now` → live window (**capped at 24 h**), absolute → archive (≤31 d), one `spacecraft` in scope | The viewer keeps these query params |
| Save model | `AuthoringDraft` (**held in the LiveView process**): baseline document + staged `commands` + per-draft `revision`. `stage/4` applies pure `AuthoringChanges.apply/3`; `save/3` → `CurrentVersions.save` with `expected_version`; `rebase/2` replays commands onto the newest version and returns `skipped`; `discard/3` | Grafana-style is **already built** on the server: every save is current (`CurrentVersions.create/save/restore`), readiness runs at save (`PublishReadiness`, rolls back on failure), optimistic lock on `latest_version` and `lock_version`, restore = new version (`based_on_version`), `VersionDiff.changes/2` labels, `Versions.list/compare/staged` |
| Live (viewer) | Timer only: every `refresh_ms` (default 2 s, 1–60 s) the LiveView re-resolves **the whole dashboard** and LiveVue diffs the props. No PubSub in view mode | Engine has unused `:live_tick` / `:stream_append` modes and two pure, caller-less helpers (`RuntimeCoordinator`, `RuntimeInvalidationRelevance`). **No real appends exist**: the chart's `append` port is only fed by Storybook |
| Live (editor) | Subscribes to `RuntimeInvalidation` for the dashboard (250 ms coalesce) to raise "changed by another session" | The console `mission:<id>` channel already maps `dashboard_version_changed` / `dashboards_changed` to `invalidate {resources: ["dashboards"]}` |
| Directory | `Reads.Dashboards.Directory.load` (query, tags, starred, archived, sort, page; shortcuts starred/recent), `DirectoryActions` star / archive / restore / duplicate | Recent comes from `record_dashboard_view` on open |
| Create | `Dashboards.Creation.create/4` (new, import JSON, clone) → `CurrentVersions.create` | |
| Settings | `Reads.Dashboards.Settings.load`; `SettingsAuthoring.execute/5`: save_settings, archive, create/revoke share, create snapshot (all need `expected_version` + `expected_revision`) | **`save_settings` bypasses `CurrentVersions`** (calls `Documents.update`, advances `latest_version` without making it current). So does the library's `add_to_draft` |
| Activity / diagnostics | `Reads.Dashboards.Activity.load` (read-only history + lifecycle events); `ExecutionDiagnostics.load` | |
| Shares / snapshots | `dashboard_shares` (mission-member link, `definition_only` or `authorized_runtime_data`, expiry, revoke); `dashboard_snapshots` (copy of the document at a version + runtime context). `SharedViews.load` | Shares aren't public links. In practice snapshots are always "definition at version, current data": settings creates them with an empty runtime context |
| Library | `Reads.Dashboards.Library.load`; `LibraryAuthoring` create item, add version, add to draft | No update or delete |
| Playlists | `Playlists.directory/present`; `PlaylistAuthoring.create` | **Create only**: no update or delete anywhere |
| Export | `GET /missions/:m/ops/dashboards/:id/export` (browser cookie): `export_bundle` + `record_deployment` | |
| Explore | `/ops/explore` = `ExplorationSnapshot` (canned questions, L20 parked) | Out of scope: the console's Telemetry Explore is fe-ops's screen |
| Authorization | `:author_dashboards` → today just `:operate_mission` (`auth/policy.ex:153`) | The session bootstrap has **no dashboard capability**, so the SPA can't hide Edit honestly (D0) |

**Frontend** (`frontend/modules/dashboards-and-exploration`). It never imports LiveVue: every page is an
`OpsPageContribution` that talks to an abstract `port.execute(action, input)`. The Oct 2026 overhaul
(`features/dashboard/*`) already implements edit in place, the Save drawer, the Versions sheet and Continue/Discard
on top of the server-held draft.

## Reuse vs rewrite

The module is frozen with the legacy pages (DECISIONS #75) and gets deleted with them. So I **port** code into the
console instead of depending on the module. That means no `@cadence/ui` or `@cadence/plugin-sdk` in the console,
no drift (the legacy copy only gets bug fixes), and the module dies cleanly at cutover. Each ported file names its
source path and commit in its header comment.

| Bucket | Files (module `src/features/…`) | Into the console |
| --- | --- | --- |
| **Port as-is (pure TS)** | `workspace/chart-*.ts` (uPlot engine: model, points, input, plot, surface, limits, annotations, events, legend, selection, live, controller, runtime port), `snapshot-series.ts`, `dashboard/time-range.ts`, `json-diff.ts`, `widget-form.ts`, `widget-data.ts`, `inspect-data.ts`, `runtime-defaults.ts`, `board-grid.ts` (GridStack wrapper, debounced `LayoutEdit[]`) | `features/dashboards/chart/**`, `features/dashboards/model/**`. Three chart files are over the 400-line limit (`chart-events.ts` 689, `chart-model.ts` 652, `chart-annotations.ts` 497) and get split while porting. `record()` from plugin-sdk is replaced by `@/api` decoders |
| **Port with edits** | `TelemetryChart.vue`, the six widget components + `WidgetBody.vue` (Tailwind only, no `@cadence/ui`), `useDashboardPage.ts` (logic only, re-pointed at a console port) | Restyled in Apogee: each widget sits in an `ApPanel`. Snake_case props are renamed |
| **Rewrite in Apogee** | Page chrome, header, toolbar, sheets, editors, Save drawer, Versions sheet, directory, settings, library, playlists, shared views | Composed from `@/ui` (`ApTakeoverHeader`, `ApSheet`, `ApTable`, `ApPanel`, `ApTimePicker`, `ApCallout`, `ApSegmented`, `ApField`, …) |
| **Rewrite as decoders** | `workspace/validation.ts`, `dashboard/validation.ts` | `features/dashboards/api.ts` readers (`@/api` decoders, one shape definition per response), checked for identity/scope/version like the originals |
| **Drop** | `DashboardGrid.vue`, `DashboardCanvas.vue`, `snapshot-presentation.ts`, `snapshot-widgets.ts` (legacy daisy class trees), `Dashboard*Widget*` shells (CadencePopover), all `*LegacyRedirect.vue`, `OpsDashboardShow`, `shared/legacy-destination.ts`, the outline / "apply to candidate" flow | — |

- **New console dependencies:** `uplot` 1.6.32 and `gridstack` 10.3.1 (the versions the module pins). Lead approves
  (K1). Their CSS is imported by the dashboards feature only, so other screens don't pay for it (lazy route chunk).
- **Chart tokens:** `chart-surface.ts` throws if any of its ~83 `--chart-*` variables is missing. Today they live in
  `packages/design-tokens/src/charts.css`, which the console doesn't load. I'll ask ux to map them to Apogee
  values, defined in a dashboards-scoped stylesheet or `apogee-ui` tokens (lead decides where, K2). Series colours
  never use status hues (OpsLists rule).
- **uPlot, not `ApTimeSeries`:** dashboards need up to 8 series, ~1200-bucket envelopes, many charts per screen and
  future appends. `ApTimeSeries` (SVG, ~400 points) stays the Investigate chart. The two should look alike
  (Q3, ux).
- The Phoenix producer checks (`producer-*-check.mjs`, run by ExUnit) pin the legacy DTOs. The console gets
  equivalent fixture tests on its decoders. The legacy checks go when the legacy pages are deleted.

## Route map (console)

Ops mode, `nav: "telemetry"`. Base `M` = `/console/:org/:mission`.

| Route | Name | Mode | Screen |
| --- | --- | --- | --- |
| `M/telemetry/dashboards` | `ops.dashboards` (kept) | ops | **Directory**: Telemetry header with `Explore · Dashboards` tabs (`ApTabLinks`), search, tag filter, starred/recent shortcuts, `ApTable` (Name link · Tags/Folder · Bound to · Updated by/when), row `⋯` (Star, Duplicate, Archive/Restore, Settings, Export), primary `New dashboard`. Archived toggle |
| `M/telemetry/dashboards/new` | `ops.dashboards.new` | ops | **New**: a small focused page: name, description, or import JSON. Clone arrives as `?from=:id` |
| `M/telemetry/dashboards/:id` | `ops.dashboard` | takeover | **Viewer** (ux spec). Query: `from`, `to`, `spacecraft`, `refresh`, `kiosk=1`, `edit=1`. `⋯` holds Versions (sheet), Share, Snapshot, Save as copy, Export, Kiosk, Settings, Diagnostics |
| `M/telemetry/dashboards/:id/edit` | — | — | Redirect → viewer `?edit=1` (user decision) |
| `M/telemetry/dashboards/:id/settings/:tab?` | `ops.dashboard.settings` | ops | **Settings**: tabs General (name, description, tags, defaults), Sharing (shares + snapshots), Activity, Diagnostics |
| `M/telemetry/dashboards/library` | `ops.dashboards.library` | ops | **Library** of reusable widgets |
| `M/telemetry/dashboards/playlists` | `ops.dashboards.playlists` | ops | **Playlists** directory + editor |
| `M/telemetry/dashboards/playlists/:pid/present` | `ops.dashboards.present` | takeover | Rotating kiosk presentation |
| `M/telemetry/dashboards/shares/:shareId`, `…/snapshots/:snapshotId` | `ops.dashboards.share`, `.snapshot` | takeover | Read-only shared view (viewer without Edit) |

- Today `ops.dashboards` takes an optional `:dashboardId` and three fe-ops callers use it (`TelemetryScreen.vue`,
  `investigate/telemetry/TelemetryTab.vue`, `timeline/model.ts`). I keep the name for the directory and add a
  redirect (`ops.dashboards` with an id → `ops.dashboard`), then ask fe-ops to switch the callers. The `Explore ·
  Dashboards` tab strip also goes into fe-ops's `TelemetryScreen` (coordinated with fe-ops).
- **Cutover:** when a slice reaches parity, Phoenix redirects the matching legacy `/missions/:m/ops/dashboards/**`
  route to its console URL (api), and the legacy page and its module feature are deleted (BACKLOG §11 row by row).
- Feature dir: `frontend/apps/console/src/features/dashboards/{api,model,chart,widgets,viewer,editor,versions,directory,settings,library,playlists,shared}`.

## Data per screen

Base `/api/v1/missions/:m/dashboards`. Session JSON, the console error envelope, `operation`-free
(dashboard writes are synchronous and idempotent on `expected_version`). All endpoints wrap the existing domain
functions named above. Nothing is reimplemented.

| Screen | Read | Writes | Today |
| --- | --- | --- | --- |
| Directory | **D1** `GET /dashboards?q&tags&starred&archived&sort&page` → rows `{id, name, description, tags, starred, archived, binding_summary, current_version, updated_at, updated_by}`, `available_tags`, `shortcuts {starred, recent}`, paging | **D2** `PUT/DELETE /:id/star`; **D3** `POST /:id/archive` (409 `used_by` unless `confirm: true`, see below), `POST /:id/restore` | LiveView only (`Directory.load`, `DirectoryActions`). `binding_summary` ("Bound to") is missing: derive from defaults + placements (context / fixed SC / constellation) |
| New | — | **D4** `POST /dashboards {name, description, document_json?}` (new/import), `POST /:id/duplicate {name}` → `{id, version}` | LiveView only (`Creation.create`, `clone_document`) |
| Viewer | **D5** `GET /:id?from&to&spacecraft_id` → `{dashboard {id, name, description, tags, current_version, updated_at, updated_by}, can_edit, scope_options, runtime {time, scope, refresh_ms}, snapshot, resolved_at}`; **D6** `POST /:id/views` (recent; fire-and-forget) | — | LiveView only (`DashboardPage.load/4`) |
| Editor | **D7** `POST /:id/preview {base_version, commands[], runtime}` → `{snapshot, changes[], outline, current_version}`, or 422 `{index, code, field}` for the first bad command; **D8** `GET /observables?q&source&spacecraft_id` (binding picker) | **D9** `POST /:id/save {base_version, commands[], message?, defaults {time?, scope?}, runtime}` → `{version}`, 409 `{current_version, saved_by, saved_at}`, 422 readiness failures; **D10** `POST /:id/rebase {base_version, commands[]}` → `{base_version, applied[], skipped[{index, event, reason}]}` + preview payload; **D11** `POST /:id/copy {name, base_version, commands[]}` | Domain exists (`AuthoringChanges`, `AuthoringDraft.replay/save/rebase`, `ObservableChoices.staged`, `copy_for_scope`); needs a stateless entry point (see save model) |
| Versions sheet | **D12** `GET /:id/versions`, `GET /:id/versions/compare?from&to` (`{changes, from_json, to_json}`); staged compare comes from D7 | **D13** `POST /:id/restore {version, expected_version}` | LiveView only (`Versions.*`, `CurrentVersions.restore`) |
| Settings › General | **D14** `GET /:id/settings` | **D15** `PATCH /:id {name, description, tags, defaults, expected_version}`. **Must create a current version** via `CurrentVersions.save` (fixes today's bypass, Q1) | LiveView only |
| Settings › Sharing | in D14 (`shares`, `snapshots`) | **D16** `POST /:id/shares {data_visibility, expires_at?}`, `DELETE /:id/shares/:sid`, `POST /:id/snapshots {runtime}` | LiveView only. A snapshot from the viewer posts the current range, so it's `frozen_time_window` (Q5 ruling) |
| Settings › Activity | **D17** `GET /:id/activity` (lifecycle events: saves, restores, archive, shares, exports) | — | LiveView only (`Activity.load`) |
| Settings › Diagnostics | **D18** `GET /:id/diagnostics` | — | LiveView only (`ExecutionDiagnostics.load`) |
| Export | **D19** `GET /:id/export` (attachment, records the deployment) under the console scope | — | Plain controller exists at the legacy path; move it so the legacy router entries can go |
| Shared view | **D20** `GET /shares/:sid?from&to`, `GET /snapshots/:sid` → `{kind, dashboard_id, data_visibility, data_semantics, expires_at, definition, snapshot}` | — | LiveView only (`SharedViews.load`) |
| Library | **D21** `GET /library?q`, `GET /library/:item` (versions, widget JSON) | **D22** `POST /library`, `POST /library/:item/versions`, `PATCH /library/:item {name, description}`, `DELETE /library/:item` (see below). "Add to dashboard" becomes an editor command (`add_widget` from a library ref, staged and saved like any edit) | LiveView only. Update/delete are **new** domain functions (Q6 ruling) |
| Playlists | **D23** `GET /playlists`, `GET /playlists/:pid/present?index` | **D24** `POST /playlists`, `PATCH /playlists/:pid {name, description, dwell_seconds, wallboard_mode, dashboard_ids}`, `DELETE /playlists/:pid` | LiveView only. Update/delete are **new** domain functions (Q6 ruling) |
| Capability | **D0** dashboard authoring capability in the session bootstrap (`dashboard.author` per organization, from the `:author_dashboards` policy, like `command.*`) | — | Missing. Until it lands, `can_edit` on D5 gates Edit |

## Save, version and conflict model

The user's model (every save is current, versions with compare and non-destructive restore, conflict
Continue/Discard) is **already what the server does**. One piece doesn't survive the move from LiveView: the draft
lives in the LiveView process. My proposal is to make the edit session **stateless on the server and owned by the
browser**:

- **The client owns the draft:** `{dashboard_id, base_version, commands[]}`. A command is the same
  `{event, input}` the LiveView stages today (`rename`, `add_section`, `update_section`, `remove_section`,
  `move_section`, `add_widget`, `update_widget`, `remove_widget`, `layout`, `runtime_defaults`). This is exactly
  `AuthoringDraft.commands`, so no new vocabulary.
- **Autosave:** the draft is written to `localStorage` per dashboard after every staged edit. It's decoded on read
  and discarded if malformed. Reopening the dashboard with a stored draft offers "Resume your unsaved edits (N
  changes, based on v12)". This covers reloads and crashes on the same browser. It doesn't move drafts between
  devices (Q2).
- **Each edit:** the client appends the command and calls **D7 preview**. The server opens the document at
  `base_version`, replays the commands through `AuthoringChanges.apply` (the same path as `rebase/replay` today),
  resolves the staged document with **live data paused** (ux: "Live values paused while editing"), and returns the
  staged snapshot + `changes` (VersionDiff labels for the Save drawer) + `current_version`. Layout drags send one
  coalesced `layout` command per gesture (`board-grid.ts` already debounces 400 ms). If the server rejects a
  command, the client drops it and shows the error in the widget sheet.
- **Save (D9):** the server replays the commands onto `base_version` and calls `CurrentVersions.save(…,
  expected_version: base_version, change_summary: message || labels)`. With "save current range and scope as
  default", it appends `runtime_defaults` built from the posted `runtime`, as `actions.ex` does today. Readiness
  runs inside the transaction: a 422 lists the failing placements, and the editor marks them. Success clears the
  stored draft and leaves edit mode on the new version.
- **Concurrent edit:**
  - While editing, the client listens to the mission `invalidate` for `dashboards`, then re-reads `current_version`
    (D5 header fields, or `current_version` from the next preview).
  - When `current_version > base_version`, it shows ux's callout: "Saved by Mira K. at 02:51Z while you were
    editing." `saved_by` / `saved_at` come from D12's newest row.
  - **Continue editing:** D10 rebase replays the commands onto the newest version and returns `applied` and
    `skipped`. The client adopts `base_version = current` and `commands = applied`, and lists the skipped ones in
    the callout ("2 edits no longer apply: Update widget 'Bus voltage' (widget removed)").
  - **Discard mine:** clears the draft and reloads the current version.
  - A save that loses the race gets 409 and goes through the same callout.
- **Restore (D13)** creates a new current version (`snapshot_kind :revert`). It is offered from the Versions sheet
  outside edit mode only. Compare uses D12 with the ported `json-diff.ts`.
- **Why stateless:** there's no new table, no orphaned server drafts, and no sticky process. Replay is pure and
  cheap next to the resolve, and it's the code path rebase already trusts. The cost is that each preview resends
  the command list (bounded: 1024 placements, so a few hundred commands at most). If drafts must follow the user
  across devices (Q2), the same `{base_version, commands}` moves into a per-user draft row with no client change
  besides where it's stored.
- **Two writes that broke "every save is current":** settings save and library add-to-draft. Per the Q1 ruling the
  domain functions themselves go through `CurrentVersions` (domain fix, lead routes). The console also sends
  settings through D15 and library inserts as editor commands.

## Delete and references

A proposal for the Q6 ruling. The rule: **refuse when deleting would break something people rely on now; warn
when the reference degrades honestly.**

| Delete | Referenced by | Behaviour |
| --- | --- | --- |
| Library item | Placements in dashboards (`library_widget_id` + `library_version`) | **Refuse while any dashboard's current version uses it.** 409 `{used_by: {dashboards: [{id, name, placements: n}]}}`. The sheet lists them as links ("Used by 3 dashboards: Bus overview, …"). You replace or detach the widget there first; detaching copies it in as an embedded widget (a normal editor command). Once unused, delete **retires** the item: it's hidden from the library, and its versions stay stored, so older dashboard versions still render and restore. Never a hard delete |
| Playlist | Nothing in the model (only URLs and kiosks) | Hard delete after a confirm that names it. A kiosk presenting it shows "This playlist was deleted." on its next advance |
| Dashboard (archive) | Playlists | **Warn, don't refuse.** D3 returns 409 `{used_by: {playlists: [{id, name}]}}` unless `confirm: true`; the dialog lists them. Present mode skips archived dashboards and says so on the slide counter ("1 archived dashboard skipped"). Restore puts it back in rotation. Shares and snapshots of an archived dashboard keep working (snapshots are copies; shares say "archived") |
| Dashboard version | — | Versions are never deleted (restore is a new version) |

`used_by` is computed server-side over current versions (library) or playlist rows (dashboards). It's the same
shape on every 409, so the client renders one "Used by" list.

**Retired library items (as built, domain dd757dae0 / a594da7ec; qa 11-14):**
- **What counts as use:** only active dashboards' current versions. An archived dashboard doesn't block a retire.
  The item page's "Used in" and the retire check use the same rule.
- **New references are refused:** `CurrentVersions.save` and `create` run `LibraryLifecycle.live_items`, so an
  edit that places a retired item is refused with field `library_item_id`. The editor reads "That library widget
  was retired or removed. Remove it from this dashboard to save." A retire that races a save comes back with a
  null command index.
- **Restore is exempt by design (domain 11-14):** `CurrentVersions.restore` copies a stored version as it was,
  so Versions keeps working for any dashboard whose history placed a retired item. Unarchiving a dashboard is
  exempt too. The restored version renders from the stored library version, and its next edit and save is
  refused until the placement is removed.
- **The editor says so up front (lead 11-14):** in edit mode, a board that places a retired library item shows
  the save refusal's sentence as a caution callout ("That library widget was retired or removed. Remove it from
  this dashboard to save."), so the author learns before Save. It needs a signal: the editor outline (`Reads.
  Dashboards.Editor.outline`) gives library placements only `editable: false`. Asked: each library placement
  gains `library: {item_id, version, retired: boolean}`.

**Audit (director):** library retire, playlist delete and dashboard archive/restore each write an audit record. They
appear in `GET /audit` (setup.md AU1) under kind `config` as server-made sentences, e.g. "Archived dashboard Bus
overview", "Retired library widget Battery tile", "Deleted playlist Night shift wall". Each sentence carries the
actor, a `target {kind: dashboard | library_item | playlist, id, label}` and the mission. Dashboard saves and restores
are already versioned, so whether they also appear in `/audit` is api's call (consistent with config revisions,
which do).

## Live data over the Channel

The user's rule is server push, never client polling. Today's legacy viewer re-resolves every 2 s per viewer. I
propose two steps. The first ships on what exists; the second is the real push.

**Step 1 (slice 2): invalidation-driven refresh, no new server code.**
- The viewer listens to `invalidate` on `mission:<id>` (`useMissionInvalidation`) for `telemetry`, `limits`,
  `alarms`, `events` and `dashboards`, and refetches D5 for the current range and scope.
- The refetch is coalesced to the refresh interval (header control: off, 1 s, 2 s, 5 s, 10 s, 30 s, 1 m; default
  from `runtime.refresh_ms`).
- `useRemoteQuery` drops stale responses and keeps the last snapshot on screen.
- No refetch happens without an invalidation, so a quiet mission costs nothing. A frozen absolute range ignores
  `telemetry`.
- Socket not `live` → the stale callout and stale tint (connection-lost rule). Reconnect → immediate refetch.
- This matches what the other console screens do (`useSeries` in Telemetry). Per-viewer cost is the same as
  legacy at worst, and lower on quiet missions.

**Step 2 (slice 7): topic `dashboard:<mission_id>:<dashboard_id>` (C1).**
- The client joins with `{runtime: {from, to, spacecraft_id}, refresh_ms}` and sends `runtime:set` when the range
  or scope changes.
- The server process subscribes to the dashboard's `RuntimeInvalidation`. It filters with the existing
  `RuntimeInvalidationRelevance`, re-executes only the affected requests (`resolve_mode: :live_tick`, which
  exists but is unused), and pushes `placements {seq, full, version, placements: [changed placements only]}`.
- A `version` event fires when the dashboard is saved elsewhere, so the editor learns it without a REST round
  trip.
- The `seq` and full-snapshot rules are the same as `fleet` and `command_group`.
- Viewers with the same `(dashboard, version, runtime)` can share one resolver (`RuntimeCoordinator` exists for
  backpressure). That's api's call.

**Step 3 (later, C2): time-series appends.** Pushes carry new buckets for `time_series` placements instead of the
whole frame. The client feeds them to the ported chart through its existing `append` port (`chart-controller.ts`
already merges by placement id and trims to the window). This needs `:stream_append` server-side. I'd only take it
if step 2's payload size proves to be a problem.

Edit mode never runs live values. It listens only for `dashboards` (step 1) or the `version` event (step 2).
Kiosk and playlists use the same path as the viewer.

## Build order (each slice ships something usable)

| # | Slice | Needs | Ships |
| --- | --- | --- | --- |
| 1 | **Read-only viewer**: takeover header (×, context, title, scope selector with `[`/`]`, ApTimePicker range, `⋯`), ported chart engine + six widgets in ApPanels, grid via `board-grid.ts` static, Inspect sheet (data table + CSV from `inspect-data.ts`), phone single column, empty state | D5, D0 (or `can_edit`), K1, K2 | Dashboards open in the console; `DashboardsRedirect` stops leaving for the viewer |
| 2 | **Live + directory**: step-1 live, refresh control, kiosk (`?kiosk=1`, 24px status line, Esc), directory page with tabs, star/archive/restore/duplicate, New page | D1–D4, D6 | Telemetry › Dashboards is fully in the console for viewing. Legacy directory + viewer redirect here |
| 3 | **Edit in place**: Edit toggle, unlocked grid, widget sheet (binding/display fields from `widget-form.ts`), sections, add/remove widget, rename, autosave draft + resume, Save drawer (message, change list, defaults opt-in), Discard | D7, D8, D9, K3 | Authors stop needing the legacy page |
| 4 | **Versions + conflict**: Versions sheet (list, compare, restore), "saved by someone else" callout with Continue/Discard and the skipped list, Save as copy | D10–D13 | Grafana-style history complete |
| 5 | **Settings**: General, Sharing (shares + snapshots), Activity, Diagnostics tabs; Export | D14–D19 | Settings/activity/diagnostics/export legacy pages deletable |
| 6 | **Shared views + playlists**: share and snapshot takeovers, playlist directory/editor, present mode | D20, D23, D24 | Shares, snapshots, playlists legacy pages deletable |
| 7 | **Channel push** (step 2) | C1 | Viewers get placement deltas; the D5 refetch loop goes |
| 8 | **Library** | D21, D22 | Last legacy dashboard page deleted; `modules/dashboards-and-exploration` dashboard features + producer checks removed (with lead) |

Slices 1–2 can start as soon as D5 exists. Until D5 lands I build slice 1 against decoded fixtures taken from the
existing `WorkspaceSnapshot` test support, so the UI is ready when the endpoint is.

## Ask list for api / api-ops (via lead)

Priority order. Each one wraps an existing domain function unless marked **new**.

1. **D5** viewer read (`DashboardPage.load/4` + `OpsWorkspaceURL` admission) and **D0** `dashboard.author`
   capability in the session.
2. **D1–D4, D6** directory, star, archive/restore, create/import/duplicate, record view. `binding_summary` is
   **new** (derived).
3. **D7, D9, D8** preview, save, observable search: a **new stateless entry** over `AuthoringDraft`
   (open-at-version + `replay`), see the save model.
4. **D10–D13** rebase, copy, versions list/compare, restore.
5. **D14–D19** settings, shares, snapshots, activity, diagnostics, export. **Domain fix** (Q1 ruling): settings
   save and library add-to-draft go through `CurrentVersions`. Snapshots take a posted runtime (Q5).
6. **D20–D24** shared views, playlists, library (+ audit records for retire, delete, archive). Update/delete for playlists and library items are **new** domain
   functions (Q6 ruling), with `used_by` and retire-not-delete for library items (see Delete and references).
   D3 archive returns `used_by.playlists`.
7. **C1** `dashboard:<m>:<d>` channel (step 2). C2 appends only if needed.
8. Legacy route redirects to console URLs at each cutover.

## D5 proposed shape (for api-ops)

`GET /api/v1/missions/:m/dashboards/:id?from&to&spacecraft_id` wraps `Reads.Dashboards.DashboardPage.load/4`
with the runtime admitted by `OpsWorkspaceURL` (same `from`/`to` grammar: `now-6h` … `now`, or ISO bounds).

```json
{"data": {
  "dashboard": {"id": "…", "name": "Bus overview", "description": null, "tags": ["power"],
                "current_version": 12, "updated_at": "2026-11-13T02:51:00Z"},
  "can_edit": true,
  "scope_options": [{"id": "spacecraft-earendil-312", "name": "EARENDIL-312"}],
  "snapshot": <WorkspaceSnapshot.build/4 map, unchanged (version 1)> | null,
  "resolved_at": "2026-11-13T02:52:10Z"}}
```

- `snapshot` is passed through unchanged (`Reads.Dashboards.WorkspaceSnapshot`, `WorkspaceFrame`), so the console
  decoder mirrors it 1:1. `null` means the dashboard was never made current and the viewer isn't an author
  (`DashboardPage.unpublished`). The console shows "This dashboard has no saved version yet."
- `current_version` is `saved.version`, and `can_edit` is `author`. `tags` come from document `metadata["tags"]`
  (`[]` when absent). `scope_options` is capped at 1000, as today.
- Errors use the console envelope: 404 `not_found` (unknown or other-mission dashboard), 422 `invalid` with
  `details.field` `spacecraft_id` (`:invalid_scope`) or `from`/`to` (range admission), 503 `unavailable` for a
  failed resolve.
- Invalidation resources: `dashboards` (document), `telemetry`, `limits`, `alarms`, `events` (data).
- **D0:** add `dashboard.author` to `organizations[].capabilities`, derived from the `:author_dashboards` policy
  (DECISIONS #38 style).

## D1–D4, D6 proposed shapes (for api-ops)

They wrap `Reads.Dashboards.Directory.load/3`, `DirectoryActions` and `Creation.create/4`.

- **D1** `GET /dashboards?q&tags=a,b&starred=true&archived=true&sort=updated|name|name_desc&page=N` →
  `{dashboards: [row], available_tags, total, page, pages, page_size, can_create, shortcuts: {starred: [row],
  recent: [row]}}`. `can_create` is `author?`.
  - `row`: `{id, name, description, tags, archived, starred, current_version, updated_at, updated_by: {id, name} |
    null, viewed_at, spacecraft}`.
  - `spacecraft` is **new**, for ux's Spacecraft column (Q4). It's derived from the document's scope default and
    placement bindings: `{mode: "fixed", spacecraft: {id, name}}`, `{mode: "context"}` (chosen when viewing),
    `{mode: "fleet"}` (only constellation-wide widgets), `{mode: "mixed"}`, or `null` when there are no widgets.
- **D2** `PUT /dashboards/:id/star` and `DELETE /dashboards/:id/star` → 204.
- **D3** `POST /:id/archive {confirm?}`:
  - → 200 `{archived: true}`;
  - 409 `in_use` with `details.used_by.playlists [{id, name}]` unless `confirm: true` (Q10);
  - audited.
  `POST /:id/restore` → 200, also audited.
- **D4** `POST /dashboards {name, description?, tags?, spacecraft: {mode: fixed|context|fleet, spacecraft_id?},
  library_item_id?}` → 201 `{id, version}`. These are ux's New fields; with a library template it starts from that
  widget. Errors: 422 `invalid` with `details.field`.
  `POST /:id/duplicate {name}` → 201 `{id, version}`. There's no import in this step (ux).
- **D6** `POST /:id/views` → 204 (feeds "recent"; the viewer fires it once per open).

## Kit (lead's answers)

- **K1 yes:** dashboards adds `uplot` 1.6.32 and `gridstack` 10.3.1 to `@cadence/console`, imported only from
  `features/dashboards` (lazy route chunk). Tell lead the commit.
- **K2:** the `--chart-*` tokens go in `packages/apogee-ui/src/styles/tokens.css`, dark and light. ux supplies the
  values. Until then the ported engine reads a temporary map in the dashboards feature that is removed when the
  tokens land.
- **K3:** lead adds a side placement to `ApSheet` (400px, right-anchored, non-modal so the grid stays usable).
- **Cockpit cluster:** composed in the takeover header's `#clocks` slot from `ClockCluster` and `useOpsCounts`,
  exported by lead from `@/shell`.
- **Q8:** dashboards edits fe-ops' three Telemetry/Timeline files itself, telling fe-ops first.

## Open questions

Resolved (see Rulings and Kit): Q1, Q2, Q5 (ux owns presentation), Q6, Q8, Q10, K1–K3.

- **Q3 (ux):** dashboards use uPlot, while Investigate uses `ApTimeSeries` (SVG). Should the chart grammar match:
  envelope, limit segments, crit wash, now-line, legend?
- **Q4 (ux):** ux's directory has a **Folder** column, but there's no folder model, only tags. Show tags until a
  folder model exists, or should tags be presented as folders? Also confirm the "Bound to" wording.
- **Q7 (ux):** spec sections still to come: playlists + present, shares/snapshots (with the frozen window), export,
  library (with the "Used by" refusal), settings tabs, and New (I propose a small page, not a sheet).
- **Q9 (api):** the live window cap is 24 h (backfill cost not measured). Keep it, so the range picker offers
  ≤24 h sliding ranges plus absolute ranges up to 31 d?
