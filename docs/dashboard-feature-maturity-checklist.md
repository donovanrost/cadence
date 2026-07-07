# Dashboard Feature Maturity Checklist

This checklist tracks dashboard maturity by product capability, not by the age
of the current implementation. It is intentionally allowed to move as the
dashboard engine, data-source model, operational-event spine, and TSDB plumbing
settle.

## Current Status

| Area | Status | Current proof | Remaining maturity work |
| --- | --- | --- | --- |
| Document model | Complete; monitor for new lifecycle states | Canonical dashboard documents persist through `ops_dashboards`, immutable `dashboard_versions`, latest/draft/published pointers, lifecycle events, publish/revert/archive/restore flows, and canonical list/new/show LiveViews. | Re-open only if dashboard branching, review workflows, or sharing semantics add new document lifecycle states. |
| Engine contract | Complete; monitor for source/widget expansion | `Engine.plan/1` and `Engine.resolve/2` batch placement source requests, execute logical sources through `SourceRegistry`, materialize frames, and validate planned requests/source results against widget frame contracts. | Re-open when new frame shapes, source capabilities, or widget-frame contract dimensions are added. |
| Runtime contexts | Partial | URL/session/document defaults hydrate `TimeContext`, `ScopeContext`, `DataContext`, and `LimitContext`; runtime controls preserve live/archive/replay time modes, data realm, source binding, data view, limit semantics, and typed scopes for mission, spacecraft, contact, ground station, source endpoint, transport, and link. The context selector can apply and clear multi-spacecraft, multi-contact, and multi-entity operational-resource scope sets, including setup-backed ground-station and link sets, from search results, producing durable `scope_ids` routes instead of requiring hand-edited URLs. | Keep broadening source-specific semantics for contact, multi-entity comparison overlay behavior, and non-telemetry scope behavior. |
| Source registry and logical source contracts | Complete; monitor for new source families | Telemetry, limits, events, and operational observables share capability, product metadata, physical source product narrowing, unsupported product posture, health/freshness/watermark, timeout, circuit-open, degraded-result, and source-action contracts. Operational-observable capabilities now expose explicit source-backed contracts tying observable groups to sampling modes, products, product families, and frame shapes; engine publish validation, runtime capability posture, and source-remediation candidate matching consume those contracts for latest, state-history, aggregate, and raw-series families, with tests proving backed ids and advertised products cannot drift. | Re-open when new source families, adapters, or capability dimensions are added. |
| Managed QuestDB path | Complete; monitor for ops expansion | Managed QuestDB migrations, canonical writes, bounded reads, native decimation, watermarks, source-health diagnostics, org/mission isolated provisioning, durable redacted provisioning jobs, retry/failure behavior, provisioning Mix task, source/job deployment status contract, deployment-run operator visibility, failed-run retry action, and stuck-run requeue action have proof. | Re-open for schema expansion, deployment allocator UI, probe policy, or stronger physical isolation operations. |
| BYO TSDB path | Partial | Customer-owned adapter execution, setup/probe/disable/enable flows, readiness fields, browser readiness proof, env-profile production material resolution, external secret-manager material resolution with redacted success/failure audit events, credential-material authorizer enforcement, adapter-reported capability discovery/materialization, classified probe diagnostics/remediation hints, timeout/circuit isolation, and external QuestDB smoke path exist. | Add RBAC/user-permission integration and deployment operations for dedicated org/mission TSDB backends. |
| Data management semantics | Partial | Canonical/as-recorded/all-revisions/recomputed read views participate in cache identity, source provenance, data links, telemetry explore links, diagnostics, source overlays, warning badges, late-data workflows, revision/correction decisions, and dashboard-side comparison review decisions including degraded partial-failure bulk outcomes. | Continue proving broader guided correction/import/replay workflows and policy handoffs. |
| Operational event dependency | Partial | Durable event envelopes, store/projectors, binding/catalog/source/limit/dashboard/data-management lifecycle rows, selected-clock audit events, contact intervals, transport execution/action/timer facts, runtime facts, connection/RF state facts, generic operational-observable state facts including antenna pointing, metric sample facts, replay-scoped readers, latest connection/RF state frame evidence back to canonical intervals/source events, antenna pointing frame evidence back to generic operational-observable state intervals/source events, and latest/metric-history frame evidence back to canonical metric sample events are in place. | Derive richer runtime/link/RF projections from canonical facts and broaden selected interval evidence for new source/runtime evidence origins. |
| Limits over time | Partial | Limit-mode preservation spans durable event payloads, late-data policy workflows, revision/correction decisions, compare/current/recomputed modes, replay-scoped reads, replay browser proof, and replay audit-only late-data decisions. | Broaden operator handoffs, replay browser coverage, and historical correctness workflows. |
| Replay workflow | Partial | Replay-run selection, progress clock/window metadata, source readiness warnings, replay-preserving copy/deep links, telemetry/latest/history reads, limits reads, Events and Operational Observables replay context, mission timeline/contact interval rows, replay `contacts.phase` state-timeline context, replay operational-observable readers, replay latest operational connection data-table row identity/DataLinks/frame evidence, replay RF state data-table row identity/frame evidence, replay antenna pointing state-timeline DataLinks/frame evidence, and replay transport-execution state-timeline degraded source-health provenance with replay source binding/run context are covered. | Tie remaining maturity to richer runtime-derived replay views as the operational-event spine matures. |
| Scope product surface | Partial | Runtime query hydration accepts mission, spacecraft, contact, ground-station, source-endpoint, transport, link, and multi-id scope URLs. Contact scopes fail closed through validation, operational resources validate setup-backed ids, unsupported operational-observable scope pairings fail closed before source execution, and rendered browser coverage proves scoped contact/source-endpoint no-data, mission-scoped/contact-scoped/multi-contact/spacecraft-scoped/source-endpoint-scoped/ground-station-scoped/multi-source-endpoint/multi-ground-station operational contact-phase timelines, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport connection-state timelines, multi-link transport-execution timeline filtering/DataLinks/frame evidence with non-primary row preservation, source-endpoint/ground-station/link operational-resource DataLinks, non-primary selected-resource/contact DataLinks and row frame evidence inside multi-source-endpoint, multi-transport, multi-contact, and multi-resource contact-phase scopes, non-primary multi-transport latest data-table row DataLinks/frame evidence with full query-scope preservation plus related source-endpoint/ground-station/link selected-ref handoff context, selected-resource query params serialize related operational-resource context, same-kind runtime scope changes clear selected operational-resource refs and selected-query keys once the selected resource leaves the current scope set, link-scoped and multi-link RF rows with non-primary DataLinks/frame evidence, multi-spacecraft command queue aggregate filtering/evidence, multi-spacecraft ingress-latency endpoint fan-out/evidence, unsupported-scope value-tile/time-series lifecycle blocking, and operator-selected multi-spacecraft, multi-contact, multi-ground-station, multi-link, multi-transport, plus multi-source-endpoint runtime scope controls. | Continue extending source-specific semantics and UI coverage for mission aggregate, ground-station, transport, source-endpoint, link, contact, multi-entity, and comparison scopes. |
| Operational observables | Partial | Backed registry/source coverage proves replay/source-binding propagation, source-backed capability contracts, scope filtering, freshness/staleness, missing snapshot warnings, unsupported observable scope blocking, connection/RF state timelines, antenna pointing state timelines, transport-execution history filtering across transport/contact/source-endpoint/ground-station/link scopes including multi-link fan-out, connection/RF latest rows with canonical interval/source-event evidence when backed by operational events, antenna pointing latest/history rows with generic operational-observable interval evidence, replay-isolated antenna pointing history, transport bitrate, RF SNR/Eb/N0/symbol-rate/Doppler metrics, ingress latency latest/history including multi-spacecraft filtering with source-endpoint row identity, contact phase including mission-scope rendering, multi-contact event-history filtering, direct source-endpoint filtering, multi-source-endpoint filtering, and spacecraft/ground-station/multi-ground-station filtering through source-endpoint ownership, command queue empty-zero/reader-failure behavior including source-endpoint scoped zero/stale rows and multi-spacecraft aggregate rows that do not mislabel the first spacecraft, fail-closed source-unavailable reader errors, and runtime-health ingress overlays. Browser/presenter coverage proves mission-scoped, contact-scoped, replay contact-scoped, multi-contact, spacecraft-scoped, source-endpoint-scoped, ground-station-scoped, multi-source-endpoint, and multi-ground-station contact-phase state timelines, value-tile links including link-scoped RF Doppler, unsupported-scope value-tile/time-series blocking, replay RF/transport history charts with canonical metric sample event frame evidence, mission aggregate command queue depth, multi-spacecraft command queue depth with preserved `scope_ids`, multi-spacecraft ingress latency fan-out with preserved endpoint DataLinks and `scope_ids`, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport transport/ground-station connection-state timelines, live and replay ground-station scoped antenna pointing state timelines with source-endpoint/ground-station DataLinks and native interval evidence, multi-link transport-execution state timelines with non-primary row identity, resolved transport DataLinks, preserved `scope_ids`, selected-scope copy payloads, frame evidence, valid link-scoped no-data lifecycle/source metadata without invented rows or DataLinks, source-unavailable lifecycle/source-badge projection when the operational source cannot answer, and live/replay degraded source-health source-status/source-badge projection plus row source-health event handoff while rows remain rendered and replay source binding/run context is preserved, rendered latest connection/RF status-matrix and data-table row frame evidence with canonical interval and source-event refs, rendered link-scoped RF status-matrix rows with link/transport/source-endpoint/ground-station DataLinks, non-primary multi-transport latest connection data-table row identity/DataLinks/frame evidence with canonical interval and source-event refs, non-primary multi-link RF data-table row identity/DataLinks/frame evidence with canonical interval/source-event refs and preserved `scope_ids`, replay latest connection data-table row identity/DataLinks/frame evidence with replay source binding, replay dataset, replay run, and canonical interval/source-event refs, replay RF lock/frame-sync data-table row identity/frame evidence with replay source binding, replay dataset, replay run, and canonical interval/source-event refs, source-endpoint command queue depth filtering/DataLinks in status-matrix, value-tile, and data-table widgets, status-matrix/data-table row frame evidence with dashboard query-scope preservation, source-endpoint empty-zero command queue DataLinks/frame evidence in the data-table path, source-endpoint stale command queue data-table row links/lifecycle, command queue source-unavailable data-table lifecycle/error projection, source-endpoint ingress latency row/chart DataLinks, partial multi-source-endpoint ingress-latency metric-history lifecycle/source metadata with returned-only endpoint chart data and no invented missing-endpoint point DataLinks, zero-point replay/archive no-data lifecycle/source metadata plus query/source-evidence route/copy context for link-scoped RF SNR/EbN0/mixed metric and transport-scoped bitrate histories, partial mixed RF and transport-bitrate metric-history lifecycle/source metadata with returned SNR/downlink-only chart data and no invented symbol-rate/uplink series, and frame evidence/copy payloads. | Add projections/streams for future observable families and keep proving freshness, missing snapshots, history contracts, and row/point/resource DataLinks across supported widgets. |
| Widget coverage | Partial | Status matrix, data table, value tile, time-series, and state-timeline coverage includes operational contact-phase timelines including mission-scoped, multi-contact, spacecraft-scoped, source-endpoint-scoped, ground-station-scoped, multi-source-endpoint, and multi-ground-station state-timeline rows, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport connection-state timelines, multi-spacecraft command queue aggregate status-matrix rows, multi-spacecraft ingress-latency status-matrix rows, operational metric value tiles, unsupported-scope blocked value tiles and time-series widgets with lifecycle-tagged notices and no chart/data-link affordances, rendered context-bound value-tile retention-gap and source-unavailable source-failure fallbacks without unresolved fallback, nil source-empty-reason leakage, or invented sample links, rendered telemetry latest data-table/status-matrix source-unavailable blocking without placeholder rows, row DataLinks, or row frame-evidence controls, rendered telemetry time-series source-unavailable blocking without chart hooks, chart markers, or synthetic point series, rendered telemetry time-series source-degraded preservation of chart data with warning source badge/evidence, rendered telemetry time-series stale preservation of chart data with warning source badge/evidence, rendered telemetry time-series unknown-watermark preservation of chart data with unknown source badge/evidence, rendered telemetry time-series retention-gap preservation of chart data with retention source badge/evidence, rendered telemetry time-series no-data blocking without chart hooks, point links, markers, or synthetic series, row-widget empty states with lifecycle-tagged `no_data` notices for status matrix, data table, state timeline, and event timeline bodies, rendered source-endpoint no-data data-table, status-matrix, state-timeline, and event-timeline body notices without placeholder rows, partial telemetry range lifecycle with returned-series chart rendering and chart-point telemetry-sample DataLinks, partial operational metric-history lifecycle with returned-series chart rendering and no invented missing series, telemetry time-series retention-gap/source-watermark cursor markers from durable watermark status plus selected-source and selected-dataset scoped persisted source-watermark event overlays, partial telemetry latest data-table and status-matrix lifecycle with only returned rows rendered, empty telemetry latest value-tile no-data lifecycle without invented sample rows/links, stale telemetry latest value-tile rendering with sampled value plus unknown source freshness, fresh telemetry latest value-tile rendering after persisted source watermark confidence, RF metric value tiles including Doppler, source-endpoint scoped command queue value tiles, missing-snapshot value tiles, operational no-data source badges, stale data-table row warnings, operational data-table frame evidence, mixed operational data-table rows flattened from multiple product frames with row DataLinks/frame evidence, stale metric lifecycle preservation, and degraded source-health preservation, RF/connection/transport-execution timelines, link-scoped transport-execution no-data state-timeline lifecycle without invented lanes/rows/links, transport-execution source-unavailable state-timeline lifecycle/source badge without invented rows/links, live and replay transport-execution degraded source-health state-timeline source badge plus row source-health event DataLink while rows remain rendered and replay context is preserved, chart-point DataLinks, chart legend hide/show guarding and grouped/shared axis toggling for multi-series time-series widgets, and selected-interval evidence. | Fill richer table/grid variants, lifecycle states, degraded/empty/partial/stale states, and remaining browser-level grid/chart interaction behavior. |
| Data links and evidence | Partial | DataLink parsing/resolution, selected-ref route/copy payloads, browser-proven multi-scope selected-ref and non-primary row frame-evidence preservation for `scope_ids`/`selected_scope_ids`, canonical operational-event inspectors, mission-event-to-operational-event related links, aggregate command queue frame evidence including multi-spacecraft aggregate copy/evidence without invented single-resource links, mission-aggregate connection-state resource links/frame evidence, contact-phase state-timeline contact DataLinks/frame evidence including replay context and non-primary beta contact route/copy payloads inside multi-contact scope, spacecraft-scope routes preserving legacy `spacecraft_id`, and source-endpoint/ground-station routes preserving generic `scope_kind`/`scope_id`, rendered latest connection/RF status-matrix and data-table rows opening canonical interval and operational-event evidence refs, browser-proven link-scoped RF status-matrix rows exposing link DataLinks alongside transport/source-endpoint/ground-station DataLinks, non-primary multi-transport data-table connection rows opening resolved transport DataLinks plus canonical interval/source-event frame evidence while preserving `scope_ids` and selected-scope copy payloads, non-primary multi-link RF data-table rows opening resolved transport DataLinks plus canonical RF-lock interval/source-event frame evidence while preserving `scope_ids` and selected-scope copy payloads, non-primary multi-link transport-execution state-timeline rows opening resolved transport DataLinks plus frame evidence while preserving `scope_ids` and selected-scope copy payloads, replay data-table connection rows opening resolved transport DataLinks plus replay canonical interval/source-event frame evidence while preserving replay source binding, replay dataset, replay run, and selected-scope payloads, replay RF state data-table rows opening replay canonical RF-lock/frame-sync interval and source-event frame evidence while preserving replay source binding, replay dataset, and replay run, source-endpoint command queue row DataLinks and query-scoped frame evidence across status-matrix and data-table render paths, source-endpoint command queue value-tile DataLinks with source-bound and query-scoped widget-frame evidence attrs, multi-spacecraft ingress-latency endpoint DataLinks/frame evidence plus multi-source-endpoint ingress-latency metric-history widget source-status/query diagnostics, partial returned-endpoint chart DataLinks without invented missing-endpoint point links, and widget-frame evidence with source identity plus `scope_ids`/`selected_scope_ids` route/copy preservation, command queue source-unavailable placement/dashboard warning projection, source-endpoint ingress latency frame evidence, telemetry time-series durable source-watermark cursor source evidence and selected-source/selected-dataset persisted source-watermark event DataLinks, RF/transport history chart-point links, selected binding/application interval evidence, latest telemetry data-table and status-matrix row telemetry-sample DataLinks and frame evidence with source/scope context, empty telemetry value-tile source evidence without invented sample DataLinks, stale telemetry value-tile telemetry-sample DataLink and widget-frame evidence preservation under unknown source freshness, latest operational metric value-tile, status-matrix row, and data-table row operational-event frame evidence, replay metric-history operational-event frame evidence including partial returned-series evidence, and replay state-timeline operational-event links have proof. | Keep open for browser-level proof of any new rendered link or evidence origin. |
| Runtime cache and invalidation | Complete; monitor for new runtime boundaries | Runtime cache keys, source-result preflight, frame materialization, refresh/backpressure decisions, invalidation boundaries, freshness evidence, and runtime diagnostics are covered. | Re-open only when new cache layers, invalidation boundaries, or source execution families are added. |
| Investigation workflows | Partial | Historical request submission, approved/started/completed/retried/corrected workflow states, group recovery, replacement retry/stale/missing-job recovery, comparison review request/resolution, and bulk correction decisions, including partial-failure degraded browser outcomes, have browser and persistence proof. | Continue turning action surfaces into guided workflows with bulk selection, approval/start/correction/retry policy semantics, job progress, and audit trails. |
| Governance and permissions | Deferred RBAC/authz platform dependency | Existing dashboard actions rely on current authentication boundaries and `todo(authz)` markers where authorization policy will be needed. | Add authorization checks and action audit visibility once the broader RBAC model exists. |
| Browser/UI verification | Partial | Chrome/DevTools smoke covers dashboard assets, real sign-in, endpoint navigation, LiveSocket/GridStack/uPlot readiness, layout persistence, reload/deep-link hydration, source/version/diagnostic panels, runtime controls including multi-spacecraft, multi-contact, multi-ground-station, multi-link, multi-transport, and multi-source-endpoint context selection/clear, workflow submissions, comparison decisions, repeated placement rendering, contact/source-endpoint no-data evidence, mission-scoped/contact-scoped/replay contact-scoped/multi-contact/spacecraft-scoped/source-endpoint-scoped/ground-station-scoped/multi-source-endpoint/multi-ground-station contact-phase state-timeline rows/DataLinks/frame evidence including replay source context, non-primary contact route/copy preservation, legacy `spacecraft_id` route preservation, generic operational-resource `scope_kind`/`scope_id` route preservation, and multi-resource `scope_ids`/`selected_scope_ids` route preservation, unsupported operational-observable scope lifecycle blocking for value tiles and raw time-series, source-endpoint/ground-station/link operational-resource DataLinks, mission and multi-spacecraft aggregate command queue frame evidence, multi-spacecraft ingress-latency endpoint rows/DataLinks/frame evidence, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport connection-state state-timeline rows/DataLinks/frame evidence including non-primary beta transport and ground-station route/copy payloads, live and replay ground-station scoped antenna pointing state-timeline row/DataLink/frame-evidence proof with generic operational-observable interval evidence, multi-link transport-execution state-timeline row/DataLink/frame-evidence proof with `scope_ids` and selected-scope copy preservation plus valid link-scoped no-data lifecycle/source metadata without invented rows or DataLinks, source-unavailable lifecycle/source-badge projection without invented rows or links, and live/replay degraded source-health source-status/source-badge projection plus row source-health event DataLink while rows remain rendered and replay source binding/run context is preserved, non-primary multi-link RF data-table DataLink/frame-evidence proof with `scope_ids` and selected-scope copy preservation, replay latest operational connection data-table row/DataLink/frame-evidence proof with replay source binding and dataset preservation, replay RF state data-table row/frame-evidence proof with replay source binding and dataset preservation, source-endpoint command queue DataLink and query-scoped frame-evidence proof for status matrix, value tile, and data table, mixed source-endpoint operational data-table proof for command queue plus ingress latency rows flattened from separate product frames with both row DataLinks, command row frame evidence, ingress metric-sample event evidence, stale mixed-widget lifecycle/row-warning preservation, degraded source-health widget source status, source evidence, row source-health DataLink, and preserved row actions, multi-source-endpoint ingress-latency time-series source-status/query diagnostics, partial returned-endpoint chart rendering without invented missing-endpoint point DataLinks, and query-scoped widget-frame evidence, source-endpoint empty-zero command queue data-table proof, presenter-level source-endpoint stale command queue data-table proof with metric sample operational-event frame evidence, telemetry time-series durable source-watermark cursor/source evidence, retention-gap marker rendering before the first sample, and selected-source/selected-dataset scoped persisted event overlay DataLinks, partial telemetry range lifecycle/source-badge/chart rendering plus chart-point telemetry-sample DataLinks, partial operational metric-history lifecycle/source-badge/chart rendering plus operational-resource chart DataLinks and returned-sample frame evidence, telemetry time-series source-unavailable source-badge/evidence blocking without chart hooks or synthetic point series, telemetry time-series source-degraded chart preservation with warning source badge/evidence, telemetry time-series stale chart preservation with warning source badge/evidence, telemetry time-series unknown-watermark chart preservation with unknown source badge/evidence, telemetry time-series retention-gap chart preservation with retention source badge/evidence, telemetry time-series no-data source-badge/evidence blocking without chart hooks, point links, markers, or synthetic series, partial telemetry latest data-table/status-matrix lifecycle and row DataLink/frame-evidence preservation, empty telemetry latest value-tile no-data lifecycle/source evidence, stale telemetry latest value-tile sampled rendering with source badge, telemetry-sample DataLink, and frame evidence preservation, fresh telemetry latest value-tile sampled rendering after persisted source watermark with fresh source status and no warning badge, ingress latency row/chart DataLinks, RF/transport metric history charts plus latest metric value tiles including RF Doppler and ingress-latency status-matrix rows including metric sample operational-event frame evidence, multi-series legend hide/show guarding, mixed-unit grouped/shared axis toggling, generic source-capability blocker labels, latest/aggregate source-product picker guidance, no-data lifecycle, RF/connection/transport-execution state timelines, and BYO source readiness. | Keep the harness current as product workflows and dashboard surfaces expand. |

Recent evidence note: operational metric-history no-data coverage now includes
source-endpoint-scoped `ingress.processing_latency_ms` in both replay and
archive paths. The rendered browser proof blocks chart mounting, preserves
query/source evidence and copy/source-inventory routes, and avoids synthetic
point DataLinks when no ingress-latency samples exist in the selected window.
The populated degraded-source replay path also proves ingress-latency history
keeps returned chart samples and source-endpoint point DataLinks while surfacing
degraded source status, source badge state, and source-health transition marker
DataLinks for the replay source binding/run.
The source-unavailable archive path now proves ingress-latency history blocks
chart hooks, point links, markers, and synthetic series on source failure while
preserving unavailable source status, source-endpoint execution scope, and
query/source evidence plus copy context.
Contact-scoped ingress latency now has source and rendered proof: ingress
metric-sample events can carry contact ids from raw evidence metadata, latest and
history source frames filter by contact, status-matrix rows preserve endpoint
identity plus `contact_id`, and browser coverage proves contact-scope filtering,
resolved row contact DataLinks, timestamp-less URL-selected contact DataLink
state, and contact-scoped frame evidence/copy payloads.
The shared ops context rail now has focused component proof for its reusable
server-rendered contract: rail hook metadata, stable collapsed/expanded section
keys, per-section status/count metadata, hidden-section filtering, and the
mission fleet-health baseline rail. Dashboard-specific rail sections also carry
stable keys for health, source status, source selection, and comparison rollup.
The live authenticated dashboard browser smoke now proves the right rail
renders on the real page, exposes dashboard health/source status/source
selection metadata, collapses through the `NavRail` hook, persists collapsed
state through reload via `localStorage`, and re-expands cleanly.
Widget source-status diagnostics now carry source-health transition state,
reason, and event ids through widget shell attrs, source badges, query
diagnostics, and evidence-open attrs. Focused presenter/component tests prove a
degraded source can remain actionable even when the only available context is
the source-health event itself.
Rendered browser proof now covers the same diagnostic chain for a degraded
telemetry time-series widget: the ready widget preserves chart data while the
widget shell, source badge, query diagnostics, query evidence button, opened
source evidence route, and copied evidence URL all retain the source-health
state, reason, and source-health event id.
Historical workflow group recovery handoffs now encode failed-item compact
fields at the durable group-summary boundary and decode them in dashboard
navigation presenters, so operator-facing failed item labels with spaces remain
intact in retry/correction handoff links and rendered recovery controls.
Rendered browser proof now covers the same encoded failed-item handoff path:
a grouped correction workflow seeds `HK counter`, verifies the compact
`label=HK%20counter` event boundary, renders the decoded handoff label, opens
the failed lifecycle event, preserves the decoded observable and point in the
correction form, and submits the corrected replacement with the same point id.
Latest-action workflow handoff links now expose stable label metadata alongside
event id, role, and href. Focused component tests and rendered browser workflow
assertions prove the metadata matches the visible operator label for request,
stage, retry, and correction result handoffs.
Grouped workflow job progress now exposes parsed queued, running, completed,
failed, and missing job counts alongside the raw progress string and per-run job
items. Focused component/LiveView tests prove the count contract, and the
real-job recovery browser workflow proves completed/failed counts and grouped
job item details on the rendered dashboard.
Replacement remaining-work browser proof now also captures each rendered
remaining-work row's job-item evidence. The real-worker correction workflow
proves the corrected replacement row preserves missing-job event evidence that
operators need before advancing replacement stages and creating replacement job
state.
Selected activity recovery now has rendered browser proof. The live dashboard
smoke selects a real activity event, applies a filter that hides it, verifies
the selected-event summary exposes hidden-by-filter recovery metadata and a
versions-panel route that clears the filter while preserving the selected event,
then follows the recovery link and proves the same event is visible again.
Comparison investigation presets now have rendered browser proof for saving,
saved-row metadata/action wiring, and deletion. The existing LiveView
persistence test covers applying a saved preset back into the runtime query and
preserving the comparison data-view parameters.
Comparison review bulk decisions now fail closed visibly when a review request
is missing telemetry source context or has no actionable findings: the versions
activity queue withholds the mutation form, renders stable unavailable metadata
and copy, focused LiveView proof verifies no observation decision rows are
written, and rendered browser proof covers both unavailable queue states without
producing an action outcome.
Bulk correction-authority decision events now remain self-explaining after the
operator leaves the review queue: telemetry revision-decision DataLinks expose
the bulk workflow id, item index/count, item observation identity, and selection
kind from persisted per-item evidence, and LiveView proof opens an applied bulk
decision event through the dashboard inspector to verify those rows render.
Mixed comparison review requests now preserve the distinction between open
queue scope and actionable mutation scope. Focused component/LiveView proof and
rendered browser smoke verify the review queue can list all open placements
while the bulk decision form, action outcome, and workflow item evidence count
only findings with an actionable observation identity.
The same mixed review path now explains skipped rows to operators. Review
request rows expose skipped count, placements, and reasons; each finding carries
stable bulk-decision status metadata and visible labels for included versus
skipped findings; focused LiveView proof and rendered browser smoke verify the
missing-observation-identity skip reason remains visible before mutation.
Comparison review resolution events now preserve bulk-decision audit context
from the source request. Durable resolution payloads, the comparison-review read
model, and rendered activity rows carry source actionable counts/placements and
source skipped counts/placements/reasons, so resolved history can explain the
same actionable/skipped split after the request leaves the open queue.
Rendered browser proof now covers the resolved mixed-review history path: a
pre-seeded resolved review with one actionable and one skipped finding opens in
review activity, keeps the request resolved, hides mutation forms, and exposes
the source actionable/skipped audit counts, placements, reasons, and visible
summary on the real page. The same proof now switches to the open-review
filter after selecting the resolved event, verifies the selected event remains
findable but hidden with a recovery route, then follows that route back to all
activity while preserving the selected resolution event and its
actionable/skipped audit context.
Dashboard lifecycle events are now first-class data-link evidence targets.
Focused resolver proof covers a telemetry backfill lifecycle event that carries
comparison-review-origin metadata, exposes the originating dashboard lifecycle
request as a related link, and resolves that request event with dashboard,
version, payload schema, review kind, count, and placement rows.
Rendered browser proof now opens the comparison-review-origin related link from
a real backfill lifecycle inspector, resolves the dashboard lifecycle request
event on the page, and verifies the selected route/copy payload preserve the
`dashboard_lifecycle_event` target and request id.
Focused LiveView proof now covers direct `dashboard_lifecycle_event` data-link
routes independently of the in-memory related-link index: a persisted comparison
review request resolves as query-only lifecycle evidence with copy-route
metadata, and a stale lifecycle event id stays inspectable as a missing
data-link target instead of being cleared as a chart selection.
The grouped comparison-review workflow proof now reloads a
`dashboard_lifecycle_event` route with `comparison_review_origin` navigation
context from a persisted backfill lifecycle event, then verifies the hydrated
inspector renders the source-event breadcrumb and preserves `nav_from`/`nav_trail`
metadata in the copied URL.
The rendered browser smoke runner now has process-level cleanup guards at both
layers: the Node runner times out scenarios internally, terminates its Chrome
runtime with SIGTERM/SIGKILL fallback, and exits if the BEAM parent process is
lost; the ExUnit browser smoke module runs Node through a supervised Port with a
command timeout before the ExUnit browser-test timeout. Focused browser reruns
for the resolved-review recovery path and the previously timed-out scenarios
complete successfully without leaving orphaned `dashboard_viewport_smoke.mjs`
processes, and the helper now has direct focused proof that a timed-out Node
child returns a nonzero result, emits the timeout diagnostic, and is removed
from the process table.
Mixed operational-latest cache revision proof now lives at the source adapter
boundary: supported mixed latest families read each contributing family revision
exactly once, and history-only transport execution observables fail closed for
latest requests before any transport-execution revision is read. The adapter no
longer carries duplicate transport-execution latest revision composition.
Source-endpoint command-queue data-table proof is split across layers: the
source adapter owns filtering/resource-link correctness, focused component tests
own the rendered row DataLink and frame-evidence attribute contract, and browser
smoke keeps the scoped row render/value proof while mission-level smoke still
exercises the full inspector click/copy path.
Dashboard async resolves now guard browser-test sandbox ownership at the worker
boundary: keyed session owners are resolved explicitly, resolve workers are
allowed against the SQL sandbox before engine work starts, and the worker is
killed if the owning test process exits mid-resolve. Focused lifecycle tests
cover owner lookup, worker allowance, successful guarded resolve, and owner-loss
cancellation; a live source-endpoint browser smoke still passes through the real
endpoint/session path.
BYO credential material now has a concrete external secret-manager backend
behind the existing `SecretBackend` contract. The HTTP backend uses `Req`, sends
only the non-secret credential descriptor to a configured endpoint, accepts
ephemeral material through the same material policy/audit path as env-backed
credentials, fails closed when no endpoint is configured, and redacts HTTP error
bodies from returned failure reasons. Focused credential tests prove request
shape, token/header handling, material extraction, fail-closed configuration,
redacted error behavior, and durable material-resolution audit events that
identify the resolver plus external secret backend without persisting endpoint
URLs, secret-manager tokens, returned bearer tokens, returned endpoints, or HTTP
error bodies.
Adapter capability discovery can now materialize backend-reported capabilities
onto the data-source descriptor through the normal probe flow. The source
context persists the discovered capability map as a changed source event with
the source-health event id and previous capabilities, while the data-source UI
probe action opts into this path so QuestDB schema evidence can update native
decimation/watermark support instead of leaving the discovery only in health
metadata. Focused source tests prove lifecycle-event materialization and
mismatch diagnostics; focused LiveView proof covers the operator probe button,
persisted BYO source descriptor update, rendered changed source event, and
source-health linkback.
QuestDB probe diagnostics now classify operator-actionable failure causes
instead of exposing only generic adapter failure text. Connection, authentication,
schema-query, and schema-mismatch failures carry stable diagnostic kind, stage,
and remediation metadata; HTTP response bodies are redacted from adapter-error
metadata. The data-source inventory and recent source-health rows expose these
fields as first-class rendered attributes and copy, so operators can distinguish
endpoint reachability, credential material, and schema migration issues without
parsing raw error text.
TSDB deployment status is now a normalized dashboard-domain contract rather than
ad hoc UI copy. Persisted managed QuestDB sources expose planned/ready state,
backend, physical boundary, and remediation through source metadata, while
redacted provisioning jobs map queued/running/completed/failed into the same
status vocabulary for future deployment-run surfaces. The Data Sources page
renders the source-derived status as stable row attributes and operator copy.
Managed QuestDB deployment runs now have a dashboard-facing read model over the
durable provisioning jobs. The Data Sources page renders queued/running/failed
run state independently of physical source rows, so failed provisioning attempts
remain visible even when no `DataSource` was registered.
Failed managed QuestDB deployment runs are now actionable from the Data Sources
page. The retry action is constrained to managed QuestDB provisioning jobs,
clears redacted failure state through the durable job retry path, and refreshes
the run row back to queued state without exposing generic background-job control
to the operator surface.
Running managed QuestDB deployment runs can also be requeued from the same
surface when an operator needs to recover a claimed run after worker loss. The
action remains constrained to managed QuestDB provisioning jobs, records a
managed-specific requeue reason, and refreshes the run row back to queued state
for normal worker pickup.
Historical workflow job guidance now distinguishes normal active jobs from
active jobs that have crossed the stale threshold. The data-link inspector
context extracts existing job started/completed rows plus stale replacement
age/threshold evidence, the guidance presenter surfaces an `inspect_stale_job`
next action with stable active-state metadata, and component tests prove the
rendered dashboard exposes the started time, age, threshold, and stale state
before any operator recovery mutation. The same job-status card now exposes the
existing inspect-stale and requeue-stale replacement-job commands with stable
job/event/age evidence attributes, while the backend commands continue to fail
closed unless the selected event is a valid stale replacement workflow event.
Missing replacement jobs now follow the same guided pattern: the inspector
context preserves the missing replacement run and expected job type, the
job-status guidance surfaces an `inspect_missing_job` next action, and the card
can invoke the existing missing-job inspection command with stable request-group,
replacement-run, and expected-job evidence attributes.
Failed replacement rows now expose a row-scoped retry action when the grouped
replacement retry policy is available and the row has both job and event
evidence, allowing operators to recover one failed replacement job through the
existing durable single-job retry path without losing the replacement-run scope.
The clicked replacement run is carried through the Phoenix event and action
outcome target context so follow-on dashboard evidence remains anchored to the
row the operator recovered.
Rendered browser proof now covers the same row-scoped failed replacement retry:
the failed remaining-work row exposes the replacement-run/job/event Phoenix
payload, the click records a single-job retry outcome, latest-action target
context stays anchored to the clicked replacement run, and the replacement job
returns to queued guidance afterward.
Correction-authority decision inspectors now keep the dashboard workflow handoff
intact: dashboard comparison-review decisions expose a related
`dashboard_lifecycle_event` link back to the review request that initiated the
bulk workflow, and the rendered inspector proves operators can recover that
source workflow context from the durable decision event.
Comparison-review bulk decision action outcomes now expose the same handoff
context directly on the activity action card: source request id, workflow id,
requested/applied/failed counts, result event ids, and target event id are stable
attributes in addition to metadata JSON, with rendered proof for full and partial
bulk decision submissions.
The generic data-link action outcome surface now promotes normalized
decision/runtime/request/result/target fields to stable attributes as well, so
late-data policy decisions, revision decisions, and historical workflow recovery
handoffs are testable without parsing metadata JSON. Those fields now come from
a shared action-outcome presentation helper with component-specific prefixes and
aliases, keeping the rendered contract aligned across data-link and
comparison-review action surfaces.
The historical workflow latest-action card now follows the same pattern: its
normalized presenter owns the root stable attributes for action state, retry
disposition, result/target handoffs, and handoff counts, while the component
keeps visible rows and navigation links focused on rendering. The hidden
workflow-controls action outcome uses that same presenter-owned mapping, so
submit feedback and latest-action evidence cannot drift on retry/result/target
fields. Historical workflow action outcomes now also carry the originating
dashboard runtime context through that same stable contract, including dashboard
id/version, time mode, replay run, data view, and limit mode, so latest-action
and submit-feedback handoffs remain tied to the same runtime context that
produced the data-management event. Rendered LiveView workflow proof now covers
the same runtime-context attributes on replay-backed stage transitions and
replay-backed correction requests, so the contract is verified through real
operator submissions rather than only presenter/component tests. Direct request
and grouped request/group-stage workflows now use the same rendered latest-action
runtime-context proof, covering live/archive import and backfill handoffs across
single and bulk operator submissions. Retry and replacement-recovery
latest-action outcomes now inherit that same dashboard runtime context from the
selected lifecycle inspector, so single-job retry and grouped retry handoffs stay
tied to the dashboard id/version, time mode, data view, and limit mode that
produced the inspected failure. Correction-created replacement request events
now persist submitted dashboard context too. Missing replacement-job inspection
has rendered proof for that same context handoff from the corrected replacement
event. Stale replacement inspection/requeue now have rendered browser proof
that the recovery controls submit the exact replacement run/job/event, durable
inspection/requeue events preserve dashboard context, requeue returns the stale
job to queued, and latest-action outcomes retain dashboard context plus
replacement run scope.
Mixed missing/failed/stale replacement groups now have rendered LiveView proof:
the dashboard seeds real corrected replacement events and missing/failed/stale
job states in one request group, then verifies the ordered closure action queue,
per-branch counts, optional group retry metadata when retry is eligible, and
row-level missing, failed-job inspection, stale-inspect, and stale-requeue
controls without hiding secondary recovery branches behind the primary action.
Late-data policy decision inspectors now make the execution boundary explicit:
accepted/rejected policy events render execution mode, source event type, policy
projection effect, and a source-event related link, with LiveView proof that an
operator can navigate from the policy decision back to the original lifecycle
event that was accepted or rejected.
Historical workflow no-op policy outcomes now retain request-group context in
the latest-action card: stale/no-eligible group submissions render the policy
reason, stage, and request group id as stable evidence instead of relying only
on flash text, with LiveView proof covering a duplicate group transition
submission and a post-start regressive group submission that refresh
eligibility without writing duplicate lifecycle events.
Historical workflow group-stage outcomes now preserve request-group context for
normal submissions too: success, structured command failure, and unconfirmed
group-stage outcomes carry the request group id through the action boundary,
and import/comparison LiveView proof renders that group id on successful latest
action cards.
Historical workflow request-creation outcomes now use the same scope-retention
contract: bulk request success reads the request group id from the recorded
events, while command-error and confirmation-required outcomes retain the
submitted run id as the intended request group. LiveView proof renders the group
id on the bulk import request latest-action card before any follow-on group
stage transition.
Grouped retry workflow outcomes now preserve the same request-group handoff
context: retry success, degraded retry, and structured no-retryable policy
errors carry request group ids through action outcomes, while LiveView proof
renders the group id on import and backfill retry latest-action cards.
Missing replacement-job inspection now preserves recovery scope after the
operator click: success and blocked inspection outcomes retain request group and
replacement run ids, with LiveView proof that the latest-action card stays
anchored to the inspected request group.
Stale replacement-job inspection/requeue now follows the same scope-retention
contract at the action boundary: rendered stale-job controls submit replacement
run ids, and success/error outcomes preserve the replacement run as the target
run for follow-on latest-action evidence.
The umbrella test runner now preserves fast dashboard inner-loop verification:
root-level `mix test apps/<child>/...` paths are routed only to their owning
child app with child-relative paths, while unscoped `mix test` and
`mix precommit` still run the full umbrella gate. Dry-run verification covers
Cadence, Cadence Simulator, Cadence Web, and mixed Cadence/Cadence Web path
selection, and a real root-level focused Cadence Web historical workflow test
run completed without invoking the full 1600+ test web suite.
The next testing maturity rule is to stop growing
`ops_dashboard_live_test.exs` as the default proof bucket. Profiling that file
with `--slowest 15` showed the serial LiveView module takes roughly 47-49
seconds locally for 119 tests, while a single line-filtered LiveView case still
pays first-run setup cost. New dashboard slices should keep one browser proof
per product wiring contract, move permutations into async command/presenter/
component tests, and split future full-stack proofs into smaller files by
workflow area so local runs can target the relevant surface without traversing
the whole dashboard console. The first split moved replacement-recovery
LiveView proofs into
`ops_dashboard_show_live/historical_workflow_replacement_recovery_live_test.exs`,
leaving the monolithic dashboard console file at 117 tests while the moved
workflow proofs run independently in roughly one second.

## Slice Backlog

| Area | Next slice | Definition of done |
| --- | --- | --- |
| Operational observables | Add the next backed observable family | Registry definition, source reader/projection, widget-frame contract, presenter coverage, browser proof, freshness/missing-snapshot semantics, and docs are updated together. |
| Scope model | Broaden non-spacecraft scopes | A source-specific browser proof shows filtering, no-data behavior, DataLinks, frame evidence, route/copy payloads, and setup validation for the chosen scope. |
| Data management | Expand guided correction/import/replay workflows | Operator action writes durable events/jobs, dashboard handoff links preserve runtime context, and browser tests prove success/failure/retry states. |
| TSDB operations | Harden BYO and managed operations | Probe/health/readiness evidence, materialized credential policy, timeout/circuit behavior, and operator remediation flows are covered. |
| Events | Add richer runtime/link/RF projections | Canonical events become the source of truth for the new runtime fact, replay/live isolation is proven, and dashboard frame evidence links back to the event/interval source. |
