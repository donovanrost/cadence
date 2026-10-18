# Frontend architecture inventory and triage

Cadence needs an explicit freshness and recovery contract before the frontend migration
expands. The current application combines live subscriptions, manually refreshed snapshots,
server timers, and an isolated polling SPA. Vue owns much of the interface already, while
the ordinary host still coordinates its current route with a mutable LiveView page session.

The first priorities are live Ops coverage, recovery after missed updates, and navigation
and operation lifetimes. The SPA direction can simplify ownership, but changing the
transport alone does not provide these guarantees.

This inventory is dated 2026-10-06 and describes commit `c07cfa23` plus the existing
uncommitted scheduling and contact-workspace work. Counts refer to this working tree,
not to a deployed release. It supersedes assumptions about current coverage in the
[September audit](architecture-audit-2026-09-27.md); that audit retains its original
reproductions and historical findings.

## Inventory coverage

- [Route inventory](frontend-route-inventory-2026-10-06.csv): all 146 route declarations
  before the API scopes, with method, handler, authentication pipeline, LiveView session,
  feature, update behavior, source, and triage IDs. These include 96 host catalog pages,
  two experiment pages, 14 generic application entry patterns, 21 redirects, ten
  authentication/session declarations, and three artifact/download endpoints.
- [Refresh and retry controls](frontend-refresh-controls-2026-10-06.csv): 91 candidates
  from Vue button elements/components whose labels or attributes mention refresh, reload,
  or retry. There are 54 refresh/reload matches and 37 retry matches. The CSV records
  source locations and separates read recovery, effect retry, validation, and draft reload.
- Current web adapters, frontend contribution registrations, notification publishers,
  ownership documentation, and selected lifecycle tests underpin the findings below.

The route catalog is exhaustively reconciled with `HostPageLive` declarations. Generic
application routes can render installed surfaces selected at runtime; their 14 entry
patterns are not an exhaustive list of installed screens. Per-operation backend durability,
all provider integrations, production latency, and deployment-specific installations need
the follow-up checks listed below. Source-confirmed behavior is distinguished from measured
behavior; an absent subscription is not a measured production delay.

## Application hosts and authority

| Entry                                                  | Navigation and rendering                                   | Reads and writes                                                                                       | Real-time behavior                                                                            |
| ------------------------------------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| 96 ordinary catalog pages                              | `BrowserHost` and Vue Router inside `HostPageLive`/LiveVue | Server context before route commit; captured page/token reads and actions; domain-specific DTO readers | Some PubSub-backed updates; most page bodies have no dedicated subscription                   |
| Two contact experiment pages                           | Vue Router and a persistent Vue shell, without LiveSocket  | Scoped HTTP resources, TanStack Query cache, scheduling v2 domain service                              | Visible-page polling every five seconds; bootstrapped shell remains static                    |
| Four generic native entry patterns                     | `ApplicationHostLive` and its surface renderer             | Application query/action providers through LiveView                                                    | Loads on entry/query/action; catch-all `handle_info` does not implement general resource push |
| Ten federated entry patterns                           | Controller bootstrap and Vue/federation host               | Existing authenticated application-host HTTP catalog/query/action API                                  | HTTP bridge `subscribe` reports local request activity; it is not a server data subscription  |
| Authentication, session, exports, redirects, artifacts | Server endpoints and normal browser navigation             | Session transitions, scoped downloads, release delivery                                                | Separate lifetimes; do not route these through a page data cache                              |

Sources: [BrowserHost](../apps/host/src/shell/BrowserHost.vue),
[HostPageLive](../../apps/cadence_web/lib/cadence_web/live/host_page_live.ex),
[experiment](contact-workspace-experiment.md),
[ApplicationHostLive](../../apps/cadence_web/lib/cadence_web/live/application_host_live.ex),
[HTTP bridge](../apps/host/src/http-host-bridge.ts).

Ordinary pages are in the `/` scope with `[:browser, :require_authenticated_scope]`, in
the `:application` LiveView session. This provides authenticated entry; subsequent host
requests reapply route policy. Generic native mission/spacecraft entries use the
`:mission` and `:spacecraft_show` sessions. Experiment and federated documents are
authenticated controller entries in the same outer scope. The contact JSON scope uses
`[:browser, :require_authenticated_user]`; the application-host JSON scope adds
`:application_host_json`. Both retain browser sessions and CSRF, with independent resource
authorization. Sign-in and invitation entry have their separate browser scopes.
These placements are inventoried, not changed. See the [router](../../apps/cadence_web/lib/cadence_web/router.ex).

Authorization, runtime DTO admission, resource identity from path captures, signed release
admission, and server-owned durable state are strengths to preserve. Choosing an SPA does
not require replacing Phoenix, weakening policies, or introducing browser-stored credentials.

## Page data freshness

`Snapshot/manual` means the inspected route loads on entry, a captured read, navigation,
or a local action/reload, with no dedicated resource subscription found in its current
host. Other context updates may incidentally reload it. The shared shell's timer does
not imply that its page body is reread. `Event-driven` identifies a change path, not a
guarantee of lossless delivery or bounded latency.

Only `commanding.workspace` currently declares `query: "live"` among the 41 compiled
Ops route contributions. Settings, configuration, and notifications receive updates
through other host mechanisms, so this is not a count of all live features.
Sources: [Ops registrations](../apps/host/src/ops-workspace/features/module-pages/contributions.ts),
[read admission](../apps/host/src/ops-workspace/features/module-pages/OpsModulePage.vue),
[live commanding contribution](../modules/commanding/src/features/workspace/contribution.ts).

| Feature family                                   | Routes | Update behavior                            | Representative adapter                                                                                                |
| ------------------------------------------------ | ------ | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Organization home                                | 1      | snapshot/manual                            | [administration_page.ex](../../apps/cadence_web/lib/cadence_web/administration_page.ex)                               |
| Mission directory and creation                   | 3      | snapshot/manual                            | [mission_page.ex](../../apps/cadence_web/lib/cadence_web/mission_page.ex)                                             |
| Spacecraft inventory and profiles                | 8      | snapshot/manual                            | [spacecraft_page.ex](../../apps/cadence_web/lib/cadence_web/spacecraft_page.ex)                                       |
| Spacecraft configuration detail                  | 1      | event-driven                               | [spacecraft_configuration_page.ex](../../apps/cadence_web/lib/cadence_web/spacecraft_configuration_page.ex)           |
| Provider accounts                                | 3      | snapshot/manual                            | [provider_account_detail_page.ex](../../apps/cadence_web/lib/cadence_web/provider_account_detail_page.ex)             |
| Mission communications and spacecraft routing    | 16     | snapshot/manual                            | [communications_setup_page.ex](../../apps/cadence_web/lib/cadence_web/communications_setup_page.ex)                   |
| Spacecraft commanding configuration              | 1      | snapshot/manual                            | [spacecraft_module_page.ex](../../apps/cadence_web/lib/cadence_web/spacecraft_module_page.ex)                         |
| Catalog and import workflow                      | 6      | mixed upload events and snapshots          | [catalog_upload.ex](../../apps/cadence_web/lib/cadence_web/catalog_upload.ex)                                         |
| Ops overview                                     | 1      | snapshot/manual                            | [ops_landing_page.ex](../../apps/cadence_web/lib/cadence_web/ops_landing_page.ex)                                     |
| Ops timeline                                     | 1      | snapshot/manual                            | [ops_timeline_page.ex](../../apps/cadence_web/lib/cadence_web/ops_timeline_page.ex)                                   |
| Dashboard viewer share and playlist presentation | 3      | snapshot/manual                            | [ops_workspace_page.ex](../../apps/cadence_web/lib/cadence_web/ops_workspace_page.ex)                                 |
| Saved dashboard snapshot                         | 1      | intentional snapshot                       | [ops_shared_view_page.ex](../../apps/cadence_web/lib/cadence_web/ops_shared_view_page.ex)                             |
| Dashboard directory authoring and governance     | 8      | snapshot/manual                            | [ops_editor_page.ex](../../apps/cadence_web/lib/cadence_web/ops_editor_page.ex)                                       |
| Telemetry exploration                            | 1      | snapshot/manual                            | [ops_exploration_page.ex](../../apps/cadence_web/lib/cadence_web/ops_exploration_page.ex)                             |
| Commanding workspace                             | 1      | event-driven plus 30-second reconciliation | [ops_command_workspace_page.ex](../../apps/cadence_web/lib/cadence_web/ops_command_workspace_page.ex)                 |
| Other command pages                              | 8      | snapshot/manual                            | [ops_command_page.ex](../../apps/cadence_web/lib/cadence_web/ops_command_page.ex)                                     |
| Alarm conditions                                 | 1      | snapshot/manual                            | [ops_alarm_conditions_page.ex](../../apps/cadence_web/lib/cadence_web/ops_alarm_conditions_page.ex)                   |
| Contact schedule record and reservation review   | 3      | snapshot/manual                            | [ops_contact_scheduling_page.ex](../../apps/cadence_web/lib/cadence_web/ops_contact_scheduling_page.ex)               |
| Fleet planning                                   | 4      | snapshot/manual                            | [ops_fleet_workflow_page.ex](../../apps/cadence_web/lib/cadence_web/ops_fleet_workflow_page.ex)                       |
| Contact requirements and templates               | 4      | snapshot/manual                            | [ops_requirement_page.ex](../../apps/cadence_web/lib/cadence_web/ops_requirement_page.ex)                             |
| Contact plan review                              | 1      | snapshot/manual                            | [ops_plan_review_page.ex](../../apps/cadence_web/lib/cadence_web/ops_plan_review_page.ex)                             |
| Data sources and historical workflows            | 6      | snapshot/manual                            | [ops_data_sources_page.ex](../../apps/cadence_web/lib/cadence_web/ops_data_sources_page.ex)                           |
| Activation approvals                             | 1      | partial settings invalidation              | [activation_approvals.ex](../../apps/cadence_web/lib/cadence_web/activation_approvals.ex)                             |
| Notifications inbox                              | 1      | event-driven                               | [notifications_bell.ex](../../apps/cadence_web/lib/cadence_web/live/notifications_bell.ex)                            |
| Platform administration and diagnostics          | 6      | snapshot/manual                            | [platform_administration_page.ex](../../apps/cadence_web/lib/cadence_web/platform_administration_page.ex)             |
| Application installation inventory               | 2      | snapshot/manual                            | [application_management.ex](../../apps/cadence_web/lib/cadence_web/application_management.ex)                         |
| Organization and mission settings                | 4      | event-driven                               | [settings_page.ex](../../apps/cadence_web/lib/cadence_web/settings_page.ex)                                           |
| Contact SPA experiment                           | 2      | 5-second polling                           | [contact_workspace_controller.ex](../../apps/cadence_web/lib/cadence_web/controllers/contact_workspace_controller.ex) |

The CSV gives each route its feature and primary adapter. Grouped rows summarize shared
behavior; they do not imply that all actions in a family have the same durability.

The highest-impact distinctions are:

- **Alarm conditions:** the page has an explicit captured read and a “Refresh conditions”
  control. It has no live read port. Updating the shell alarm count does not update this
  condition list. [Panel](../modules/limits-and-alarming/src/features/alarm-conditions/AlarmConditionsPanel.vue)
- **Published dashboard viewer:** `time_mode: live` chooses the read's time context, while
  the renderer displays a snapshot and explicitly installs a no-op chart runtime port.
  A lower-level chart supports append events, but that does not connect the ordinary viewer
  to a producer. This is an intentional current boundary and an Ops product capability gap.
  Immutable saved snapshots should remain immutable.
  [Canvas](../modules/dashboards-and-exploration/src/features/workspace/WorkspaceSnapshotCanvas.vue),
  [viewer](../modules/dashboards-and-exploration/src/features/workspace/DashboardWorkspace.vue),
  [chart port](../modules/dashboards-and-exploration/src/features/workspace/chart-runtime.ts)
- **Commanding:** the new workspace consumes scoped invalidations, but standalone monitor,
  history, stage, and review routes do not inherit that subscription. The monitor component
  can also be embedded in the live workspace; component reuse does not make both route
  paths equivalent. [Workspace](../../apps/cadence_web/lib/cadence_web/ops_command_workspace_page.ex),
  [monitor registration](../modules/commanding/src/features/mission-commands/contribution.ts)
- **Contact experiment:** both resources poll; notifications, fleet posture, and alarms in
  its shell are not subscribed. Reservation review still leaves the SPA. The experiment is
  a navigation proof, not a completed real-time workspace.

## Timers and subscriptions

| Mechanism                                          | Current behavior                                                                                  | Classification and disposition                                                                                                |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Phoenix socket heartbeat                           | Installed JS client defaults to 30 seconds; app does not override                                 | Connection liveness; does not schedule data updates                                                                           |
| Ops shell refresh                                  | 15 seconds per connected host after Ops hook installation; reads only while Ops context is active | Data polling for fleet health, alarm and command summaries; replace relevant reads with change propagation                    |
| Command shell and workspace invalidation           | 250 ms after a relevant change; coalesces bursts                                                  | Event batching; retain bounded batching where appropriate                                                                     |
| Command workspace reconciliation                   | 30 seconds while its page session is active                                                       | Periodic fallback for missed notices and shared catalog/access changes; replace only after recovery and source coverage exist |
| Contact experiment                                 | Five seconds for visible active queries; also mount/focus/reconnect reads                         | Resource polling; replace before promotion                                                                                    |
| UTC clock and opportunity expiry                   | One-second local timers                                                                           | Presentation/time-dependent validity; no data polling                                                                         |
| Chart activity timers                              | Derived from incoming update cadence                                                              | Freshness indicators, not a stream producer                                                                                   |
| Search/layout debounces and request/load deadlines | One-shot timers tied to local work                                                                | Interaction scheduling and failure detection; do not remove as polling                                                        |
| Catalog upload drain                               | 10 ms retry while completion waits for LiveView upload processing                                 | Upload coordination; requires replacement if upload transport changes                                                         |
| Job runner and provider reconciliation             | Server execution/recovery lifetimes                                                               | Outside browser refresh policy; inventory separately before changing                                                          |

Sources: [socket setup](../../apps/cadence_web/assets/js/app.js),
[Ops hook](../../apps/cadence_web/lib/cadence_web/live/ops_shell_hook.ex),
[Ops interval](../../apps/cadence_web/lib/cadence_web/live/ops_shell_hook/context_deps.ex),
[command batching](../../apps/cadence_web/lib/cadence_web/live/ops_shell_hook/command_updates.ex),
[command reconciliation](../../apps/cadence_web/lib/cadence_web/ops_command_workspace_page.ex),
[query defaults](../apps/host/src/ops-workspace/features/contact-workspace/client.ts),
[expiry clock](../modules/planning-and-contacts/src/features/contact-scheduling/schedule-draft.ts),
[chart activity](../modules/dashboards-and-exploration/src/features/workspace/chart-live.ts),
[upload coordination](../../apps/cadence_web/lib/cadence_web/catalog_upload.ex).

The shared [ScopedReadUpdates](../../apps/cadence/lib/cadence/platform/scoped_read_updates.ex)
publishes PubSub notices outside transactions; nested callers defer publication to the
outer transaction owner. It does not persist an outbox or replay cursor. The
[EventBus](../../apps/cadence/lib/cadence/platform/event_bus.ex) explicitly leaves missed
delivery reconciliation to durable owners. Contacts and limits already expose typed facts,
but facts alone do not establish delivery to a browser resource.

The useful existing browser subscription paths are commanding changes, settings changes,
spacecraft configuration changes, and per-user notifications. Trace every relevant producer,
including background jobs, before claiming complete coverage for any of them. Connection
status in [OpsWorkspaceFrame](../apps/host/src/ops-workspace/features/frame/OpsWorkspaceFrame.vue)
is distinct from whether each resource has caught up.

## State and operation ownership

| State                         | Current owner                                                            | Triage implication                                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Browser URL                   | Vue Router, with LiveSocket history suppression                          | Two lifecycle participants; normal navigation waits for `host:context`                                                    |
| Current server page           | `HostPageLive.host_path`, page tokens, sessions and subscriptions        | Context preparation mutates this before browser route commit                                                              |
| Normal page data              | Validated host snapshots and feature-local admitted snapshots            | Many custom refresh/recovery implementations; a patch is not always a resource reread                                     |
| Experiment resource data      | Scoped TanStack Query cache                                              | Clear lifetime, cancellation, cached Back; push delivery and automatic transient recovery remain absent                   |
| Settings/configuration drafts | Explicit host stores plus feature editors                                | Preserve as reference patterns; incoming data must not erase edits                                                        |
| Other drafts                  | Mostly component/composable lifetime                                     | Route persistence varies; set requirements per workflow rather than adding a universal store                              |
| Scheduling v2 commands        | Actor/scope-bound operation journal and durable jobs                     | Existing reference for immutable inputs, accepted effects and exact-operation recovery                                    |
| Fleet policy commands         | Durable latest-operation row per actor/mission                           | Useful but bounded recovery, not a general operation history                                                              |
| Other effect correlation      | Varies; data-source adapter keeps operation/sequence in the page session | Underlying jobs may persist while the UI loses its attempted-operation identity                                           |
| Federated action completion   | Shared generation-based lifecycle                                        | A later action can suppress an earlier effect's completion; requery failure can enter rejection handling after completion |

Sources: [history ownership](../apps/host/src/shell/host-browser-history.ts),
[host context preparation](../../apps/cadence_web/lib/cadence_web/live/host_page_live.ex),
[scheduling architecture](contact-scheduling-architecture.md),
[policy recovery](../../apps/cadence_web/lib/cadence_web/ops_fleet_policy_recovery.ex),
[data-source session](../../apps/cadence_web/lib/cadence_web/ops_data_sources_page.ex),
[federated action lifecycle](../packages/plugin-sdk/src/bridge.ts).

The existing `OpsPageNavigationPort` returns `void`, while another port reports
completed/cancelled/unchanged/failed. Monitor/history controls still depend on replacement
props to release navigation state. This remains relevant to the earlier unchanged-route
finding. Reusing Vue Router directly or a settled navigation port avoids that ambiguity.
See [ports](../packages/plugin-sdk/src/ops-page-contribution.ts) and
[monitor](../modules/commanding/src/features/mission-commands/CommandMonitor.vue).

## Prioritized backlog

P1 means resolve before relying on the affected Ops behavior or expanding the experiment.
P2 means planned architecture or UX work. These are implementation priorities, not claims
of a production incident. Owners below are code areas, not assigned people.

| ID    | Priority                  | Work and owner                                                                     | Evidence and impact                                                                                                | Completion criterion                                                                                                                                                                                                                                                     |
| ----- | ------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| FE-01 | P1                        | Complete live resource coverage; Ops feature owners and web adapters               | Confirmed static gap for alarms, standalone command pages, contacts, timeline and other operational snapshots      | An external committed change reaches an idle mounted page automatically; declare and measure each resource's freshness budget; preserve filters and drafts                                                                                                               |
| FE-02 | P1                        | Deliver live telemetry to the dashboard viewer; dashboards and telemetry owners    | Confirmed no-op runtime port in the compiled snapshot canvas                                                       | Authorized bounded subscription, initial snapshot, ordered updates or explicit resync, cleanup, backpressure, and visible source freshness; historical/saved snapshots stay frozen                                                                                       |
| FE-03 | P1                        | Define shared subscription and recovery contract; platform, web and host           | Best-effort notices, partial source coverage, independent timers, no common replay/revision protocol               | Subscribe/snapshot race and change-during-read cannot leave stale state; reconnect catches up; scope/access loss invalidates authority; publication survives commit-to-notification failure through a durable mechanism or an explicitly justified reconciliation policy |
| FE-04 | P1                        | Remove route/session disagreement and settle navigation; host                      | Earlier cancelled-navigation reproduction; unchanged preparation-before-commit mechanism remains in current source | A→B→A, cancelled/duplicate navigation, timeout and late reply leave the visible page usable and subscribed; no stuck navigation flags. Resource APIs independent of a mutable server page are the preferred target                                                       |
| FE-05 | P1 for external effects   | Inventory and extend operation recovery; domain owners                             | Scheduling v2 improved; policy has bounded persistence; other page-session correlations remain                     | Per action, document acceptance, immutable identity/input, concurrency, durable execution, uncertain outcome and recovery after navigation/process loss; never infer success or blindly repeat an effect                                                                 |
| FE-06 | P2, dependent on recovery | Remove routine refresh dependence; feature owners                                  | 91 control candidates, not 91 defects                                                                              | Automatic reads/reconnect/retry handle recoverable failures; routine refresh buttons disappear after proof. Preserve deliberate retry of an operation and draft-discard semantics; rename or redesign separately where needed                                            |
| FE-07 | P2                        | Separate read supersession from effect accounting in federation SDK                | Earlier overlapping-action reproduction; generation suppression and completion/requery catch remain                | Each accepted effect keeps its outcome independently; a failed reread cannot convert success into failure; overlapping independent actions retain both outcomes                                                                                                          |
| FE-08 | P2, target decision first | Adopt one application navigation/data owner and retire replaced adapters; host/web | Four host paths, duplicated context/action orchestration, LiveView upload dependency                               | Record the SPA target and migration boundary; migrate whole workflows, preserve auth and release admission, replace uploads deliberately, and delete superseded route/session/history machinery as routes move                                                           |
| FE-09 | P2                        | Measure responsiveness and freshness; host/domain read owners                      | Existing 41 ms experiment measures click-to-loading only; synchronous work shares a LiveView mailbox               | Compare cold/warm navigation, data-ready latency, event-to-display lag and reconnect catch-up under representative latency, data volume and concurrent operations                                                                                                        |
| FE-10 | P1, cross-cutting         | Add real producer-to-browser freshness gates; frontend/web/domain tests            | Current tests exercise admission, manual refresh and selected notices; no universal freshness gate                 | A second actor/job changes data while the page is untouched; disconnect/rejoin, publication failure, duplicates, late reads, revoked access and navigation are covered using actual producer paths                                                                       |

## Recommended sequence

1. **Specify freshness and recovery for alarms, command execution, contacts and telemetry.**
   Separate low-rate resource invalidations from high-rate telemetry delivery. Establish
   FE-10 scenarios and trace committed producers before choosing transport details.
2. **Build the shared resource subscription contract with contacts and alarms as references.**
   Contacts provides durable command recovery and the SPA resource boundary; alarms forces
   proof that another producer updates an idle page. Complete reservation review and live
   shell context before promoting the contact experiment. This addresses FE-01/03/06 without
   treating removal of a timer or button as completion.
3. **Complete telemetry streaming and align commanding.** Preserve the existing working
   commanding subscription while replacing its reconciliation fallback only when its
   producer/recovery coverage warrants it. Resolve standalone monitor/history ownership.
4. **Migrate complete route families to the agreed SPA host and retire old implementations.**
   Prioritize Ops, then management workflows. Audit effect lifetimes before migrating each
   family. Replace LiveView-specific catalog uploads deliberately; keep session transitions
   and downloads as server endpoints. Run the latency comparison before claiming a speedup.

The proposed SPA uses Vue Router for navigation, TanStack Query for resource reads, Vue
for local interaction state, and authenticated Phoenix Channels for live delivery. Pinia
is an option for demonstrated shared client state, not a substitute for query caching,
durable operations, or synchronization. The [experiment](contact-workspace-experiment.md) remains
isolated until its workflow and freshness criteria pass.

## Refresh control interpretation

The Vue template scan excludes Storybook and the contract-probe app from the delivered
CSV and does not count tests. It includes ordinary and compatibility components, which
may be reused on multiple screens. It does not cover every dynamically supplied label,
non-button link, HEEx control, or installed third-party surface.

The initial triage yields 53 read-refresh candidates, 33 read-recovery candidates,
three effect retries, one validation retry, and one explicit saved-draft reload.
These are candidates for handler review, not a blanket removal patch. In particular:

- “Retry acceptance” reuses a scheduling operation's immutable identity.
- “Retry deployment” and retrying failed historical-work items are domain effects.
- “Reload saved draft” has an editing/discard decision distinct from data freshness.
- Live resources should recover transient read failures automatically with bounded backoff.
  Permanent denial or invalid input needs an appropriate state, not endless retries.
- Automatic incoming data must preserve uncommitted edits and require renewed review when
  the evidence for a command changes.

## Verification and remaining evidence

Current focused checks passed: **207 tests across nine files**, with one additional
producer-dependent test explicitly skipped because its producer fixture was not supplied.
The sets were 169 host tests, ten dashboard tests, and 28 commanding tests. These validate
current behavior and protections; they do not close the gaps above.

Commands from `frontend/`:

```sh
corepack pnpm --filter @cadence/plugin-host exec vp test --run src/shell/BrowserHost.test.ts src/ops-workspace/features/module-pages/alarm-conditions.test.ts src/ops-workspace/features/module-pages/read-port.test.ts src/ops-workspace/features/contact-workspace/workspace.test.ts
corepack pnpm --filter @cadence/dashboards-and-exploration exec vp test --run src/features/workspace/DashboardWorkspace.test.ts src/features/workspace/chart-runtime.test.ts src/features/workspace/ownership.test.ts
corepack pnpm --filter @cadence/commanding exec vp test --run src/features/workspace/CommandWorkspacePage.test.ts src/features/workspace/CommandWorkspace.test.ts
```

The inventory counts were derived from the current router/catalog and Vue template ASTs.
CSV parsing, route reconciliation, source locations, Markdown links and formatting are
checked with this documentation change. Existing test sources show real command notice and
settings invalidation coverage; their backend suites were not rerun for this audit.
The old cancelled-navigation and federated-effect failures remain historical reproductions
with current source evidence, not newly executed reproductions.

No application behavior, routes, timers, controls or dependencies change in this audit.
Full frontend acceptance, production browser/producer gates, and `mix precommit` are not
rerun for documentation-only work, following [frontend validation rules](../AGENTS.md).
Freshness acceptance requires FE-10's actual producer-to-browser checks; component fixtures
and a connected indicator are insufficient evidence. Existing CI already separates frontend
quality from producer/federation browser checks in the [workflow](../../.github/workflows/frontend.yml).
