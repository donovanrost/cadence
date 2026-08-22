# Dashboard and Ops information architecture delivery plan

Status: implemented in the live checkout on 2026-08-01. This document retains
the delivery rationale and records the resulting route, ownership, persistence,
and verification boundaries.

Observed: 2026-08-01

Primary inputs:

- [Dashboard information architecture and page structure](dashboard-information-architecture-and-page-structure.md)
- [Grafana and Cadence dashboard feature audit](dashboard-grafana-cadence-feature-audit.md)
- [Dashboard interaction improvements](dashboard-grafana-interaction-improvements-plan.md)

## Implementation result

The W0-W8 program now exists as one integrated product slice:

- the Ops layout owns one continuous right context rail with alarm, command,
  and fleet posture on ordinary, dashboard-author, and Ops-admin pages;
- the left navigation is grouped into Observe, Act, Plan, and System, while the
  Dashboard Directory owns search, sort, lifecycle filters, tags, stars,
  recents, clone, and import discovery;
- Alarms, Commands, Timeline, canonical Explore, Data Sources, and Data
  Operations are first-class mission workspaces with context-preserving
  handoffs;
- the telemetry-first Viewer is read-only with respect to dashboard documents,
  Compare is page-local, and the dedicated Editor stages section, placement,
  widget, binding, repeat, and presentation changes until one Save;
- Settings, Activity, and Diagnostics own configuration, lifecycle, and
  execution detail outside the Viewer;
- source inventory/detail is readable by operators, while source mutation and
  destructive Data Operations recovery remain administrator routes; and
- permission-aware shares, snapshots, Library versions, Playlists,
  presentation/wallboard mode, governed export/import, deployment records, a
  dashboard-as-code schema, and CI validation complete the reuse layer.

The implementation reuses the canonical Dashboard Document and existing
operational stores. Additive persistence is limited to dashboard preferences
and the genuinely new management concepts named in W8. The right context rail
remains operational context at a glance; it is not an inspector and it is not
replaced by dashboard selection, Compare, archive, replay, or page-local time.

Verification evidence is recorded in section 8.5. The full browser matrix
passes 93 scenarios, including the authenticated Directory -> Viewer -> Editor
and Viewer -> Activity/Diagnostics/Data Operations journeys, context-rail
presence, current telemetry, archive/replay behavior, degraded sources, and
ingress-latency history compatibility.

## 1. Outcome

Deliver Grafana-quality dashboard discovery, viewing, authoring, investigation,
reuse, and governance without rebuilding every workflow inside the Dashboard
Viewer.

The implemented product structure should have:

- a telemetry-first Dashboard Viewer;
- a separate staged Dashboard Editor;
- dedicated Settings, Activity, and Diagnostics pages;
- first-class Explore, Alarms, Timeline, Commands, Sources, and Data Operations
  workspaces;
- an Ops navigation rail organized by Observe, Act, Plan, and System; and
- a shell-owned context rail that carries live operational awareness across
  every Ops page.

The context rail is a program-level constraint, not a dashboard feature. It
shows glanceable current mission context such as alarm posture and command
queue/state without taking the operator away from the task beneath it.

## 2. Live-checkout starting point

The plan starts from the current implementation rather than an imagined clean
slate.

### 2.1 Existing foundations

- `live_session :ops` already supplies organization scope, mission loading, the
  user menu, `OpsShellHook`, and the Ops layout.
- `live_session :ops_admin` already adds organization-admin enforcement while
  retaining the Ops layout and shell hook.
- `OpsShellHook` currently loads fleet health, dashboard summaries, active
  dashboard identity, and the active navigation item.
- `OpsContextRail` already supplies the collapsed/expanded shell, stable DOM
  contract, status dots, counts, resizing, and locally persisted rail state.
- Dashboard, Explore, Sources, Contacts, Planning, Requirements, and Approvals
  already have operational routes.
- The domain already has useful read and control foundations for latest limit
  state, mission events, command queues/status, contacts, source health,
  dashboard lifecycle, and historical-data workflows.
- The Dashboard Viewer already carries typed scope/time/replay context and many
  evidence-preserving links.

### 2.2 Boundaries that need to change

- The Ops layout renders only the status bar and left navigation rail. The
  right context rail is inserted by a small subset of pages, so it cannot yet
  provide continuous cross-page operational awareness.
- The dashboard page currently replaces the mission-health rail content with a
  page-specific comparison section. Compare is page-local and should not own
  the Ops context rail.
- The left navigation is a flat Modes list, marks Explore as Dashboards, and
  repeats every dashboard.
- The Dashboard Viewer owns editing, lifecycle, publishing, diagnostics,
  defaults, and historical-data workflow controls that now need stable pages.
- Data Sources combines operator-readable posture with administrator mutation.
- Alarms, Timeline, and Commands have domain foundations but no first-class
  mission Ops pages.

### 2.3 Active dashboard foundation

The current working tree already contains a large coherent interaction slice
that appears to implement most of the existing five-item interaction plan:

- Test binding and binding-preview results;
- operational dashboard sections;
- chart range selection and richer shared chart behavior;
- catalog-bounded presentation controls; and
- domain repeat authoring.

This plan treats that work as **W0: complete the active interaction
foundation**. It is part of the same dashboard and Ops program as the shell and
page-structure changes. Related workstreams may build on and reshape it directly
while their shared behavior remains covered by tests.

## 3. Delivery rules

1. **Ship vertical slices.** A route, real read path, interaction, tests, and
   context-preserving navigation land together.
2. **Add before removing.** Introduce the new route and prove parity before
   removing the old sheet, inline form, or menu action.
3. **Keep one canonical owner.** Rehost existing stores and domain workflows;
   do not copy their state into dashboard-specific persistence.
4. **Keep the context rail shell-owned.** Page-local selection and Compare use
   a separate inspector and cannot replace rail content.
5. **Keep operational and page context distinct.** The rail defaults to live,
   mission-wide operational state even when the current page is historical,
   replayed, filtered, or scoped.
6. **Authorize at the router.** Mutating routes receive a capability-bearing
   live session or `on_mount` policy; hiding controls is not authorization.
7. **Preserve URLs during migration.** Add authenticated redirects for renamed
   routes and keep query-context round trips covered by tests.
8. **Avoid premature persistence.** Use existing document, lifecycle, command,
   limit, contact, source, and historical-workflow stores until a workstream
   proves a new durable concept is necessary.
9. **Treat related changes as shared program state.** The active dashboard
   changes are part of this effort and may evolve with later workstreams. Still
   preserve genuinely unrelated work such as independent architecture changes.
10. **Use real operational data.** Browser acceptance uses real Cadence read
    paths and visibly current telemetry, not presentation-only fixtures.

## 4. Dependency map

```text
W0 Active dashboard interaction foundation (continues throughout)
├── integrates with W1 Ops shell and context-rail foundation
└── integrates with W4 Separate Dashboard Viewer and Editor

W1 ──> W2 Alarm and command operational-awareness verticals
W1 ──> W3 Navigation and dashboard discovery
W4 ──> W5 Extract Settings, Activity, and Diagnostics

W2 + W5 ──> W6 Sources and Data Operations separation
W2 + W6 ──> W7 Explore, Timeline, and cross-page investigation
W4 + W5 ──> W8 Library, sharing, deployment, and wallboards
```

W0, W1, and W4 may evolve on the same branch because their shared Dashboard
Viewer and shell touchpoints are part of the intended migration. Sequence
behavioral cutovers carefully, but do not require artificial commit boundaries
or file-level isolation between related workstreams. W0 is an ongoing
foundation, not a gate that W1 or W4 must wait to clear.

## 5. Workstreams

### W0. Complete the active interaction foundation

Priority: P0

Goal: finish and verify the existing dashboard interaction work while using it
as the foundation for the new page boundaries.

Scope:

1. Reconcile the active implementation against all five sections of
   `dashboard-grafana-interaction-improvements-plan.md`.
2. Confirm document migration and default behavior for dashboards without
   sections, new presentation options, or repeat declarations.
3. Confirm Test binding never persists a dashboard revision.
4. Confirm range selection moves the entire dashboard to one archive context
   and Return live remains one action.
5. Confirm section edits, placement moves, widget edits, and repeat changes use
   the current lifecycle semantics intentionally.
6. Run focused domain, LiveView, JavaScript, and browser verification.
7. Record any intentionally deferred acceptance criterion in the interaction
   plan and assign it to W1, W4, or another owning workstream.

Exit criteria:

- every interaction-plan acceptance criterion is either proven or explicitly
  deferred with an owner and destination workstream;
- existing dashboards render without migration or behavior regressions;
- the focused browser pass covers live, archive, empty, sectioned, and repeated
  dashboards; and
- shared behavior remains green as W1 shell ownership and W4 route extraction
  reshape the same modules.

When a change spans W0, W1, or W4, assign its acceptance criterion to one owner
and test the integrated behavior. It does not need to be split merely to produce
separate diffs.

### W1. Make the Ops shell own operational context

Priority: P0

Goal: make the context rail genuinely continuous across every Ops page while
preserving the current compact/collapsible interaction.

#### W1.1 Establish a shell-owned rail

Implementation:

1. Add one `ops_context` snapshot assign to `OpsShellHook`.
2. Render the right context rail in `layouts/ops.html.heex`, beside `<main>`, so
   both `:ops` and `:ops_admin` sessions receive it automatically.
3. Preserve the existing `#ops-context-rail`, storage key, collapsed badge
   strip, expansion, and resize contracts.
4. Remove page-owned `<.mission_context_rail>` instances only after the layout
   rail is visible and tested on those pages.
5. Move dashboard Compare out of `ContextRailSections` into a page-local sheet
   or docked inspector.
6. Remove the dashboard-specific context-rail assembly after Compare parity is
   proven.

Initial shell snapshot contract:

- mission identity and observed-at timestamp;
- an ordered module collection with stable keys;
- status, count, freshness/staleness, and canonical destination per module; and
- explicitly pinned operational focus when one exists.

W1 adapts the existing fleet-health fallback into that contract. W2 adds alarm
and command summaries from their existing canonical read paths. The snapshot is
a read model, not a new source of truth.

#### W1.2 Refresh and continuity

Implementation:

1. Load the snapshot during the existing Ops `on_mount` chain.
2. Refresh it through existing domain notifications where available, with a
   bounded heartbeat to expose stale projections.
3. Keep refresh ownership in the shell hook/shared boundary rather than adding
   a timer implementation to every Ops LiveView.
4. Preserve expansion, module order, and explicitly pinned operational focus
   while navigating between Ops routes.
5. Do not store mission identifiers, command identifiers, or operational facts
   in global browser local storage. Persist only harmless UI preferences there;
   keep operational focus mission-scoped in server/session state.
6. Do not inherit the current page's time, replay, search, or scope parameters
   unless the operator explicitly pins a visibly labeled operational focus.

Acceptance criteria:

- the same rail DOM contract is present on Dashboard Directory, Viewer,
  Explore, Sources, Contacts, Planning, Requirements, and Approvals;
- navigation between those pages preserves rail continuity;
- a historical or replay dashboard does not turn the rail historical;
- the collapsed affordance remains visible and preserves the existing
  status-dot/count contract;
- page-local Compare and selection do not clear or replace operational modules;
  and
- no page renders a second context rail.

Migration safety:

- mount the layout rail while page-owned rails are feature-gated off one page
  at a time;
- retain the current rail component and JS hook; change ownership before
  redesigning presentation; and
- keep fleet-health fallback content until the alarm and command projections
  are proven.

### W2. Deliver alarm and command awareness as vertical slices

Priority: P0/P1

Goal: give the first context-rail modules canonical destinations and real
mission workflows.

#### W2.1 Read-only Alarms page and rail module

Route: `/missions/:mission_id/ops/alarms`

Implementation:

1. Build the read-only page from canonical latest limit states and limit
   events.
2. Support severity, spacecraft, subsystem/point, and state filters.
3. Link each condition to its definition, activation interval, exact sample,
   and evidence where those facts exist.
4. Build the rail projection from the same read boundary: highest severity,
   active count, recent transition, and observed-at time.
5. Keep nominal state silent in the collapsed rail.

Acceptance criteria:

- a rail alarm summary is consistent with the Alarms page for the same read
  snapshot;
- the module remains live and mission-wide while the current page is archive or
  replay;
- selecting Open alarms preserves a return target and relevant originating
  context;
  and
- the page contains no definition-mutation controls.

#### W2.2 Read-only Commands page and rail module

Route: `/missions/:mission_id/ops/commands`

Implementation:

1. Build the initial page from existing command request, queue-entry, release,
   transport, and verifier projections.
2. Start read-only: filters, queue/state timeline, command identity, requested
   by, target, age, release posture, and verifier outcome.
3. Add rail projections for queued, release-pending, in-flight/released, failed
   or indeterminate, and the explicitly followed command.
4. Label stale or unavailable command projections distinctly from an empty
   queue.
5. Defer request/release mutation until its route capability and confirmation
   contract are separately accepted.

Acceptance criteria:

- queue counts agree with the canonical command projection;
- empty, unavailable, and stale states are distinguishable;
- a followed command remains visible while navigating between Ops pages; and
- ordinary read access does not expose release controls.

#### W2.3 Later context modules

Add current/next contact, material link-state changes, and broad source
conditions only after their canonical page links and exception semantics are
clear. Do not add modules merely because data is available.

### W3. Clarify navigation and dashboard discovery

Priority: P0/P1

Goal: make the product hierarchy predictable before adding more destinations.

#### W3.1 Ops navigation

Implementation:

1. Group the left rail into Observe, Act, Plan, and System.
2. Make Explore a first-class Observe item.
3. Add Alarms, Timeline, and Commands as their routes become available.
4. Replace the complete dashboard list with at most five starred and five
   recent dashboards.
5. Keep New Dashboard as a visible authoring entry point only when authorized.
6. Reduce the top status bar to mission identity, UTC/connection, notifications,
   user/admin posture, and the smallest urgent alarm signal.

Explore route migration:

- canonical: `/missions/:mission_id/ops/explore`;
- legacy: `/missions/:mission_id/ops/telemetry/explore`;
- preserve the legacy path as an authenticated redirect carrying its complete
  query string.

#### W3.2 Dashboard Directory

Implementation order:

1. Search, sort, lifecycle filter, and archived view over existing summaries.
2. Tags and tag filters using dashboard-owned durable metadata.
3. Per-user stars and recent dashboards through a small scoped preference
   store; do not write this state into the shared Dashboard Document.
4. Create, clone, and import entry points with capability-aware visibility.
5. Library and Playlists tabs remain disabled or absent until W8 supplies their
   routes.

Acceptance criteria:

- hundreds of dashboards do not make the navigation rail unusable;
- Directory search/filter/sort state has a shareable or restorable URL where
  useful;
- stars and recent state are user-scoped and mission-scoped;
- Explore receives its own active navigation state; and
- legacy Explore bookmarks retain their query context.

### W4. Separate Dashboard Viewer and Editor

Priority: P0/P1

Goal: replace inline, immediately persisted authoring with one staged edit
transaction and a WYSIWYG canvas.

Route: `/missions/:mission_id/ops/dashboards/:dashboard_id/edit`

#### W4.1 Extract an editor boundary

Implementation:

1. Ratify the dashboard-author capability and enforce it in a dedicated
   authenticated live session or router-level `on_mount` policy.
2. Reuse the current Dashboard Document, placement editor, widget registry,
   engine, section behavior, binding preview, presentation controls, and repeat
   authoring from W0.
3. Create a local staged transaction from the starting dashboard version.
4. Render the candidate document through the production engine in the Editor.
5. Keep live operational ticks paused and clearly labeled while editing.
6. Treat layout, section, binding, options, and widget changes as local until
   Save.

#### W4.2 Save, Discard, and conflict behavior

Implementation:

1. Save one coherent draft version with a semantic change summary.
2. Discard restores the exact starting version without persistence.
3. Leaving with dirty state prompts without creating a revision.
4. Detect a stale starting version and offer reload or an explicit conflict
   resolution path; never silently overwrite.
5. Review & Publish saves the draft, then navigates to Activity with the version
   selected.

#### W4.3 Reduce the Viewer

After Editor parity:

- replace inline Edit/Add/Section controls with Edit Dashboard navigation;
- remove all document mutation events and forms from the Viewer boundary;
- retain telemetry, runtime scope/time, shared selection, annotations,
  exceptional data issues, Share, and fast drilldowns; and
- retain page-local Inspect/Compare separately from the Ops context rail.

Acceptance criteria:

- moving or resizing ten widgets produces no durable versions before Save;
- Save produces exactly one coherent version;
- Discard produces none;
- candidate widgets use production rendering and explain no-data/error states;
- Viewer runtime context never dirties the document; and
- unauthorized users cannot enter or invoke Editor mutation routes.

Migration safety:

- keep the existing inline editor available behind an implementation switch
  until Editor parity tests pass;
- route new authoring entry points to the Editor before deleting viewer events;
  and
- remove old mutation code in follow-up slices by responsibility, not as one
  broad rewrite.

### W5. Extract dashboard lifecycle pages

Priority: P1

Goal: move page-sized dashboard workflows out of Viewer sheets without changing
their canonical stores.

#### W5.1 Dashboard Settings

Route: `/missions/:mission_id/ops/dashboards/:dashboard_id/settings`

Owns:

- name and description;
- durable runtime defaults;
- dashboard links and access posture;
- export/deployment settings when introduced; and
- archive/restore entry points with confirmation.

The read page may share normal Ops access. Mutations require the dashboard-author
policy at the router.

#### W5.2 Dashboard Activity

Route: `/missions/:mission_id/ops/dashboards/:dashboard_id/activity`

Owns:

- version history and semantic diffs;
- review requests and decisions;
- publish readiness and impact;
- restore/revert into a new draft; and
- lifecycle audit.

Start with a read-only route using the existing version/activity presentation.
Move publish and restore mutations only after route-level capability tests are
in place.

#### W5.3 Dashboard Diagnostics

Route: `/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics`

Owns:

- plan, request, frame, cache, source-execution, refresh, and invalidation
  collections;
- filtering and a master/detail selection;
- copyable diagnostic identity; and
- context-preserving links to Explore, Sources, Catalog, and Admin Runtime.

The Viewer keeps only a compact issue explanation and Open Diagnostics link.

Acceptance criteria:

- each collection has a stable URL and browser history;
- existing lifecycle and diagnostic records are read from their current stores;
- Viewer actions navigate to the new pages with dashboard/runtime context;
- Viewer no longer renders the extracted sheets after parity; and
- defaults, publishing, and diagnostics have distinct authorization posture.

### W6. Separate Sources and Data Operations

Priority: P0 trust repair, then P1 extraction

Goal: distinguish live data-plane posture from privileged source mutation and
mission-wide historical repair.

#### W6.0 Restore trust first

Before route extraction:

1. Fix the observed Data Sources `:events` render failure.
2. Fix source-health event reconstruction failures.
3. Add a healthy, visibly current mission/source browser fixture.
4. Prove Dashboard → issue/evidence → Explore → Data Sources navigation.

#### W6.1 Data Sources inventory and detail

Routes:

- `/missions/:mission_id/ops/data-sources`
- `/missions/:mission_id/ops/data-sources/:data_source_id`

Own operator-readable inventory, bindings, capabilities, readiness, health,
retention, watermarks, activity, and remediation links.

#### W6.2 Data Source settings

Route: `/missions/:mission_id/ops/data-sources/:data_source_id/settings`

Place registration, credentials references, adapter configuration,
enable/disable, provision/deprovision, rotation, and destructive controls in
`:ops_admin` or a narrower source-administrator live session because they alter
data-plane posture.

#### W6.3 Data Operations

Route: `/missions/:mission_id/ops/data-operations`

Rehost the existing dashboard-owned historical modules in bounded groups:

1. request creation and request status;
2. group/job progress and recovery;
3. correction requests;
4. comparison review and revision decisions; and
5. closure/readiness and audit history.

Move presentation and orchestration boundaries first; retain current domain
commands, stores, identifiers, and lifecycle semantics. Viewer and Explore may
launch a prefilled request, but Data Operations owns every subsequent step.

Acceptance criteria:

- a request can be followed without the dashboard that first exposed the gap;
- all affected dashboards are discoverable from the workflow;
- historical repair state is not duplicated into a Dashboard Document;
- source readers never see credential or destructive controls; and
- privileged routes reject unauthorized direct navigation.

### W7. Complete investigation and operational correlation

Priority: P1

Goal: make Cadence meaningfully better than Grafana at explaining mission
telemetry and related operations.

#### W7.1 Canonical Explore route and question-led entry

- retain all typed scope/time/replay/data/source context;
- add queryless mission questions and investigation presets;
- make packet-to-pixel evidence and selected sample identity first-class;
- Add to Dashboard opens W4 Editor with a staged candidate; and
- no Explore action mutates a Dashboard Document directly.

#### W7.2 Timeline

Route: `/missions/:mission_id/ops/timeline`

Build from the existing mission-events projection. Start read-only with contact,
limit, command, source, catalog/binding, backfill/revision, and transport/runtime
events. Every annotation links to the canonical event and every event can return
to an originating Dashboard/Explore context.

#### W7.3 Cross-page context contracts

Prove these flows end to end:

```text
Dashboard issue → local inspector → Explore → Sources/Diagnostics
Dashboard alarm annotation → Alarms → exact limit/sample/evidence
Dashboard command annotation → Commands → request/queue/release/verifier state
Dashboard/Explore gap → Data Operations → repair → same comparison context
Link degradation preset → Contacts + Comms + Timeline
```

Acceptance criteria:

- context links round-trip mission, scope, time, replay, data view, source, and
  selected evidence where relevant;
- hover remains client-local while explicit selection owns browser history;
- no canonical event is recreated as editable dashboard annotation state; and
- the Ops context rail remains live and continuous throughout every flow.

### W8. Add reuse, sharing, deployment, and wallboards

Priority: P2/P3

Goal: complete the Grafana-familiar management layer after viewing, authoring,
and degraded-state behavior are trustworthy.

Delivery order:

1. permission-aware sharing of the current runtime context;
2. read-only snapshots with explicit data/runtime semantics;
3. versioned widget Library items and update posture;
4. governed dashboard export/import;
5. dashboard-as-code schema and CI validation;
6. Playlists and presentation mode; and
7. wallboard mode with unmistakable live freshness and degraded-state signals.

New persistence is allowed here only for concepts that are genuinely new:
library item/version, share/snapshot policy, playlist, and deployment record.
Dashboard definitions continue to use the canonical Dashboard Document.

Acceptance criteria:

- import/export round-trips without silently changing binding semantics;
- library updates never silently rewrite consuming dashboards;
- snapshots and shares declare authorization and data visibility;
- playlists reference dashboards rather than copying their documents; and
- wallboards cannot hide stale, partial, disconnected, or unsupported state.

## 6. Router and authentication placement

The implementation places routes as follows.

| Boundary | Routes | Why |
| --- | --- | --- |
| Existing authenticated `live_session :ops` | Directory, Viewer, canonical Explore, read-only Activity, read-only Diagnostics, Alarms, Timeline, read-only Commands, Contacts, Planning, Requirements, source inventory/detail, and Data Operations read paths. | These require organization scope, mission loading, the shared Ops shell/context rail, and operator-readable mission state. |
| Authenticated `live_session :ops_dashboard_author` with `DashboardAuthorAuth` | New Dashboard/import/clone, Editor, Settings, Library mutation, and Playlist mutation. | These change mission-shared dashboard artifacts and must not rely on hidden or disabled controls. |
| Existing `live_session :ops_admin` or narrower source/data administrator policy | Source registration/settings, credentials, provision/deprovision, approvals, destructive data-operation recovery, and other data-plane posture changes. | These actions have broader operational consequences than ordinary read access. |
| A future command-author/release policy/session | Command request, stage, approval, release, cancel, and retry actions. | Viewing command state and releasing a command are materially different capabilities and require explicit confirmation/audit boundaries. |
| Existing mission sessions | Catalog, Spacecraft, Comms, and Applications. | They define mission resources and semantics rather than operate the live console. |
| Existing platform-admin session | Cross-organization runtime and platform diagnostics. | Platform tenancy and runtime administration remain separate from mission Ops. |

All `/ops` live sessions—including authoring and administrator sessions—retain
the Ops layout, `OpsShellHook`, `current_scope`, and the shell-owned context
rail. Context modules use `current_scope` and mission identity when calling
their owning contexts; templates derive the user only through
`@current_scope.user`.

The implemented dashboard-author policy action is `:author_dashboards`.
Dashboard export is an authenticated controller route and performs the same
explicit author-policy check before reading or recording an artifact. Direct
route denial tests cover the author and administrator boundaries.

## 7. State and persistence plan

| State | Initial owner | Migration posture |
| --- | --- | --- |
| Dashboard document, sections, placements, bindings, options, repeat declarations | Existing Dashboard Document/version stores. | No new store. W4 changes transaction timing, not document ownership. |
| Runtime scope/time/replay/data/source selection | Existing URL and session runtime context. | Preserve keys and round-trip contracts across new routes. |
| Page-local selection and Compare | URL-promoted selection plus client-local hover/cursor state. | Move presentation out of the context rail without changing evidence identity. |
| Context-rail snapshot | New read model assembled from existing canonical projections. | Ephemeral and refreshable; never a new source of truth. |
| Context-rail UI preference | Existing local rail hook for harmless presentation; server/session state for mission-scoped operational focus. | Never persist operational identifiers in global local storage. |
| Stars and recent dashboards | New user + organization + mission-scoped preference records. | Additive migration in W3; not Dashboard Document metadata. |
| Tags | Dashboard-owned durable metadata. | Prefer additive document/summary support unless query scale proves an index table is required. |
| Versions/review/publish/archive | Existing dashboard lifecycle stores. | Rehost in W5 without copying. |
| Historical repair/revision workflow | Existing historical-data stores and commands. | Rehost in W6 without copying. |
| Library/share/snapshot/playlist/deployment | New domain concepts in W8. | Add separate schemas only with explicit contracts and migrations. |

All database changes are additive until the corresponding old UI path has been
removed and production data has been proven readable through the new owner.

## 8. Verification strategy

### 8.1 Inner loop for every slice

1. Domain tests for the owning read, policy, state, or document boundary.
2. Small LiveView/component tests in isolated files using stable DOM IDs.
3. JavaScript tests for rail continuity, URL promotion, chart behavior, and
   local interaction state when applicable.
4. `mix precommit.affected` after focused tests.

### 8.2 Route and authorization tests

For every new route:

- unauthenticated access redirects through the existing auth flow;
- organization and mission scope are loaded at the router/live-session layer;
- read-only capability can render but cannot invoke mutations;
- direct navigation to privileged routes is denied without capability;
- `current_scope` is passed to owning contexts; and
- cross-organization and cross-mission identifiers do not resolve.

### 8.3 Browser journeys

Release checkpoints use the running product with real data:

1. navigate Dashboard Directory → Viewer → Explore → Sources and back;
2. move between Viewer, Contacts, Planning, and Sources while a rail alarm and
   followed command remain continuous;
3. open a historical dashboard while the rail remains visibly live/current;
4. edit ten widget/layout fields, Discard, repeat, Save, and observe one version;
5. review/publish from Activity and return to the published Viewer;
6. launch historical repair from Viewer, complete/follow it in Data Operations,
   and return to the same comparison context; and
7. verify collapsed, expanded, narrow-screen, disconnected, stale, empty, and
   unauthorized states.

### 8.4 Test-file map

Keep major behaviors isolated rather than growing one cross-product LiveView
test file:

| Behavior | Focused test file |
| --- | --- |
| Shell-owned rail on every Ops route | `ops_shell_context_rail_live_test.exs` |
| Rail snapshot aggregation, freshness, and mission scoping | `ops_context_snapshot_test.exs` |
| Rail hook continuity and collapsed module badges | `ops_context_rail_test.mjs` |
| Read-only alarm collection and evidence links | `ops_alarms_live_test.exs` |
| Command queue/state and read-only policy | `ops_commands_live_test.exs` |
| Navigation grouping and Explore redirect | `ops_navigation_live_test.exs` |
| Dashboard directory search/filter/star/recent behavior | `ops_dashboard_directory_live_test.exs` |
| Editor staged Save/Discard/conflict transaction | `ops_dashboard_editor_transaction_live_test.exs` |
| Editor route authorization | `ops_dashboard_editor_auth_live_test.exs` |
| Settings ownership and authorization | `ops_dashboard_settings_live_test.exs` |
| Activity versions/review/publish | `ops_dashboard_activity_live_test.exs` |
| Diagnostics filters and context handoff | `ops_dashboard_diagnostics_live_test.exs` |
| Source reader versus administrator access | `ops_data_source_access_live_test.exs` |
| Data Operations request/recovery handoff | `ops_data_operations_handoff_live_test.exs` |
| Cross-page runtime/evidence context round trips | `ops_investigation_navigation_live_test.exs` |

Add stable IDs as the surfaces are introduced, including
`#ops-context-rail`, `[data-ops-context-section="alarms"]`,
`[data-ops-context-section="commands"]`, `#ops-alarms-list`,
`#ops-command-queue`, `#dashboard-editor`, `#dashboard-editor-save`, and
`#dashboard-editor-discard`. LiveView tests should use `has_element?/2`,
`element/2`, form helpers, and outcome assertions rather than raw HTML text.

### 8.5 Authoritative gates

- Run the owning project's focused tests during implementation.
- Run `mix precommit.affected` as the default coherent-slice gate.
- Run root `mix precommit` serially at every release checkpoint and before any
  completion claim.
- Do not describe browser, full-suite, publish, or overall-maturity coverage as
  complete without the corresponding evidence.

Implementation verification on 2026-08-01:

- `mix precommit.affected`: passed for all five affected workspace projects;
  Cadence 1,726 tests, Cadence Simulator 133 tests, and Cadence Web 1,732 tests
  passed, with compile, Credo, architecture, and extension checks green;
- `mix test.browser`: 3 browser-smoke scenarios passed;
- `mix test.browser.full`: 93 browser scenarios passed;
- focused replay current-value coverage passes after accepting
  `:replay_run_id` as a Postgres current-value source filter; and
- root `mix precommit`: passed after the final changes, including compilation
  with warnings as errors, Credo, architecture and extension checks, Cadence
  1,727 tests, Catalog 26 tests, CCSDS 295 tests, Cadence Simulator 133 tests,
  and Cadence Web 1,732 non-browser tests.

## 9. Release checkpoints

### R0. Interaction baseline

Contains: W0.

Exit signal: the five existing interaction improvements are verified and
integrated into the program baseline, with current dashboards backward
compatible.

### R1. Continuous operational shell

Contains: W1 and the read-only portions of W2.

Exit signal: every Ops page shares one context rail; live alarm and command
posture survive navigation and have real canonical destinations.

### R2. Familiar dashboard workshop

Contains: W3, W4, and W5.

Exit signal: a Grafana-literate operator can discover, view, compose, save or
discard, review, publish, configure, and diagnose dashboards through distinct,
predictable pages.

### R3. Cadence-native operational investigation

Contains: W6 and W7.

Exit signal: telemetry, sources, historical repair, limits, commands, contacts,
and mission events are context-preserving parts of one investigation without
being collapsed into the Viewer.

### R4. Reuse and deployment

Contains: W8.

Exit signal: dashboards can be safely shared, reused, exported/imported,
validated, rotated, and presented without weakening freshness, provenance,
authorization, or degraded-state visibility.

## 10. First implementation queue

The first execution sequence should be deliberately small:

1. **W0 interaction integration**
   - use the current dashboard changes as the active implementation foundation;
   - finish the focused tests and real browser pass;
   - record proven/deferred acceptance criteria; and
   - allow W1/W4 changes to reshape shared modules when the integrated behavior
     remains explicit and tested.
2. **W1.1 shell-owned rail**
   - add the shared snapshot assign;
   - mount the existing rail component in the Ops layout;
   - retain fleet-health fallback content;
   - remove duplicated page-owned rail instances one page at a time; and
   - add a cross-page rail-presence/continuity test.
3. **W1.2 separate dashboard Compare**
   - rehost Compare in a page-local inspector;
   - prove it does not affect rail modules or persistence; and
   - remove the dashboard-specific rail assembler.
4. **W2.1 alarm vertical**
   - add the read-only Alarms route/page;
   - add the alarm rail projection; and
   - prove live mission context while the current page is historical.
5. **W2.2 command vertical**
   - add the read-only Commands route/page;
   - add queue/followed-command rail projections; and
   - keep all mutation deferred behind explicit command capabilities.

W4 Editor extraction may begin while the first queue is progressing when it
uses the same tested interaction foundation. W3 navigation reshaping should
still follow the shell-owned rail so the product has a stable Ops shell before
the number of routes grows.
