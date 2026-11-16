# Parity audit: legacy Explore and Data operations before §11c(D) (dashboards, 11-16)

**Scope (lead):** the retained legacy ops pages left after §11c(C1)/(C2): `/ops/explore`, `/ops/telemetry/explore` and
`/ops/data-operations[/manage]`. Method as `parity-ops-c.md`: every **action** and **information** item on each legacy
page → in the console (where), partial, or missing; tiered; what each gap needs. **Read-only**, on head `72966c894`;
each console "Yes" traced to code. **C** = `frontend/apps/console/src/features`.

## Gate (ux review 11-16, `ux/reviews/2026-11-16-parity-ops-d.md`)
DECISIONS #75 parks **L16** (data operations) and **L20** (canned questions): their legacy pages stay until the user
revisits. So `/ops/explore` and `/ops/data-operations` can't be deleted by building gaps alone; each needs the user's
call (unpark and build, or accept the gap).

## Status (11-16)
- **D11 built:** the capped-read line on both screens, with ux's words naming the part shown (api: the fallback
  store keeps the EARLIEST 20,000 raw samples, so the plot runs from the range start to the last bucket's end;
  native decimation never truncates). Telemetry d93886412 + e1e8f8a49 (dashboards; qa PASS 09:58Z), Investigate
  8e01920a7 + 03e5e5bff (fe-ops).
- **D12 frontend built:** points with no spacecraft read "Pick a spacecraft to plot <point>." (focus moves only from
  "Choose a spacecraft"). The 301 itself still needs api to map `spacecraft_id` → that spacecraft's **SCID** (`?sc=`
  takes SCIDs; fe-ops).
- **"Couldn't be confirmed" replaced:** a failed re-read keeps the last plot under "Couldn't refresh at …; showing
  data read at …" + Try again (ux's condition), in the same Telemetry commits.
- **D1, D2, D12 (301) → api** (lead). D1's home is Investigate (a Sample aside from T3 rows; ux), fe-ops once the read
  exists. D2's target is exactly the link AlarmProvenance builds (`ops.spacecraft` with `tab: telemetry`, `?points=`,
  `focus=`, `at=<sample time>`), so both builders need the SCID, point and sample time; the limits app's prefix
  check must accept `/console/…/spacecraft/`.
- **Data operations (L16) → the director / user** (unpark or accept).

## Triage

### Tier 1 (safety / audit)
| # | Gap | Legacy | Console today | Needs |
| --- | --- | --- | --- | --- |
| D1 | **Sample inspection**: raw vs engineering value, quality, generation/receipt time, packet id, raw evidence id, packet definition + version, validity, stored source/binding/endpoint, replay run | Explore › Selected sample (`SampleInspection.vue`) | Investigate `?at=` rings a time; "Show the sample that raised it" + sample id in Technical details (`investigate/AlarmProvenance.vue:32-50`); no console sample read | **api**: a one-sample read (ExplorationSnapshot is host-page only); then frontend in Investigate's Technical details. Pairs with A7c "Open exact sample" |
| D2 | **Evidence links into /ops/explore** must be repointed before deletion | Alarms "Open exact sample and evidence" (`ops_console/actions/ui_interactions.ex:314-320`); the limits app's posture `evidence_href` (`reads/limit_state_evidence.ex:32`, prefix-checked in `modules/limits-and-alarming/src/shared/states.ts:22-30`) | no console route takes a `sample_id` | **api** (both builders) + the limits app's prefix check; target Investigate `?at=` now, the D1 read later |
| D3 | **Historical data workflows**: group decisions (Approve / Reject / Start / Complete / Mark failed), retry failed items, request a correction, each with a required reason, a stale-evidence check, a confirm and a per-event actor/reason trail | Data operations › manage (`NativeHistoricalWorkflows.vue`; `ops_console/actions/historical_workflow_actions.ex:111-156,316,326`) | none; only a single cut-off backfill/import job surfaces on Now (`now/jobs.ts:96-114`, `contacts/JobBlock.vue`), no reason captured | **api** (console reads + writes; the domain exists, `Commands.*historical_data_workflow*`) then frontend. Parked as **L16** (DECISIONS #75); urgent only if L16 is unparked |

### Tier 2 (operator workflow)
| # | Gap | Needs |
| --- | --- | --- |
| D4 | **Request a backfill / import** (workflow, group, binding, UTC span, points, reason, confirm) with Validate and the "binding changed: use version N" guard | api + frontend (L16) |
| D5 | **Request groups view**: list (state, progress, events), detail with all summary counts, audit events, jobs, origins, `?group=` permalink, last-operation receipt, the unconfirmed-outcome lock. IA home: Setup › Data sources › Operations tab (`ux/information-architecture.md:182,205`) | api + frontend (L16); then Now's backfill outcome-unknown row links there (it has `noAction` today, `now/jobs.ts:136-137`) |
| D6 | **Raw observations** (not buckets) with sample ids and a receipt vs generation axis | api (M10 is bucketed, generation axis only: `api/ops.md:576`) |
| D7 | **Non-numeric points** (enum, string, boolean) | api (M10 numeric only, `api/ops.md:590`) + frontend (`telemetry/api.ts:29-31`) |
| D8 | **Revision view** (canonical / as recorded / all revisions / recomputed) and the validity filter | api |
| D9 | **Realm and replay run** (rehearsal, simulation, replay data); archive / replay-run windows | api; domain on exposure |
| D10 | **Non-spacecraft scopes** (contact, endpoint, station, transport, link) and the `operational_observables` source | api / domain |
| D11 | **History truncation notice**: `truncated` decoded (`investigate/api.ts:33`), never rendered | **frontend only** |
| D12 | **`/ops/telemetry/explore` keeps the spacecraft**: the 301 (`legacy_ops_redirect_controller.ex:12-19`) carries only `from`, `to`, `p`, and the console plots spacecraft × point, so a bookmark opens a point chip with an empty plot | api (small): map `spacecraft_id` → `sc` |

### Tier 3 (nice-to-have)
- Data source / binding filter on Explore (api); query diagnostics (api); observation count and "read at" (frontend).
- Dashboard → Explore hand-off with "Open source dashboard" back (frontend, dashboards; the console has Inspect instead).
- Render decoded-but-unused fields: bucket `count` (`investigate/api.ts:22`), the limit interval's `limit_set_name`, definition id/version and scope (`:55-61`); Sources' binding `realm` in Technical details (`sources/bindings.ts:27`) (frontend only).
- Data operations' extra summary counts, `blocked_count`, audit `actor_id`/`event_type`, job times, Validate's per-field feedback (legacy wire only, so api).

### Gone by design / obsolete (ux confirmed 11-16, except canned questions)
- **Canned questions** (`apply_question`): NOT gone by design; L20 is parked (DECISIONS #75), so it's the user's
  call. ux's four empty-state links shipped meanwhile (`telemetry/PlotPanel.vue`).
- **Row limit and order:** meaningless for a bucketed plot.
- **"Refreshed result could not be confirmed":** replaced by live invalidation, on ux's condition that a failed
  re-read keeps the last plot with its read time (built 11-16).
- **`add_to_dashboard`:** already removed (legacy-deletion.md L8 notes).
- **Federated `OpsTelemetryExplore`, `OpsDataOperations[Manage]` surfaces:** "Open in workspace" links only; they go with their pages.
- Not equivalents (no overlap): Now's ingress / settlement / archive items; catalog `import_runs`; the dashboards' removed backfill-lifecycle overlays (`dashboards/chart/chart-events.ts:8-12`).

### Side finding (11-16)
A legacy federated action path for historical data workflows skipped the native path's reason, stale-evidence and
lock checks. Reported to lead; the unused actions are being removed (api's server half, dashboards' manifest half).
A sweep for the same pattern in other applications' host actions is in progress (dashboards).

## Per-page evidence

### /ops/explore (`modules/dashboards-and-exploration/src/features/exploration/ExplorationPanel.vue`)
Route `router.ex:542-544` (`host_policy: :ops`), rj `dashboards.exploration`; server `ops_exploration_page.ex` →
`reads/dashboards/exploration_snapshot.ex` (model v3). Console: `telemetry/TelemetryScreen.vue` (`ops.telemetry`) and
`investigate/telemetry/TelemetryTab.vue`.

| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Point id input | action | Yes: search + exact id (`telemetry/PointsPanel.vue`) | console adds latest values and limit marks |
| Time windows: latest / live / 15 m–24 h / range | action | Partial: presets + custom range (`PlotPanel.vue:65`) | no "latest N samples" |
| Archive / replay-run windows, replay run id | action | No | D9 |
| Time axis (receipt vs generation) | action | No | D6 |
| Revision view, validity filter | action | No | D8 |
| Order, row limit 1–1000 | action | No | by design (bucketed) |
| Source and scope (logical source, realm, data source, binding, scope kind/id, limit semantics) | action | No (spacecraft only, `useSeries.ts:35-39`) | D9, D10, tier 3 |
| Spacecraft filter | action | Yes: chips | console plots up to 6 spacecraft × point (`selection.ts:52-56`) |
| Run query, URL holds it | action | Yes: `?sc&p&range|from&to` (`selection.ts:40-47`) | |
| Refresh, "couldn't be confirmed" | action/info | Yes: live invalidation, retry | |
| Source dashboard name + "Open source dashboard" | info/action | No | tier 3 |
| Observations returned, "Read at" | info | No | tier 3 |
| Effective window and axis | info | Partial: picker + aria-label (`PlotPanel.vue:108`) | |
| Status: point required / empty / unavailable / unsupported source or scope | info | Partial: "Pick a point", "History not available" (`PlotPanel.vue:67-98`) | no "unsupported" states |
| "Result limit reached" | info | No | D11 (`truncated` decoded) |
| Query diagnostics | info | No | tier 3 |
| Rows: time + axis, value + unit | info | Partial: bucket mean/min/max (`ValuesTable.vue`; Investigate T3 all buckets + CSV) | D6 |
| Non-numeric values | info | No | D7 |
| Row sample id; source / binding / realm / dataset | info | No | D1, D9 |
| Select a sample → Selected sample panel (quality, times, raw/engineering json/hex, source, binding, provenance) + Clear | action/info | No | D1 |
| Canned questions | action | Partial by design: four links | L20 parked |

### /ops/telemetry/explore
A redirect, not a page: `router.ex:211-215` → `LegacyOpsRedirectController.telemetry_explore` → 301 to
`/console/<org>/<mission>/telemetry?from&to&p=<point_id>`. Point and window carry over; the spacecraft and every other
key drop (D12).

### /ops/data-operations and /manage (`modules/data-operations/src/features/historical-workflows/NativeHistoricalWorkflows.vue`, one component, mode reader|manage)
Routes `router.ex:460-462` (`:ops`) and `:550-552` (`:ops_admin`); rj `data-operations.history[-manage]`; server
`ops_historical_workflows_page.ex`, read `reads/application_surfaces/data_operations/historical_workflows.ex`
(`authorize` :166: operate_mission, + manage_missions for manage), actions `historical_workflow_actions.ex`,
`historical_workflow_request.ex`. **The console has no route, screen or JSON endpoint for any of it** (L16 parked).

| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Request groups list (id, workflow, state, progress, events), 25/page | info | No | D5 |
| Selected group: state, progress, 5 counts | info | No | D5; more counts on the wire |
| `?group=` permalink, open in another tab | action | No | D5 |
| Audit events (stage, time, run, point, realm, source, binding, span, reason, operation id), paged | info | No | D3/D5 |
| Jobs (id, status, attempts, run), paged | info | Partial: a cut-off job as a Now row (`now/actionQueue.ts:410-411`, ids in Technical details `now/jobs.ts:66-77`) | no job list |
| Origins (dashboard / comparison review) | info | No | D5 |
| Last-operation receipt | info | No | D5 |
| Unconfirmed-outcome lock + Refresh | info/action | No | D5 |
| Search / page telemetry bindings (id, realm, version) | action | Partial: Setup › Data sources bindings (`sources/MissionBindingsTable.vue`) | no version, evidence, search |
| Request a backfill / import + Validate + binding-version guard | action | No | D4 |
| (manage) Group transitions with eligible counts, reason, confirm, evidence hash | action | No | D3 |
| (manage) Retry N failed items | action | Partial: single cut-off job Retry… / Close without retry… (`now/jobs.ts:96-114`) | not group-level, no reason |
| (manage) Request a correction of a failed event | action | No | D3 |
| (manage) Retry counts; who decided and why per event | info | No | D3 |
| Reader ↔ manage links | action | No | |

## Order (proposal)
D11 now (frontend only, S) → D2 + D12 (api, small; repoint before any deletion) → D1 with A7c (api read, then
Investigate) → decide L16's unpark for D3–D5 (director) → D6–D10 as api's telemetry reads grow (M10 successors) →
tier 3 as touched. **§11c(D) is gated** like (C): each gap built or explicitly accepted as dropped (dropping an
operator capability is the user's call).
