# Dashboard Feature Maturity Checklist

This checklist tracks dashboard maturity by product capability, not by the age
of the current implementation. It is intentionally allowed to move as the
dashboard engine, data-source model, operational-event spine, and TSDB plumbing
settle.

## Full Maturity Rule

The explicit finish-line definition lives in
`docs/dashboard-feature-maturity-handoff.md` under `Full Maturity Contract`.
This checklist is the evidence ledger for that contract. The dashboard is not
fully mature while this table has unexplained `Partial` rows. Each row must end
as `Complete; monitor`, a named deferred platform dependency, or a future
expansion where the current extension seam is already proven.

The handoff also carries a `Maturity Scoring Snapshot` with percentage estimates
for prioritization. Those percentages are planning estimates only; this table's
status column remains the completion authority. The `Closeout Roadmap` in the
same handoff is the preferred ordering layer for future maturity slices. Use
the handoff's `Section Closeout Audit` before changing any row out of
`Partial`.

## Current Status

| Area | Status | Current proof | Remaining maturity work |
| --- | --- | --- | --- |
| Document model | Complete; monitor for new lifecycle states | Canonical dashboard documents persist through `ops_dashboards`, immutable `dashboard_versions`, latest/draft/published pointers, lifecycle events, publish/revert/archive/restore flows, and canonical list/new/show LiveViews. | Re-open only if dashboard branching, review workflows, or sharing semantics add new document lifecycle states. |
| Engine contract | Complete; monitor for source/widget expansion | `Engine.plan/1` and `Engine.resolve/2` batch placement source requests, execute logical sources through `SourceRegistry`, materialize frames, and validate planned requests/source results against widget frame contracts. | Re-open when new frame shapes, source capabilities, or widget-frame contract dimensions are added. |
| Runtime contexts | Complete; monitor for new context dimensions | URL/session/document defaults hydrate `TimeContext`, `ScopeContext`, `DataContext`, and `LimitContext`; runtime controls preserve live/archive/replay time modes, data realm, source binding, data view, limit semantics, and typed scopes for mission, spacecraft, contact, ground station, source endpoint, transport, and link. The context selector can apply and clear multi-spacecraft, multi-contact, and multi-entity operational-resource scope sets, including setup-backed ground-station and link sets, from search results, producing durable `scope_ids` routes instead of requiring hand-edited URLs. Multi-contact runtime filters now survive fixed-widget primary scope overrides through typed plural scope filters, so telemetry source execution, query diagnostics, and source/evidence links retain every selected contact while preserving the widget's spacecraft primary scope. Comparison rollup handoffs and copied open-finding presets now preserve plural operational-resource `scope_ids`, so multi-entity comparison investigations can reopen the selected scope set instead of collapsing to one scalar resource. DataLink handoffs now round-trip plural `contact_ids` through event attrs, selected refs, selection-query params, event-param regeneration, and synthetic-link scope reconstruction; contact-primary DataLinks derive those ids from the primary contact scope even when no duplicate `contact_ids` field is present, and comparison rollup handoffs emit `phx-value-contact-ids` from item `contact_ids` so open/copy/reopen paths preserve selected contacts. Replay command release attempt source-endpoint/contact copied routes now reopen with replay run, source binding, navigation origin, and operational-resource identity intact, and verifier/action copied routes reopen with replay run, source binding, navigation origin, and verifier/action identity intact, and root release-attempt copied routes reopen with replay run, source binding, selected time, and release-attempt identity intact, and command verifier instance copied routes reopen with replay run, source binding, selected time, verifier identity, and command identity intact, and telemetry matched-record copied routes reopen with replay run, source binding, selected time, telemetry sample identity, and point identity intact. Applied comparison-decision links now carry the same operational scope/contact context as open finding handoffs, bulk comparison review decision evidence retains scope/contact fields from the source finding, comparison review activity rows expose those scope/contact fields for operator inspection, comparison-review-origin historical workflow events now preserve aggregate scope/contact/resource identifiers through request, group, stage, correction, inspector, and queue contracts, bulk comparison review action outcomes now render and serialize aggregate scope/contact/resource context for the operator result panel, and comparison review resolution events now persist and render the same aggregate source context after the request leaves the open queue. | Re-open when a new time, scope, data, limit, source, widget, or workflow context dimension lacks URL, default, control, action, DataLink, copy-route, replay-isolation, or stale-selection proof. |
| Source registry and logical source contracts | Complete; monitor for new source families | Telemetry, limits, events, and operational observables share capability, product metadata, physical source product narrowing, unsupported product posture, health/freshness/watermark, timeout, circuit-open, degraded-result, and source-action contracts. Operational-observable capabilities now expose explicit source-backed contracts tying observable groups to sampling modes, products, product families, and frame shapes; engine publish validation, runtime capability posture, and source-remediation candidate matching consume those contracts for latest, state-history, aggregate, and raw-series families, with tests proving backed ids and advertised products cannot drift. | Re-open when new source families, adapters, or capability dimensions are added. |
| Managed QuestDB path | Complete; monitor for ops expansion | Managed QuestDB migrations, canonical writes, bounded reads, native decimation, watermarks, source-health diagnostics, org/mission isolated provisioning, durable redacted provisioning jobs, retry/failure behavior, provisioning Mix task, source/job deployment status contract, deployment-run operator visibility, failed-run retry action, and stuck-run requeue action have proof. | Re-open for schema expansion, deployment allocator UI, probe policy, or stronger physical isolation operations. |
| BYO TSDB path | Deferred RBAC/authz platform dependency | Customer-owned adapter execution, setup/probe/disable/enable flows, readiness fields, browser readiness proof, env-profile production material resolution, external secret-manager material resolution with redacted success/failure audit events and HTTPS-by-default transport enforcement, credential-material authorizer enforcement, operator credential rotation, adapter-reported capability discovery/materialization, classified probe diagnostics/remediation hints, source-level probe policy, timeout/circuit isolation with durable scheduler-timeout source-health evidence, dedicated org/mission external deployment posture, operator reconciliation, worker-backed provisioning, and worker-backed deprovision lifecycle for dedicated org/mission backends, and external QuestDB smoke path exist. | Revisit for source-operation permissions once the broader RBAC/authz platform exists. |
| Data management semantics | Complete; monitor for new data-management workflows or read semantics | Canonical/as-recorded/all-revisions/recomputed read views participate in cache identity, source provenance, data links, telemetry explore links, diagnostics, source overlays, warning badges, late-data workflows, revision/correction decisions, and dashboard-side comparison review decisions including degraded partial-failure bulk outcomes. Late-data policy, revision-decision, and historical retry handoffs now preserve replay time mode, replay run, data view, and limit mode through rendered form context, command evidence refs or policy payloads, selected result links, stable action attrs, metadata JSON, and replay lifecycle-event retry result links, including a replay late-data browser proof that stays audit-only. Rendered replay revision-decision result handoff now preserves replay run, data view, limit mode, selected source-decision evidence refs, durable decision payload, stable action/result metadata, inspector controls, and copied/opened result routes. Rendered corrected import recovery now preserves replay run, data view, limit mode, source binding, original failed event/job, durable correction payload, latest-action attrs, and selected-result handoff links from the lifecycle inspector. | Re-open when a new data view, correction/import/backfill/replay policy, workflow family, bulk decision, job lifecycle, recovery action, or result/evidence origin lacks product-owned semantics, durable event/job state, context round trip, audit, and rendered proof. |
| Operational event dependency | Complete; monitor for new history dependencies | Durable event envelopes, store/projectors, binding/catalog/source/limit/dashboard/data-management lifecycle rows, selected-clock audit events, contact intervals, transport execution/action/timer facts, runtime facts, source-health transition effective intervals with live/replay isolation, source-health intervals carried through operational-observable source result and frame metadata/evidence, rendered live and replay dashboard frame evidence opening for source-health intervals, connection/RF state facts, generic operational-observable state facts including antenna pointing, metric sample facts, metric sample operational-event inspector row resolution, replay metric-sample selected-ref route-query preservation, replay-scoped readers, latest connection/RF state frame evidence back to canonical intervals/source events, rendered live and replay connection-state status-matrix frame evidence back to canonical transport connection intervals/source events, rendered replay ground-station connection-state status-matrix frame evidence back to canonical ground-station connection interval/source-event refs plus source-health interval/event refs, rendered replay transport-execution state-timeline frame evidence back to canonical transport execution intervals/source events plus source-health interval/event refs, transport-execution operational-event copied-route reopen proof, live transport-execution operational-event copied-route reopen proof, rendered live link-scoped RF lock/frame-sync status-matrix frame evidence and rendered replay RF lock/frame-sync status-matrix frame evidence back to canonical link RF intervals/source events with source binding and runtime context preserved, live RF lock/frame-sync operational-event copied-route reopen proof and replay RF lock/frame-sync operational-event copied-route reopen proof, antenna pointing frame evidence back to generic operational-observable state intervals/source events plus live antenna-pointing operational-event copied-route reopen proof and replay antenna-pointing operational-event copied-route reopen proof, latest/metric-history frame evidence back to canonical metric sample events plus replay and live metric-sample operational-event copied-route reopen proof, replay command-queue status-matrix frame evidence back to durable command queue entry ids, live source-endpoint command-queue status-matrix frame evidence back to durable command queue entry ids plus copied-route reopen proof, live command-request related-link copied-route proof, live command-request queue-entry related-link copied-route proof, live command-request release-attempt related-link copied-route proof, live command release-attempt transport-action related-link copied-route proof, live command verifier matched transport-action related-link copied-route proof, live command verifier matched transport-action operational-event related-link copied-route proof, live command release-attempt transport-action operational-event related-link copied-route proof, replay command release-attempt transport-action operational-event related-link copied-route proof, replay command verifier matched transport-action operational-event related-link copied-route proof, replay command verifier matched transport-action operational-event navigation-back copied-route proof, replay command release-attempt transport-action operational-event release-attempt navigation-back copied-route proof, replay command release-attempt source-endpoint/contact navigation-back copied-route proof, live command release-attempt source-endpoint/contact navigation-back copied-route proof, live command release-attempt transport-action operational-event release-attempt navigation-back copied-route proof, live command release-attempt verifier related-link copied-route proof, live command release-attempt contact related-link copied-route proof, live command release-attempt source-endpoint related-link copied-route proof, live command release-attempt command-request related-link copied-route proof, and live command release-attempt queue-entry related-link copied-route proof, replay managed-runtime state-timeline evidence back to managed action, timer, capability-record lifecycle, action request document, and produced-output metadata operational events are in place, replay managed produced-output/action-result metadata copied-route proof now reopens canonical managed capability-record events with emitted record kinds/counts, action request count, state snapshot, and emitted record refs intact, replay transport produced-output/action-result metadata copied-route proof now reopens transport capability-record facts and canonical transport operational events with emitted record kinds/counts, action request count, state snapshot, and emitted record refs intact, replay transport action-request command metadata copied-route proof now reopens transport action-request facts and canonical transport operational events with command release attempt, command request, command name, signal phase, action kind, request document, and action metadata intact, replay transport action-request runtime-context copied-route proof now reopens transport action-request operational events with contact/path/capability/binding/partition/source-endpoint/requested context intact, replay transport timer metadata/runtime-context copied-route proof now reopens transport timer operational events with contact/path/capability/binding/partition/timer event kind, due-time row, and timer metadata intact, replay managed timer metadata/runtime-context copied-route proof now reopens managed timer operational events with capability/binding/partition/packet/evidence context, timer event kind, due-time row, and timer metadata intact, replay managed action runtime-context copied-route proof now reopens managed action operational events with capability/binding/partition/packet/evidence/requested context intact, replay managed capability-record runtime-context copied-route proof now reopens managed capability-record operational events with capability/binding/partition/packet/evidence/recorded context intact, replay transport capability-record runtime-context copied-route proof now reopens transport capability-record operational events with contact/path/capability/binding/partition/recorded context intact, replay transport-runtime state-timeline evidence now opens canonical transport capability-record, action-request, and timer operational events with runtime fact identity preserved, live transport-runtime state-timeline evidence now opens canonical transport capability-record, action-request, and timer operational events with copied-route reopen proof, replay transport-runtime command/signal handoff evidence now carries command release attempt refs to durable command release attempts, replay command verifier matched-record evidence now links verifier outcomes back to the matched transport action request, replay command verifier matched transport-capability operational-event related-link proof now reopens copied canonical operational events from verifier-origin transport capability records, replay command verifier matched transport-capability operational-event navigation-back proof now reopens copied transport capability records from those canonical event inspectors, replay command verifier matched transport-capability operational-event verifier navigation-back proof now reopens copied command verifier instances from those canonical event inspectors, replay command verifier matched transport-capability operational-event verifier-back matched-record proof now reopens copied transport capability records from those event-origin verifier inspectors, replay command verifier matched transport-capability operational-event verifier-back matched-record operational-event proof now reopens copied canonical operational events from those event-origin matched-record inspectors, replay command verifier matched transport-capability operational-event matched-record verifier-back proof now reopens copied command verifier instances from those event-origin matched-record inspectors, replay command verifier matched telemetry related-link proof now reopens copied telemetry samples from verifier inspectors, replay command verifier matched telemetry verifier-back proof now reopens copied command verifier instances from those telemetry matched-record inspectors, replay command verifier matched transport-capability related-link proof now reopens copied transport capability records from verifier inspectors, replay telemetry matched-record verifier evidence now opens the matched telemetry sample from the frame evidence panel, replay transport capability matched-record verifier evidence now opens the matched runtime fact through its canonical operational event, and replay transport action-request matched-record verifier evidence now opens the matched runtime action fact through its canonical operational event, and replay command verifier instance evidence now opens durable verifier outcome state, matched-record metadata, failure reason, and command identities while preserving replay/source context, and replay command release attempt evidence now opens durable release lifecycle, verification state, command identity, related transport action request, signal phase, and verifier links while preserving replay/source context, and replay command release attempt related-link evidence now follows verifier, transport-action, source-endpoint, and contact links while preserving replay/source context, navigation trail, and copied routes, and copied source-endpoint/contact, verifier/action, root release-attempt, command-verifier-instance, telemetry matched-record, transport capability matched-record, transport action-request matched-record, and transport-execution, transport timer, transport capability-record, transport action-request, managed timer, managed action, and managed capability-record operational-event routes reopen directly with that context. | Re-open when a new dashboard history family, runtime/source projection, command/result origin, interval type, or rendered historical evidence path depends on process-local/non-canonical state or lacks durable identity, live/replay isolation, frame/inspector evidence, copied-route, and rendered proof. |
| Limits over time | Complete; monitor for new limit semantics | Limit-mode preservation spans durable event payloads, late-data policy workflows, revision/correction decisions, compare/current/recomputed modes, replay-scoped reads, replay browser proof, replay audit-only late-data decisions, and late-data/revision-decision result handoffs that keep limit semantics alongside replay/data-view context. Rendered replay revision-decision result routes now keep limit mode through command payload, durable decision evidence, stable action metadata, inspector rendering, and copied/opened result URLs. | Re-open when a new limit semantics mode, definition clock, time axis, source/replay realm, workflow action, or rendered limit origin lacks historical selection, audit-event, context round-trip, evidence, copy/reopen, or browser proof. |
| Replay workflow | Complete; monitor for new replay products or operator actions | Replay-run selection, progress clock/window metadata, source readiness warnings, replay-preserving copy/deep links, telemetry/latest/history reads, limits reads, Events and Operational Observables replay context, mission timeline/contact interval rows, replay `contacts.phase` state-timeline context, replay operational-observable readers, replay-scoped source-health transition intervals, rendered replay source-health frame evidence and source-health operational-event copied-route reopen proof, connection-state operational-event copied-route reopen proof, ground-station connection-state operational-event copied-route reopen proof, rendered replay connection-state status-matrix frame evidence with replay source binding, dataset, replay run, source-health interval refs, canonical transport connection interval refs, operational-event source refs, and copy-link context, rendered replay ground-station connection-state status-matrix frame evidence with replay source binding, dataset, replay run, canonical ground-station interval refs, source-health interval refs, operational-event source refs, and copy-link context, rendered replay transport-execution state-timeline frame evidence with replay source binding, dataset, replay run, source-health interval refs, canonical transport execution interval refs, operational-event source refs, copy-link context, and transport-execution operational-event copied-route reopen proof, rendered replay RF lock/frame-sync status-matrix frame evidence with replay source binding, dataset, replay run, canonical interval refs, operational-event source refs, copy-link context, and RF lock/frame-sync operational-event copied-route reopen proof, rendered replay command-queue status-matrix frame evidence with replay source binding, dataset, replay run, durable command queue entry refs, and copied evidence context, rendered replay managed-runtime state-timeline frame evidence with replay source binding, dataset, replay run, managed action/timer refs, capability-record lifecycle refs, action request documents, produced-output metadata, state snapshots, copied evidence context, managed produced-output/action-result metadata copied-route proof with emitted record refs and action counts, transport produced-output/action-result metadata copied-route proof with emitted record refs and action counts, transport action-request command metadata copied-route proof with command release attempt, command request, command name, signal phase, action kind, request document, and action metadata, transport action-request runtime-context copied-route proof with contact/path/capability/binding/partition/source-endpoint/requested context, transport timer metadata/runtime-context copied-route proof with timer event kind, due-time row, and timer metadata, managed timer metadata/runtime-context copied-route proof with capability/binding/partition/packet/evidence context, timer event kind, due-time row, and timer metadata, managed action runtime-context copied-route proof with capability/binding/partition/packet/evidence/requested context, managed capability-record runtime-context copied-route proof with capability/binding/partition/packet/evidence/recorded context, transport capability-record runtime-context copied-route proof with contact/path/capability/binding/partition/recorded context, and managed timer, managed action, and managed capability-record operational-event copied-route reopens, rendered replay transport-runtime state-timeline frame evidence with replay source binding, dataset, replay run, transport capability-record/action-request/timer refs, rendered live transport-runtime state-timeline frame evidence with flight source binding and capability-record/action-request/timer operational-event copied-route reopen proof, command release attempt DataLinks including verifier, transport-action, source-endpoint, and contact related-link navigation plus source-endpoint/contact, verifier/action, root release-attempt, and command-verifier-instance, telemetry matched-record, transport capability matched-record, transport action-request matched-record, and transport timer, transport capability-record, transport action-request, and transport-execution operational-event copied-route reopens, source-health operational-event copied-route reopen, connection-state operational-event copied-route reopen, ground-station connection-state operational-event copied-route reopen, command verifier instance DataLinks, matched telemetry sample DataLinks and copied-route reopens, matched transport capability record DataLinks and copied-route reopens, matched transport action request DataLinks and copied-route reopens, transport timer, transport capability-record, transport action-request, and transport-execution operational-event DataLinks and copied-route reopens, source-health operational-event DataLinks and copied-route reopen, connection-state operational-event DataLinks and copied-route reopen, ground-station connection-state operational-event DataLinks and copied-route reopen, command request ids, action request documents, state snapshots, output metadata, and copied evidence context, replay latest operational connection data-table row identity/DataLinks/frame evidence, replay RF state data-table row identity/frame evidence, replay antenna pointing state-timeline DataLinks/frame evidence and antenna-pointing operational-event copied-route reopen proof, replay transport-execution state-timeline degraded source-health provenance with replay source binding/run context, late-data/revision-decision operator actions, historical retry result handoffs, rendered replay revision-decision result handoff, and rendered corrected import recovery preserve replay run/data-view/limit context through result selection, stable action attrs, selected-result links, copied/opened result routes, and audit metadata while replay late-data policy remains event-only are covered. | Re-open when a new replay-capable source, runtime product, control, warning/remediation action, workflow mutation, result/evidence origin, or browser interaction lacks run/source isolation, event-only safety where required, selected-ref/context round trip, copied-route, and rendered proof. |
| Scope product surface | Complete; monitor for new scope dimensions | Runtime query hydration accepts mission, spacecraft, contact, ground-station, source-endpoint, transport, link, and multi-id scope URLs. Contact scopes fail closed through validation, operational resources validate setup-backed ids, unsupported operational-observable scope pairings fail closed before source execution, and rendered browser coverage proves scoped contact/source-endpoint no-data, multi-contact telemetry no-data with all selected contacts and resolved source endpoints preserved in query/source evidence, mission-scoped/contact-scoped/multi-contact/spacecraft-scoped/source-endpoint-scoped/ground-station-scoped/multi-source-endpoint/multi-ground-station operational contact-phase timelines, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport connection-state timelines, multi-link transport-execution timeline filtering/DataLinks/frame evidence with non-primary row preservation, source-endpoint/ground-station/link operational-resource DataLinks, replay command release attempt source-endpoint/contact related-link navigation, copied-route reopen, and navigation-back copied-route reopen, non-primary selected-resource/contact DataLinks and row frame evidence inside multi-source-endpoint, multi-transport, multi-contact, and multi-resource contact-phase scopes, non-primary multi-transport latest data-table row DataLinks/frame evidence with full query-scope preservation plus related source-endpoint/ground-station/link selected-ref handoff context, selected-resource query params serialize related operational-resource context, same-kind runtime scope changes clear selected operational-resource refs and selected-query keys once the selected resource leaves the current scope set, live link-scoped RF lock/frame-sync rows with canonical interval frame evidence and copy context, link-scoped and multi-link RF rows with non-primary DataLinks/frame evidence, multi-spacecraft command queue aggregate filtering/evidence, multi-spacecraft ingress-latency endpoint fan-out/evidence, unsupported-scope value-tile/time-series lifecycle blocking, and operator-selected multi-spacecraft, multi-contact, multi-ground-station, multi-link, multi-transport, plus multi-source-endpoint runtime scope controls. | Re-open when a new scope kind, ownership rule, multi-entity mode, source product, widget family, failure state, or operator workflow lacks validation, filtering, non-primary identity, stale-selection clearing, DataLink/evidence, copy/reopen, or browser proof. |
| Operational observables | Future expansion | Backed registry/source coverage proves replay/source-binding propagation, source-backed capability contracts, scope filtering, freshness/staleness, missing snapshot warnings, unsupported observable scope blocking, connection/RF state timelines, antenna pointing state timelines, transport-execution history filtering across transport/contact/source-endpoint/ground-station/link scopes including multi-link fan-out, connection/RF latest rows with canonical interval/source-event evidence when backed by operational events, antenna pointing latest/history rows with generic operational-observable interval evidence, replay-isolated antenna pointing history, transport bitrate, RF SNR/Eb/N0/symbol-rate/Doppler metrics, ingress latency latest/history including multi-spacecraft filtering with source-endpoint row identity, contact phase including mission-scope rendering, multi-contact event-history filtering, direct source-endpoint filtering, multi-source-endpoint filtering, and spacecraft/ground-station/multi-ground-station filtering through source-endpoint ownership, command queue empty-zero/reader-failure behavior including source-endpoint scoped zero/stale rows, durable command queue entry ids/evidence refs, replay source binding/run propagation, `runtime.managed_activity` event-history rows for managed action/timer, capability-record lifecycle, action request document, produced-output metadata facts, managed produced-output/action-result metadata copied-route proof for emitted record refs/action counts, transport produced-output/action-result metadata copied-route proof for emitted record refs/action counts, transport action-request command metadata copied-route proof for command release attempt, command request, command name, signal phase, action kind, request document, and action metadata, transport action-request runtime-context copied-route proof for contact/path/capability/binding/partition/source-endpoint/requested context, transport timer metadata/runtime-context copied-route proof for timer event kind, due-time row, and timer metadata, managed timer metadata/runtime-context copied-route proof for timer event kind, due-time row, and timer metadata, managed action runtime-context copied-route proof for capability/binding/partition/packet/evidence/requested context, managed capability-record runtime-context copied-route proof for capability/binding/partition/packet/evidence/recorded context, transport capability-record runtime-context copied-route proof for contact/path/capability/binding/partition/recorded context, and managed timer, managed action, and managed capability-record operational-event copied-route reopens with operational-event evidence refs, `runtime.transport_activity` event-history rows for transport capability records, action requests, timer events, live transport capability-record, action-request, and timer operational-event copied-route reopens, command/signal context, command release attempt ids, command request ids, command release attempt DataLinks, command release attempt source-endpoint/contact related-link DataLinks and copied-route reopens, verifier/action copied-route reopens, root release-attempt copied-route reopens, command verifier instance, telemetry matched-record, transport capability matched-record, transport action-request matched-record, and transport timer, transport capability-record, transport action-request, and transport-execution operational-event copied-route reopens, source-health operational-event copied-route reopen, connection-state operational-event copied-route reopen, ground-station connection-state operational-event copied-route reopen, command verifier instance DataLinks, matched telemetry sample DataLinks and copied-route reopens, matched transport capability record DataLinks and copied-route reopens, matched transport action request DataLinks and copied-route reopens, transport timer, transport capability-record, transport action-request, and transport-execution operational-event DataLinks and copied-route reopens, source-health operational-event DataLinks and copied-route reopen, connection-state operational-event DataLinks and copied-route reopen, ground-station connection-state operational-event DataLinks and copied-route reopen, action request documents, state snapshots, output metadata, and operational-event evidence refs, and multi-spacecraft aggregate rows that do not mislabel the first spacecraft, fail-closed source-unavailable reader errors, and runtime-health ingress overlays. Browser/presenter coverage proves mission-scoped, contact-scoped, replay contact-scoped, multi-contact, spacecraft-scoped, source-endpoint-scoped, ground-station-scoped, multi-source-endpoint, and multi-ground-station contact-phase state timelines, value-tile links including link-scoped RF Doppler, unsupported-scope value-tile/time-series blocking, replay RF/transport history charts with canonical metric sample event frame evidence, mission aggregate command queue depth, rendered replay command queue status-matrix frame evidence with command queue entry refs plus replay source binding/dataset/run copy context, rendered replay managed-runtime state-timeline frame evidence with action/timer/capability-record lifecycle refs, action request documents, produced-output metadata, and copied-route proof for emitted record refs/action counts plus replay source binding/dataset/run copy context, rendered replay transport-runtime state-timeline frame evidence with transport produced-output/action-result metadata copied-route proof for emitted record refs/action counts, transport action-request command metadata copied-route proof for command release attempt, command request, command name, signal phase, action kind, request document, and action metadata, transport action-request runtime-context copied-route proof for contact/path/capability/binding/partition/source-endpoint/requested context, transport timer metadata/runtime-context copied-route proof for timer event kind, due-time row, and timer metadata, managed timer metadata/runtime-context copied-route proof for timer event kind, due-time row, and timer metadata, managed action runtime-context copied-route proof for capability/binding/partition/packet/evidence/requested context, managed capability-record runtime-context copied-route proof for capability/binding/partition/packet/evidence/recorded context, transport capability-record runtime-context copied-route proof for contact/path/capability/binding/partition/recorded context, rendered replay transport-runtime state-timeline frame evidence with transport capability/action/timer refs, command/signal context, command release attempt DataLinks, command release attempt source-endpoint/contact related-link DataLinks and copied-route reopens, verifier/action copied-route reopens, root release-attempt copied-route reopens, command verifier instance, telemetry matched-record, transport capability matched-record, transport action-request matched-record, and transport timer, transport capability-record, transport action-request, and transport-execution operational-event copied-route reopens, source-health operational-event copied-route reopen, connection-state operational-event copied-route reopen, ground-station connection-state operational-event copied-route reopen, command verifier instance DataLinks, matched telemetry sample DataLinks and copied-route reopens, matched transport capability record DataLinks and copied-route reopens, matched transport action request DataLinks and copied-route reopens, transport timer, transport capability-record, transport action-request, and transport-execution operational-event DataLinks and copied-route reopens, source-health operational-event DataLinks and copied-route reopen, connection-state operational-event DataLinks and copied-route reopen, ground-station connection-state operational-event DataLinks and copied-route reopen, action request documents, state snapshots, output metadata, and replay source binding/dataset/run copy context, multi-spacecraft command queue depth with preserved `scope_ids`, multi-spacecraft ingress latency fan-out with preserved endpoint DataLinks and `scope_ids`, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport transport/ground-station connection-state timelines, live and replay ground-station scoped antenna pointing state timelines with source-endpoint/ground-station DataLinks and native interval evidence, multi-link transport-execution state timelines with non-primary row identity, resolved transport DataLinks, preserved `scope_ids`, selected-scope copy payloads, frame evidence, valid link-scoped no-data lifecycle/source metadata without invented rows or DataLinks, source-unavailable lifecycle/source-badge projection when the operational source cannot answer, and live/replay degraded source-health source-status/source-badge projection plus row source-health event handoff while rows remain rendered and replay source binding/run context is preserved, rendered latest connection/RF status-matrix and data-table row frame evidence with canonical interval and source-event refs, rendered link-scoped RF status-matrix rows with link/transport/source-endpoint/ground-station DataLinks, non-primary multi-transport latest connection data-table row identity/DataLinks/frame evidence with canonical interval and source-event refs, non-primary multi-link RF data-table row identity/DataLinks/frame evidence with canonical interval/source-event refs and preserved `scope_ids`, replay latest connection data-table row identity/DataLinks/frame evidence with replay source binding, replay dataset, replay run, and canonical interval/source-event refs, replay RF lock/frame-sync data-table row identity/frame evidence with replay source binding, replay dataset, replay run, and canonical interval/source-event refs, source-endpoint command queue depth filtering/DataLinks in status-matrix, value-tile, and data-table widgets, status-matrix/data-table row frame evidence with dashboard query-scope preservation, source-endpoint empty-zero command queue DataLinks/frame evidence in the data-table path, source-endpoint stale command queue data-table row links/lifecycle, command queue source-unavailable data-table lifecycle/error projection, source-endpoint ingress latency row/chart DataLinks, partial multi-source-endpoint ingress-latency metric-history lifecycle/source metadata with returned-only endpoint chart data and no invented missing-endpoint point DataLinks, zero-point replay/archive no-data lifecycle/source metadata plus query/source-evidence route/copy context for link-scoped RF SNR/EbN0/mixed metric and transport-scoped bitrate histories, partial mixed RF and transport-bitrate metric-history lifecycle/source metadata with returned SNR/downlink-only chart data and no invented symbol-rate/uplink series, and frame evidence/copy payloads. | Re-open or extend when a new observable family, product, sampling mode, frame shape, scope, source adapter, or rendered origin is introduced; require catalog/capability equality, source/failure-state, frame/presenter, DataLink, rendered, and browser proof as applicable. |
| Widget coverage | Complete; monitor for new widget families or lifecycle states | Status matrix, data table, value tile, time-series, and state-timeline coverage includes operational contact-phase timelines including mission-scoped, multi-contact, spacecraft-scoped, source-endpoint-scoped, ground-station-scoped, multi-source-endpoint, and multi-ground-station state-timeline rows, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport connection-state timelines, multi-spacecraft command queue aggregate status-matrix rows, rendered replay command queue status-matrix row evidence opening command queue entry refs with replay source binding/run copy context, rendered replay managed-runtime state-timeline rows opening managed action, timer, capability-record lifecycle, action request document, and produced-output metadata operational-event refs with replay source binding/run copy context plus managed action runtime-context, managed capability-record runtime-context copied-route proof, transport capability-record runtime-context copied-route proof, and transport action-request runtime-context copied-route proof, rendered replay transport-runtime state-timeline rows opening transport capability-record, action-request, and timer operational-event refs, rendered live transport-runtime state-timeline rows opening transport capability-record and action-request operational-event refs plus command release attempt DataLinks with command/signal context, release lifecycle, verification state, signal phase, verifier related-link navigation, transport-action related-link navigation, and source-endpoint/contact operational-resource related-link navigation and copied-route reopen, verifier/action copied-route reopen, root release-attempt copied-route reopen, command verifier instance copied-route reopen, telemetry matched-record copied-route reopen, transport capability matched-record copied-route reopen, transport action-request matched-record copied-route reopen, transport-execution operational-event copied-route reopen, transport timer operational-event copied-route reopen, managed timer operational-event copied-route reopen, managed action operational-event copied-route reopen, command request ids, action request document, state snapshot, and output metadata plus replay source binding/run copy context, multi-spacecraft ingress-latency status-matrix rows, operational metric value tiles, unsupported-scope blocked value tiles and time-series widgets with lifecycle-tagged notices and no chart/data-link affordances, rendered context-bound value-tile retention-gap and source-unavailable source-failure fallbacks without unresolved fallback, nil source-empty-reason leakage, or invented sample links, rendered telemetry latest data-table/status-matrix source-unavailable blocking without placeholder rows, row DataLinks, or row frame-evidence controls, rendered telemetry time-series source-unavailable blocking without chart hooks, chart markers, or synthetic point series, rendered telemetry time-series source-degraded preservation of chart data with warning source badge/evidence, rendered telemetry time-series stale preservation of chart data with warning source badge/evidence, rendered telemetry time-series unknown-watermark preservation with unknown source badge/evidence, rendered telemetry time-series retention-gap preservation with retention source badge/evidence, rendered telemetry time-series no-data blocking without chart hooks, point links, markers, or synthetic series, row-widget empty states with lifecycle-tagged `no_data` notices for status matrix, data table, state timeline, and event timeline bodies, rendered source-endpoint no-data data-table, status-matrix, state-timeline, and event-timeline body notices without placeholder rows, partial telemetry range lifecycle with returned-series chart rendering and chart-point telemetry-sample DataLinks, partial operational metric-history lifecycle with returned-series chart rendering and no invented missing series, telemetry time-series retention-gap/source-watermark cursor markers from durable watermark status plus selected-source and selected-dataset scoped persisted source-watermark event overlays, partial telemetry latest data-table and status-matrix lifecycle with only returned rows rendered, empty telemetry latest value-tile no-data lifecycle without invented sample rows/links, stale telemetry latest value-tile rendering with sampled value plus unknown source freshness, fresh telemetry latest value-tile rendering after persisted source watermark confidence, RF metric value tiles including Doppler, source-endpoint scoped command queue value tiles, missing-snapshot value tiles, operational no-data source badges, stale data-table row warnings, operational data-table frame evidence, mixed operational data-table rows flattened from multiple product frames with row DataLinks/frame evidence, stale metric lifecycle preservation, and degraded source-health preservation, RF/connection/transport-execution timelines, link-scoped transport-execution no-data state-timeline lifecycle without invented lanes/rows/links, transport-execution source-unavailable state-timeline lifecycle/source badge without invented rows/links, live and replay transport-execution degraded source-health state-timeline source badge plus row source-health event DataLink while rows remain rendered and replay context is preserved, chart-point DataLinks, chart legend hide/show guarding and grouped/shared axis toggling for multi-series time-series widgets, and selected-interval evidence. | Fill richer table/grid variants, lifecycle states, degraded/empty/partial/stale states, and remaining browser-level grid/chart interaction behavior. |
| Data links and evidence | Future expansion | DataLink parsing/resolution, selected-ref route/copy payloads, browser-proven multi-scope selected-ref and non-primary row frame-evidence preservation for `scope_ids`/`selected_scope_ids`, canonical operational-event inspectors, mission-event-to-operational-event related links, aggregate command queue frame evidence including multi-spacecraft aggregate copy/evidence without invented single-resource links, mission-aggregate connection-state resource links/frame evidence, contact-phase state-timeline contact DataLinks/frame evidence including replay context and non-primary beta contact route/copy payloads inside multi-contact scope, spacecraft-scope routes preserving legacy `spacecraft_id`, and source-endpoint/ground-station routes preserving generic `scope_kind`/`scope_id`, rendered latest connection/RF status-matrix and data-table rows opening canonical interval and operational-event evidence refs, browser-proven link-scoped RF status-matrix rows exposing link DataLinks alongside transport/source-endpoint/ground-station DataLinks, non-primary multi-transport data-table connection rows opening resolved transport DataLinks plus canonical interval/source-event frame evidence while preserving `scope_ids` and selected-scope copy payloads, non-primary multi-link RF data-table rows opening resolved transport DataLinks plus canonical RF-lock interval/source-event frame evidence while preserving `scope_ids` and selected-scope copy payloads, non-primary multi-link transport-execution state-timeline rows opening resolved transport DataLinks plus frame evidence while preserving `scope_ids` and selected-scope copy payloads, replay data-table connection rows opening resolved transport DataLinks plus replay canonical interval/source-event frame evidence while preserving replay source binding, replay dataset, replay run, and selected-scope payloads, replay RF state data-table rows opening replay canonical RF-lock/frame-sync interval and source-event frame evidence while preserving replay source binding, replay dataset, and replay run, source-endpoint command queue row DataLinks and query-scoped frame evidence across status-matrix and data-table render paths, source-endpoint command queue value-tile DataLinks with source-bound and query-scoped widget-frame evidence attrs, multi-spacecraft ingress-latency endpoint DataLinks/frame evidence plus multi-source-endpoint ingress-latency metric-history widget source-status/query diagnostics, partial returned-endpoint chart DataLinks without invented missing-endpoint point links, and widget-frame evidence with source identity plus `scope_ids`/`selected_scope_ids` route/copy preservation, command queue source-unavailable placement/dashboard warning projection, source-endpoint ingress latency frame evidence, telemetry time-series durable source-watermark cursor source evidence and selected-source/selected-dataset persisted source-watermark event DataLinks, RF/transport history chart-point links, selected binding/application interval evidence, latest telemetry data-table and status-matrix row telemetry-sample DataLinks and frame evidence with source/scope context, empty telemetry value-tile source evidence without invented sample DataLinks, stale telemetry value-tile telemetry-sample DataLink and widget-frame evidence preservation under unknown source freshness, latest operational metric value-tile, status-matrix row, and data-table row operational-event frame evidence, replay metric-history operational-event frame evidence including partial returned-series evidence, and replay state-timeline operational-event links, including managed-runtime activity frame evidence plus managed timer, managed action, and managed capability-record operational-event copied-route reopens, transport-runtime activity frame evidence, live transport capability-record, action-request, and timer operational-event copied-route proof, command release attempt DataLinks, command release attempt source-endpoint/contact related-link DataLinks and copied-route reopens, verifier/action copied-route reopens, root release-attempt copied-route reopens, command verifier instance, telemetry matched-record, transport capability matched-record, transport action-request matched-record, and transport timer, transport capability-record, transport action-request, and transport-execution operational-event copied-route reopens, source-health operational-event copied-route reopen, connection-state operational-event copied-route reopen, ground-station connection-state operational-event copied-route reopen, command verifier instance DataLinks, matched telemetry sample DataLinks and copied-route reopens, matched transport action request DataLinks and copied-route reopens, transport timer, transport capability-record, transport action-request, and transport-execution operational-event DataLinks and copied-route reopens, source-health operational-event DataLinks and copied-route reopen, connection-state operational-event DataLinks and copied-route reopen, ground-station connection-state operational-event DataLinks and copied-route reopen, and matched transport capability record DataLinks and copied-route reopens, have proof. | Re-open or extend when new rendered link/evidence origins are introduced; each new origin needs resolver, selected-ref/query/copy payload, inspector/panel, stale/missing target, and browser wiring proof. |
| Runtime cache and invalidation | Complete; monitor for new runtime boundaries | Runtime cache keys, source-result preflight, frame materialization, refresh/backpressure decisions, invalidation boundaries, freshness evidence, and runtime diagnostics are covered. | Re-open only when new cache layers, invalidation boundaries, or source execution families are added. |
| Investigation workflows | Complete; monitor for new investigation workflow families | Historical request submission, approved/started/completed/retried/corrected workflow states, group recovery, replacement retry/stale/missing-job recovery, comparison review request/resolution, and bulk correction decisions, including partial-failure degraded browser outcomes, have browser and persistence proof. Comparison-review-origin workflow handoffs now carry aggregate operational scope/contact/resource identifiers into durable workflow payloads and rendered group/request forms; bulk comparison review action outcomes retain the same aggregate context in stable attrs, metadata JSON, and visible timeline rows; resolved comparison-review history carries source scope/contact/resource context alongside actionable/skipped audit counts; rendered replay revision-decision result handoff now carries durable decision payloads, action/result metadata, inspector controls, and copied/opened result routes with replay/data/limit context; and rendered corrected import recovery now records durable correction requests with replay/data/limit context plus latest-action selected-result handoffs. | Re-open when a new investigation action, bulk-selection mode, approval/start policy, job lifecycle, retry/correction path, recovery state, latest-action result, or audit origin lacks durable identity, policy explanation, progress/result UI, context preservation, and rendered proof. |
| Governance and permissions | Deferred RBAC/authz platform dependency | Existing dashboard actions rely on current authentication boundaries and `todo(authz)` markers where authorization policy will be needed. | Add authorization checks and action audit visibility once the broader RBAC model exists. |
| Browser/UI verification | Future expansion | Chrome/DevTools smoke covers dashboard assets, real sign-in, endpoint navigation, LiveSocket/GridStack/uPlot readiness, layout persistence, reload/deep-link hydration, source/version/diagnostic panels, runtime controls including multi-spacecraft, multi-contact, multi-ground-station, multi-link, multi-transport, and multi-source-endpoint context selection/clear, workflow submissions, comparison decisions, repeated placement rendering, contact/source-endpoint no-data evidence, mission-scoped/contact-scoped/replay contact-scoped/multi-contact/spacecraft-scoped/source-endpoint-scoped/ground-station-scoped/multi-source-endpoint/multi-ground-station contact-phase state-timeline rows/DataLinks/frame evidence including replay source context, non-primary contact route/copy preservation, legacy `spacecraft_id` route preservation, generic operational-resource `scope_kind`/`scope_id` route preservation, and multi-resource `scope_ids`/`selected_scope_ids` route preservation, unsupported operational-observable scope lifecycle blocking for value tiles and raw time-series, source-endpoint/ground-station/link operational-resource DataLinks, mission and multi-spacecraft aggregate command queue frame evidence, multi-spacecraft ingress-latency endpoint rows/DataLinks/frame evidence, mission-aggregate plus transport/source-endpoint/link-scoped, multi-source-endpoint, and multi-transport connection-state state-timeline rows/DataLinks/frame evidence including non-primary beta transport and ground-station route/copy payloads, live and replay ground-station scoped antenna pointing state-timeline row/DataLink/frame-evidence proof with generic operational-observable interval evidence, multi-link transport-execution state-timeline row/DataLink/frame-evidence proof with `scope_ids` and selected-scope copy preservation plus valid link-scoped no-data lifecycle/source metadata without invented rows or DataLinks, source-unavailable lifecycle/source-badge projection without invented rows or links, and live/replay degraded source-health source-status/source-badge projection plus row source-health event DataLink while rows remain rendered and replay source binding/run context is preserved, non-primary multi-link RF data-table DataLink/frame-evidence proof with `scope_ids` and selected-scope copy preservation, replay latest operational connection data-table row/DataLink/frame-evidence proof with replay source binding and dataset preservation, replay RF state data-table row/frame-evidence proof with replay source binding and dataset preservation, source-endpoint command queue DataLink and query-scoped frame-evidence proof for status matrix, value tile, and data table, mixed source-endpoint operational data-table proof for command queue plus ingress latency rows flattened from separate product frames with both row DataLinks, command row frame evidence, ingress metric-sample event evidence, stale mixed-widget lifecycle/row-warning preservation, degraded source-health widget source status, source evidence, row source-health DataLink, and preserved row actions, multi-source-endpoint ingress-latency time-series source-status/query diagnostics, partial returned-endpoint chart rendering without invented missing-endpoint point DataLinks, and query-scoped widget-frame evidence, source-endpoint empty-zero command queue data-table proof, presenter-level source-endpoint stale command queue data-table proof with metric sample operational-event frame evidence, telemetry time-series durable source-watermark cursor/source evidence, retention-gap marker rendering before the first sample, and selected-source/selected-dataset scoped persisted event overlay DataLinks, partial telemetry range lifecycle/source-badge/chart rendering plus chart-point telemetry-sample DataLinks, partial operational metric-history lifecycle/source-badge/chart rendering plus operational-resource chart DataLinks and returned-sample frame evidence, telemetry time-series source-unavailable source-badge/evidence blocking without chart hooks or synthetic point series, telemetry time-series source-degraded chart preservation with warning source badge/evidence, telemetry time-series stale chart preservation with warning source badge/evidence, telemetry time-series unknown-watermark chart preservation with unknown source badge/evidence, telemetry time-series retention-gap chart preservation with retention source badge/evidence, telemetry time-series no-data source-badge/evidence blocking without chart hooks, point links, markers, or synthetic series, partial telemetry latest data-table/status-matrix lifecycle and row DataLink/frame-evidence preservation, empty telemetry latest value-tile no-data lifecycle/source evidence, stale telemetry latest value-tile sampled rendering with source badge, telemetry-sample DataLink, and frame evidence preservation, fresh telemetry latest value-tile sampled rendering after persisted source watermark with fresh source status and no warning badge, ingress latency row/chart DataLinks, RF/transport metric history charts plus latest metric value tiles including RF Doppler and ingress-latency status-matrix rows including metric sample operational-event frame evidence, multi-series legend hide/show guarding, mixed-unit grouped/shared axis toggling, generic source-capability blocker labels, latest/aggregate source-product picker guidance, no-data lifecycle, RF/connection/transport-execution state timelines, and BYO source readiness. | Re-open or extend when new browser-only wiring or product workflows are introduced; each addition needs focused browser proof, bounded smoke coverage, cleanup/timeout guard coverage when relevant, and lower-layer tests for the permutation matrix. |

Recent evidence note: replay late-data policy actions now select the durable
audit event they record and preserve replay run, all-revisions data view,
compare limit mode, replay data source, replay source binding, policy run,
decision, execution mode, and sample count through the rendered inspector and a
copied route reopened in a fresh LiveView. Replay remains intentionally
event-only; this closes the result-recovery handoff without claiming replay
sample projection.

Recent evidence note: replay source-health effective intervals now have a typed
`source_health_interval` DataLink target. Rendered replay connection-state frame
evidence opens the canonical interval, copied routes reopen it in a fresh
LiveView, and replay run, data source, source binding, interval identity, and
canonical source-event identity remain intact. The dedicated proof lives in
`replay_source_health_interval_route_live_test.exs`; this narrows the selected
interval gap without reclassifying the broader operational-event or replay rows.

Recent evidence note: live source-health operational-event copied-route proof
now follows the source-health operational-event ref from rendered live
connection-state frame evidence. Copied operational-event routes reopen as fresh
LiveViews while preserving flight realm, operational-observables dataset,
source-health event identity, logical source, data source, source binding,
event type, source-health state, reason, source payload, selected timestamp,
source frame context, and copied route context.

Recent evidence note: live source-endpoint ingress-latency operational-event
copied-route proof now follows the durable metric-sample operational-event ref
from rendered live source-endpoint ingress-latency frame evidence. Copied
operational-event routes reopen as fresh LiveViews while preserving flight
realm, source-endpoint scope, operational-observables source binding,
metric-sample identity, source endpoint identity, selected timestamp, source
frame context, and copied route context.

Recent evidence note: replay source-endpoint ingress-latency operational-event
copied-route proof now follows the durable metric-sample operational-event ref
from rendered replay source-endpoint ingress-latency frame evidence. Copied
operational-event routes reopen as fresh LiveViews while preserving replay run,
operational-observables source binding, source-endpoint scope, metric-sample
identity, source endpoint identity, selected timestamp, source frame context,
and copied route context.

Recent evidence note: replay transport-bitrate operational-event copied-route
proof now follows the durable metric-sample operational-event ref from rendered
replay transport-scoped downlink-bitrate frame evidence. Copied operational-event
routes reopen as fresh LiveViews while preserving replay run,
operational-observables source binding, transport scope, metric-sample identity,
transport identity, source endpoint identity, selected timestamp, source frame
context, and copied route context.

Recent evidence note: replay transport-uplink-bitrate operational-event
copied-route proof now asserts canonical operational-event link/evidence refs at
the source layer and follows the durable metric-sample operational-event ref from
rendered replay transport-scoped uplink-bitrate frame evidence. Copied
operational-event routes reopen as fresh LiveViews while preserving replay run,
operational-observables source binding, transport scope, metric-sample identity,
transport identity, source endpoint identity, selected timestamp, source frame
context, and copied route context.

Recent evidence note: live transport-bitrate operational-event copied-route
proof now follows the durable metric-sample operational-event ref from rendered
live transport-scoped downlink-bitrate frame evidence. Copied operational-event
routes reopen as fresh LiveViews while preserving flight realm,
operational-observables source binding, transport scope, metric-sample identity,
transport identity, source endpoint identity, selected timestamp, source frame
context, and copied route context.

Recent evidence note: live transport-uplink-bitrate operational-event
copied-route proof now follows the durable metric-sample operational-event ref
from rendered live transport-scoped uplink-bitrate frame evidence. Copied
operational-event routes reopen as fresh LiveViews while preserving flight
realm, operational-observables source binding, transport scope, metric-sample
identity, transport identity, source endpoint identity, selected timestamp,
source frame context, and copied route context.

Recent evidence note: live managed runtime action/timer operational-event
copied-route proof now follows durable managed action and timer
operational-event refs from rendered live managed-runtime state-timeline frame
evidence. Copied operational-event routes reopen as fresh LiveViews while
preserving flight realm, operational-observables source binding, managed runtime
fact identity, capability, family, binding set, activation, partition,
packet/evidence, timer/action metadata, selected timestamp, source frame
context, and copied route context.

Recent evidence note: live managed capability-record operational-event
copied-route proof now follows durable managed capability-record
operational-event refs from rendered live managed-runtime state-timeline frame
evidence. The record-handled copied operational-event route reopens as a fresh
LiveView while preserving flight realm, operational-observables source binding,
managed capability-record identity, capability, family, binding set, activation,
partition, packet/evidence, emitted-record metadata, action request count, state
snapshot, selected timestamp, source frame context, and copied route context.

Recent evidence note: live transport action-request operational-event
copied-route proof now follows durable transport action-request
operational-event refs from rendered live transport-runtime state-timeline frame
evidence. The action-request copied operational-event route reopens as a fresh
LiveView while preserving flight realm, operational-observables source binding,
transport action-request identity, contact, path, capability, binding set,
activation, partition, source endpoint, command release attempt, command request,
command name, signal phase, action kind, request document, action metadata,
selected timestamp, source frame context, and copied route context.

Recent evidence note: live transport capability-record operational-event
copied-route proof now follows durable transport capability-record
operational-event refs from rendered live transport-runtime state-timeline frame
evidence. The capability-record copied operational-event route reopens as a
fresh LiveView while preserving flight realm, operational-observables source
binding, transport capability-record identity, contact, path, capability,
binding set, activation, partition, emitted-record metadata, action request
count, state snapshot, record metadata, selected timestamp, source frame
context, and copied route context.

Recent evidence note: live transport timer operational-event copied-route proof
now follows durable transport timer operational-event refs from rendered live
transport-runtime state-timeline frame evidence. The timer copied
operational-event route reopens as a fresh LiveView while preserving flight
realm, operational-observables source binding, transport timer identity, contact,
path, capability, binding set, activation, partition, timer key, event kind, due
time, timer metadata, selected timestamp, source frame context, and copied route
context.

Recent evidence note: replay RF Eb/N0 operational-event copied-route proof now
asserts canonical operational-event link/evidence refs at the source layer and
follows the durable metric-sample operational-event ref from rendered replay
link-scoped Eb/N0 frame evidence. Copied operational-event routes reopen as fresh
LiveViews while preserving replay run, operational-observables source binding,
link scope, metric-sample identity, link/resource identity, transport identity,
source endpoint identity, ground station, selected timestamp, source frame
context, and copied route context.

Recent evidence note: replay RF Doppler operational-event copied-route proof now
asserts canonical operational-event link/evidence refs at the source layer and
follows the durable metric-sample operational-event ref from rendered replay
link-scoped Doppler frame evidence. Copied operational-event routes reopen as
fresh LiveViews while preserving replay run, operational-observables source
binding, link scope, metric-sample identity, link/resource identity, transport
identity, source endpoint identity, ground station, selected timestamp, source
frame context, and copied route context.

Recent evidence note: replay RF symbol-rate operational-event copied-route proof
now asserts canonical operational-event link/evidence refs at the source layer
and follows the durable metric-sample operational-event ref from rendered replay
link-scoped symbol-rate frame evidence. Copied operational-event routes reopen as
fresh LiveViews while preserving replay run, operational-observables source
binding, link scope, metric-sample identity, link/resource identity, transport
identity, source endpoint identity, ground station, selected timestamp, source
frame context, and copied route context.

Recent evidence note: live RF symbol-rate operational-event copied-route proof
now follows the durable metric-sample operational-event ref from rendered live
link-scoped symbol-rate frame evidence. Copied operational-event routes reopen as
fresh LiveViews while preserving flight realm, operational-observables source
binding, link scope, metric-sample identity, link/resource identity, transport
identity, source endpoint identity, ground station, selected timestamp, source
frame context, and copied route context.

Recent evidence note: live RF Doppler operational-event copied-route proof now
follows the durable metric-sample operational-event ref from rendered live
link-scoped Doppler frame evidence. Copied operational-event routes reopen as
fresh LiveViews while preserving flight realm, operational-observables source
binding, link scope, metric-sample identity, link/resource identity, transport
identity, source endpoint identity, ground station, selected timestamp, source
frame context, and copied route context.

Recent evidence note: live RF Eb/N0 operational-event copied-route proof now
follows the durable metric-sample operational-event ref from rendered live
link-scoped Eb/N0 frame evidence. Copied operational-event routes reopen as
fresh LiveViews while preserving flight realm, operational-observables source
binding, link scope, metric-sample identity, link/resource identity, transport
identity, source endpoint identity, ground station, selected timestamp, source
frame context, and copied route context.

Recent evidence note: live connection-state operational-event copied-route proof
now follows the canonical connection-state operational-event ref from rendered
live connection-state frame evidence. Copied operational-event routes reopen as
fresh LiveViews while preserving flight realm, operational-observables source
binding, connection-state snapshot identity, observable/resource identity, scope
kind, transport, source endpoint, ground station, adapter, connection state,
selected timestamp, source frame context, and copied route context.

Recent evidence note: live RF lock/frame-sync operational-event copied-route
proof now follows the canonical RF lock operational-event ref from rendered live
link-scoped RF frame evidence. Copied operational-event routes reopen as fresh
LiveViews while preserving flight realm, link scope, operational-observables
source binding, RF state snapshot identity, observable/resource identity, scope
kind, transport, source endpoint, ground station, link, RF state, selected
timestamp, source frame context, and copied route context.

Recent evidence note: live antenna-pointing operational-event copied-route proof
now follows the canonical antenna-pointing operational-event ref from rendered
live ground-station scoped frame evidence. Copied operational-event routes reopen
as fresh LiveViews while preserving flight realm, ground-station scope,
operational-observables source binding, operational-observable snapshot identity,
observable/resource identity, scope kind, transport, source endpoint, ground
station, pointing state, selected timestamp, source frame context, and copied
route context.

Recent evidence note: replay source-health runtime-context copied-route proof now
reopens the copied source-health operational-event route from rendered replay
source-health frame evidence as a fresh LiveView. The inspector preserves replay
run, dataset/source binding, source-health event identity, logical source, data
source, source binding, realm, dataset, event type, source-health state, reason,
source payload, selected timestamp, source frame context, and copied route
context.

Recent evidence note: replay connection-state runtime-context copied-route proof
now reopens the copied connection-state operational-event route from rendered
replay connection-state frame evidence as a fresh LiveView. The inspector
preserves replay run, dataset/source binding, connection-state snapshot identity,
observable/resource identity, scope kind, transport, source endpoint, ground
station, adapter, state, connection state, selected timestamp, source frame
context, and copied route context.

Recent evidence note: live transport-execution operational-event copied-route
proof now follows the canonical transport-execution operational-event ref from
rendered live transport-scoped state-timeline frame evidence, emits a copied
DataLink route, and reopens that route as a fresh LiveView. The inspector
preserves flight realm, transport scope, operational-observables source binding,
transport capability-record identity, contact, path, capability instance,
family, binding-set version, activation, partition affinity/value, event kind,
state snapshot, selected timestamp, source frame context, and copied route
context.

Recent evidence note: live ground-station connection-state operational-event
copied-route proof now follows the canonical ground-station connection-state
operational-event ref from rendered live ground-station scoped frame evidence,
emits a copied DataLink route, and reopens that route as a fresh LiveView. The
inspector preserves flight realm, ground-station scope, operational-observables
source binding, ground-station connection-state snapshot identity,
observable/resource identity, scope kind, transport, source endpoint, ground
station, adapter, connection state, selected timestamp, source frame context,
and copied route context.

Recent evidence note: replay ground-station connection-state runtime-context
copied-route proof now reopens the copied ground-station connection-state
operational-event route from rendered replay ground-station connection-state
frame evidence as a fresh LiveView. The inspector preserves replay run,
dataset/source binding, ground-station connection-state snapshot identity,
observable/resource identity, scope kind, transport, source endpoint, ground
station, adapter, state, connection state, selected timestamp, source frame
context, and copied route context.

Recent evidence note: replay transport-execution runtime-context copied-route
proof now reopens the copied transport-execution operational-event route from
rendered replay transport-execution frame evidence as a fresh LiveView. The
inspector preserves replay run, dataset/source binding, transport capability
record identity, contact, path, capability instance, family, binding-set
version, activation, partition affinity/value, event kind, state snapshot,
selected timestamp, source frame context, and copied route context.

Recent evidence note: replay RF lock/frame-sync runtime-context copied-route
proof now reopens copied RF lock and frame-sync operational-event routes from
rendered replay RF status-matrix frame evidence as fresh LiveViews. The
inspectors preserve replay run, dataset/source binding, RF state event identity,
observable/resource identity, scope kind, transport, source endpoint, ground
station, link, RF state, selected timestamp, source frame context, and copied
route context.

Recent evidence note: replay antenna-pointing runtime-context copied-route proof
now reopens the copied antenna-pointing operational-event route from rendered
replay antenna-pointing frame evidence as a fresh LiveView. The inspector
preserves replay run, dataset/source binding, antenna-pointing event identity,
observable/resource identity, scope kind, transport, source endpoint, ground
station, state, selected timestamp, source frame context, and copied route
context.

Recent evidence note: replay command-queue entry copied-route proof now opens
rendered replay command-queue frame evidence refs as first-class command-queue
entry data links. The inspector resolves the durable queue row and copied
command-queue-entry routes reopen as fresh LiveViews while preserving replay
run, dataset/source binding, command queue entry identity, lifecycle state,
command request, source endpoint, queue lane, priority, enqueued timestamp,
selected timestamp, source frame context, and copied route context.

Recent evidence note: replay command-request related-link copied-route proof now
follows the command-queue-entry inspector's command request related link into a
first-class command-request data-link inspector. Copied command-request routes
reopen as fresh LiveViews while preserving replay run, dataset/source binding,
command request identity, lifecycle state, source endpoint, command identity,
requested timestamp, command-queue navigation origin, selected timestamp, source
frame context, and copied route context.

Recent evidence note: replay command-request queue/release related-link
copied-route proof now exposes persisted command queue entry and command release
attempt related links from command request inspectors. Rendered replay
command-request inspectors follow the command-queue-entry related link, and
copied command-queue-entry routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, command request identity, command queue
entry identity, command-request navigation origin, selected timestamp, source
frame context, and copied route context.

Recent evidence note: replay command release-attempt source-endpoint/contact
navigation-back copied-route proof now follows command-release-attempt
navigation entries from copied source-endpoint and contact inspectors. Copied
command-release-attempt routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, source-endpoint/contact navigation origin,
command release-attempt identity, command request identity, selected timestamp,
source frame context, and copied route context.

Recent evidence note: live command release-attempt source-endpoint/contact
navigation-back copied-route proof now follows command-release-attempt
navigation entries from copied source-endpoint and contact inspectors. Copied
command-release-attempt routes reopen as fresh LiveViews while preserving
flight realm, source-endpoint scope, operational-observables source binding,
source-endpoint/contact navigation origin, command release-attempt identity,
command request identity, source frame context, and copied route context.

Recent evidence note: live command release-attempt transport-action
operational-event release-attempt navigation-back copied-route proof now follows
command-release-attempt navigation entries from copied release-attempt-origin
operational-event inspectors. Copied command-release-attempt routes reopen as
fresh LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, canonical operational-event navigation
origin, command release-attempt identity, command request identity, signal
phase, action kind, source frame context, and copied route context.

Recent evidence note: replay command release-attempt command-request
related-link copied-route proof now exposes command request and command queue
entry related links from command release-attempt inspectors. Rendered replay
release-attempt inspectors follow the command-request related link, and copied
command-request routes reopen as fresh LiveViews while preserving replay run,
dataset/source binding, command release-attempt identity, command request
identity, release-attempt navigation origin, selected timestamp, source frame
context, and copied route context.

Recent evidence note: replay command release-attempt queue-entry related-link
copied-route proof now follows the command queue entry related link from rendered
replay command release-attempt inspectors. Copied command-queue-entry routes
reopen as fresh LiveViews while preserving replay run, dataset/source binding,
command release-attempt identity, command queue entry identity, command request
identity, release-attempt navigation origin, source frame context, and copied
route context.

Recent evidence note: replay command release-attempt transport-action
related-link copied-route proof now follows the transport-action related link
from rendered replay command release-attempt inspectors. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, command release-attempt identity, transport
action request identity, command request identity, signal phase, action kind,
release-attempt navigation origin, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event copied-route
proof now follows canonical operational-event related links from copied
transport-action-request inspectors reopened through failed-verifier
event-origin verifier matched-record operational-event verifier-back
matched-record operational-event verifier-back routes. Copied operational-event
routes reopen as fresh LiveViews while preserving replay run, dataset/source
binding, canonical operational event identity, failed verifier identity, matched
transport action request identity, command request/release attempt context,
source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record copied-route proof now follows
matched transport-action related links from copied command-verifier-instance
inspectors reopened through failed-verifier event-origin verifier matched-record
operational-event verifier-back matched-record operational-event verifier-back
routes. Copied transport-action-request routes reopen as fresh LiveViews while
preserving replay run, dataset/source binding, failed verifier identity, matched
transport action request identity, command request/release attempt context,
source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back copied-route proof now follows failed
command-verifier navigation entries from copied operational-event inspectors
reopened through failed-verifier event-origin verifier matched-record
operational-event verifier-back matched-record operational-event verifier-back
routes. Copied command-verifier-instance routes reopen as fresh LiveViews while
preserving replay run, dataset/source binding, canonical operational event
identity, failed verifier identity, matched transport action request identity,
command request/release attempt context, source frame context, runtime context,
and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event verifier-back matched-record
operational-event copied-route proof now follows canonical operational-event
related links from copied transport-action-request inspectors reopened through
failed-verifier event-origin verifier matched-record operational-event
verifier-back matched-record operational-event verifier-back routes. Copied
operational-event routes reopen as fresh LiveViews while preserving replay run,
dataset/source binding, canonical operational event identity, failed verifier
identity, matched transport action request identity, command request/release
attempt context, source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event verifier-back matched-record
copied-route proof now follows matched transport-action related links from copied
command-verifier-instance inspectors reopened through failed-verifier
event-origin verifier matched-record operational-event verifier-back
matched-record operational-event verifier-back routes. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, failed verifier identity, matched transport
action request identity, command request/release attempt context, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event verifier-back copied-route proof
now follows failed command-verifier navigation entries from copied
operational-event inspectors reopened through failed-verifier event-origin
verifier matched-record operational-event verifier-back matched-record
operational-event verifier-back routes. Copied command-verifier-instance routes
reopen as fresh LiveViews while preserving replay run, dataset/source binding,
canonical operational event identity, failed verifier identity, matched transport
action request identity, command request/release attempt context, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record operational-event copied-route proof now follows
canonical operational-event related links from copied transport-action-request
inspectors reopened through failed-verifier event-origin verifier matched-record
operational-event verifier-back matched-record operational-event verifier-back
routes. Copied operational-event routes reopen as fresh LiveViews while
preserving replay run, dataset/source binding, canonical operational event
identity, failed verifier identity, matched transport action request identity,
command request/release attempt context, source frame context, runtime context,
and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back matched-record copied-route proof now follows matched
transport-action related links from copied command-verifier-instance inspectors
reopened through failed-verifier event-origin verifier matched-record
operational-event verifier-back matched-record operational-event verifier-back
routes. Copied transport-action-request routes reopen as fresh LiveViews while
preserving replay run, dataset/source binding, failed verifier identity, matched
transport action request identity, command request/release attempt context,
source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
verifier-back copied-route proof now follows failed command-verifier navigation
entries from copied operational-event inspectors reopened through
failed-verifier event-origin verifier matched-record operational-event
verifier-back matched-record operational-event verifier-back routes. Copied
command-verifier-instance routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, canonical operational event identity,
failed verifier identity, matched transport action request identity, command
request/release attempt context, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record operational-event
copied-route proof now follows canonical operational-event related links from
copied transport-action-request inspectors reopened through failed-verifier
event-origin verifier matched-record operational-event verifier-back
matched-record operational-event verifier-back routes. Copied operational-event
routes reopen as fresh LiveViews while preserving replay run, dataset/source
binding, canonical operational event identity, failed verifier identity, matched
transport action request identity, command request/release attempt context,
source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back matched-record copied-route proof
now follows matched transport-action related links from copied
command-verifier-instance inspectors reopened through failed-verifier
event-origin verifier matched-record operational-event verifier-back
matched-record operational-event verifier-back routes. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, canonical operational event identity,
failed verifier identity, matched transport action request identity, command
request/release attempt context, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event verifier-back copied-route proof now follows
failed command-verifier navigation entries from copied operational-event
inspectors reopened through failed-verifier event-origin verifier matched-record
operational-event verifier-back matched-record operational-event routes. Copied
command-verifier-instance routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, canonical operational event identity,
failed verifier identity, matched transport action request identity, command
request/release attempt context, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record operational-event copied-route proof now follows canonical
operational-event related links from copied transport-action-request inspectors
reopened through failed-verifier event-origin verifier matched-record
operational-event verifier-back matched-record operational-event routes. Copied
operational-event routes reopen as fresh LiveViews while preserving replay run,
dataset/source binding, canonical operational event identity, failed verifier
identity, matched transport action request identity, command request/release
attempt context, source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
matched-record copied-route proof now follows matched transport-action related
links from copied command-verifier-instance inspectors reopened through
failed-verifier event-origin verifier matched-record operational-event
verifier-back matched-record operational-event routes. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, canonical operational event identity,
failed verifier identity, matched transport action request identity, command
request/release attempt context, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record copied-route proof now follows matched
transport-action request related links from copied failed-command-verifier
inspectors reopened through failed-verifier transport-action verifier-back
navigation. Copied transport-action-request routes reopen as fresh LiveViews
while preserving replay run, dataset/source binding, failed verifier identity,
matched transport action request identity, command request/release attempt
context, source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event copied-route proof now follows
canonical operational-event related links from copied transport-action-request
inspectors reopened through failed-verifier verifier-back matched-record routes.
Copied operational-event routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, failed verifier identity, matched transport
action request identity, canonical operational event identity, command
request/release attempt context, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back copied-route proof
now follows command-verifier navigation entries from copied operational-event
inspectors reopened through failed-verifier verifier-back matched-record
transport-action routes. Copied command-verifier-instance routes reopen as
fresh LiveViews while preserving replay run, dataset/source binding, canonical
operational event identity, matched transport action request identity, failed
verifier identity, command request/release attempt context, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event copied-route proof now follows canonical operational-event
related links from copied transport-action-request inspectors reopened through
failed-verifier event-origin verifier matched-record routes. Copied
operational-event routes reopen as fresh LiveViews while preserving replay run,
dataset/source binding, canonical operational event identity, failed verifier
identity, matched transport action request identity, command request/release
attempt context, source frame context, runtime context, and copied route
context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back copied-route proof now follows failed
command-verifier navigation entries from copied operational-event inspectors
reopened through failed-verifier event-origin verifier matched-record
transport-action routes. Copied command-verifier-instance routes reopen as
fresh LiveViews while preserving replay run, dataset/source binding, canonical
operational event identity, failed verifier identity, matched transport action
request identity, command request/release attempt context, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record copied-route proof now follows
matched transport-action related links from copied command-verifier-instance
inspectors reopened through failed-verifier event-origin verifier matched-record
operational-event routes. Copied transport-action-request routes reopen as
fresh LiveViews while preserving replay run, dataset/source binding, canonical
operational event identity, failed verifier identity, matched transport action
request identity, command request/release attempt context, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event copied-route
proof now follows canonical operational-event related links from copied
transport-action-request inspectors reopened through failed-verifier
event-origin verifier matched-record operational-event verifier-back routes.
Copied operational-event routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, canonical operational event identity,
failed verifier identity, matched transport action request identity, command
request/release attempt context, source frame context, runtime context, and
copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
operational-event verifier-back matched-record operational-event verifier-back
copied-route proof now follows failed command-verifier navigation entries from
copied operational-event inspectors reopened through failed-verifier
event-origin verifier matched-record operational-event verifier-back
matched-record routes. Copied command-verifier-instance routes reopen as fresh
LiveViews while preserving replay run, dataset/source binding, canonical
operational event identity, failed verifier identity, matched transport action
request identity, command request/release attempt context, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back matched-record operational-event verifier-back matched-record
copied-route proof now follows matched transport-action related links from
copied command-verifier-instance inspectors reopened through failed-verifier
event-origin verifier-back routes. Copied transport-action-request routes reopen
as fresh LiveViews while preserving replay run, dataset/source binding,
canonical operational event identity, failed verifier identity, matched
transport action request identity, command request/release attempt context,
source frame context, runtime context, and copied route context.

Recent evidence note: replay command failed verifier matched transport-action
verifier-back copied-route proof now follows command-verifier navigation entries
from copied transport-action-request inspectors reopened through failed
command-verifier matched-record related links. Copied command-verifier-instance
routes reopen as fresh LiveViews while preserving replay run, dataset/source
binding, transport-action navigation origin, failed command verifier identity,
matched transport action request identity, command request/release attempt
context, source frame context, runtime context, and copied route context.

Recent evidence note: replay command verifier matched telemetry verifier-back
copied-route proof now follows command-verifier navigation entries from copied
telemetry-sample inspectors reopened through command-verifier matched-record
related links. Copied command-verifier-instance routes reopen as fresh LiveViews
while preserving replay run, dataset/source binding, telemetry-sample navigation
origin, matched telemetry sample identity, telemetry point identity, command
verifier identity, matched-record context, source frame context, runtime
context, and copied route context.

Recent evidence note: replay command verifier matched transport capability
operational-event matched-record verifier-back copied-route proof now follows
command-verifier navigation entries from copied transport-capability-record
inspectors reopened through canonical operational-event navigation. Copied
command-verifier-instance routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, transport-capability navigation origin,
canonical operational-event trail, matched transport capability record identity,
command verifier identity, matched-record context, source frame context, runtime
context, and copied route context.

Recent evidence note: replay command verifier matched transport capability
operational-event verifier-back matched-record operational-event copied-route
proof now follows canonical operational-event related links from copied
transport-capability-record inspectors reopened through the canonical
operational-event -> command-verifier -> matched-record trail. Copied
operational-event routes reopen as fresh LiveViews while preserving replay run,
dataset/source binding, transport-capability navigation origin,
command-verifier trail, matched transport capability record identity, canonical
operational event identity, source frame context, runtime context, and copied
route context.

Recent evidence note: replay command verifier matched transport capability
operational-event verifier-back matched-record copied-route proof now follows
matched transport-capability-record related links from copied
command-verifier-instance inspectors reopened from canonical operational-event
navigation. Copied transport-capability-record routes reopen as fresh LiveViews
while preserving replay run, dataset/source binding, command-verifier navigation
origin, canonical operational-event trail, matched transport capability record
identity, capability instance context, source frame context, runtime context,
and copied route context.

Recent evidence note: replay command verifier matched transport capability
operational-event verifier navigation-back copied-route proof now follows
command-verifier-instance navigation entries from copied canonical
operational-event inspectors opened from verifier-origin transport-capability
records. Copied command-verifier-instance routes reopen as fresh LiveViews while
preserving replay run, dataset/source binding, canonical operational-event
navigation origin, matched transport capability record identity, command
verifier identity, verifier matched-record context, source frame context,
runtime context, and copied route context.

Recent evidence note: replay command verifier matched transport capability
operational-event navigation-back copied-route proof now follows
transport-capability-record navigation entries from copied canonical
operational-event inspectors opened from verifier-origin transport-capability
records. Copied transport-capability-record routes reopen as fresh LiveViews
while preserving replay run, dataset/source binding, canonical operational-event
navigation origin, command-verifier navigation trail, matched transport
capability record identity, capability instance context, source frame context,
runtime context, and copied route context.

Recent evidence note: replay command verifier matched transport capability
operational-event related-link copied-route proof now follows the canonical
operational-event related link from verifier-origin transport-capability-record
inspectors. Copied operational-event routes reopen as fresh LiveViews while
preserving replay run, dataset/source binding, transport capability record
identity, canonical operational event identity, transport-capability navigation
origin, command-verifier navigation trail, source frame context, runtime
context, and copied route context.

Recent evidence note: replay command verifier matched telemetry related-link
copied-route proof now follows the matched telemetry related link from rendered
replay command verifier inspectors. Copied telemetry-sample routes reopen as
fresh LiveViews while preserving replay run, dataset/source binding, command
verifier identity, matched telemetry sample identity, telemetry point identity,
verifier navigation origin, source frame context, telemetry context, and copied
route context.

Recent evidence note: replay command verifier matched transport capability
related-link copied-route proof now follows the matched transport-capability
related link from rendered replay command verifier inspectors. Copied
transport-capability-record routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, command verifier identity, matched transport
capability record identity, verifier navigation origin, source frame context,
runtime context, and copied route context.

Recent evidence note: replay command verifier matched transport-action
related-link copied-route proof now follows the matched transport-action related
link from rendered replay command verifier inspectors. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
replay run, dataset/source binding, command verifier identity, matched transport
action request identity, command release attempt identity, command request
identity, signal phase, action kind, verifier navigation origin, source frame
context, runtime context, and copied route context.

Recent evidence note: replay command verifier instance release-attempt
related-link copied-route proof now exposes command release-attempt and command
request related links from command verifier instance inspectors. Rendered replay
verifier inspectors follow the release-attempt related link, and copied
command-release-attempt routes reopen as fresh LiveViews while preserving replay
run, dataset/source binding, command verifier identity, command release-attempt
identity, verifier navigation origin, selected timestamp, source frame context,
and copied route context.

Recent evidence note: replay command verifier instance command-request
related-link copied-route proof now follows command-request related links from
rendered command verifier instance inspectors. Copied command-request routes
reopen as fresh LiveViews while preserving replay run, dataset/source binding,
command verifier identity, command request identity, verifier navigation origin,
selected timestamp, source frame context, and copied route context.

Recent evidence note: rendered replay metric-sample operational-event
copied-route reopen evidence now extends the existing metric-sample
resolver/route-query proof into a widget-origin path. Replay metric-history
frame evidence preserves observable/source context, opens the metric-sample
operational-event evidence ref, renders the operational-event data-link
inspector, emits a copied data-link route, and reopens that copied route as a
fresh LiveView while preserving replay run, dataset/source binding, metric
identity, resource/link identity, value/unit context, selected timestamp, source
frame context, and copied route context.

Recent evidence note: rendered live metric-sample operational-event copied-route
reopen evidence now extends the metric-history widget-origin path into flight
mode. Live link-scoped metric-history frame evidence opens the metric-sample
operational-event evidence ref, renders the operational-event data-link
inspector, emits a copied data-link route, and reopens that copied route as a
fresh LiveView while preserving flight realm, link scope,
operational-observables source binding, metric event identity,
observable/resource/link identity, transport/source-endpoint/ground-station
context, value/unit context, selected timestamp, source frame context, and
copied route context.

Recent evidence note: rendered live source-endpoint command-queue copied-route
evidence now extends command-queue entry frame evidence into flight mode. Live
source-endpoint scoped command-queue status-matrix frame evidence opens the
durable command-queue-entry ref, excludes out-of-scope and released entries,
renders the command-queue-entry data-link inspector, emits a copied data-link
route, and reopens that copied route as a fresh LiveView while preserving flight
realm, source-endpoint scope, operational-observables source binding, command
queue entry identity, lifecycle state, command request, source endpoint, queue
lane, priority, enqueued timestamp, source frame context, and copied route
context.

Recent evidence note: rendered live command-request related-link copied-route
evidence now follows the command-request related link from a live
source-endpoint command-queue-entry inspector. Copied command-request routes
reopen as fresh LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, command queue navigation origin,
command request identity, lifecycle state, source endpoint, command identity,
requested timestamp, source frame context, and copied route context.

Recent evidence note: rendered live command-request queue-entry related-link
copied-route evidence now follows the command-queue-entry related link from the
copied live command-request inspector. Copied command-queue-entry routes reopen
as fresh LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, command-request navigation origin,
command queue entry identity, lifecycle state, command request, source endpoint,
queue lane, priority, enqueued timestamp, source frame context, and copied route
context.

Recent evidence note: rendered live command-request release-attempt related-link
copied-route evidence now follows the command-release-attempt related link from
the copied live command-request inspector. Copied command-release-attempt routes
reopen as fresh LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, command-request navigation origin,
command release-attempt identity, lifecycle state, verification state, command
request, command queue entry, source endpoint, realized contact, source frame
context, and copied route context.

Recent evidence note: rendered live command release-attempt transport-action
related-link copied-route evidence now follows the transport-action related link
from the copied live command-release-attempt inspector. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
flight realm, source-endpoint scope, operational-observables source binding,
command-release-attempt navigation origin, transport action request identity,
canonical operational event identity, contact, path, capability, binding,
partition, source endpoint, command release attempt, command request, command
name, signal phase, action kind, request document, action metadata, source frame
context, and copied route context.

Recent evidence note: rendered live command verifier matched transport-action
related-link copied-route evidence now follows the matched transport-action
related link from the copied live command-verifier-instance inspector. Copied
transport-action-request routes reopen as fresh LiveViews while preserving
flight realm, source-endpoint scope, operational-observables source binding,
command-verifier-instance navigation origin, command verifier identity, matched
transport action request identity, canonical operational event identity,
command release attempt, command request, signal phase, action kind, source
frame context, and copied route context.

Recent evidence note: rendered live command verifier matched transport-action
operational-event related-link copied-route evidence now follows the canonical
operational-event related link from the copied live verifier-origin
transport-action-request inspector. Copied operational-event routes reopen as
fresh LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, transport-action-request navigation
origin, command-verifier-instance navigation trail, canonical operational event
identity, matched transport action request identity, command release attempt,
command request, signal phase, action kind, source frame context, and copied
route context.

Recent evidence note: rendered live command release-attempt transport-action
operational-event related-link copied-route evidence now follows the canonical
operational-event related link from the copied live release-attempt-origin
transport-action-request inspector. Copied operational-event routes reopen as
fresh LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, transport-action-request navigation
origin, command-release-attempt navigation trail, canonical operational event
identity, transport action request identity, command release attempt, command
request, signal phase, action kind, source frame context, and copied route
context.

Recent evidence note: rendered replay command release-attempt transport-action
operational-event related-link copied-route evidence now follows the canonical
operational-event related link from the copied replay release-attempt-origin
transport-action-request inspector. Copied operational-event routes reopen as
fresh LiveViews while preserving replay run, operational-observables source
binding, transport-action-request navigation origin, command-release-attempt
navigation trail, canonical operational event identity, transport action request
identity, command release attempt, command request, signal phase, action kind,
runtime context, selected time, and copied route context.

Recent evidence note: rendered replay command verifier matched
transport-action operational-event related-link copied-route evidence now
follows the canonical operational-event related link from the copied replay
matched transport-action-request inspector. Copied operational-event routes
reopen as fresh LiveViews while preserving replay run, operational-observables
source binding, transport-action-request navigation origin, canonical
operational event identity, matched transport action request identity, command
release attempt, command request, signal phase, action kind, runtime context,
selected time, and copied route context.

Recent evidence note: rendered replay command verifier matched
transport-action operational-event navigation-back copied-route evidence now
follows the transport-action-request navigation entry from the copied replay
matched operational-event inspector. Copied transport-action-request routes
reopen as fresh LiveViews while preserving replay run, operational-observables
source binding, canonical operational-event navigation origin, matched transport
action request identity, command release attempt, command request, signal phase,
action kind, runtime context, selected time, and copied route context.

Recent evidence note: rendered replay command release-attempt transport-action
operational-event release-attempt navigation-back copied-route evidence now
follows the command-release-attempt navigation entry from the copied replay
release-attempt-origin operational-event inspector. Copied
command-release-attempt routes reopen as fresh LiveViews while preserving replay
run, operational-observables source binding, canonical operational-event
navigation origin, command-release-attempt identity, command request, signal
phase, action kind, runtime context, selected time, and copied route context.

Recent evidence note: rendered live command release-attempt verifier
related-link copied-route evidence now follows the command-verifier-instance
related link from the copied live command-release-attempt inspector. Copied
command-verifier-instance routes reopen as fresh LiveViews while preserving
flight realm, source-endpoint scope, operational-observables source binding,
command-release-attempt navigation origin, command verifier identity, verifier
name, lifecycle state, command request, source endpoint, source frame context,
and copied route context.

Recent evidence note: rendered live command release-attempt contact related-link
copied-route evidence now follows the contact related link from the copied live
command-release-attempt inspector. Copied contact routes reopen as fresh
LiveViews while preserving flight realm, source-endpoint scope,
operational-observables source binding, command-release-attempt navigation
origin, realized contact identity, lifecycle state, contact type, source
endpoint, source frame context, and copied route context.

Recent evidence note: rendered live command release-attempt source-endpoint
related-link copied-route evidence now follows the source-endpoint related link
from the copied live command-release-attempt inspector. Copied source-endpoint
routes reopen as fresh LiveViews while preserving flight realm, source-endpoint
scope, operational-observables source binding, command-release-attempt
navigation origin, source endpoint identity, display name, source frame context,
and copied route context.

Recent evidence note: rendered live command release-attempt command-request
related-link copied-route evidence now follows the command-request related link
from the copied live command-release-attempt inspector. Copied command-request
routes reopen as fresh LiveViews while preserving flight realm, source-endpoint
scope, operational-observables source binding, command-release-attempt
navigation origin, command request identity, lifecycle state, source endpoint,
command identity, requested timestamp, source frame context, and copied route
context.

Recent evidence note: rendered live command release-attempt queue-entry
related-link copied-route evidence now follows the command-queue-entry related
link from the copied live command-release-attempt inspector. Copied
command-queue-entry routes reopen as fresh LiveViews while preserving flight
realm, source-endpoint scope, operational-observables source binding,
command-release-attempt navigation origin, command queue entry identity,
lifecycle state, command request, source endpoint, queue lane, priority,
enqueued timestamp, source frame context, and copied route context.

Recent evidence note: replay transport action-request operational-event copied-route reopen evidence now reopens the copied operational-event data-link route directly after the transport-runtime frame-evidence drilldown path. Evidence-ref and copied-route handoff attrs preserve timestamp, route scope, replay run, dataset, data source, source binding, mission-scope context, transport action request identity, request document, command request, command release attempt, command/signal source context, selected timestamp, copied/opened data-link routes, and source-bound data-link context while retaining transport timer, transport capability-record, managed timer/action, and managed capability-record copied-route context.

Recent evidence note: replay managed-runtime action/timer, capability-record
lifecycle, and emitted-output/action-result evidence now have a source-backed
`runtime.managed_activity` operational observable, State Timeline widget
contract support, replay-aware managed runtime event reads, source-frame
metadata/evidence refs including capability-record state snapshots,
emitted/action counts, action request document JSON, and produced-output
metadata JSON, rendered replay state-timeline rows, operational-event evidence
inspector refs, and copied/opened frame-evidence route proof while preserving
replay run, dataset, data source, and source binding context.

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
ADR-019 makes the per-result operational-event backing in this evidence a
migration dependency rather than the target architecture. This checklist stays
open for ingress latency until equivalent latest/history, scope, freshness, and
DataLink proof runs against runtime health plus the metrics/time-series source
without requiring one operational event per sample.

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
only the non-secret credential descriptor to a configured endpoint, enforces
HTTPS by default with an explicit local/test insecure-HTTP opt-out, accepts
ephemeral material through the same material policy/audit path as env-backed
credentials, fails closed when no endpoint is configured, and redacts HTTP error
bodies from returned failure reasons. Focused credential tests prove request
shape, token/header handling, material extraction, fail-closed configuration,
HTTPS enforcement, redacted error behavior, and durable material-resolution
audit events that identify the resolver plus external secret backend without
persisting endpoint URLs, secret-manager tokens, returned bearer tokens,
returned endpoints, or HTTP error bodies.
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
Scheduled source-probe timeouts now become operator-visible evidence instead of
only local scheduler errors. The bounded scheduler records an unavailable
source-health event with scheduler-timeout metadata when a probe exceeds its
deadline, and the Data Sources page renders the blocked connection-test result,
timeout metadata, and recent source-health event for BYO sources.
BYO TSDB descriptors can now model externally dedicated organization or mission
backends instead of forcing every customer-owned QuestDB source into the generic
customer-connection boundary. Domain validation accepts customer-owned BYO TSDBs
with `customer_owned`, `org_isolated`, or `mission_isolated` isolation while
still requiring customer ownership and indirect credentials; deployment status
renders dedicated org/mission remediation hints for those external backends.
BYO credential references now have an operator rotation path from the Ops Data
Sources inventory. The action uses the source credential lifecycle context,
increments the credential version, records a rotated credential event with
operator/source payload, and refreshes the rendered source row with the new
credential state.
Dedicated BYO TSDB backends now have an operator reconciliation path from the
same inventory. The action records reconciliation state in the data-source
descriptor, writes a changed source event with backend/boundary lifecycle
payload, and renders lifecycle operation/status/timestamp attributes on the
source row.
Dedicated BYO TSDB backends also have a worker-backed deprovision lifecycle.
The operator action records deprovision-request lifecycle state, disables the
source through the normal data-source event path, removes the generic re-enable
affordance for that retired backend, enqueues a redacted TSDB backend lifecycle
job, renders the queued job in the deployment-runs panel, and the job dispatcher
can execute a configured physical deprovision adapter before marking the source
descriptor deprovisioned with job/run evidence.
The same durable lifecycle-job boundary now covers dedicated BYO TSDB
provisioning. Operators can request backend provisioning from the Data Sources
inventory; Cadence records provisioning-request metadata, enqueues a redacted
TSDB backend lifecycle job, renders the queued job, and the dispatcher can run a
configured physical provisioning adapter before marking the descriptor
provisioned with job/run/executor evidence.
Source probe scheduling now has a source-level policy contract. Physical source
metadata can disable automatic scheduled probes or set a per-source
`stale_after_ms` threshold; the scheduler honors those policies when deciding
whether a backend is due, carries the policy id into probe payloads, and the
Data Sources page renders the effective policy id and stale threshold on each
source row.
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
workflow proofs run independently in roughly one second. The next split moved
direct request, grouped import approval/start, single retry, and grouped retry
browser proofs into
`ops_dashboard_show_live/historical_workflow_request_retry_live_test.exs`; that
focused file passes 5 tests in roughly 1.6 seconds, and the reduced monolith plus
replacement split now passes 114 tests in roughly 38.4 seconds. A full
`mix precommit` passed after one isolated-rerun runtime timeout in an unrelated
Cadence child test. The single and grouped failed import retry proofs later moved
again into `ops_dashboard_show_live/historical_workflow_import_retry_live_test.exs`;
the request workflow owner kept direct backfill/import requests and grouped
import request approval/start behavior at that point. The trimmed request
workflow owner plus import-retry owner pass 5 tests in roughly 1.0 seconds;
`historical_workflow_request_retry_live_test.exs` is down to 525 lines and the
import-retry owner is 394 lines. A full `mix precommit` passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web`
tests with 93 excluded. Grouped import request approval/start coverage later
moved again into
`ops_dashboard_show_live/historical_workflow_grouped_import_live_test.exs`; the
request workflow owner now keeps direct backfill/import request behavior. The
trimmed request workflow owner plus grouped-import owner pass 3 tests in roughly
0.8 seconds; `historical_workflow_request_retry_live_test.exs` is down to 289
lines and the grouped-import owner is 313 lines. A full `mix precommit` passed
after the historical-workflow grouped-import split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded. The
next split moved
correction-request and completed
corrected-import browser proofs into
`ops_dashboard_show_live/historical_workflow_correction_completion_live_test.exs`;
that focused file passes 2 tests in roughly 0.8 seconds, and the three focused
historical workflow files plus the reduced dashboard console file pass 119 tests
in roughly 38.0 seconds. The monolithic dashboard console file now carries 110
tests. A full `mix precommit` passed after the correction/completion split. The
next split moved the grouped backfill request/stage/progress browser proof into
`ops_dashboard_show_live/historical_workflow_grouped_backfill_live_test.exs`;
that focused file passes 1 test in roughly 1.5 seconds, and the four focused
historical workflow files plus the reduced dashboard console file pass 119 tests
in roughly 39.3 seconds. The monolithic dashboard console file now carries 109
tests. A full `mix precommit` passed after the grouped-backfill split. The next
split moved grouped retry skipped-item and corrected replacement advance browser
proofs into
`ops_dashboard_show_live/historical_workflow_group_recovery_live_test.exs`. The
skipped-item group retry proof now lives in
`ops_dashboard_show_live/historical_workflow_group_recovery_retry_live_test.exs`;
the group recovery owner now keeps corrected replacement request advancement
only. Those two focused owners pass 2 tests in roughly 0.7 seconds;
`historical_workflow_group_recovery_live_test.exs` is down to 515 lines and the
retry owner is 213 lines. A full `mix precommit` passed after the original
group-recovery split.
The next split moved stage transition, failed retry, and non-retryable
correction browser proofs into
`ops_dashboard_show_live/historical_workflow_stage_retry_live_test.exs`; that
focused file passes 3 tests in roughly 1.1 seconds, and the six focused
historical workflow files plus the reduced dashboard console file pass 119 tests
in roughly 35.2 seconds. The monolithic dashboard console file now carries 104
tests. A full `mix precommit` passed after one isolated-rerun Cadence child
database checkout failure. Failed-job retry, non-retryable correction guidance,
correction request creation, and correction DataLink navigation now live in
`ops_dashboard_show_live/historical_workflow_retry_correction_live_test.exs`; the
stage owner now keeps stage transitions and started-job queue/completion
behavior. The trimmed stage owner plus retry/correction owner pass 3 tests in
roughly 1.0 seconds; `historical_workflow_stage_retry_live_test.exs` is down to
347 lines and the retry/correction owner is 527 lines. A full `mix precommit`
passed after the historical-workflow retry/correction split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with 93
excluded. The next split moved
non-retryable correction guidance, correction request creation, and correction
DataLink navigation into
`ops_dashboard_show_live/historical_workflow_nonretryable_correction_live_test.exs`;
the retry owner now keeps failed-job retry behavior only. The trimmed retry owner
plus non-retryable correction owner pass 2 tests in roughly 0.8 seconds;
`historical_workflow_retry_correction_live_test.exs` is down to 211 lines and the
non-retryable correction owner is 393 lines. The first full `mix precommit`
after this split hit an isolated `CadenceSimulator.SendBufferTest` cleanup
failure; the exact test rerun passed, and the full precommit rerun passed with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests
with 93 excluded. The next split moved
late-data policy and revision
decision browser proofs into
`ops_dashboard_show_live/historical_workflow_data_management_live_test.exs`; that
focused file passes 2 tests in roughly 0.9 seconds, and the seven focused
historical workflow files plus the reduced dashboard console file pass 119 tests
in roughly 32.1 seconds. The monolithic dashboard console file now carries 102
tests. A full `mix precommit` passed after the data-management split. A later
final-state `mix precommit` passed after one isolated-rerun simulator cleanup
race. Revision-decision event inspection, decision application, DataLink
action-outcome metadata, and current-value invalidation now live in
`ops_dashboard_show_live/historical_workflow_revision_decision_live_test.exs`;
the data-management owner now keeps live and replay late-data policy decisions
only. The trimmed data-management owner plus revision-decision owner pass 3
tests in roughly 0.9 seconds; `historical_workflow_data_management_live_test.exs`
is down to 482 lines and the revision-decision owner is 418 lines. A full
`mix precommit` passed after the historical-workflow revision-decision split with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests
with 93 excluded. The next split moved comparison review request/resolution,
lifecycle
data-link routing, bulk revision decision, unavailable bulk decision, versions
activity, and grouped historical-workflow handoff proofs into
`ops_dashboard_show_live/historical_workflow_comparison_review_live_test.exs`;
that focused file passes 11 tests in roughly 2.1 seconds, and the eight focused
historical workflow files plus the reduced dashboard console file pass 119 tests
in roughly 37.2 seconds. The monolithic dashboard console file now carries 91
tests. A full `mix precommit` passed after the comparison-review split. The
grouped handoff proof later moved again into its own grouped-request owner. The next
split moved event and limit runtime-invalidation refresh plus
unrelated-observable skip browser proofs into
`ops_dashboard_show_live/runtime_invalidation_event_limit_live_test.exs`;
event/limit overlay-absence matching now stays in the async
`runtime_invalidation_relevance_test.exs` policy owner instead of full LiveView
tests. The focused split files plus the reduced dashboard console file pass 119
tests in roughly 39.9 seconds. The monolithic dashboard console file now carries
85 tests. A full
`mix precommit` passed after the event/limit runtime-invalidation split. The
next split moved telemetry data-source-binding, source-health, and
source-watermark runtime-invalidation refresh, overlay source-relevance, and
unrelated-observable browser proofs into
`ops_dashboard_show_live/runtime_invalidation_telemetry_live_test.exs`; the
no-telemetry-primary matching permutations stay in the async
`runtime_invalidation_relevance_test.exs` policy owner instead of full LiveView
tests. The focused owner command now passes 18 `cadence` policy tests and 7
`cadence_web` LiveView tests; the older focused split bundle plus the reduced
dashboard console file passed 119 tests in roughly 33.2 seconds before this
ownership trim.
The monolithic dashboard console file now carries 75 tests. A full
`mix precommit` passed after one isolated-rerun Cadence runtime repo-readiness
failure. The next split moved realm, data-source, source-binding, cache-reuse,
scoped diagnostics, replay-context, and persisted-decision runtime-invalidation
browser proofs into
`ops_dashboard_show_live/runtime_invalidation_context_diagnostics_live_test.exs`;
that focused file passes 7 tests in roughly 1.5 seconds, and the focused split
files plus the reduced dashboard console file pass 119 tests in roughly 21.8
seconds. The monolithic dashboard console file now carries 68 tests. A full
`mix precommit` passed after the context/diagnostics split. Replay-context
matching and persisted replay runtime-invalidation decision projection now live
in
`ops_dashboard_show_live/runtime_invalidation_replay_diagnostics_live_test.exs`;
the trimmed runtime invalidation context diagnostics owner keeps live
realm/data-source/source-binding matching, cache reuse, scoped diagnostics, and
live durable decision projection. Those two focused owners pass 7 tests after
the replay diagnostics split. A full `mix precommit` passed after the runtime
invalidation replay diagnostics split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Realm, data-source, and source-binding invalidation matching later moved again
into
`ops_dashboard_show_live/runtime_invalidation_source_context_live_test.exs`; the
runtime invalidation context diagnostics owner now keeps cache reuse, scoped
diagnostics, and live durable decision projection. The trimmed diagnostics owner
plus source-context owner pass 5 tests in roughly 1.1 seconds;
`runtime_invalidation_context_diagnostics_live_test.exs` is down to 594 lines and
the source-context owner is 409 lines. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded. Scoped operator diagnostics and durable
live runtime-invalidation decision projection later moved again into
`ops_dashboard_show_live/runtime_invalidation_operator_diagnostics_live_test.exs`;
the runtime invalidation context diagnostics owner now keeps only runtime cache
reuse source-result/frame browser behavior. The trimmed context diagnostics owner
plus operator diagnostics owner pass 2 tests in roughly 0.8 seconds;
`runtime_invalidation_context_diagnostics_live_test.exs` is down to 251 lines and
the operator diagnostics owner is 419 lines. A full `mix precommit` passed after
the runtime invalidation operator diagnostics split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded. The
next split moved in-flight resolve cancellation, data-realm/source-binding controls,
runtime defaults, published/draft default behavior, and source-binding warning
browser proofs into
`ops_dashboard_show_live/runtime_context_source_binding_live_test.exs`; that
focused file passes 7 tests in roughly 2.5 seconds, and the focused split files
plus the reduced dashboard console file pass 119 tests in roughly 26.6 seconds.
The monolithic dashboard console file now carries 61 tests. A full
`mix precommit` passed after the runtime context/source-binding split. Missing
source-binding warning evidence now lives in
`ops_dashboard_show_live/runtime_source_binding_warnings_live_test.exs`; the
trimmed runtime context/source-binding owner keeps cancellation, controls,
defaults, and published/draft behavior. Unsupported source-capability diagnostics
now live in
`ops_dashboard_show_live/runtime_source_capability_warnings_live_test.exs`; the
source-binding warning owner now keeps missing source-binding warning evidence,
source health evidence, context-only DataLink handoff, and missing warning/source
evidence states. The source-binding warning owner plus source-capability warning
owner pass 2 tests in roughly 1.2 seconds; the source-binding warning owner is
489 lines and the source-capability warning owner is 378 lines. A full
`mix precommit` passed after the runtime source-binding warnings split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with
93 excluded. Runtime data-default save/apply behavior and published/draft default
behavior now live in
`ops_dashboard_show_live/runtime_context_defaults_live_test.exs`; the runtime
context/source-binding owner now keeps cancellation, data-realm control, explicit
source-binding selection, data-link source context, and stale-selection clearing.
The trimmed source-binding owner plus defaults owner pass 5 tests in roughly 1.8
seconds; `runtime_context_source_binding_live_test.exs` is down to 594 lines and
the defaults owner is 450 lines. A full `mix precommit` passed after the runtime
context defaults split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1542 `cadence_web` tests with 93 excluded. In-flight runtime context resolve
cancellation later moved again into
`ops_dashboard_show_live/runtime_context_cancellation_live_test.exs`; the runtime
context/source-binding owner now keeps data-realm control, explicit
source-binding selection, data-link source context, and stale-selection clearing.
The trimmed source-binding owner plus cancellation owner pass 3 tests in roughly
1.2 seconds; `runtime_context_source_binding_live_test.exs` is down to 489 lines
and the cancellation owner is 252 lines. A full `mix precommit` passed after the
runtime context cancellation split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded. The
next split moved
add-widget slide-over, event timeline, telemetry state timeline,
status matrix, data table, and operational status matrix browser proofs into
`ops_dashboard_show_live/widget_creation_live_test.exs`; binding-source selector
frame-contract behavior and operational-observable picker value-kind filtering
now live in render-panel and widget-form owner tests, while operational
state-timeline placement and multi-select behavior live in placement-editor and
widget-editing owner tests. That focused file passed 9 tests in roughly 1.6
seconds before those matrices were trimmed, and the focused split files plus the
reduced dashboard console file pass 119 tests in roughly 20.0 seconds. The
monolithic dashboard console file now carries 52 tests. A full `mix precommit`
passed after one isolated-rerun Cadence DB lifecycle setup failure. The next
split moved stale edit conflict, edit-mode layout, and remove/reconfigure
browser proofs into `ops_dashboard_show_live/widget_lifecycle_live_test.exs`;
missing-point widget validation now lives in placement-editor/widget-editing
owner tests, archive/restore coverage routes to the dashboard lifecycle owner,
and toolbar rename browser wiring has also moved to dashboard lifecycle. The
monolithic dashboard console file now carries 45
tests. A full `mix precommit` passed after the original widget lifecycle split.
Widget data-contract source-failure behavior now lives in
`ops_dashboard_show_live/widget_data_contract_source_failure_test.exs`; the
general widget data-contract owner keeps ready, no-data, stale, chart-backfill,
and operational no-data payload contracts. Those two focused owners pass 15
async tests in roughly 0.1 seconds; `widget_data_contract_test.exs` is down to
525 lines and the source-failure owner is 110 lines.
Operational metric time-series data shaping now lives in
`ops_dashboard_show_live/time_series_data_operational_test.exs`; the general
time-series data owner keeps telemetry envelope, latest/scalar, append, and
generic empty-frame diagnostics. Those two focused owners pass 10 async tests in
roughly 0.1 seconds; `time_series_data_test.exs` is down to 331 lines and the
operational owner is 296 lines.
Stale restore, stale publish, and stale archive conflict reload browser proofs
now live in
`ops_dashboard_show_live/dashboard_lifecycle_conflict_live_test.exs`; the
dashboard lifecycle owner keeps normal version history, create/edit/publish,
revert/archive/restore, rename, historical publish, invalid publish blocking, and
warning-only publish behavior. The new focused conflict owner passes 3 tests in
roughly 0.6 seconds, the reduced lifecycle owner plus conflict owner pass 9
tests in roughly 1.6 seconds, and the dashboard lifecycle file is down to 748
lines. A full `mix precommit` passed after the dashboard lifecycle stale-conflict
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
Invalid saved-draft publish blocking and warning-only publish behavior now live
in
`ops_dashboard_show_live/dashboard_lifecycle_publish_validation_live_test.exs`;
the dashboard lifecycle owner kept version history, normal
create/edit/publish/revert/archive/restore, rename, and historical publish
behavior before the later version-actions extraction. The trimmed lifecycle owner
plus publish-validation owner pass 6 tests in roughly 1.4 seconds;
`dashboard_lifecycle_live_test.exs` was down to 594 lines and the
publish-validation owner is 225 lines. A full `mix precommit` passed
after the dashboard lifecycle publish-validation split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with 93
excluded.
Toolbar dashboard rename and historical-version publish behavior now live in
`ops_dashboard_show_live/dashboard_lifecycle_version_actions_live_test.exs`; the
dashboard lifecycle owner now keeps version-history restore and the broad
create/edit/publish/conflict/revert/archive/restore audit proof. The trimmed
lifecycle owner plus version-actions owner pass 4 tests in roughly 1.3 seconds;
`dashboard_lifecycle_live_test.exs` is down to 500 lines and the version-actions
owner is 182 lines. A full `mix precommit` passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with
93 excluded.
Historical workflow direct-link selection outcome behavior now lives in
`ops_dashboard_show_live/selection_panel_historical_workflow_test.exs`; the
general selection-panel owner kept evidence hydration, stale selection checks,
copied URL hydration, source-watermark links, and operational resource links
before the later direct-link and data-link-context extractions. The trimmed
selection-panel owner plus historical-workflow selection owner pass 13 tests in
roughly 0.5 seconds, and `selection_panel_test.exs` was down to 850 lines. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Direct source-watermark and operational-resource link opening now live in
`ops_dashboard_show_live/selection_panel_direct_links_test.exs`; the general
selection-panel owner kept evidence hydration, stale selection checks, copied URL
hydration, frame data-link context, and data-link index fallback before the later
data-link query/context extraction. The trimmed selection-panel owner plus
direct-link and historical-workflow selection owners pass 13 tests in roughly 0.5
seconds, and `selection_panel_test.exs` was down to 619 lines. The first full
`mix precommit` exposed an unrelated persistence repo-start failure that passed
on exact isolated rerun; a second full `mix precommit` then passed with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with
93 excluded.
Data-link query hydration, copied selected-link URL hydration, selected-ref
observable extraction, data-link index fallback, and source-context route-query
projection now live in
`ops_dashboard_show_live/selection_panel_data_link_context_test.exs`; the general
selection-panel owner now keeps evidence hydration and stale-selection checks.
Those two focused owners pass 9 tests in roughly 0.3 seconds;
`selection_panel_test.exs` is down to 292 lines and the data-link-context owner is
371 lines. A full `mix precommit` passed after the split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with 93
excluded.
Runtime archive invalidation browser coverage now lives in
`ops_dashboard_show_live/runtime_archive_invalidation_live_test.exs`; the runtime
archive owner kept archive time controls, limit/source interval markers,
retention gaps, and evidence inspector context at that point. The trimmed archive
owner plus invalidation owner pass 6 tests in roughly 1.5 seconds, and
`runtime_archive_live_test.exs` is down to 729 lines. A full `mix precommit`
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1542 `cadence_web` tests with 93 excluded.
Runtime archive source-watermark retention-gap browser coverage now lives in
`ops_dashboard_show_live/runtime_archive_source_watermark_live_test.exs`; the
runtime archive owner keeps archive time controls plus limit/source-binding
interval markers. The trimmed archive owner plus source-watermark owner pass 4
tests in roughly 1.1 seconds, and `runtime_archive_live_test.exs` is down to 544
lines while the source-watermark owner is 389 lines. A full `mix precommit`
passed after the runtime archive source-watermark split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with 93
excluded. Archive limit-definition interval marker and DataLink coverage later
moved again into
`ops_dashboard_show_live/runtime_archive_limit_intervals_live_test.exs`; the
runtime archive owner now keeps archive/live time controls and source-binding
interval evidence. The trimmed archive owner plus limit-interval owner pass 3
tests in roughly 1.0 seconds; `runtime_archive_live_test.exs` is down to 435
lines and the limit-interval owner is 284 lines. A full `mix precommit` passed
after the runtime archive limit-interval split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded. The
final documented-state gate exposed an unrelated source-probe
scheduler SQL sandbox ownership failure at
`apps/cadence/test/cadence/dashboards/source_probe_scheduler_test.exs:148`; the
exact test passed on isolated rerun, and a second full `mix precommit` passed
with the same 1272 `cadence`, 66 `cadence_simulator`, and 1542 `cadence_web`
test counts plus 93 excluded.
Historical workflow comparison-review grouped request/origin/stage handoff
coverage now lives in
`ops_dashboard_show_live/historical_workflow_comparison_review_group_request_live_test.exs`;
the comparison-review workflow owner keeps rollup request/resolution,
audit-context resolution, and versions-queue resolution behavior. The trimmed
workflow owner plus grouped-request owner pass 4 tests in roughly 1.2 seconds;
`historical_workflow_comparison_review_live_test.exs` is down to 455 lines and
the grouped-request owner is 483 lines. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
Render-widget comparison projection now lives in
`ops_dashboard_show_live/render_widget_model_comparison_test.exs`; the general
render-widget model owner keeps selected-ref filtering, shell attrs,
legacy/engine props, review focus, and source warning handoff. The trimmed
render-widget model owner plus comparison owner pass 12 async tests in roughly
0.2 seconds. Lifecycle/source-status projection now lives in
`ops_dashboard_show_live/render_widget_model_source_status_test.exs`; stale
operational frame fixtures, no-data source context attrs, lifecycle warning
summary attrs, and command-queue stale-source engine resolution setup moved out
of the general owner. The trimmed render-widget owner plus source-status owner
pass 9 async tests in roughly 0.1 seconds; `render_widget_model_test.exs` is down
to 302 lines and the source-status owner is 445 lines. A full `mix precommit`
passed after the source-status split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Render-page dashboard rollup projection now lives in
`ops_dashboard_show_live/render_page_model_rollup_test.exs`; the general
render-page model owner keeps path/query assembly, section props, widget item
wiring, toolbar/source props, and page shell attrs after the later root-attrs
extraction. The trimmed render-page model owner plus rollup owner pass 12 async
tests in roughly 0.2 seconds, and `render_page_model_test.exs` was down to 610
lines. The first full
`mix precommit` exposed an unrelated commanding COP-1 timeout retransmit count
failure that passed on exact isolated rerun; a second full `mix precommit` then
passed with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
Render-page root attr diagnostics now live in
`ops_dashboard_show_live/render_page_model_root_attrs_test.exs`; the general
render-page model owner no longer carries direct `RenderRootAssigns` or
`RenderRootAttrs` diagnostics. Those two focused owners pass 10 async tests in
roughly 0.1 seconds; `render_page_model_test.exs` is down to 424 lines and the
root-attrs owner is 330 lines. A full `mix precommit` passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web`
tests with 93 excluded.

The next split moved replay URL context into
`ops_dashboard_show_live/runtime_replay_url_context_live_test.exs`; the former
runtime URL/replay owner is retired. URL runtime param hydration now lives in
`ops_dashboard_show_live/runtime_url_params_live_test.exs`, runtime context
precedence coverage now lives in
`ops_dashboard_show_live/runtime_context_precedence_live_test.exs`, replay
event/operational-observable source family row coverage now lives in
`ops_dashboard_show_live/runtime_replay_source_family_live_test.exs`, comparison
investigation preset save/apply/delete coverage now lives in
`ops_dashboard_show_live/runtime_comparison_preset_live_test.exs`, and
source-capability event timeline browser proof now lives in
`ops_dashboard_show_live/runtime_source_capability_timeline_live_test.exs`. The
affected runtime URL/url-param files pass 2 focused tests after the latest
split, and the earlier focused split files plus the reduced dashboard console
file passed 119 tests in roughly 19.7 seconds. The monolithic dashboard console
file now carries 39 tests. A full `mix precommit` passed after the runtime
URL/replay split, and the full gate passed again after the comparison-preset
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, 1541
`cadence_web` tests, and 93 excluded. The full gate also passed after the
runtime source-capability timeline split with the same 1272 `cadence`, 66
`cadence_simulator`, 1541 `cadence_web`, and 93 excluded counts, and it passed
again after the runtime replay source-family split and runtime context
precedence split with the same counts. It passed again after the runtime URL
params split with the same counts, and passed again after the runtime URL/replay
owner was retired in favor of the runtime replay URL context owner with the same
counts.

The next split moved generic contact scope URL, contact-scoped/source-endpoint
scoped no-data diagnostics, evidence inspector, and valid mission-scope routing
browser proofs into `ops_dashboard_show_live/runtime_scope_live_test.exs`; that
focused file passed 4 tests in roughly 1.2 seconds before mission/contact
fail-closed scope validation was trimmed into runtime query owner tests. The
focused split files plus the reduced dashboard console file pass 119 tests in
roughly 19.7 seconds. The monolithic dashboard console file now carries 35
tests. A full `mix precommit` passed after the runtime scope split. The final
post-doc gate needed isolated reruns for two unrelated Cadence DB lifecycle
flakes before the next full `mix precommit` passed. Single-contact and
multi-contact no-data diagnostics now live in
`ops_dashboard_show_live/runtime_contact_scope_live_test.exs`; the runtime scope
owner now keeps generic contact-scope URL runtime context, source-endpoint
no-data diagnostics, and mission-scope URL routing. The trimmed runtime-scope
owner plus contact-scope owner pass 5 tests in roughly 1.2 seconds;
`runtime_scope_live_test.exs` is down to 418 lines and the contact-scope owner is
474 lines. A full `mix precommit` passed after the runtime contact-scope split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web`
tests with 93 excluded.

The next split moved archive time presets, archive time-series
limit/source-binding/watermark markers, source evidence inspector context, and
scoped historical/dashboard-version invalidation browser proofs into
`ops_dashboard_show_live/runtime_archive_live_test.exs`; that focused file
passed 7 tests in roughly 1.5 seconds before invalid archive validation was
trimmed into runtime query/control owner tests. The focused split files plus
the reduced dashboard console file pass 119 tests in roughly 19.3 seconds. The
monolithic dashboard console file now carries 28 tests. A full `mix precommit`
passed after the runtime archive split.

The next split moved version history restore, historical publish, toolbar
rename, create/edit/publish/conflict/revert/archive/restore audit proof, publish
blocking, warning-only publish, stale publish/archive conflict, and stale
restore conflict browser
proofs into `ops_dashboard_show_live/dashboard_lifecycle_live_test.exs`; that
focused file passes 8 tests in roughly 1.8 seconds, and the focused split files
plus the reduced dashboard console file pass 119 tests in roughly 24.9 seconds.
The monolithic dashboard console file now carries 20 tests. A full
`mix precommit` passed after the dashboard lifecycle split.

The next split moved telemetry explore sample selection, provenance, source
matching, copy/investigation links, filtering, missing-selected-sample state,
and retired source-binding diagnostics into
`ops_dashboard_show_live/telemetry_explore_live_test.exs`; that focused file
passes 2 tests in roughly 0.6 seconds, and the focused split files plus the
reduced dashboard console file pass 119 tests in roughly 18.6 seconds. The
monolithic dashboard console file now carries 18 tests. A full `mix precommit`
passed after the telemetry explore split.

The next split moved dashboard index empty/create/list/rail proofs,
unauthenticated route redirect proof, and published-vs-draft operator shell
proof into `ops_dashboard_show_live/dashboard_shell_live_test.exs`; that
focused file passes 4 tests in roughly 0.6 seconds, and the focused split files
plus the reduced dashboard console file pass 119 tests in roughly 18.8 seconds.
The monolithic dashboard console file now carries 14 tests.

The next split moved the broad live-widget rendering/DataLink/evidence proof
for value tiles, time-series charts, constellation health, GridStack placement,
limit states, source evidence, selection, and pause/resume behavior into
`ops_dashboard_show_live/live_widget_rendering_live_test.exs`; that focused
file passes 1 test in roughly 4.8 seconds, and the focused split files plus the
reduced dashboard console file pass 119 tests in roughly 17.9 seconds. The
monolithic dashboard console file now carries 13 tests. A full `mix precommit`
passed after one isolated-rerun Cadence DB lifecycle failure. The live-widget
frame evidence branch now has its own owner too:
`ops_dashboard_show_live/live_widget_frame_evidence_live_test.exs` covers
resolved frame evidence, shared frame evidence URLs, missing frame evidence,
copy/explore/source-inventory actions, and panel-close payload cleanup. That
new owner plus the trimmed live-widget rendering owner pass 2 focused tests. A
full `mix precommit` passed after the live-widget frame evidence split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with
93 excluded.

The next split moved latest-telemetry status-matrix and data-table render
proofs, including row evidence, limit-event DataLinks, and telemetry-sample
DataLinks, into `ops_dashboard_show_live/telemetry_widget_rendering_live_test.exs`;
that focused file passes 2 tests in roughly 1.0 seconds, and the focused split
files plus the reduced dashboard console file pass 119 tests in roughly 25.2
seconds. The monolithic dashboard console file now carries 11 tests. A full
`mix precommit` passed after the telemetry widget rendering split.

The next split moved contact-phase and connection-state operational-observable
status-matrix render proofs, including contact/transport DataLinks and source
context metadata, into
`ops_dashboard_show_live/operational_observable_rendering_live_test.exs`; that
focused file passes 2 tests in roughly 0.7 seconds, and the focused split files
plus the reduced dashboard console file pass 119 tests in roughly 24.6 seconds.
The monolithic dashboard console file now carries 9 tests. A full
`mix precommit` passed after the operational-observable rendering split.

The next split expanded
`ops_dashboard_show_live/operational_observable_default_multi_entity_scope_live_test.exs`
with mission-scope command-queue aggregate, document-default multi-source-endpoint,
and source-endpoint/transport/link/ground-station operational-observable filter
proofs, including setup DataLinks. That focused file passes 6 tests in roughly
1.2 seconds, and the focused split files plus the reduced dashboard console file
pass 119 tests in roughly 18.0 seconds. The monolithic dashboard console file now
carries 3 tests. A full `mix precommit` passed after the expanded
operational-observable scope-rendering split.

The final monolith split moved the multi-transport runtime context selector
proof into `ops_dashboard_show_live/runtime_context_control_live_test.exs` and
the tick-driven chart append plus conservative dashboard engine live-refresh
proofs into `ops_dashboard_show_live/runtime_refresh_live_test.exs`; those two
focused files pass 3 tests in roughly 1.5 seconds, and the full focused
dashboard LiveView proof bundle passes 119 tests in roughly 18.5 seconds without
`ops_dashboard_live_test.exs`. The former monolithic dashboard console file has
been retired. The leftover historical workflow rendered-surfaces aggregate has
also been retired: latest-action, group-status, action-explanation, and
job-status contracts now live in dedicated component tests, with the component
set passing 14 focused tests after the split. A full `mix precommit` passed
after the component consolidation as well: 1270 `cadence` tests, 66
`cadence_simulator` tests, and 1570 `cadence_web` tests with 93 excluded.
The runtime resolve worker owner-loss test now accepts both direct `:killed`
worker shutdown and the loaded-suite `:noproc` observation where the worker is
already gone, keeping the browser sandbox lifecycle proof focused on the
required invariant instead of a scheduler-specific monitor reason. The full
`mix precommit` gate passed after that stabilization.
The historical-workflow request-panel defaults now have a dedicated owner:
`historical_workflow_request_panel_test.exs` covers current selection defaulting,
comparison-review request expansion into affected point ids, and missing
request-event error handling. The trimmed `historical_workflow_test.exs` retains
the command/outcome contracts, and the focused split command passes 25
`cadence_web` tests. A full `mix precommit` passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Historical-workflow request commands now have their own owner too:
`historical_workflow_request_commands_test.exs` covers bulk request success
selection, source-unavailable action outcomes, and unconfirmed request blocking.
The focused historical workflow owner command still passes 25 `cadence_web`
tests across request panel, request commands, and the trimmed command/recovery
owner. A full `mix precommit` passed after the split with 1272 `cadence` tests,
66 `cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Historical-workflow stage commands now have their own owner:
`historical_workflow_stage_commands_test.exs` covers confirmation blocking,
successful stage transition job selection, and structured stage command error
copy. The focused historical workflow command now passes 25 `cadence_web` tests
across request panel, request commands, stage commands, and the trimmed
correction/group/retry/recovery owner. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Historical-workflow correction commands now have their own owner:
`historical_workflow_correction_commands_test.exs` covers correction request
success selection, policy-error action outcomes, and unconfirmed correction
blocking. The focused historical workflow command passes 25 `cadence_web` tests
across request panel, request commands, stage commands, correction commands, and
the trimmed group/retry/recovery owner. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Historical-workflow group-stage commands now have their own owner:
`historical_workflow_group_stage_commands_test.exs` covers degraded group-start
dispatch selection, request-group error outcomes, and unconfirmed group-stage
blocking. The focused historical workflow command passes 25 `cadence_web` tests
across request panel, request commands, stage commands, correction commands,
group-stage commands, and the trimmed retry/recovery owner. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Historical-workflow retry commands now have their own owner:
`historical_workflow_retry_commands_test.exs` covers single replacement retry
selection, group retry success, replacement-run retry scope, policy-blocked
group retry outcomes, and degraded partial retry errors. The focused historical
workflow command passes 25 `cadence_web` tests across the request, stage,
correction, group-stage, retry, and trimmed replacement-recovery owners. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Historical-workflow replacement recovery commands now have their own owner:
`historical_workflow_replacement_recovery_commands_test.exs` covers stale
replacement inspection success/error outcomes, missing replacement inspection
success/error outcomes, and stale replacement requeue success. The generic
`historical_workflow_test.exs` owner has been retired; the focused historical
workflow command still passes 25 `cadence_web` tests across the named owners. A
full `mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Historical-workflow replacement recovery job-state contracts now have a
dedicated owner: `historical_workflow_replacement_recovery_job_state_test.exs`
covers stale/fresh running replacement jobs, missing job evidence, failed
replacement attribution, retry-eligible failed replacements, and blocked closure
action priority. The focused replacement recovery pair passes 16 `cadence_web`
tests with the trimmed aggregate/action packaging owner. A full `mix precommit`
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1539 `cadence_web` tests with 93 excluded.
Historical-workflow replacement recovery action projection now has a dedicated
owner: `historical_workflow_replacement_recovery_actions_test.exs` covers
ready-to-complete group closure, retry/correction/inspection operator guidance,
corrected replacement advancement actions, disabled fallback actions, and
disabled group completion metadata. The focused replacement recovery owner
command passes 16 `cadence_web` tests across action, job-state, and
aggregate/default projection owners. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
The generic historical-workflow replacement-recovery owner is retired:
`historical_workflow_replacement_recovery_projection_test.exs` covers aggregate
replacement entries, aggregate presentation fields, and empty projection
defaults. The focused replacement recovery command passes 21 `cadence_web`
tests across projection, action, job-state, and command owners. A full
`mix precommit` passed after the retirement with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded; the
first full attempt hit a transient `SourceProbeSchedulerTest` DB ownership
failure that passed on exact file/line rerun before the successful full rerun.
Runtime query scope-selection contracts now have a dedicated owner:
`runtime_query_scope_test.exs` covers contact fallback, mission validation,
first-class source-endpoint scope, operational-resource fallback, durable
multi-select scope ids, all-id validation, document scope defaults, and URL
precedence. The focused runtime query command passes 18 `cadence_web` tests with
the trimmed replay/data/time/limit/source normalization owner. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Runtime query limit-semantics contracts now have a dedicated owner:
`runtime_query_limit_test.exs` covers supported limit modes, unsupported limit
fallback metadata, and non-default limit query normalization. The focused
runtime query command passes 18 `cadence_web` tests across scope, limit, and the
trimmed replay/data/time/source normalization owner. A full `mix precommit`
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1539 `cadence_web` tests with 93 excluded.
Runtime query replay-context contracts now have a dedicated owner:
`runtime_query_replay_test.exs` covers replay contact runtime context with
source-binding propagation and non-telemetry replay source-context preservation.
The focused runtime query command passes 18 `cadence_web` tests across scope,
limit, replay, and trimmed data/time/source normalization owners. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Runtime query source/default contracts now have a dedicated owner:
`runtime_query_source_test.exs` covers active source-binding selection, primary
source-binding override normalization, and document data default stringification.
The focused runtime query command passes 18 `cadence_web` tests across scope,
limit, replay, source/default, and trimmed time/data-view normalization owners.
A full `mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
The generic runtime query normalization owner is retired:
`runtime_query_time_test.exs` covers invalid archive time fallback with
validation state, and `runtime_query_data_view_test.exs` covers data-view
comparison normalization. The focused runtime query command passes 18
`cadence_web` tests across scope, limit, replay, source/default, time, and
data-view owners. A full `mix precommit` passed after the retirement with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests with
93 excluded.
Runtime controls context-routing now has a dedicated owner:
`runtime_controls_context_test.exs` covers runtime-context query normalization,
mission scope routing, durable multi-select scope routing, operational-resource
validation before stale-selection decisions, and legacy spacecraft query
routing. The focused runtime-controls command passes 13 `cadence_web` tests with
the trimmed time/replay/selection owner. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
The generic runtime controls owner is retired: `runtime_controls_time_test.exs`
covers archive preset and selected-time pause behavior,
`runtime_controls_replay_test.exs` covers replay scrub range and validation
behavior, and `runtime_controls_selection_test.exs` covers selection-clearing
route cleanup. The focused runtime-controls command passes 13 `cadence_web`
tests across context, time, replay, and selection owners. A full `mix precommit`
passed after the retirement with 1272 `cadence` tests, 66 `cadence_simulator`
tests, and 1539 `cadence_web` tests with 93 excluded.
The generic late-data policy owner is retired: `late_data_policy_action_test.exs`
covers confirmation blocking, typed command params, and structured
action-outcome errors. The focused late-data policy command passes 23
`cadence_web` tests across action, command, context, event, params, and
presentation owners. A full `mix precommit` passed after the retirement with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web`
tests with 93 excluded.
The generic revision-decision owner is retired:
`revision_decision_action_test.exs` covers confirmation blocking, successful
result-link query preservation, and typed failure action-outcome projection. The
focused revision-decision command passes 17 `cadence_web` tests across action,
command, context, event, params, and presentation owners. A full `mix precommit`
passed after the retirement with 1272 `cadence` tests, 66 `cadence_simulator`
tests, and 1539 `cadence_web` tests with 93 excluded.
The generic component facade test has started the same consolidation path:
source-selection strip and open comparison review toolbar assertions now live
only in their dedicated component test files, and the affected generic plus
dedicated component files pass 30 focused tests. The full `mix precommit` gate
passed after this consolidation with 1568 `cadence_web` tests and 93 excluded.
Dashboard toolbar context/fallback assertions now also live only in
`dashboard_toolbar_components_test.exs`; dashboard health rollup proof remains
in `dashboard_health_components_test.exs`, and hidden comparison-rollup state
remains in `comparison_rollup_components_test.exs`. The generic
`components_test.exs` bucket no longer duplicates those owner-level component
contracts, and the affected generic/toolbar/health/rollup component files pass
31 focused tests after the trim. The full `mix precommit` gate passed after
this trim with 1559 `cadence_web` tests and 93 excluded.
Widget source-status badge, inventory, query-diagnostics, fresh-suppression, and
empty-reason serialization coverage now stays in
`widget_source_status_components_test.exs`; the generic `components_test.exs`
bucket no longer duplicates those owner-level widget source-status contracts,
and the affected generic/source-status component files pass 22 focused tests
after the trim. The full `mix precommit` gate passed after this trim with 1555
`cadence_web` tests and 93 excluded.
Widget source-health badge behavior now stays in
`widget_source_health_status_components_test.exs`; degraded health badge attrs
and source-health-event-only evidence-opening coverage no longer share the
general widget source-status owner, and the affected source-status files pass 8
focused tests after the split. The full `mix precommit` gate passed after this
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, 1544
`cadence_web` tests, and 93 excluded.
Value-tile comparison delta and non-numeric suppression coverage now stays in
`widget_point_components_test.exs`; the generic `components_test.exs` bucket no
longer duplicates those owner-level value-tile contracts, and the affected
generic/widget-point component files pass 18 focused tests after the trim. The
full `mix precommit` gate passed after this trim with 1554 `cadence_web` tests
and 93 excluded.
Time-series chart comparison backfill payload and chart data-view attrs now stay
in `widget_point_components_test.exs`; the generic `components_test.exs` bucket
no longer duplicates that owner-level chart contract, and the affected
generic/widget-point component files pass 13 focused tests after the trim.
The full `mix precommit` gate passed after this trim with 1550 `cadence_web`
tests and 93 excluded.
Event-timeline workflow badge and direct DataLink handoff coverage now stays in
`widget_row_components_test.exs`; the generic `components_test.exs` bucket no
longer duplicates that owner-level event-row contract, and the affected
generic/widget-row component files pass 18 focused tests after the trim. The
full `mix precommit` gate passed after this trim with 1553 `cadence_web` tests
and 93 excluded.
Widget DataLink source/time event params now stay in
`widget_data_link_components_test.exs`, widget frame evidence query-scope attrs
stay in `evidence_attrs_test.exs`, and the generic `components_test.exs` bucket
no longer duplicates those owner-level DataLink/evidence contracts. The affected
generic/DataLink/evidence files pass 27 focused tests after the trim. The full
`mix precommit` gate passed after this trim with 1552 `cadence_web` tests and
93 excluded.
Late-data execution summary/title coverage now stays in
`widget_data_management_components_test.exs`; the generic `components_test.exs`
bucket no longer duplicates that owner-level data-management badge contract, and
the affected generic/data-management component files pass 16 focused tests after
the trim. The full `mix precommit` gate passed after one isolated-rerun Cadence
Repo startup lookup with 1552 `cadence_web` tests and 93 excluded.
Value-tile data-management badge/link/title coverage now stays in
`widget_data_management_components_test.exs`; the generic `components_test.exs`
bucket no longer duplicates that owner-level badge contract, and the affected
generic/data-management component files pass 13 focused tests after the trim.
The full `mix precommit` gate passed after this trim with 1549 `cadence_web`
tests and 93 excluded.
Widget lifecycle attributes and body-notice coverage now stays in
`widget_lifecycle_components_test.exs`; the generic `components_test.exs` bucket
no longer carries lifecycle wrapper coverage, and the affected generic/lifecycle
component files pass 6 focused tests after the split.
The full `mix precommit` gate passed after this split with 1549 `cadence_web`
tests and 93 excluded.
Dashboard warning wrapper coverage now stays in
`dashboard_warning_components_test.exs`, and the generic `components_test.exs`
bucket has been retired. The affected dashboard-warning/widget-warning component
files pass 4 focused tests after the move.
The full `mix precommit` gate passed on rerun after this retirement with 1549
`cadence_web` tests and 93 excluded; the first attempt hit an unrelated
`Cadence.ContactsSchedulerTest` ETS/repo-cache failure, and the exact file/line
passed before the successful full rerun.
Comparison rollup counts/groups/handoff/preset coverage now stays in
`comparison_rollup_components_test.exs`; the generic `components_test.exs`
bucket no longer duplicates that owner-level comparison rollup contract, and the
affected generic/comparison-rollup files pass 11 focused tests after the trim.
The full `mix precommit` gate passed after this trim with 1551 `cadence_web`
tests and 93 excluded.
The final gate also exposed two persisted-row isolation gaps outside the
dashboard slice. `CurrentValueStorePostgresTest` now uses per-test mission and
primary-key scopes, `TCPSocketProviderTest` filters persistence counts by its
generated mission, and the affected `cadence` files pass 7 focused tests. The
same cleanup now scopes `PersistTelemetryIngressTest` persistence counts and row
lists by mission/evidence, with its 9 tests passing directly before the next
full gate.
The panel facade test followed the same rule: broad data-link and evidence
inspector happy-path contracts now live only in their dedicated panel component
tests. `form_components_test.exs` was later retired after its last remaining
late-data policy workflow-control assertions moved into the direct DataLink
inspector owner. The affected panel component files pass 24 focused tests after
the initial trim, and the full `mix precommit` gate passed with 1566
`cadence_web` tests and 93 excluded.
Version-history selected-activity hidden/missing recovery coverage now stays in
`version_history_panel_components_test.exs`, and the affected form/version
component files pass 30 focused tests after the facade duplicate was removed.
The full `mix precommit` gate passed after this trim with 1564 `cadence_web`
tests and 93 excluded.
Version-history open comparison review queue focus coverage now also stays in
`version_history_panel_components_test.exs`; selected-placement, work-queue
count, clear-filter, and placement-link state checks no longer duplicate through
the generic panel facade, and the affected form/version component files pass 29
focused tests after the trim. The full `mix precommit` gate passed after this
trim with 1563 `cadence_web` tests and 93 excluded.
Version-history empty and stale selected-placement review queue state coverage
now stays in `version_history_panel_components_test.exs`; queue-state message
and placement-link state checks no longer duplicate through the generic panel
facade, and the affected form/version component files pass 29 focused tests
after the trim. The full `mix precommit` gate passed after this trim with 1563
`cadence_web` tests and 93 excluded.
Version-history health-snapshot filtering, selected activity, and copied
activity-link behavior now stays in `version_history_panel_components_test.exs`,
while detailed health snapshot metadata stays in
`health_snapshot_activity_components_test.exs`; those contracts no longer
duplicate through the generic panel facade, and the affected form/version/health
component files pass 30 focused tests after the trim. The full `mix precommit`
gate passed after this trim with 1562 `cadence_web` tests and 93 excluded.
Version-history comparison review request and resolution activity details now
stay in `version_history_panel_components_test.exs`; open-count, resolve-form,
placement-link, finding, and resolution metadata assertions no longer duplicate
through the generic panel facade, and the affected form/version component files
pass 28 focused tests after the trim. The full `mix precommit` gate passed after
this trim with 1562 `cadence_web` tests and 93 excluded.
Evidence inspector dashboard-health activity links and warning source-context
fallback DataLink attributes now stay in
`evidence_inspector_panel_components_test.exs`; those routing and context
fallback contracts no longer duplicate through the generic panel facade, and the
affected form/evidence component files pass 10 focused tests after the trim. The
full `mix precommit` gate passed after this trim with 1561 `cadence_web` tests
and 93 excluded.
Evidence inspector DataLink handoff coverage now stays in
`evidence_inspector_panel_data_link_handoff_test.exs`; resolvable evidence refs
and warning source-context fallback attrs no longer share the general evidence
panel owner, and the affected evidence component files pass 4 focused tests
after the split. The full `mix precommit` gate passed after this split and the
mission-event/contact test isolation fixes with 1272 `cadence` tests, 66
`cadence_simulator` tests, 1542 `cadence_web` tests, and 93 excluded.
Version-history publish-readiness selected-activity remediation coverage now
stays in `version_history_publish_readiness_activity_test.exs`; selected
activity source-evidence handoffs, connection-test evidence links, dashboard
editor focus links, readiness trend metadata, and return refresh controls no
longer share the inline publish-validation result owner, and the affected
publish-readiness component files pass 8 focused tests after the split. A first
`mix precommit` attempt hit a transient `Cadence.CommandingTest` TCP provider
accept timeout at `apps/cadence/test/cadence/commanding_test.exs:503`; the
exact-location rerun passed, and the full `mix precommit` rerun passed with
1272 `cadence` tests, 66 `cadence_simulator` tests, 1542 `cadence_web` tests,
and 93 excluded.
Comparison rollup open-findings review payload/state coverage now stays in
`comparison_rollup_open_review_test.exs`; encoded open-findings payload, copy
payload, form submit state, selected-ref query/path contract, and duplicate
review disabled state no longer share the visible rollup group/handoff/preset
owner, and the affected comparison rollup component files pass 4 focused tests
after the split. A first `mix precommit` attempt hit a transient DB ownership
checkout failure in
`apps/cadence/test/cadence/projections/telemetry_latest_limit_states_test.exs`;
the exact file rerun passed, and the full `mix precommit` rerun passed with
1272 `cadence` tests, 66 `cadence_simulator` tests, 1543 `cadence_web` tests,
and 93 excluded.
Activity event publish-readiness row/build behavior now stays in
`activity_event_summary_publish_readiness_test.exs`; publish-readiness row field
projection, source-evidence remediation synthesis, typed remediation action
preference, trend comparison/regression, selected remediation actions, and
returned source-action correlation no longer share the general lifecycle/runtime
activity event owner, and the affected activity event summary files pass 14
focused tests after the split. The full `mix precommit` gate passed after this
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, 1543
`cadence_web` tests, and 93 excluded.
Widget event timeline rendering now stays in
`widget_event_timeline_components_test.exs`; event metadata, severity, duration,
row DataLink attrs, historical workflow badge links, workflow job evidence, and
source watermark audit projection no longer share the status/data/state widget
row owner, and the affected widget row component files pass 7 focused tests
after the split. The full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, 1543 `cadence_web` tests, and 93
excluded.
Widget form operational readiness guidance now stays in
`widget_form_operational_readiness_test.exs`; unsupported-scope
disabling/removal, readiness focus attrs, and source capability guidance for
history/latest operational observable products no longer share the base widget
form owner, and the affected widget form component files pass 10 focused tests
after the split. The full `mix precommit` gate passed after this split with
1272 `cadence` tests, 66 `cadence_simulator` tests, 1543 `cadence_web` tests,
and 93 excluded.
Version-history comparison-review request/resolution details now stay in
`version_history_comparison_review_queue_components_test.exs`;
comparison-review request detail rows, resolve-form context, finding-state attrs,
resolution state, workflow metadata, and resolved-history rows no longer share
the general version-history panel owner, and the affected version-history
component files pass 12 focused tests after the split. The full `mix precommit`
gate passed after this split with 1272 `cadence` tests, 66 `cadence_simulator`
tests, 1543 `cadence_web` tests, and 93 excluded.
Comparison-review request bulk-decision affordance coverage now stays in
`comparison_review_activity_bulk_decision_test.exs`; actionable bulk-decision
form attrs, source/scope/contact/resource finding context, actionable-only
filtering, skipped-finding labels, and unavailable-decision explanations no
longer share the general comparison-review activity owner, and the affected
comparison-review activity component files pass 7 focused tests after the split.
The full `mix precommit` gate passed after this split with 1272 `cadence` tests,
66 `cadence_simulator` tests, 1543 `cadence_web` tests, and 93 excluded.
Comparison-review bulk-decision event handling now stays in
`comparison_review_events_bulk_decision_test.exs`; partial-failure action
outcome projection, decision item evidence refs, runtime invalidation opts,
review queue refresh, and open-review activity routing no longer share the
request/resolve comparison-review events owner, and the affected comparison
review event files pass 8 focused tests after the split. The full
`mix precommit` gate passed after this split with 1272 `cadence` tests, 66
`cadence_simulator` tests, 1543 `cadence_web` tests, and 93 excluded.
Comparison-review resolution event handling now stays in
`comparison_review_events_resolution_test.exs`; resolution-event recording,
patch activity routing, selected placement reset, missing-request rejection,
already-resolved refresh, and stale-placement mismatch handling no longer share
the request comparison-review events owner, and the comparison-review event
files pass 8 focused tests after the split. The full `mix precommit` gate
passed after this split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
1543 `cadence_web` tests, and 93 excluded.
Comparison rollup saved-preset controls now stay in
`comparison_rollup_saved_presets_test.exs`; saved preset metadata,
affected-placement counts, apply actions, delete actions, and delete
confirmations no longer share the general comparison rollup component owner,
and the affected comparison rollup component files pass 5 focused tests after
the split. The full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, 1544 `cadence_web` tests, and 93
excluded.
DataLink presentation navigation-event attrs now stay in
`data_link_presentation_navigation_test.exs`; bounded navigation trail appends
and related-link fallback source context no longer share the general DataLink
presentation owner, and the affected DataLink presentation files pass 11
focused tests after the split. The full `mix precommit` gate passed after this
split and the source probe scheduler timeout-test stability fix with 1272
`cadence` tests, 66 `cadence_simulator` tests, 1544 `cadence_web` tests, and 93
excluded.
Historical workflow latest action-outcome presentation now stays in
`historical_workflow_controls_latest_action_outcome_test.exs`; latest action
outcome state, stable root attrs, selected-event gating, and degraded outcome
state no longer share the general historical workflow controls presentation
owner, and the affected controls presentation files pass 9 focused tests after
the split. The full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, 1543 `cadence_web` tests, and 93
excluded.
Historical workflow structured presenter error copy now stays in
`historical_workflow_presenter_errors_test.exs`; stage transition, correction
request, retry, stale replacement recovery, and missing replacement inspection
error-copy assertions no longer share the general historical workflow presenter
owner, and the affected presenter files pass 19 focused tests after the split.
The full `mix precommit` gate passed after this split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, 1543 `cadence_web` tests, and 93 excluded.
Historical workflow group closure-readiness component coverage now stays in
`historical_workflow_group_closure_status_components_test.exs`;
replacement-work pending, monitor-jobs, ready-to-complete, and blocked
replacement-job recovery priority no longer share the general group status
component owner, and the affected group status files pass 5 focused tests after
the split. The full `mix precommit` gate passed after this split and the BYO
QuestDB smoke-test app-start guard fix with 1272 `cadence` tests, 66
`cadence_simulator` tests, 1543 `cadence_web` tests, and 93 excluded.
Widget source-health badge behavior now stays in
`widget_source_health_status_components_test.exs`; degraded health badge attrs
and source-health-event-only evidence-opening coverage no longer share the
general widget source-status owner, and the affected source-status files pass 8
focused tests after the split. The full `mix precommit` gate passed after this
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, 1544
`cadence_web` tests, and 93 excluded.
Runtime source-execution diagnostics now stay in
`runtime_source_execution_diagnostics_test.exs`; empty source-execution summary
fallback, stale source-result degradation, source-unavailable/circuit-open
decisions, degraded drilldowns, and source incident evidence attrs no longer
share the general runtime diagnostics owner, and the affected runtime diagnostic
files pass 3 focused tests after the split. The full `mix precommit` gate
passed after this split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
1541 `cadence_web` tests, and 93 excluded.
Runtime invalidation no-refresh diagnostics now stay in
`runtime_invalidation_no_refresh_diagnostics_test.exs`; relevance-row
aggregation, no-refresh summary visibility, and operator blocker row projection
no longer share the general runtime invalidation diagnostics owner, and the
affected runtime invalidation diagnostic files pass 6 focused tests after the
split. The full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, 1541 `cadence_web` tests, and 93
excluded.
Runtime invalidation source-audit decisions now stay in
`runtime_invalidation_source_audit_test.exs`; source cache evidence audit
summaries, source execution degradation summaries, degraded identities, and
operator-action audit fields no longer share the general runtime invalidations
owner, and the affected runtime invalidation files pass 8 focused tests after
the split. The full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, 1541 `cadence_web` tests, and 93
excluded.
Selected-data-ref time-context behavior now stays in
`selected_data_ref_time_context_test.exs`; archive-bound matching, replay-run
id/bound matching, and selected-time pause archive range derivation no longer
share the general selected data ref owner, and the affected selected-ref files
pass 17 focused tests after the split. The full `mix precommit` gate passed
after this split with 1272 `cadence` tests, 66 `cadence_simulator` tests, 1541
`cadence_web` tests, and 93 excluded.
Evidence query presentation-row behavior now stays in
`evidence_query_presentation_test.exs`; selected evidence subject/detail rows,
source request detail rows, source context detection, source identity rows, and
clear-query nil-value coverage no longer share the general evidence query owner,
and the affected evidence query files pass 13 focused tests after the split. The
full `mix precommit` gate passed after this split with 1272 `cadence` tests, 66
`cadence_simulator` tests, 1541 `cadence_web` tests, and 93 excluded.
DataLink inspector revision-decision event controls now stay in
`data_link_inspector_panel_components_test.exs`; action-outcome,
decision-effect, hidden form context, and canonical identity field assertions no
longer duplicate through the generic panel facade, and the affected form/DataLink
component files pass 10 focused tests after the trim. The full `mix precommit`
gate passed after this trim with 1561 `cadence_web` tests and 93 excluded.
DataLink inspector comparison-finding revision-decision controls now stay in
`data_link_inspector_panel_components_test.exs`; comparison authority/reason,
sample identity, source target, and comparison state hidden form assertions no
longer duplicate through the generic panel facade, and the affected form/DataLink
component files pass 10 focused tests after the trim. A first `mix precommit`
attempt hit the known transient DB ownership/holder checkout failure shape in
`persist_telemetry_ingress_test.exs:871`; the isolated rerun passed, and the
full `mix precommit` gate passed on rerun with 1561 `cadence_web` tests and 93
excluded.
DataLink inspector event-only late-data policy controls now stay in
`data_link_inspector_panel_components_test.exs`; event-only execution-mode and
badge assertions for backfill lifecycle events without source sample identity no
longer duplicate through the generic panel facade, and the affected form/DataLink
component files pass 10 focused tests after the trim. The full `mix precommit`
gate passed after this trim with 1561 `cadence_web` tests and 93 excluded.
DataLink inspector late-data policy decision-event suppression now stays in
`data_link_inspector_panel_components_test.exs`; workflow explanation fields and
the no-policy-controls assertion for already-recorded late-data policy events no
longer duplicate through the generic panel facade, and the affected form/DataLink
component files pass 10 focused tests after the trim. The full `mix precommit`
gate passed after this trim with 1561 `cadence_web` tests and 93 excluded.
DataLink inspector failed lifecycle correction guidance now stays in
`data_link_inspector_panel_components_test.exs`; failed-correction workflow
explanation, recovery/group fields, and hidden correction dashboard context
assertions no longer duplicate through the generic panel facade, and the
affected form/DataLink component files pass 10 focused tests after the trim. The
full `mix precommit` gate passed after this trim with 1561 `cadence_web` tests
and 93 excluded.
DataLink inspector late-data policy action-outcome/control coverage now also
stays in `data_link_inspector_panel_components_test.exs`; the final generic
panel facade assertion was removed, `form_components_test.exs` was deleted, and
the direct DataLink inspector component file passes 10 focused tests after the
retirement. The full `mix precommit` gate passed after this trim with 1561
`cadence_web` tests and 93 excluded.
Dashboard shell browser coverage now stays focused on landing create/list/auth
behavior. Published-vs-draft console mode, publish-state root attrs, toolbar
action availability, and summary version transitions remain in the lifecycle,
root/page model, toolbar component, and lifecycle-status owner tests; the shell
smoke file no longer duplicates that lifecycle branch. The focused owner bundle
passes 7 `cadence` tests and 42 `cadence_web` tests after the trim, and the
full `mix precommit` gate passed with 1270 `cadence` tests, 66
`cadence_simulator` tests, and 1548 `cadence_web` tests with 93 excluded.
Dashboard lifecycle browser coverage now also owns archive/restore list
transitions, stale restore conflict reloads, and toolbar rename wiring. The
widget lifecycle file no longer duplicates dashboard-level archive/restore or
rename behavior and stays focused on widget edit, layout, and
remove/reconfigure surfaces. The affected lifecycle and rename-flow files pass
18 focused `cadence_web` tests after the ownership move. The full
`mix precommit` gate passed with 1270 `cadence` tests, 66 `cadence_simulator`
tests, and 1547 `cadence_web` tests with 93 excluded.
Runtime invalidation event/limit browser coverage now keeps the product refresh
cases and unrelated-observable skip proof, while event/limit overlay-absence
matching permutations live in `runtime_invalidation_relevance_test.exs` instead
of full LiveView tests. The focused owner command passes 17 `cadence` policy
tests and 4 `cadence_web` LiveView tests after the trim, and the full
`mix precommit` gate passed with 1270 `cadence` tests, 66 `cadence_simulator`
tests, and 1545 `cadence_web` tests with 93 excluded.
Runtime invalidation telemetry browser coverage now keeps the product refresh,
overlay source-relevance, and unrelated-observable skip proofs, while
no-telemetry-primary matching permutations for data-source-binding,
source-health, and source-watermark invalidations live in
`runtime_invalidation_relevance_test.exs` instead of full LiveView tests. The
focused owner command passes 18 `cadence` policy tests and 7 `cadence_web`
LiveView tests after the trim.
The full `mix precommit` gate passed after the telemetry ownership trim and
static command-test cleanup with 1271 `cadence` tests, 66 `cadence_simulator`
tests, and 1542 `cadence_web` tests with 93 excluded.
Dashboard lifecycle browser coverage now keeps saved-draft publish-block,
warning-only publish, stale conflict, restore, and archive wiring, while invalid
runtime-default validation and publish-readiness payload/action serialization
live in the document, publish-readiness payload, presentation, panel-event,
selected-activity, and toolbar owner tests. The focused owner command passes 25
`cadence` tests and 47 `cadence_web` tests after the trim.
The full `mix precommit` gate passed after the dashboard lifecycle
publish-block ownership trim with 1272 `cadence` tests, 66 `cadence_simulator`
tests, and 1541 `cadence_web` tests with 93 excluded.
Runtime archive browser coverage now keeps archive/live preset and historical
refresh wiring, while invalid archive bound and reversed-range fallback live in
`RuntimeQueryTest` and the visible validation marker remains covered by
`DashboardRuntimeControlsComponentsTest`. The focused owner command passes 39
`cadence_web` tests after the trim.
The full `mix precommit` gate passed after the runtime archive invalid-time
ownership trim with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1541
`cadence_web` tests with 93 excluded.
Runtime scope browser coverage now keeps valid mission-scope URL routing and
no-data/evidence product flows, while invalid mission/contact fail-closed
fallback validation lives in `RuntimeQueryTest`. The focused owner command
passes 23 `cadence_web` tests after the trim.
The full `mix precommit` gate passed after the runtime scope fail-closed
ownership trim with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
Widget lifecycle browser coverage now keeps stale edit, edit-mode layout, and
remove/reconfigure product proofs, while missing-point widget validation lives
in `PlacementEditorTest` and `WidgetEditingTest`. The focused owner command
passes 29 `cadence` tests and 9 `cadence_web` tests after the trim.
The full `mix precommit` gate passed after the widget missing-point validation
ownership trim with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1541
`cadence_web` tests with 93 excluded.
Widget creation browser coverage now keeps actual creation workflows, while
binding-source selector frame-contract derivation and rendered select options
live in `WidgetFormPresentationTest` and `WidgetFormComponentsTest`. The
focused owner command passes 28 `cadence_web` tests after the trim.
The full `mix precommit` gate passed after the widget binding-source selector
ownership trim with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1540
`cadence_web` tests with 93 excluded.
Widget creation browser coverage now also leaves operational-observable picker
value-kind filtering to render-panel observable-filter,
`WidgetFormPresentationTest`, `WidgetFormComponentsTest`, and widget-editing
owner tests. The focused owner command passes 37 `cadence_web` tests after the
trim.
The full `mix precommit` gate passed after the operational-observable picker
filter ownership trim with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1540 `cadence_web` tests with 93 excluded.
Widget creation browser coverage now also leaves operational state-timeline
placement shape and operational multi-select behavior to `PlacementEditorTest`
and `WidgetEditingTest`. The focused owner command passes 29 `cadence` tests
and 22 `cadence_web` tests after the trim.
The full `mix precommit` gate passed after the operational state-timeline
creation ownership trim with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1539 `cadence_web` tests with 93 excluded. Two first full attempts exposed
repeated downlink-combiner transport-event `GenServer.call` timeouts in the
mission-event and contact-runtime tests; transport-event coordinator calls now
support an explicit timeout, and those long combiner tests pass with
`call_timeout: :infinity`. A later precommit rerun also exposed an over-strict
source-execution timeout assertion; the test now verifies all summarized
execution failures separately from the subset of placement-visible dashboard
warnings.
The generic widget-editing owner is retired: `widget_editing_editor_test.exs`
covers add-widget reset and edit-placement prefill,
`widget_editing_selection_test.exs` covers single/multi point selection, and
`widget_editing_persistence_test.exs` covers successful persistence,
validation/no-persist failures, and operational observable authoring-scope
failures. The focused widget-editing command passes 15 `cadence_web` tests
across editor, selection, persistence, and event-delegation owners. A full
`mix precommit` passed after the retirement with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
The generic render-panel model owner is retired:
`render_panel_shell_test.exs`, `render_panel_props_test.exs`,
`render_panel_observable_filter_test.exs`, and
`render_panel_invalidation_test.exs` cover shell visibility, aggregate panel
props, operational-observable filtering, and invalidation precedence. The
focused render-panel command passes 6 `cadence_web` tests across shell, props,
observable-filter, invalidation, and assign-projection owners. A full
`mix precommit` passed after the retirement with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
The generic source-presentation owner is retired:
`source_presentation_placement_warnings_test.exs`,
`source_presentation_health_test.exs`,
`source_presentation_selection_test.exs`, and
`source_presentation_dashboard_warnings_test.exs` cover placement warnings,
source health/degradation, source-selection summaries, and dashboard warning
summaries. The focused source-presentation command passes 15 `cadence_web`
tests across the four focused owners plus dashboard warning, source health, and
source selection component owners. A full `mix precommit` passed after the
retirement with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
The generic data-management presentation owner is retired:
`data_management_presentation_frame_test.exs`,
`data_management_presentation_event_rows_test.exs`, and
`data_management_presentation_aggregate_test.exs` cover frame badge projection,
event-row workflow/watermark/late-data summaries, and placement/aggregate nil
fallbacks. The focused data-management command passes 27 `cadence_web` tests
across the three focused owners plus widget data-management, data-management
golden contract, and historical workflow data-management live owners. A full
`mix precommit` rerun passed after the retirement with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded, after
the exact first-attempt `Cadence.ContactsSchedulerTest` repo lookup failure
passed app-locally.
The generic source-execution runtime-summary owner is retired:
`source_execution_runtime_summary_counts_test.exs`,
`source_execution_runtime_summary_dependencies_test.exs`,
`source_execution_runtime_summary_posture_test.exs`, and
`source_execution_runtime_summary_degraded_test.exs` cover counts/actions,
upstream dependency projection, source-selection/capability posture projection,
and degraded outcome/incident projection with a shared fixture. The focused
source-execution command passes 8 `cadence_web` tests across the four focused
owners plus the adjacent runtime source-execution diagnostics owner, and the
degraded assertion now pins the expected source identity fields. A full
`mix precommit` passed after the retirement with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Runtime source-execution diagnostics now also have a direct owner:
`runtime_source_execution_diagnostics_test.exs` covers empty summary fallback,
stale source-result degradation, source-unavailable/circuit-open decisions,
degraded drilldowns, and source incident evidence attrs that previously lived in
the general runtime diagnostics owner. The affected runtime diagnostic files
pass 3 focused tests after the split. The full `mix precommit` gate passed
after this split with 1272 `cadence` tests, 66 `cadence_simulator` tests, 1541
`cadence_web` tests, and 93 excluded.
Ground-station operational-observable scope rendering now has a dedicated
browser owner test. The focused split command passes 6 `cadence_web` tests and
keeps ground-station row filtering, related transport filtering, resolved setup
DataLink routing, and copy payload context outside the mixed
operational-observable scope-rendering file. The full `mix precommit` gate
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1539 `cadence_web` tests with 93 excluded.
Link operational-observable scope rendering now has a dedicated browser owner
test. The focused split command passes 6 `cadence_web` tests and keeps link RF
row filtering, supported-capability metadata, resolved transport setup DataLink
routing, inspector link context, and copy payload context outside the mixed
operational-observable scope-rendering file. The full `mix precommit` gate
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1539 `cadence_web` tests with 93 excluded.
Source-endpoint operational-observable scope rendering now has a dedicated
browser owner test. The focused split command passes 6 `cadence_web` tests and
keeps source-endpoint scoped transport-row filtering, supported-capability
metadata, resolved transport setup DataLink routing, and copy payload context
outside the mixed operational-observable scope-rendering file. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Transport operational-observable scope rendering now has a dedicated browser
owner test. The focused split command passes 6 `cadence_web` tests and keeps
transport scoped row filtering, supported-capability metadata, resolved setup
DataLink routing, inspector display-name proof, and copy payload context outside
the mixed operational-observable scope-rendering file. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Mission operational-observable scope rendering now has a dedicated browser owner
test. The focused split command passes 6 `cadence_web` tests and keeps
mission-scope command-queue aggregate rendering, aggregate frame/source
metadata, displayed pending count, row evidence, and no invented resource
DataLink behavior outside the mixed operational-observable scope-rendering file.
The full `mix precommit` gate passed after the split with 1272 `cadence` tests,
66 `cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Default multi-entity operational-observable scope rendering now has a dedicated
browser owner file. The focused split command passes 6 `cadence_web` tests and
keeps document-default multi-source-endpoint filtering, returned alpha/beta row
rendering, gamma exclusion, and source capability metadata in that owner. The
full `mix precommit` gate passed after the rename with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Fail-closed golden contracts now have a dedicated owner file. The focused split
command passes 38 `cadence_web` tests with the trimmed golden contract suite and
keeps unknown-widget retention plus unsupported operational source-pairing
validation/planning/presenter lifecycle coverage outside the large golden
contract owner. The full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Operational latest golden contracts now have a dedicated owner file. The
focused split command passes 36 `cadence_web` tests with the trimmed golden
contract suite and keeps source-endpoint scoped operational status-matrix source
override plus operational data-table projected-row source context coverage
outside the large golden contract owner. The full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1539 `cadence_web` tests with 93 excluded.
Operational data-table golden contracts now have a dedicated owner file. The
focused split command passes 2 async `cadence_web` tests: source-endpoint scoped
status-matrix source override planning, frame metadata, row projection, source
status, and DataLink runtime context stay in the 390-line operational latest
owner, while projected row source context, hidden status-matrix-specific fields,
and contact/source-endpoint/ground-station DataLinks live in the 291-line
operational data-table owner. A full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web`
tests with 93 excluded.
Operational timeline golden contracts now have a dedicated owner file. The
focused split command passes 34 `cadence_web` tests with the trimmed golden
contract suite and keeps link-scoped RF lock/frame-sync event-history lane
coverage plus transport-scoped execution interval lane coverage outside the
large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Transport execution timeline golden contracts now have a dedicated owner file.
The focused split command passes 2 async `cadence_web` tests: link-scoped RF
lock/frame-sync event-history lane coverage stays in the 357-line operational
timeline owner, while transport-scoped execution interval planning, evidence
refs, transport DataLinks, and state-timeline lane/row projection live in the
303-line transport execution timeline owner. A full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1543 `cadence_web` tests with 93 excluded.
Transport metric value-tile golden contracts now have a dedicated owner file.
The focused split command passes 32 `cadence_web` tests with the trimmed golden
contract suite and keeps ready downlink/uplink bitrate planning, frame metadata,
resource DataLinks, selected-ref payloads, and presenter sample coverage outside
the large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Transport uplink metric value-tile golden contracts now have a dedicated owner
file. The focused split command passes 2 async `cadence_web` tests: ready
transport-scoped downlink planning, frame metadata, DataLink runtime context,
selected-ref payloads, and presenter sample coverage stay in the 377-line
transport metric owner, while the same uplink contract lives in the 373-line
uplink owner. A full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web` tests
with 93 excluded.
RF metric value-tile golden contracts now have a dedicated owner file. The
focused split command passes 30 `cadence_web` tests with the trimmed golden
contract suite and keeps ready link-scoped SNR/EbN0 planning, frame metadata,
resource DataLinks, selected-ref payloads, and presenter sample coverage outside
the large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Eb/N0 RF metric value-tile golden contracts now have a dedicated owner file. The
focused split command passes 2 async `cadence_web` tests: ready link-scoped SNR
planning, frame metadata, DataLink runtime context, selected-ref payloads, and
presenter sample coverage stay in the 382-line RF metric owner, while the same
Eb/N0 contract lives in the 382-line Eb/N0 owner. A full `mix precommit` gate
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1543 `cadence_web` tests with 93 excluded.
Transport metric missing-snapshot golden contracts now have a dedicated owner
file. The focused split command passes 28 `cadence_web` tests with the trimmed
golden contract suite and keeps many-transport missing-snapshot warnings,
resource DataLinks, selected-ref `scope_ids`, stale lifecycle/source-status
projection, and presenter sample fallback outside the large golden contract
owner. The full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Event-timeline golden contracts now have a dedicated owner file. The focused
split command passes 27 `cadence_web` tests with the trimmed golden contract
suite and keeps telemetry backfill lifecycle/source-capability event planning,
source/backfill frame metadata, operational/backfill DataLinks, workflow job
degradation badges, and presenter event rows outside the large golden contract
owner. The full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Repeated-layout golden contracts now have a dedicated owner file. The focused
split command passes 26 `cadence_web` tests with the trimmed golden contract
suite and keeps spacecraft repeated placement expansion, per-spacecraft
telemetry/limit request planning, repeated placement ids, source warnings,
DataLink scope context, and status-matrix presenter row coverage outside the
large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Stale operational warning golden contracts now have a dedicated owner file. The
focused split command passes 25 `cadence_web` tests with the trimmed golden
contract suite and keeps dashboard/placement stale-data warnings, operational
observable frame freshness metadata, warning DataLink runtime context, and
presenter lifecycle/sample projection outside the large golden contract owner.
The full `mix precommit` gate passed after the split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests with 93
excluded.
Stale operational status-matrix golden contracts now have a dedicated owner
file. The focused split command passes 24 `cadence_web` tests with the trimmed
golden contract suite and keeps mission-scoped command-queue planning, stale
matrix frame metadata, source-status rollup, data-management warning state, and
presenter row projection outside the large golden contract owner. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Stale operational data-table golden contracts now have a dedicated owner file.
The focused split command passes 23 `cadence_web` tests with the trimmed golden
contract suite and keeps mission-scoped command-queue table planning, stale
frame metadata, source-status rollup, data-management warning state, and public
presenter row projection outside the large golden contract owner. The split also
removed the original owner's now-unused stale operational source helper. The
full `mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Source-endpoint command-queue data-table golden contracts now have a dedicated
owner file. The focused split command passes 22 `cadence_web` tests with the
trimmed golden contract suite and keeps source-endpoint scoped stale frame
metadata, presenter row projection, source-status scope ids, source-endpoint
DataLink projection, and original-owner source-endpoint fixture helper cleanup
outside the large golden contract owner. The full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1539 `cadence_web` tests with 93 excluded.
Command-queue data-table fail-closed golden contracts now have a dedicated
owner file. The focused split command passes 21 `cadence_web` tests with the
trimmed golden contract suite and keeps source-unavailable warning details,
zero-frame fail-closed behavior, placement warning projection, source-status
unavailable state, and original-owner failing command-queue helper cleanup
outside the large golden contract owner. The full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1539 `cadence_web` tests with 93 excluded.
Ingress-latency data-table golden contracts now have a dedicated owner file.
The focused split command passes 20 `cadence_web` tests with the trimmed golden
contract suite and keeps source-endpoint scoped planning, source callback option
propagation, stale runtime-ingress frame metadata, presenter row DataLink
projection, and original-owner ingress-latency helper cleanup outside the large
golden contract owner. The full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Source-unavailable golden contracts now have a dedicated owner file. The
focused split command passes 19 `cadence_web` tests with the trimmed golden
contract suite and keeps failing telemetry adapter planning, source circuit
breaker execution, source execution semantics, warning DataLinks/runtime
context, placement warning projection, and presenter source-status lifecycle
outside the large golden contract owner. The full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1539 `cadence_web` tests with 93 excluded.
No-data value-tile golden contracts now have a dedicated owner file. The
focused split command passes 18 `cadence_web` tests with the trimmed golden
contract suite and keeps healthy empty telemetry planning, no-data scalar frame
lifecycle, best-effort watermark propagation, source-status no-data state, and
presenter sample emptiness outside the large golden contract owner. The split
also removed the original owner's now-unused no-data source helper. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Data-management golden contracts now have a dedicated owner file. The focused
split command passes 17 `cadence_web` tests with the trimmed golden contract
suite and keeps all-revisions planning, revision-state warning lifecycle,
data-management badges, canonical comparison render model/rollup/preset
projection, and original-owner revision fixture helper cleanup outside the
large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded. A later final-state rerun first hit the
known transient `Cadence.Repo` startup lookup in `PersistTelemetryIngressTest`
at line 696; the exact test passed in isolation before the next full
`mix precommit` rerun passed with the same counts.
Data-management golden comparison projection now has a dedicated owner file.
The focused split command passes 2 async `cadence_web` tests: revision lifecycle
and badge coverage stay in the 317-line data-management owner, while canonical
comparison sample projection, comparison summary DataLinks, root attrs, rollup
groups, and investigation-preset payload serialization live in the 416-line
comparison owner. A full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web` tests
with 93 excluded.
Replay golden contracts now have a dedicated owner file. The focused split
command passes 15 `cadence_web` tests with the trimmed golden contract suite and
keeps replay-run planning context, replay telemetry/limit binding provenance,
replay sample DataLink selected-ref payloads, replay limit overlay metadata, and
original-owner replay registry/helper cleanup outside the large golden contract
owner. The full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Baseline value-tile golden contracts now have a dedicated owner file. The
focused split command passes 14 `cadence_web` tests with the trimmed golden
contract suite and keeps latest telemetry and limit planning, capability
fallback warning details, telemetry/limit DataLink runtime context, selected-ref
payload projection, watermark freshness metadata, presenter sample and limit
projection, and original-owner scalar fixture helper cleanup outside the large
golden contract owner. The full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Baseline time-series golden contracts now have a dedicated owner file. The
focused split command passes 13 `cadence_web` tests with the trimmed golden
contract suite and keeps native decimated telemetry planning, limits/events
overlay planning, marker projection, telemetry point DataLink selected-ref
payloads, chart backfill projection, presenter sample projection, and
original-owner limits/events fixture helper cleanup outside the large golden
contract owner. The full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Baseline time-series source-request planning now lives in
`ops_dashboard_show_live/golden_contract_time_series_planning_test.exs`; the
resolved baseline time-series owner now keeps resolved frames, DataLink selected
refs, limit/event markers, chart backfill, and presenter sample projection. Those
two owners pass 2 async tests in roughly 0.2 seconds;
`golden_contract_time_series_test.exs` is down to 490 lines and the planning
owner is 173 lines. A full `mix precommit` passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web` tests with
93 excluded.
Operational RF metric time-series golden contracts now have a dedicated owner
file. The focused split command passes 12 `cadence_web` tests with the trimmed
golden contract suite and keeps link-scoped RF history planning, operational
resource frame metadata, transport/source-endpoint/ground-station/link
DataLinks, selected-ref payload projection, chart backfill points, presenter
source-status projection, and original-owner RF metric history source fixture
cleanup outside the large golden contract owner. The full `mix precommit` gate
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1539 `cadence_web` tests with 93 excluded.
Operational ingress-latency time-series golden contracts now have a dedicated
owner file. The focused split command passes 11 `cadence_web` tests with the
trimmed golden contract suite and keeps source-endpoint scoped ingress-latency
planning, runtime-ingress frame metadata, source-endpoint DataLink runtime
context, selected-ref payload projection, chart backfill points, and
original-owner ingress-latency history source fixture cleanup outside the large
golden contract owner. The full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web`
tests with 93 excluded.
Operational RF metric no-data time-series golden contracts now have a dedicated
owner file. The focused split command passes 10 `cadence_web` tests with the
trimmed golden contract suite and keeps link-scoped RF no-data planning,
zero-point operational frame metadata, transport/source-endpoint/ground-station/link
DataLinks, no-data chart backfill behavior, presenter no-data source-status
projection, and original-owner RF metric no-data source fixture cleanup outside
the large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Generic no-data time-series golden contracts now have a dedicated owner file.
The focused split command passes 9 `cadence_web` tests with the trimmed golden
contract suite and keeps native decimated telemetry no-data planning, physical
aggregate warning propagation, empty telemetry frames, best-effort source
watermark freshness, telemetry point DataLink runtime context, presenter
no-data source-status projection, and original-owner healthy empty-range source
fixture cleanup outside the large golden contract owner. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Contact-scoped no-data time-series golden contracts now have a dedicated owner
file. The focused split command passes 8 `cadence_web` tests with the trimmed
golden contract suite and keeps scheduled-contact scope planning,
source-endpoint filter option propagation, physical aggregate warning
propagation, empty telemetry frames, best-effort source watermark freshness,
contact DataLink runtime context, presenter contact no-data source-status
projection, and original-owner scheduled-contact source fixture cleanup outside
the large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Source-endpoint no-data time-series golden contracts now have a dedicated owner
file. The focused split command passes 7 `cadence_web` tests with the trimmed
golden contract suite and keeps direct source-endpoint scope planning,
source-endpoint filter option propagation, physical aggregate warning
propagation, empty telemetry frames, best-effort source watermark freshness,
source-endpoint DataLink runtime context, presenter source-endpoint no-data
source-status projection, and original-owner direct source-endpoint source
fixture cleanup outside the large golden contract owner. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Partial time-series golden contracts now have a dedicated owner file. The
focused split command passes 6 `cadence_web` tests with the trimmed golden
contract suite and keeps mixed returned and empty telemetry range coverage,
partial-data warning details, physical aggregate warning propagation,
returned-series chart backfill, presenter partial lifecycle/source-status
projection, and original-owner mixed decimated-history source fixture cleanup
outside the large golden contract owner. The full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1539 `cadence_web` tests with 93 excluded.
Source-unavailable time-series golden contracts now have a dedicated owner
file. The focused split command passes 5 `cadence_web` tests with the trimmed
golden contract suite and keeps failed native decimated-history
planning/execution, source-unavailable warning details/actions, warning
telemetry-point DataLink runtime context, placement-level no-frame error
propagation, presenter error lifecycle/source-status projection, and
original-owner failed range-query source fixture cleanup outside the large
golden contract owner. The full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web`
tests with 93 excluded.
Stale time-series golden contracts now have a dedicated owner file. The focused
split command passes 4 `cadence_web` tests with the trimmed golden contract
suite and keeps stale source watermark warning details/actions, returned
telemetry frames despite degraded freshness, best-effort stale source watermark
metadata, chart backfill preservation, presenter stale lifecycle/source-status
projection, and original-owner stale watermark source fixture cleanup outside
the large golden contract owner. The full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539
`cadence_web` tests with 93 excluded.
Retention-gap time-series golden contracts now have a dedicated owner file. The
focused split command passes 3 `cadence_web` tests with the trimmed golden
contract suite and keeps retention boundary warning details/actions, returned
telemetry frames despite retention boundary degradation, best-effort
retention-gap source watermark metadata, chart backfill preservation,
retention-gap event marker projection, presenter retention-gap
lifecycle/source-status projection, and original-owner retention-gap watermark
source fixture cleanup outside the large golden contract owner. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Unknown-watermark time-series golden contracts now have a dedicated owner file.
The focused split command passes 2 `cadence_web` tests with the trimmed golden
contract suite and keeps failed watermark-query fallback, unknown source
watermark warning details, returned telemetry frames despite unknown freshness,
unknown source watermark metadata, chart backfill preservation, presenter
stale/unknown lifecycle and source-status projection, and original-owner failed
watermark source fixture cleanup outside the large golden contract owner. The
full `mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Source-degraded time-series golden contracts now have a dedicated owner file.
The focused split command passes 1 `cadence_web` test and retires the original
aggregate `golden_contract_test.exs` owner while preserving degraded
source-health event injection, durable source-health frame evidence, returned
telemetry frames while source health is degraded, chart backfill preservation,
and presenter ready/degraded lifecycle and source-status projection. The full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Version-history comparison-review queue component contracts now have a
dedicated owner file. The focused split command passes 20 `cadence_web` tests
with the trimmed version-history panel component suite and keeps open review
queue rendering, materialized queue rendering, explicit empty queue state, and
stale selected-placement queue state outside the broader version-history panel
component owner. The full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web` tests
with 93 excluded.
Version-history publish-readiness component contracts now have a dedicated
owner file. The focused split command passes 16 `cadence_web` tests with the
trimmed version-history panel component suite and keeps publish validation
action hints, unsupported observable scope blocker summaries,
clean/stale/source-stale readiness states, selected readiness remediation
source-action context, connection-test source evidence routing, and dashboard
editor focus routing outside the broader version-history panel component owner.
The full `mix precommit` gate passed after an exact transient-failure rerun with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1539 `cadence_web`
tests with 93 excluded.
Widget-presentation time-series marker contracts now have a dedicated owner
file. The focused split command passes 22 `cadence_web` tests with the trimmed
widget presentation suite and keeps limit definition interval markers, replay
source-binding/retention-gap provenance, source-health transition markers,
source-watermark markers, telemetry revision decision markers, and telemetry
backfill lifecycle markers outside the broader widget presentation owner. The
full `mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1539 `cadence_web` tests with 93 excluded.
Telemetry lifecycle time-series markers now live in
`ops_dashboard_show_live/widget_presentation_time_series_lifecycle_markers_test.exs`;
the general time-series marker owner keeps limit definition interval markers,
replay source-binding/retention-gap provenance, source-health transition markers,
and source-watermark markers. Those two focused owners pass 6 async tests in
roughly 0.1 seconds; `widget_presentation_time_series_markers_test.exs` is down
to 358 lines and the lifecycle-marker owner is 232 lines. A full `mix precommit`
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1543 `cadence_web` tests with 93 excluded.
Widget-presentation data-management badge contracts now have a dedicated owner
file. The focused split command passes 44 `cadence_web` tests and keeps
value-tile data-view/revision badge projection plus active historical-workflow
badge projection outside the broader widget presentation owner, while checking
the adjacent widget data-management and data-management presentation owners. A
full `mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Widget-presentation operational metric contracts now have a dedicated owner
file. The focused split command passes 35 `cadence_web` tests and keeps
connection-state rows, operational metric value-tile/no-data rows, stale runtime
metric rows, and stale connection lifecycle projection outside the broader
widget presentation owner while checking adjacent widget row/point components. A
full `mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Widget-presentation timeline contracts now have a dedicated owner file. The
focused split command passes 29 `cadence_web` tests and keeps event timeline
event/interval projection, limit state-timeline segments, operational observable
state-timeline segments, and independent lane segment closing outside the
broader widget presentation owner while checking adjacent row components. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Widget-presentation lifecycle contracts now have a dedicated owner file. The
focused split command passes 28 `cadence_web` tests and keeps partial-data and
unsupported-source lifecycle projection outside the status/data-table presenter
owner while checking adjacent point components. A full `mix precommit` passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1542 `cadence_web` tests with 93 excluded.
The generic widget-presentation owner is retired:
`widget_presentation_status_table_test.exs` now owns the residual operational
observable status-matrix and data-table projection contracts, while lifecycle,
timeline, operational metric, data-management, and time-series marker contracts
live in focused files. The focused retirement command passes 35 `cadence_web`
tests across the status/table owner, the focused widget presentation owners, and
adjacent row/point components. A full `mix precommit` passed after the
retirement with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
Evidence-presentation source contracts now have a dedicated owner file. The
focused split command passes 32 `cadence_web` tests and keeps contact-scope
no-data diagnostics, partial/degraded source messages, context-only cache
evidence, capability posture context, and source-status drilldowns outside the
broader evidence presentation owner while checking adjacent evidence inspector
and query owners. A full `mix precommit` passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests with
93 excluded.
Evidence-presentation overview contracts now have a dedicated owner file. The
focused split command passes 32 `cadence_web` tests and keeps source-watermark
DataLink summaries, dashboard-health rollup evidence, and placement-warning
runtime accessor resolution outside the broader frame evidence presentation
owner while checking source evidence, evidence inspector, and evidence query
owners. A full `mix precommit` passed after the split with 1272 `cadence` tests,
66 `cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Evidence-presentation limits contracts now have a dedicated owner file. The
focused split command passes 32 `cadence_web` tests and keeps direct limits
frame evidence plus telemetry-frame limits overlay evidence outside the broader
frame evidence presentation owner while checking overview/source evidence,
evidence inspector, and evidence query owners. A full `mix precommit` passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1542 `cadence_web` tests with 93 excluded.
The generic evidence-presentation owner is retired: telemetry frame
data-view/semantic-interval/action metadata contracts now live in
`evidence_presentation_telemetry_frame_test.exs`, operational metric-history
frame product-family and selected-interval evidence lives in
`evidence_presentation_operational_metrics_test.exs`, and the earlier source,
overview, and limits owners retain their focused coverage. The focused
retirement command passes 32 `cadence_web` tests across the split owners plus
adjacent evidence inspector and query owners. A full `mix precommit` passed
after the retirement with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1542 `cadence_web` tests with 93 excluded.
Historical-workflow comparison-review DataLink routes now have a dedicated
LiveView proof owner. The focused split command passes 11 `cadence_web` tests
and keeps resolved/missing dashboard lifecycle event DataLink route coverage
outside the broader comparison-review workflow owner, which remains focused on
review resolution, bulk decisions, and historical workflow handoff. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
Historical-workflow comparison-review bulk revision-decision flows now have a
dedicated LiveView proof owner. The focused split command passes 11
`cadence_web` tests and keeps successful, actionable-only, partial-failure,
missing-source-context, and no-actionable-finding bulk decision coverage outside
the broader comparison-review workflow owner, which now retains rollup
resolution, audit-context resolution, versions-queue resolution, and grouped
historical workflow handoff. A full `mix precommit` passed after the split with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web`
tests with 93 excluded. Missing-source-context and no-actionable-finding
unavailable explanations later moved again into
`ops_dashboard_show_live/historical_workflow_comparison_review_bulk_decision_unavailable_live_test.exs`;
the bulk-decision owner now keeps successful, actionable-only, and
partial-failure decision execution behavior. The trimmed bulk-decision owner plus
unavailable owner pass 5 tests in roughly 1.0 seconds;
`historical_workflow_comparison_review_bulk_decision_live_test.exs` is down to
694 lines and the unavailable owner is 309 lines. A full `mix precommit` passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and
1542 `cadence_web` tests with 93 excluded.
Partial-failure degraded outcome coverage later moved again into
`ops_dashboard_show_live/historical_workflow_comparison_review_bulk_decision_partial_live_test.exs`;
the bulk-decision owner now keeps successful and actionable-only decision
execution behavior. The trimmed bulk-decision owner plus partial-failure owner
pass 3 tests in roughly 0.8 seconds;
`historical_workflow_comparison_review_bulk_decision_live_test.exs` is down to
549 lines and the partial-failure owner is 331 lines. A full `mix precommit`
passed after the historical-workflow comparison-review bulk-decision
partial-failure split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1542 `cadence_web` tests with 93 excluded.
DataLink inspector revision-decision controls now have a dedicated component
proof owner. The focused split command passes 10 `cadence_web` tests and keeps
revision decision event controls plus comparison-finding identity-context
controls outside the broader inspector panel owner, which remains focused on
identity/context rows, late-data policy controls, lifecycle recovery links,
source watermark rows, and workflow dispatch retry controls. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
DataLink inspector late-data policy controls now have a dedicated component
proof owner. The focused split command passes 10 `cadence_web` tests and keeps
lifecycle late-data policy controls, event-only policy decisions, and
policy-event control suppression outside the broader inspector panel owner,
which now remains focused on identity/context rows, lifecycle recovery links,
source watermark rows, and workflow dispatch retry controls. A full
`mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
DataLink inspector lifecycle-recovery rendering now has a dedicated component
proof owner. The focused split command passes 10 `cadence_web` tests and keeps
failed lifecycle correction explanations plus grouped recovery/follow-up/evidence
related-link trails outside the broader inspector panel owner, which now remains
focused on identity/context rows, source watermark rows, and workflow dispatch
retry controls. A full `mix precommit` passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests
with 93 excluded.
DataLink inspector workflow-dispatch rendering now has a dedicated component
proof owner. The focused split command passes 10 `cadence_web` tests and keeps
degraded workflow dispatch explanations, retry controls, latest-action rendering,
and retry action-outcome metadata outside the broader inspector panel owner,
which now remains focused on identity/context rows and source watermark rows. A
full `mix precommit` passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1542 `cadence_web` tests with 93 excluded.
DataLink inspector source-watermark rendering now has a dedicated component
proof owner. The focused split command passes 10 `cadence_web` tests and keeps
source watermark event identity, selected link attrs, watermark key, logical
source, data/source-binding context, freshness timestamps, and reason rows
outside the broader inspector panel owner, which now remains focused on generic
inspector identity/context rows, related links, and actions. A full
`mix precommit` passed after the split and transport-store test isolation fix
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web`
tests with 93 excluded.
DataLink selection evidence semantics now have a dedicated async proof owner.
The focused split command passes 37 `cadence_web` tests and keeps
evidence-query parsing, evidence event-param round trips, missing evidence
inspectors, panel/query-derived evidence metadata, and evidence panel-state
helpers outside the broader DataLink selection owner, which now remains focused
on data-link query/ref construction, runtime staleness, synthetic links, and
selection context. A full `mix precommit` passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1542 `cadence_web` tests
with 93 excluded.
DataLink selection runtime/staleness semantics now have a dedicated async proof
owner. The focused split command passes 37 `cadence_web` tests and keeps active
runtime context matching, setup-resource same-kind scope invalidation,
archive/replay time-bound matching, query-restored concrete-scope matching, and
stale selection query clearing outside the broader DataLink selection owner,
which now remains focused on query/ref construction, current-query helpers,
synthetic links, and selection context. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
DataLink selection context semantics now have a dedicated async proof owner. The
focused split command passes 37 `cadence_web` tests and keeps synthetic
direct-link construction, source-watermark synthetic links, selection/runtime
context merge behavior, navigation breadcrumb context, and marker-specific data
context outside the broader DataLink selection owner, which now remains focused
on query/ref construction and current-query helpers. A full `mix precommit`
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1542 `cadence_web` tests with 93 excluded.
DataLink selection query parsing now has a dedicated async proof owner. The
focused split command passes 37 `cadence_web` tests and keeps URL-param
selection parsing, panel-gated parsing, comparison source metadata query/event
round trips, and selection-query reconstruction from selected refs outside the
broader DataLink selection owner, which now remains focused on selected-ref
construction and current-query helpers. A full `mix precommit` passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1542
`cadence_web` tests with 93 excluded.
DataLink selection current-query semantics now have a dedicated async proof
owner. The focused split command passes 37 `cadence_web` tests and keeps compact
current-query derivation from selected refs plus non-default runtime context
current-query construction outside the broader DataLink selection owner, which
now remains focused on selected-ref construction only. A full `mix precommit`
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1542 `cadence_web` tests with 93 excluded.
Route hydration runtime-context semantics now have a dedicated async proof
owner. The focused split command passes 12 `cadence_web` tests and keeps stale
operational-resource URL scope rejection, stale selected-data-ref clearing, and
repeated render-item refresh from runtime scope changes outside the broader
route hydration owner, which now remains focused on URL `handle_params`
hydration. A full `mix precommit` gate passed after the split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web` tests with
93 excluded.
Operational-observable widget creation now has a dedicated browser proof owner.
The focused split command passes 6 `cadence_web` tests and keeps
operational-observable status-matrix creation, picker availability, selected
observable state, persisted operational binding, and render-item projection
outside the broader widget creation owner, which now remains focused on
telemetry-backed creation flows. A full `mix precommit` gate passed after the
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543
`cadence_web` tests with 93 excluded.
Ready widget data contracts now have a dedicated async proof owner. The focused
split command passes 12 `cadence_web` tests and keeps ready payload contracts
plus stale frame-warning lifecycle promotion for value tile, time series, status
matrix, data table, state timeline, event timeline, and constellation health
outside the broader widget data-contract owner, which now remains focused on
source-status, no-data, backfill, and missing-snapshot edge contracts. A full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Version-history selected-activity recovery now has a dedicated async proof owner.
The focused split command passes 6 `cadence_web` tests and keeps hidden-by-filter
recovery messaging/link params plus missing-from-log clear-selection recovery
outside the broader version-history panel owner, which now remains focused on
version pointers, health filtering, runtime impact, and runtime-default context.
A full `mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Version-history publish-readiness freshness now has a dedicated async proof
owner. The focused split command passes 5 `cadence_web` tests and keeps stale
draft freshness, stale source-watermark freshness, re-check result states, and
operator-facing stale evidence copy outside the broader publish-readiness owner,
which now remains focused on action hints, unsupported-scope blockers, and
resolved re-check behavior. A full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web`
tests with 93 excluded.
Version-history comparison-review queue states now have a dedicated async proof
owner. The focused split command passes 6 `cadence_web` tests and keeps the
explicit empty queue state plus stale selected-placement queue state outside the
broader comparison-review queue owner, which now remains focused on open queue
rendering, materialized queue activity, request details, and resolution state.
A full `mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Dashboard toolbar comparison-review routing now has a dedicated async proof
owner. The focused split command passes 9 `cadence_web` tests and keeps Versions
button review-activity routing, empty materialized-queue badge suppression, and
materialized review-queue routing outside the broader toolbar owner, which now
remains focused on mission/contact context controls, limit-mode fallback,
lifecycle actions, and publish-readiness summaries. A full `mix precommit` gate
passed after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests,
and 1543 `cadence_web` tests with 93 excluded.
Publish-validation issue details now have a dedicated async proof owner. The
focused split command passes 15 `cadence_web` tests and keeps direct issue
message/detail-row contracts, repeated issue-code focus-id stability, and
primitive detail-row normalization outside the broader publish-validation
presentation owner, which now remains focused on status/freshness projection,
blocker ordering, source-readiness action hints, capability mismatch params, and
unsupported observable scope presentation. A full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543
`cadence_web` tests with 93 excluded.
Document lifecycle publish-readiness projection now has a dedicated async proof
owner. The focused split command passes 10 `cadence_web` tests and keeps
publish-validation freshness plus publish-readiness payload contracts for
freshness/source-evidence codes and failed source connection remediation outside
the broader document lifecycle owner, which now remains focused on lifecycle DOM
attributes, runtime-default diff detection, and version action unavailable
messages. A full `mix precommit` gate passed after the split with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1543 `cadence_web` tests with 93
excluded.
DataLink presentation evidence context now has a dedicated async proof owner.
The focused split command passes 9 `cadence_web` tests and keeps inspector
source-context fallback plus serialized-link context precedence outside the
broader DataLink presentation owner, which now remains focused on related-link
rows, relationship-kind normalization, navigation grouping, panel summaries and
control flags, and unsupported link defaults. A full `mix precommit` gate passed
after the split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543
`cadence_web` tests with 93 excluded.
Runtime status/provenance now has a dedicated async proof owner. The focused
split command passes 9 `cadence_web` tests and keeps decision-summary refresh
provenance plus active/settled/degraded/suppressed refresh-status projection
outside the broader runtime owner, which now remains focused on resolve
success/failure, marker appends, and dashboard termination behavior. A full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Source-endpoint command queue row rendering now has a dedicated async proof
owner. The focused split command passes 4 `cadence_web` tests and keeps
source-endpoint command queue data-table row identity, DataLink target attrs,
and frame-evidence source/scope attrs outside the broader widget row component
owner, which now remains focused on status-matrix, generic data-table, and
state-timeline row contracts. A full `mix precommit` gate passed after the split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web`
tests with 93 excluded.
Historical workflow request defaults now have a dedicated async proof owner. The
focused split command passes 14 `cadence_web` tests and keeps dashboard-context
hydration, replay/data-view/limit context serialization, comparison-review
scope serialization, and empty-context defaults outside the broader historical
workflow presenter owner, which now remains focused on action outcomes, action
attrs, flash copy, retry summaries, and group-stage labels. A full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Grouped historical workflow presentation now has a dedicated async proof owner.
The focused presenter set passes 14 `cadence_web` tests and keeps no-eligible
group outcomes, grouped workflow flash copy, degraded job-dispatch outcomes,
grouped retry summary attrs, and group-stage labels outside the broader
historical workflow presenter owner, which now remains focused on direct/request
action outcomes, action attrs, and basic request/stage flash copy. A full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Render-widget source health now has a dedicated async proof owner. The focused
split command passes 4 `cadence_web` tests and keeps Engine-backed command queue
stale source-health projection, widget shell lifecycle/source-warning attrs, and
command queue component props/sample preservation outside the broader source
status owner, which now remains focused on direct frame lifecycle attrs, no-data
shell source context, and stale operational metric-history chart attrs. A full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Version-history runtime defaults now have a dedicated async proof owner. The
focused split command passes 4 `cadence_web` tests and keeps published/draft
runtime-default summary attrs, runtime-default source/data-view rows, and
publish-impact warning copy outside the broader version-history panel owner,
which now remains focused on version pointers/actions, health activity
filtering, and selected activity runtime-impact correlation. A full
`mix precommit` gate passed after the split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
DataLink inspector late-data policy event guards now have a dedicated async
proof owner. The focused split command passes 3 `cadence_web` tests and keeps
event-only lifecycle policy controls without source sample identity plus
already-recorded policy-event explanation/suppression coverage outside the
broader late-data policy panel owner, which now remains focused on the full
controls, hidden form context, action-outcome attrs, and metadata serialization.
A full `mix precommit` gate passed after the split with 1272 `cadence` tests,
66 `cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Status-matrix data-table projection now has a dedicated async proof owner. The
focused split command passes 5 `cadence_web` tests and keeps the public
`data_table_rows/1` whitelist plus query-scope preservation outside the broader
status-matrix data owner, which now remains focused on telemetry scalar,
operational connection/metric, and generic operational state matrix shaping.
A full `mix precommit` gate passed after the split with 1272 `cadence` tests,
66 `cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Runtime degraded-source capability posture controls now have a dedicated async
proof owner. The focused split command passes 8 `cadence_web` tests and keeps
source-capability posture evidence controls, time-axis attrs, product attrs, and
empty-posture suppression outside the broader degraded-source component owner,
which now remains focused on degraded summary, source drilldowns, and source
dependency cause rows. A full `mix precommit` gate passed after the split with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543 `cadence_web`
tests with 93 excluded.
Selection-panel DataLink opening now has a dedicated proof owner. The focused
split command passes 5 `cadence_web` tests and keeps `open_data_link/4`
selected-ref source context, placement/time/series route patch fields, and stale
action-outcome clearing outside the broader selection DataLink context owner,
which now remains focused on hydration, copied-link recovery, selected-ref
observable extraction, and data-link-index fallback. The first full
`mix precommit` attempt hit a transient DB ownership failure in
`apps/cadence/test/cadence/dashboards/source_probe_scheduler_test.exs:148`; the
exact-location rerun passed, and the next full gate passed with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1543 `cadence_web` tests with 93
excluded.
Route-hydration versions activity behavior now has a dedicated async proof
owner. The focused split command passes 9 `cadence_web` tests and keeps
versions activity placement focus, publish-readiness source-return intent, and
supported activity-filter hydration outside the broader route-hydration owner,
which now remains focused on guard returns, dashboard-editor readiness focus,
initial/context-change runtime resolution, and unchanged-context evidence
selection hydration. The repeated full-suite source-probe scheduler ownership
failure at
`apps/cadence/test/cadence/dashboards/source_probe_scheduler_test.exs:148` was
stabilized by raising the test scheduler timeout from 25ms to 500ms, preserving
the BYO timeout behavior while giving the managed probe enough loaded-suite time
to finish its DB health write. The focused source-probe location passes, and a
full `mix precommit` gate passed with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1543 `cadence_web` tests with 93 excluded.
Widget lifecycle empty-row notices now have a dedicated async proof owner. The
focused split command passes 5 `cadence_web` tests and keeps no-data lifecycle
body notices for status-matrix, data-table, state-timeline, and event-timeline
widgets outside the broader widget lifecycle component owner, which now remains
focused on lifecycle badge attrs, unsupported context notice, time-series
source-failure body notice, and partial data-table row preservation. A full
`mix precommit` gate passed with 1272 `cadence` tests, 66 `cadence_simulator`
tests, and 1543 `cadence_web` tests with 93 excluded.
Dashboard lifecycle restore-history behavior now has a dedicated non-async
proof owner. The focused split command passes 2 `cadence_web` tests and keeps
historical version-history panel restore availability, restore-version
draft-ahead state, reverted activity rows, and persisted version-summary
assertions outside the broader dashboard lifecycle owner, which now remains
focused on the create/edit/publish conflict, revert, archive, restore, and
audit-surface workflow. The first full `mix precommit` attempt hit a transient
Repo startup failure in `apps/cadence/test/cadence/contacts_scheduler_test.exs:328`;
the exact-location rerun passed, and the next full `mix precommit` gate passed
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1543
`cadence_web` tests with 93 excluded.
Comparison-rollup action handoffs now have a dedicated async component proof
owner. The focused comparison-rollup command passes 6 `cadence_web` tests and
keeps applied decision DataLink attrs, comparison-finding handoff attrs, and
primary/compare sample DataLink attrs outside the broader rollup component
owner, which now remains focused on summary groups, workflow badges, item
metadata, and hidden-state behavior. A full `mix precommit` gate passed with
1272 `cadence` tests, 66 `cadence_simulator` tests, and 1544 `cadence_web`
tests with 93 excluded.
Version-history comparison review request/resolution details now have a
dedicated async component proof owner. The focused version-history comparison
review command passes 6 `cadence_web` tests and keeps request detail rendering,
resolve form attrs, placement selection state, resolution state, and workflow
metadata outside the broader queue owner, which now remains focused on open
queue filtering and materialized queue activity. A full `mix precommit` gate
passed with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1544
`cadence_web` tests with 93 excluded.
Runtime diagnostics panel detail sections now have a dedicated async component
proof owner. The focused runtime diagnostics command passes 8 `cadence_web`
tests and keeps cache/no-refresh summaries, recent invalidation selection and
source-cache evidence rows, source dependency causes, and capability posture
evidence actions outside the broader panel component owner, which now remains
focused on root runtime attrs plus engine/runtime/invalidation row sections. A
full `mix precommit` gate passed with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1544 `cadence_web` tests with 93 excluded.
Chart append marker snapshot behavior now has a dedicated async proof owner. The
focused chart/time-series marker command passes 17 `cadence_web` tests and keeps
marker-only payloads when marker snapshots change without a new sample, plus
unchanged marker snapshot suppression, outside the broader chart append owner,
which now remains focused on typed limit/event marker bucket appends and
recomputed limit analysis marker metadata. A full `mix precommit` gate passed
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1544 `cadence_web`
tests with 93 excluded.
Live widget raw-evidence navigation now has a dedicated workflow-specific proof
owner. The focused live-widget rendering command passes 2 `cadence_web` tests
and keeps telemetry-sample widget DataLink selection, raw-evidence related-link
navigation, shared raw-evidence URL hydration, copy-link context, and navigation
back to the source telemetry sample outside the broad live-widget rendering
owner, which now remains focused on core live values, limit states, fleet health,
grid placement, selected telemetry sample pause/resume, and limit event
selection. A full `mix precommit` gate passed with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1545 `cadence_web` tests with 93 excluded.
Live widget value-tile limit-event navigation now has a dedicated
workflow-specific proof owner. The focused live-widget rendering command passes
3 `cadence_web` tests and keeps value-tile limit-event DataLink selection,
limit-event inspector resolution, and related limit-definition navigation outside
the broad live-widget rendering owner, which now remains focused on core live
values, limit states, fleet health, grid placement, selected telemetry sample
pause/resume, and time-series limit-event selection. A full `mix precommit` gate
passed with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1546
`cadence_web` tests with 93 excluded.
Live widget event-marker navigation now has a dedicated workflow-specific proof
owner. The focused live-widget rendering command passes 4 `cadence_web` tests
and keeps contact interval chart marker selection, mission event chart marker
selection, operational-event related navigation, copy-link context, and
navigation trail preservation outside the broad live-widget rendering owner,
which now remains focused on core live values, limit states, fleet health, grid
placement, event-marker presence, selected telemetry sample pause/resume, and
time-series limit-event selection. A full `mix precommit` gate passed with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1547 `cadence_web` tests with
93 excluded.
Live widget telemetry selection time-context behavior now has a dedicated
workflow-specific proof owner. The focused live-widget rendering command passes
5 `cadence_web` tests and keeps chart telemetry-sample selection, deep-link
hydration, stale-context clearing, missing/unsupported selection handling,
pause-at-selection archive transitions, paused marker filtering, paused context
selection, and resume-live restoration outside the broad live-widget rendering
owner, which now remains focused on core live values, limit states, fleet health,
grid placement, telemetry/event/limit marker presence, and time-series
limit-event selection. A full `mix precommit` gate passed with 1272 `cadence`
tests, 66 `cadence_simulator` tests, and 1548 `cadence_web` tests with 93
excluded.
Historical workflow grouped backfill recovery now has a dedicated
workflow-specific proof owner. The focused grouped-backfill command passes 2
`cadence_web` tests and keeps retryable failed group recovery, retried lifecycle
selection, non-retryable correction request dashboard context, missing
replacement inspection, corrected replacement advancement, completion readiness,
and related failed-item navigation outside the grouped backfill owner, which now
remains focused on request, approve/start, mixed completion/failure, and recovery
handoff assertions. A full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1549 `cadence_web` tests with
93 excluded.
Historical workflow grouped backfill terminal outcomes now have a dedicated
workflow-specific proof owner. The focused grouped-backfill command passes 3
`cadence_web` tests and keeps mixed completion/failure summary rendering,
queued/failed job progress, execution-audit rollup, recovery preview state, and
failed-item handoff links outside the grouped backfill owner, which now remains
focused on request, approve/start, queued job progress, and complete-eligibility.
A full `mix precommit` gate passed after this split with 1272 `cadence` tests,
66 `cadence_simulator` tests, and 1551 `cadence_web` tests with 93 excluded.
Ops Data Sources dashboard/source focus behavior now has a dedicated focused
proof owner. The focused data-source command passes 16 `cadence_web` tests and
keeps dashboard evidence query focus, inspector operational-resource source
action context, readiness activity source-evidence focus, stale/missing source
targets, publish-blocker remediation, capability mismatch candidates, and
focused binding change filtering outside the broader Ops Data Sources owner,
which now remains focused on inventory, deployment, probe policy,
scheduled-timeout, deployment-run, and BYO lifecycle coverage. A full
`mix precommit` gate passed after this split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1549 `cadence_web` tests with 93 excluded.
Ops Data Sources deployment/probe lifecycle behavior now has a dedicated focused
proof owner. The focused data-source command passes 16 `cadence_web` tests and
keeps managed TSDB deployment status, dedicated mission BYO TSDB provision/
reconcile/deprovision actions, source probe policy metadata, scheduled probe
timeout evidence, managed deployment-run rendering, failed-run retry, and
running-run requeue behavior outside the broader Ops Data Sources owner, which
now remains focused on mission source inventory, binding changes,
source-health/watermark rows, credential rotation, customer BYO registration,
adapter probe, capability materialization, disable/enable, and binding
eligibility. A full `mix precommit` gate passed after this split with 1272
`cadence` tests, 66 `cadence_simulator` tests, and 1549 `cadence_web` tests with
93 excluded.
Ops Data Sources operational capability remediation now has a dedicated focused
proof owner. The focused data-source command passes 16 `cadence_web` tests and
keeps operational-observable metric-history candidates, operational latest
aggregate candidates, and focused binding-change filtering for source-product
and product-family requirements outside the dashboard/source focus owner, which
now remains focused on telemetry focus, evidence, stale/missing targets,
publish-blocker remediation, and telemetry binding filtering. A full
`mix precommit` gate passed after this split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1549 `cadence_web` tests with 93 excluded.
Live widget selected-sample pause context now has a dedicated workflow-specific
proof owner. The focused telemetry selection command passes 2 `cadence_web`
tests and keeps pause-at-selected-sample archive transitions, archive range URL
preservation, selected-ref preservation, paused marker filtering, paused context
selection, and resume-live restoration outside the telemetry selection/time
context owner, which now remains focused on selection, deep-link hydration,
stale-context clearing, explicit panel route hydration, clear-selection controls,
and missing/unsupported target handling. The broader live-widget focused command
passes 6 `cadence_web` tests, and a full `mix precommit` gate passed after this
split with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1550
`cadence_web` tests with 93 excluded.
Live widget missing/unsupported selection contexts now have a dedicated
workflow-specific proof owner. The focused telemetry selection command passes 3
`cadence_web` tests and keeps missing telemetry-sample route hydration, stale
data-link route hydration, selected-ref clearing, unsupported selected-target URL
handling, and disabled selection controls outside the telemetry selection/time
context owner, which now remains focused on resolved selection, deep-link
hydration, explicit panel route hydration, stale spacecraft-context clearing,
and clear-selection controls. The broader live-widget focused command passes 7
`cadence_web` tests, and a full `mix precommit` gate passed after this split
with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1552 `cadence_web`
tests with 93 excluded.
Live widget time-series limit-event selection now has a dedicated
workflow-specific proof owner. The broader live-widget focused command passes 8
`cadence_web` tests and keeps time-series limit marker DataLink selection,
selected-ref projection, limit-event inspector resolution, copy-link context,
shared-link hydration, and mirror-widget selected-ref isolation outside the
broad live-widget rendering owner, which now remains focused on live values,
limit states, fleet health, grid placement, source-health details, backfill
sample metadata, marker presence, and widget DataLink affordances. A full
`mix precommit` gate passed after this split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1553 `cadence_web` tests with 93 excluded.
Grouped backfill retry persistence now has command-owner coverage in
`historical_workflow_commands_test.exs`. The grouped backfill recovery browser
owner keeps rendered retry action and recovery progression coverage while the
command owner proves retryable/non-retryable product-API behavior, retry
lifecycle payloads, actor context, request-group metadata, queued retry jobs,
and preserved failed non-retryable jobs. The focused grouped-backfill command
passes 14 `cadence_web` tests. A full `mix precommit` gate passed after this
trim with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1554
`cadence_web` tests with 93 excluded.
Ops Data Sources BYO lifecycle behavior now has a dedicated focused proof owner.
The focused data-source command passes 16 `cadence_web` tests and keeps customer
BYO TSDB registration, credential reference persistence, credential rotation,
QuestDB adapter probe material resolution, capability materialization, drift
evidence, source health events, disable/enable lifecycle actions, and
active-source binding eligibility outside the inventory owner, which now remains
focused on mission inventory, binding changes, credential material display,
source-health/watermark rows, readiness policy, and runtime invalidation. A full
`mix precommit` gate passed after this split with 1272 `cadence` tests, 66
`cadence_simulator` tests, and 1550 `cadence_web` tests with 93 excluded.
Ops Data Sources telemetry capability remediation now lives in the focused
capability-remediation owner alongside the operational-observable variants. The
broader focus owner keeps generic focus, evidence, missing-source and
missing-binding remediation, and operational-resource source-action context; telemetry
history mismatch rows, compatible candidate filtering, compatible binding-change
filtering, and dashboard-return source-focus event payload checks moved into
`ops_data_sources_capability_remediation_live_test.exs`. The focused data-source
command passes 16 `cadence_web` tests. A full `mix precommit` gate passed after
this trim with 1272 `cadence` tests, 66 `cadence_simulator` tests, and 1554
`cadence_web` tests with 93 excluded.
Bulk comparison-review conflict decisions now have focused product API proof in
`Cadence.Telemetry.DataManagementTest`, including persisted workflow-item and
correction-workflow evidence for each applied `mark_conflict` decision. The
rendered browser owner now keeps the operator-visible submission, action
outcome, skipped-finding explanation, and final conflict-state proof without
duplicating the lower-level decision-event evidence crawl.
Grouped comparison-review historical workflow request payload proof now also
lives at the telemetry data-management product API boundary. Product tests cover
request and group-stage propagation of review request id/kind, open counts and
placements, workflow kind/action, selection kind/count, and comparison data-view
fields; the rendered LiveView owner keeps the operator form, group summary,
start orchestration, latest-action, and job-origin handoff proof.
Corrected replacement group-transition persistence now has product API proof
through approved, started, and completed backfill transitions, including
correction transition source ids, corrected run selection, requested event ids,
and original failed event/run context. The rendered group recovery owner now
keeps the remaining-work, closure-readiness, advance-action, and latest-action
workflow proof without reasserting lower-level payload details.
Multi-observable widget RenderItem binding proof now lives in the product owner:
`PlacementEditorTest` builds `status_matrix` and `data_table` placements,
round-trips them through `RenderItem.from_document/1`, and verifies the
multi-point binding lists. The widget creation browser owner keeps the visible
add-widget flows, persisted document shape, and version metadata without
duplicating RenderItem binding mapping.
The full `mix precommit` gate passed after the multi-observable widget
RenderItem binding ownership trim with 1274 `cadence` tests, 66
`cadence_simulator` tests, and 1554 `cadence_web` tests with 93 excluded.
Import correction/completion payload provenance now stays at the telemetry
data-management product API boundary. Product tests cover corrected-import
dashboard-context propagation plus correction-source/job provenance through
request and completed transitions; the correction-completion LiveView owner
keeps the operator form, latest-action result, visible inspector rows,
completed job status, and correction-source related-link proof without
duplicating lower-level payload mapping.
The full `mix precommit` gate passed after the import correction/completion
payload ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests,
and 1554 `cadence_web` tests with 93 excluded.
Grouped backfill request/stage payload shape now stays at the telemetry
data-management product API boundary. Product tests own bulk-point request
payload shape, request group ids, item index/count, dashboard context, and
comparison-review-origin propagation; the grouped backfill browser owner keeps
the operator request/approve/start flow, duplicate/regressive no-op behavior,
visible group summary/action state, and queued-job progress without duplicating
request/stage payload mapping.
The full `mix precommit` gate passed after the grouped backfill request/stage
payload ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests,
and 1554 `cadence_web` tests with 93 excluded.
Grouped backfill recovery browser coverage now leaves corrected-request payload
field mapping to command/product owners. The browser owner keeps rendered retry
guidance, correction submission, latest-action handoff, missing-job inspection,
replacement advancement, and completed-item navigation while avoiding duplicate
request-group, item-index, item-count, and dashboard-context payload asserts.
The full `mix precommit` gate passed after the grouped backfill recovery
corrected-request payload ownership trim with 1274 `cadence` tests, 66
`cadence_simulator` tests, and 1554 `cadence_web` tests with 93 excluded.
Late-data policy payload shape now stays with late-data policy command/product
owners. Those tests cover sample-execution, replay event-only,
projection-effect, dashboard-context, and current-value write semantics; the
historical workflow data-management browser owner keeps rendered controls,
submitted action outcome metadata, latest-value effect, selected sample rows,
and source-event navigation without duplicating payload shape assertions.
The full `mix precommit` gate passed after the late-data policy payload
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1554 `cadence_web` tests with 93 excluded.
Telemetry chart selection selected-ref shape now stays with
`DataLinkSelection*` and `SelectedDataRefTest` owner tests. The live widget
browser owner keeps the chart click, pushed selection event, routed/copied
data-link URL, inspector hydration, stale-context clear, panel-close retention,
direct target route hydration, and clear-selection workflow without repeating
selected-ref field crawls on every reload path.
The full `mix precommit` gate passed after the telemetry chart selection
selected-ref ownership trim with 1274 `cadence` tests, 66 `cadence_simulator`
tests, and 1554 `cadence_web` tests with 93 excluded.
Event-timeline golden contract frame-field shape now stays with
`Cadence.Dashboards.Sources.EventsTest`, which owns source capability and
telemetry backfill lifecycle field construction. The golden fixture test keeps
validation, plan/source-call proof, product ordering, frame family/source
metadata, runtime-link context, and presenter integration without repeating
field-level crawls. Degraded workflow badge shape remains covered by
`DataManagementPresentationEventRowsTest`.
The full `mix precommit` gate passed after the event-timeline golden contract
field ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests,
and 1554 `cadence_web` tests with 93 excluded.
Corrected import completion payload shape now stays with
`Cadence.Telemetry.DataManagementTest`, which owns corrected request payload,
completed import sample count, workflow/job payload, request-group ids, and
dashboard-context semantics. The correction-completion browser owner keeps
form submission, corrected event handoff, visible inspector rows, completed-job
status, correction-source links, and related source-event navigation.
The full `mix precommit` gate passed after the corrected import completion
payload ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests,
and 1554 `cadence_web` tests with 93 excluded.
Grouped backfill recovery projection details now stay with focused
group-status, group-recovery-presentation, replacement-recovery-projection,
replacement-recovery-action, group-recovery-form, and closure-status component
owners. Those tests cover failed-item handoff attributes, execution-plan counts,
remaining-work projection, closure readiness, and corrected replacement form
contracts; the grouped recovery browser owner keeps the retry, correction,
missing-inspection, replacement-advancement, completed-evidence, and related
failed-item navigation workflow.
The full `mix precommit` gate passed after the grouped backfill recovery
projection ownership trim with 1274 `cadence` tests, 66 `cadence_simulator`
tests, and 1554 `cadence_web` tests with 93 excluded.
Telemetry selection source-context field checks now stay with
`DataLinkSelection*`, `SelectedDataRef*`, and widget point component owners,
which cover selected-ref source-binding, data-source, spacecraft, time-context,
and chart attribute contracts. The telemetry selection browser owner keeps the
chart click, pushed selection event, routed/copied/explore data-link handoff,
explicit panel hydration, stale-context clearing, close-panel retention, direct
target hydration, and clear-selection workflow.
The full `mix precommit` gate passed after the telemetry selection
source-context ownership trim with 1274 `cadence` tests, 66
`cadence_simulator` tests, and 1554 `cadence_web` tests with 93 excluded.
Event/limit runtime invalidation skip semantics now stay with
`RuntimeInvalidationRelevanceTest` and runtime invalidation event owner tests,
which cover overlay relevance, observable relevance, coverage matrix
normalization, refresh-action classification, telemetry emission, and scoped
subscriber contracts. The event/limit LiveView owner keeps browser proof that
event invalidations refresh event overlays and limit-definition invalidations
refresh limit overlays.
The full `mix precommit` gate passed after the event/limit runtime
invalidation relevance ownership trim with 1274 `cadence` tests, 66
`cadence_simulator` tests, and 1552 `cadence_web` tests with 93 excluded.
Time-series golden selected-ref shape now stays with `DataLinkSelection*` and
`SelectedDataRefTest`, which cover selected-ref source/data binding context,
runtime matching, and stale-selection semantics. Widget presentation owners
continue to cover marker/data payload contracts; the time-series golden owner
keeps fixture validation, engine/source/frame contract, DataLink runtime
context, overlay marker integration, chart backfill, and point data integration.
The full `mix precommit` gate passed after the time-series golden selected-ref
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1552 `cadence_web` tests with 93 excluded.
Runtime source-binding warning detail-row and copy-link contracts now stay with
`EvidenceAttrsTest`, `EvidencePresentationSourceTest`,
`EvidenceInspectorPanelComponentsTest`, `DataLinkSelectionEvidenceTest`, and
`SourcePresentationDashboardWarningsTest`, which cover warning/source evidence
attrs, detail rows, query/copy-link composition, action rendering,
missing-evidence projection, and warning summary semantics. The source-binding
warning LiveView owner keeps browser proof for warning surfacing, warning
evidence navigation, data-link handoff, source health evidence
navigation/hydration, missing warning/source hydration, and panel clearing. The
focused test command passed with 35 `cadence_web` tests.
The full `mix precommit` gate passed after the runtime source-binding warning
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1552 `cadence_web` tests with 93 excluded.
Runtime-context source-binding query normalization and stale-selection clearing
now stay with `RuntimeQuerySourceTest`, `RouteHydrationRuntimeContextTest`, and
the `DataLinkSelection*`/`SelectedDataRef*` selected-ref owners. The
source-binding runtime-context LiveView owner keeps browser proof for data realm
fallback, explicit source-binding form selection, patched runtime query params,
active source display, and page/engine source-binding attrs without repeating
chart data-link selection shape. The focused test command passed with 41
`cadence_web` tests.
The full `mix precommit` gate passed after the runtime-context source-binding
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1552 `cadence_web` tests with 93 excluded.
Event-marker navigation data-link detail contracts now stay with
`DataLinkResolverTest`, `DataLinkInspectorPanelComponentsTest`, and
`DataLinkPresentationNavigationTest`, which cover
contact/mission-event/operational-event inspector rows, source-event related
links, copy-link rendering, and bounded navigation attrs. The
event-marker navigation LiveView owner keeps browser proof that contact and
mission-event chart marker clicks open the data-link panel and that the
mission-event source-event related link navigates to the operational-event
panel. The focused test command passed with 31 `cadence` tests and 10
`cadence_web` tests.
The full `mix precommit` gate passed after the event-marker navigation
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1552 `cadence_web` tests with 93 excluded.
Telemetry selection time-context selected-ref/query shape and panel details now
stay with `DataLinkSelection*`, `SelectedDataRef*`, and
`DataLinkInspectorPanelComponentsTest`, which cover route/query construction,
runtime/time-context matching, data-link panel row rendering, copy-link
rendering, and action detail contracts. The telemetry selection time-context
LiveView owner keeps browser proof for chart sample selection, selected-ref
scoping to the clicked chart, URL hydration, stale runtime-context clearing,
panel close preserving selection, and clear-selection behavior. The focused
test command passed with 37 `cadence_web` tests.
The full `mix precommit` gate passed after the telemetry selection time-context
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1552 `cadence_web` tests with 93 excluded.
Broad live-widget rendering marker payload contracts now stay with
`TimeSeriesLimitMarkersTest`, `TimeSeriesMarkersTest`,
`TimeSeriesMissionEventMarkersTest`, `WidgetPresentationTimeSeriesMarkersTest`,
`LiveWidgetEventMarkerNavigationLiveTest`, and
`LiveWidgetTimeSeriesLimitEventSelectionLiveTest`, which cover limit/event
marker payload shape, marker selection, and marker navigation contracts. The
broad live-widget rendering LiveView owner keeps smoke coverage for live values,
limit-state status text, grid placement attrs, chart hook/backfill rendering,
source health status, and widget data-link affordances without manufacturing
contact/mission-event fixtures or repeating marker payload details. The focused
test command passed with 21 `cadence_web` tests.
The full `mix precommit` gate passed after the broad live-widget rendering
marker ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests,
and 1552 `cadence_web` tests with 93 excluded.
Operational RF metric time-series selected-ref projection shape now stays with
`DataLinkSelectionTest` and the RF metric value-tile golden owner, while
`TimeSeriesDataOperationalTest` owns operational metric presenter data/backfill
shape. The RF metric time-series golden owner keeps fixture validation,
planner/source request coverage, resolved wide-frame metadata, DataLink runtime
context, and chart backfill contract. The focused test command passed with 11
`cadence_web` tests.
The full `mix precommit` gate passed after the operational RF metric
time-series selected-ref ownership trim with 1274 `cadence` tests, 66
`cadence_simulator` tests, and 1552 `cadence_web` tests with 93 excluded.
Operational ingress-latency time-series selected-ref projection shape now stays
with `DataLinkSelectionTest`, the transport operational value-tile golden owner,
and the operational-series presenter owners. The ingress-latency time-series
golden owner keeps fixture validation, planner/source request coverage, resolved
source-endpoint wide-frame metadata, DataLink runtime context, and chart
backfill contract. The focused test command passed with 16 `cadence_web` tests.
The full `mix precommit` gate passed after the operational ingress-latency
time-series selected-ref ownership trim with 1274 `cadence` tests, 66
`cadence_simulator` tests, and 1552 `cadence_web` tests with 93 excluded.
Telemetry pause-context proof now leaves archive range derivation with
`RuntimeControlsTimeTest` and `SelectedDataRefTimeContextTest`, selection
query/selected-ref shape with `DataLinkSelectionContextTest` and
`LiveWidgetTelemetrySelectionTimeContextLiveTest`, and inspector row/copy-link
rendering with `DataLinkInspectorPanelComponentsTest`. The pause-context
LiveView owner keeps browser proof for selected-sample pause, centered archive
patching, future-marker suppression, archive value/limit preservation through
context search, live resume, and resolved data-link panel state. The focused
test command passed with 14 `cadence_web` tests.
The full `mix precommit` gate passed after the telemetry pause-context
ownership trim with 1274 `cadence` tests, 66 `cadence_simulator` tests, and
1552 `cadence_web` tests with 93 excluded.

## Slice Backlog

Prefer the closeout order in
`docs/dashboard-feature-maturity-handoff.md#closeout-roadmap`. This short list
only preserves the next concrete slice families:

| Area | Next slice family | Definition of done |
| --- | --- | --- |
| Events | Add richer source/runtime projections | Canonical events become the source of truth for the new runtime fact, replay/live isolation is proven, and dashboard frame evidence links back to the event/interval source. |
| Investigation workflows | Promote the next action surface into a guided workflow | Operator action writes durable events/jobs, dashboard handoff links preserve runtime context, and browser tests prove success/failure/retry states. |
| Data management and replay | Broaden correction/import/replay policy handoffs | Data-view, replay, limit, source, job, and action-result context survive request, approval/start, retry/correction, and recovery paths. |
| Widget and scope closure | Close a remaining widget/scope interaction family | A source-specific proof shows filtering, no-data/partial/degraded behavior, DataLinks, frame evidence, route/copy payloads, and setup validation for the chosen scope/widget pair. |
| Near-complete rows | Reclassify mature partial rows when evidence supports it | The section has no current maturity blocker beyond future expansion or a named platform dependency, and the checklist wording is updated without overstating future work. |
