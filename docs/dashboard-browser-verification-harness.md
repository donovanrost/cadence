# Dashboard Browser Verification Harness

This harness gives the dashboard feature a checked-in browser smoke path without
adding a Playwright/npm dependency. It launches Chrome or Chromium in headless
mode and talks to it through the Chrome DevTools Protocol from Node built-ins.

## Command

Run the checked-in viewport fixture through ExUnit:

```sh
MIX_ENV=test mix cmd --app cadence_web mix test test/cadence_web/assets/dashboard_viewport_smoke_test.exs
```

Run the rendered LiveView dashboard smoke through ExUnit:

```sh
MIX_ENV=test mix cmd --app cadence_web mix test test/cadence_web/assets/dashboard_rendered_viewport_smoke_test.exs
```

Run the browser script directly:

```sh
node apps/cadence_web/assets/test/dashboard_viewport_smoke.mjs
```

To point the same harness at another static artifact or running page:

```sh
node apps/cadence_web/assets/test/dashboard_viewport_smoke.mjs --url http://127.0.0.1:4001/missions/<mission-id>/ops/dashboards/<dashboard-id>
node apps/cadence_web/assets/test/dashboard_viewport_smoke.mjs --profile rendered-dashboard --html /tmp/rendered-dashboard.html
node apps/cadence_web/assets/test/dashboard_viewport_smoke.mjs --profile live-dashboard --url http://localhost:4001/missions/<mission-id>/ops/dashboards/<dashboard-id> --login-url http://localhost:4001/sign-in --login-email operator@example.test --login-password password
```

## Test Isolation

The rendered LiveView smoke suite runs inside `CadenceWeb.ConnCase` with
`async: false`, so `ConnCase` owns the SQL sandbox checkout and starts it in
shared mode for the test. The in-process Bandit endpoint used by the browser
suite should not call `Ecto.Adapters.SQL.Sandbox.mode/2` again; doing so makes
the browser harness compete with the case template for ownership mode and can
leave later assertions coupled to a stale or replaced owner. Endpoint/request
processes should receive the existing `sandbox_owner` and use the existing
browser-test allowance hooks when a request process needs explicit ownership
access.

Long browser scenarios can run past Ecto's default sandbox ownership timeout.
Those suites should opt into a module or test tag such as
`sandbox_ownership_timeout: 600_000` so `CadenceWeb.ConnCase` extends only that
test owner's checkout lifetime instead of raising the timeout globally for every
web test.

The browser script has named interaction modes. `full` is the default and runs
the viewport plus live interaction scenario. `completed-workflow`,
`retry-workflow`, `correction-workflow`, `closure-completion-workflow`,
`group-job-recovery-workflow`, `group-retry-skipped-workflow`,
`group-replacement-retry-workflow`, `group-replacement-stale-workflow`, and
`group-replacement-missing-job-workflow` run follow-on workflow inspection
scenarios that the ExUnit wrapper prepares with specific persisted events and
jobs. `group-replacement-mixed-workflow` opens a single request group with
missing, failed, and stale corrected-replacement jobs and verifies the live DOM
exposes the ordered closure action queue plus each row-level recovery control.
`comparison-review-bulk-decision` opens a prepared comparison-review queue
item and submits the bulk conflict-decision form through the browser. The same
mode can assert both all-success and degraded partial-failure outcomes, including
requested/applied/failed counts when one finding no longer has a resolvable
observation identity. `repeat-render`
verifies expanded repeated placements through the live GridStack DOM, reload,
lifecycle attributes, and edit-mode attachment. `source-endpoint-no-data`
opens a direct source-endpoint scoped dashboard with intentionally empty
telemetry and verifies the rendered source/query evidence, copy payload, and
inventory/health links preserve the endpoint context. The same pass renders
data-table, status-matrix, state-timeline, and event-timeline widgets in that
empty source-endpoint context and proves their body notices carry the `no_data`
lifecycle state without rendering placeholder rows. `contact-no-data` runs the
sibling contact-scoped case and verifies the resolved source endpoint is
preserved alongside the contact in evidence and source actions.
`partial-telemetry-time-series` opens an archive telemetry chart whose range
request asks for one populated observable and one empty observable. It verifies
the widget/source lifecycle is `partial`, the source badge and body notice are
warning-level, and the chart still renders only the returned series.
`partial-telemetry-data-table` opens a live/latest telemetry data table whose
request asks for one populated observable and one empty observable. It verifies
the widget/source lifecycle is `partial`, only the returned row renders, and
the returned row keeps telemetry-sample DataLinks, frame evidence, source
binding, data source, selected observable, and selected scope context.
`partial-telemetry-status-matrix` runs the same live/latest partial-row proof
for the status-matrix widget, proving row-grid widgets share the same partial
source contract and preserve returned-row actions/evidence without placeholder
rows for empty observables.
`empty-telemetry-value-tile` opens a live/latest telemetry value tile whose
single requested observable has no latest sample. It verifies the widget
lifecycle is `no_data`, source freshness remains `unknown` when watermark
confidence is absent, no value or sample DataLink is invented, and source badge
evidence preserves the source request, data source, binding, and selected
spacecraft scope.
`stale-telemetry-value-tile` opens a live/latest telemetry value tile with a
returned sample but no source watermark confidence. It verifies the widget
lifecycle is `stale`, the value still renders, the source badge remains
unknown, and telemetry-sample DataLinks plus widget-frame evidence preserve the
sample, source, binding, observable, and selected spacecraft scope.
`fresh-telemetry-value-tile` opens the same live/latest telemetry shape after a
persisted source-level watermark is recorded for the telemetry data source. It
verifies the widget returns to `ready`, source status is `fresh` with
`best_effort` confidence, source warning badges disappear, and frame evidence
still preserves source, binding, observable, and spacecraft scope.
`telemetry-watermark-marker-evidence` opens an archive or replay telemetry
time-series chart with a retention-gap watermark cursor. It verifies
retention-gap and source-watermark cursor markers preserve source request,
realm, time mode, time axis, replay run, requested realm/data-view context, and
open source evidence. The archive fixture proves the cursor can come from a
durable source-watermark status, not only an adapter-returned in-memory
watermark, and that the chart x-domain includes operational marker intervals
even when a retention gap sits before the first returned telemetry sample. When
the fixture seeds a persisted source-watermark event and opts the widget into
`:events`, the same mode also proves the telemetry time-series chart renders a
`source_watermark_event` overlay marker and opens the resolved source-watermark
DataLink without losing data source, binding, dataset, replay, placement,
timestamp, or copy-payload context. The archive fixture also seeds unrelated
telemetry watermark events for another binding and another dataset, then
verifies the time-series overlay excludes both.
`runtime-context-source-endpoint-batch` opens a context-bound dashboard,
searches setup-backed source endpoints through the runtime context selector,
clicks the batch source-endpoint action, verifies the selected badge/root attrs
and URL carry `scope_kind=source_endpoint` plus comma-delimited `scope_ids`,
then clears back to the dashboard default context without leaving stale scope
query params behind.
`runtime-context-spacecraft-batch` runs the same operator path for spacecraft,
proving spacecraft search results can be promoted to a multi-spacecraft
dashboard scope with `scope_kind=spacecraft` and durable comma-delimited
`scope_ids`, then cleared back to the dashboard default context.
`runtime-context-contact-batch` runs the same operator path for scheduled
contacts, proving contact search results can be promoted to a multi-contact
dashboard scope with `scope_kind=contact` and durable comma-delimited
`scope_ids`, then cleared back to the dashboard default context.
`runtime-context-ground-station-batch` runs the same operator path for
setup-backed ground stations, proving ground-station search results can be
promoted to `scope_kind=ground_station` plus durable comma-delimited
`scope_ids`, then cleared back to the dashboard default context.
`runtime-context-link-batch` runs the same operator path for setup-backed link
assignments, proving link search results can be promoted to `scope_kind=link`
plus durable comma-delimited `scope_ids`, then cleared back to the dashboard
default context.
`source-endpoint-operational-resource` opens a source-endpoint scoped
operational-observable dashboard, verifies transport rows are filtered by that
scope, clicks the row-level transport DataLink, and checks the inspector/copy
payload preserve scope, data source, and source binding.
`ground-station-operational-resource` runs the same browser path for
ground-station scope, including station setup resolution and related transport
row filtering.
`link-operational-resource` runs the same browser path for link scope,
including scoped RF-lock row filtering, transport setup resolution, and
DataLink/copy payload preservation of link, data source, and source binding
context.
`operational-rf-state-timeline` opens a link-scoped RF state timeline with
deterministic RF lock/frame-sync event history, verifies scoped timeline lanes
and transition rows preserve operational source context, filters unrelated link
history, then opens a row-level transport DataLink and checks the inspector/copy
payload preserve link scope plus selected transport evidence. The same mode can
also run against replay-scoped default operational-observable state events and
assert replay realm, replay run, replay source binding, and replay dataset
metadata survive the rendered timeline, DataLink route, inspector, and copy
payload. In replay mode it also opens frame evidence, proves native RF interval
evidence refs render as clickable DataLink handoffs, and resolves the selected
RF interval while preserving replay/source context.
`operational-connection-state-timeline` opens a ground-station scoped
connection-state timeline with deterministic transport and ground-station
connection facts, verifies scoped timeline lanes and transition rows preserve
operational source context, filters unrelated transport/station history, opens
row-level frame evidence, proves native transport/ground-station connection
interval evidence refs render as clickable DataLink handoffs, and resolves the
selected interval while preserving ground-station, data-source, and
source-binding context. Multi-transport mode also opens a non-primary beta
transport row DataLink and frame-evidence action, proving the URL and copy
payload preserve both the dashboard `scope_ids` set and selected evidence/link
context. Multi-source-endpoint mode applies the same proof to source-endpoint
`scope_ids`, including non-primary beta transport and ground-station rows,
frame evidence, native interval evidence handoffs, and selected-resource
DataLink routing without collapsing the dashboard scope set.
`operational-transport-execution-state-timeline` opens a transport-scoped
transport execution state timeline with deterministic operational-event-backed
interval history, verifies scoped timeline lanes and transition rows preserve
operational source context, filters unrelated transport history, then opens a
row-level transport DataLink and checks the inspector/copy payload preserve
transport scope plus selected transport evidence.
`operational-metric-value-tile` opens a transport-scoped operational metric
value tile, verifies the widget-level transport, source-endpoint, and
ground-station DataLinks preserve operational source context, clicks the
transport DataLink, and checks the inspector/copy payload preserve the selected
scope, data source, source binding, and link-assignment evidence.
`operational-unsupported-scope-value-tile` opens a mission-scoped operational
metric value tile for a transport-scoped bit-rate observable, proving the
planner's `unsupported_observable_scope` warning renders as a blocked
unsupported lifecycle plus lifecycle-tagged body notice, with no chart hook or
value DataLinks instead of running a mis-scoped source request.
`operational-rf-metric-value-tile` opens a link-scoped RF SNR value tile,
verifies the missing-snapshot source state remains visible while transport,
source-endpoint, and ground-station DataLinks preserve operational source
context, clicks the transport DataLink, and checks the inspector/copy payload
preserve link scope plus selected transport evidence.
`operational-metric-missing-snapshot-value-tile` opens the same widget shape
against a configured transport without runtime metric data, verifies the
missing-snapshot source warning renders as an unknown/warning source state,
then opens the transport DataLink and checks the inspector/copy payload preserve
the row-specific selected transport id with operational source context.
`operational-metric-replay-time-series` opens replay-scoped RF SNR and
transport-bitrate time-series charts backed by canonical operational-observable
metric events, verifies only the selected replay run contributes chart samples,
and checks the rendered hooks preserve replay realm, replay run, source binding,
data source, scope, and point target metadata. It clicks the multi-series
bitrate chart legend to hide/show one series, proves the last visible series
cannot be hidden, clicks a mixed-unit RF chart axis control from unit-grouped to
shared and back, then clicks rendered chart points and verifies the transport
DataLink inspectors, routes, and copy payloads preserve link scope, selected
transport, replay run, data source, and source binding.
`operational-contact-phase-timeline` opens a contact-scoped state timeline
seeded with scheduled and realized contact lifecycle rows, verifies unrelated
contacts are filtered out, opens the realized contact DataLink, and checks frame
evidence preserves contact query scope.
`operational-contact-phase-replay-timeline` opens the same contact-projection
timeline in replay mode with a replay operational-observables binding, then
verifies rendered rows, the realized-contact DataLink, frame evidence, route
params, and copy payloads preserve replay realm, replay run, data source, source
binding, dataset, and contact query scope.
`operational-contact-phase-mission-timeline` opens a mission-scoped state
timeline, verifies all current-mission contact lanes render while a different
mission's contact is absent, opens a scheduled-contact DataLink, and checks row
frame evidence preserves mission query scope through route and copy context. Its
`operational-contact-phase-multi-contact-timeline` variant opens the same
widget with comma-delimited contact `scope_ids`, verifies selected alpha and
beta contact lanes render while gamma is filtered out, and proves the
non-primary beta contact DataLink plus row frame evidence preserve
`scope_ids`/`selected_scope_ids` route and copy context.
`operational-contact-phase-spacecraft-timeline` opens the same state timeline
under spacecraft scope, verifies contact lanes are filtered through
source-endpoint ownership, opens the realized contact DataLink, and checks row
frame evidence preserves the spacecraft query through the legacy
`spacecraft_id` route parameter while keeping the selected scope metadata on
`selected_scope_kind`/`selected_scope_id`.
`operational-contact-phase-source-endpoint-timeline` and
`operational-contact-phase-ground-station-timeline` exercise the same contact
phase state-timeline contract for operational-resource scopes. They verify
contact lanes are filtered through source endpoint refs, with ground-station
scope resolved through source-endpoint metadata, and prove the realized-contact
DataLink plus row frame evidence preserve the generic `scope_kind`/`scope_id`
route and copy context.
Their `operational-contact-phase-multi-source-endpoint-timeline` and
`operational-contact-phase-multi-ground-station-timeline` variants open
alpha+beta resource scopes with `scope_ids`, verify both contact lanes render
while gamma is filtered out, and prove a non-primary beta contact DataLink plus
row frame evidence preserve `scope_ids`/`selected_scope_ids` separately from
the selected contact target.
`operational-command-queue-depth` opens a mission-scoped status matrix seeded
with two pending command queue entries and one released entry, verifies the
rendered aggregate row counts only pending commands, confirms it does not invent
a resource DataLink, and opens frame evidence to prove logical source, source
request, data source, source binding, rendered query-scope attrs, selected
evidence scope params, and mission-scope copy context survive the browser route.
The same mode also covers a multi-spacecraft dashboard scope, proving command
queue filtering counts only the selected spacecraft set, renders the row as an
aggregate over the full comma-delimited `scope_ids` set rather than the first
spacecraft, avoids an invented single-resource DataLink, and preserves both
`scope_ids` and `selected_scope_ids` through evidence route/copy payloads.
Its source-endpoint value-tile variant also opens widget-level frame evidence
and proves the header action preserves the selected query scope through
`selected_scope_kind`/`selected_scope_id` while leaving `selected_scope_ids`
for multi-scope selections.
`operational-data-table-command-queue` runs the same mission aggregate command
queue path through a `cadence.data_table` widget, verifies the rendered table row
preserves the public data-table source attributes and aggregate count, confirms
it does not invent a resource DataLink, and opens frame evidence to prove source
request, data source, source binding, rendered query-scope attrs, selected
evidence scope params, and mission-scope copy context survive the browser route.
`mixed-operational-data-table` binds one source-endpoint scoped data table to
`commanding.queue_depth` and `ingress.processing_latency_ms`, proving the
presenter flattens separate operational product frames into distinct table rows,
preserves each row's product family/capability/source context, keeps
source-endpoint DataLinks on both rows, opens both row DataLinks, opens the
command row frame evidence, and opens ingress row frame evidence back to the
canonical metric-sample operational event. When called with expected lifecycle
and warning-code arguments, the same mode also proves a stale ingress metric
keeps the mixed table stale while preserving row actions and ingress row
warning metadata. With degraded source-health arguments, it proves the mixed
table keeps ready row data while surfacing degraded widget source status, opens
source evidence from the source badge, opens the row source-health event
DataLink, and preserves the command/ingress row DataLinks and frame evidence.

The canonical metric-sample event assertion above describes the current
migration implementation. ADR-019 removes per-result ingress-latency events;
the successor browser contract must preserve the row, scope, freshness, and
resource DataLinks while sourcing live data from runtime health and historical
data from the metrics/time-series boundary. It must not require an invented
operational-event evidence reference for each numerical point.

`operational-ingress-latency` opens a source-endpoint scoped status matrix
seeded through the telemetry ingress persistence write path, verifies the
durable selected endpoint latency renders while a second endpoint is filtered
out, opens the row-level source-endpoint DataLink, verifies its inspector and
copy payload preserve source, binding, and scope context, and opens frame
evidence to prove logical source, source request, data source, source binding,
and source-endpoint scope survive the browser route.
`operational-ingress-latency-multi-spacecraft` opens a spacecraft-scoped status
matrix with comma-delimited `scope_ids`, seeds durable ingress latency samples
through the same write path for alpha, beta, and unselected gamma endpoints,
verifies only alpha and beta endpoint rows render, proves gamma is filtered
out, and checks endpoint DataLinks plus row frame evidence preserve the
spacecraft comparison scope through `scope_ids` and `selected_scope_ids`.
`operational-ingress-latency-time-series` opens a multi-source-endpoint scoped
raw-series time-series widget seeded through the same telemetry ingress write
path, verifies all selected endpoint samples render through the uPlot chart,
checks chart backfill point metadata carries source-endpoint DataLinks, opens the
rendered source-endpoint DataLink to prove source, binding, placement, and
scope copy context survive the browser route, checks widget source-status and
query diagnostics preserve source identity plus the multi-endpoint query scope,
and opens query/widget-level frame evidence to prove metric-history header
evidence preserves source identity plus `scope_ids`/`selected_scope_ids` query
scope in the route and copy payload.
`replay-mission-timeline-managed-runtime` opens a replay-scoped event timeline
dashboard seeded with managed runtime operational events for two replay runs,
then verifies the rendered browser row contains only the selected replay run's
managed action, replay events binding, events data source, replay dataset,
operational event id, and mission-event DataLink.
`replay-contact-interval` opens a replay-scoped event timeline dashboard seeded
with scheduled contact interval operational events for two replay runs, then
verifies only the selected replay run's contact row renders with replay events
source context, opens the row-level contact DataLink inspector, and proves the
patched route/copy payload preserves selected contact, replay run, and source
binding identity.
`byo-source-readiness` opens the mission data-source inventory, verifies a
customer-owned QuestDB source row exposes credential state, provider, version,
resolved material state, public endpoint, connection-test evidence, and redacted
secret field names, and checks browser-rendered text does not leak secret token
material.

If Chrome is not in a standard location, set `CHROME_BIN` or pass
`--chrome-bin`:

```sh
CHROME_BIN=/path/to/chrome node apps/cadence_web/assets/test/dashboard_viewport_smoke.mjs
```

## What It Proves Today

The default fixture verifies desktop and narrow mobile viewport invariants:

- no horizontal page overflow
- dashboard grid items render with non-zero size
- a chart surface, inspector panel, and copy action are present
- critical regions are not offscreen
- peer critical regions do not overlap
- marked text and controls do not overflow their containers

`dashboard_rendered_viewport_smoke_test.exs` now seeds a mission, spacecraft,
telemetry samples, and a real dashboard document, renders the LiveView route,
writes the rendered Phoenix dashboard HTML to a temporary artifact, runs
`mix assets.build`, links the compiled `app.css`, verifies the compiled `app.js`
exists, and runs the same Chrome smoke in `rendered-dashboard` profile. That
profile verifies real dashboard selectors such as `#ops-dashboard-show-page`,
`DashboardGrid`, `TelemetryChart`, `#dashboard-panel`, and
`#dashboard-data-link-copy-link`.

The same ExUnit file also runs the harness in `live-dashboard` profile against a
real authenticated Phoenix endpoint started inside the test. It signs in through
the browser, navigates to the dashboard route, waits for the mounted LiveSocket,
verifies the DashboardGrid hook's GridStack-mounted marker, verifies the
TelemetryChart hook rendered a uPlot surface, clicks a real ClipboardButton, and
checks that the selected data-link copy control preserves the selected panel,
target, id, and placement in its deep-link payload. It also checks desktop plus
narrow viewport invariants against the full ops layout. It
also runs a wide-viewport interaction pass that opens and closes the dashboard
action menu, proves runtime context controls are visible, toggles edit layout
mode, verifies GridStack interaction handles arm/disarm, mutates a widget
layout through the real GridStack instance, reloads the selected dashboard URL,
and proves both the saved layout and data-link panel hydrate again. The same
pass opens source-selection drilldowns, version history, runtime diagnostics,
and the historical workflow request form to prove those workflow surfaces render
with their key context fields in a real browser. It also submits a confirmed
historical backfill request from the browser and verifies the resulting
data-link workflow controls expose a successful request outcome with target
event and run identifiers. From that resulting data-link panel, the harness
then records the follow-on approved stage transition through the real stage
form and verifies the normalized `stage_transition` outcome, updated workflow
stage, and latest-action target event/run identifiers. It then records the
started stage transition, verifies the queued job id/status in the browser, and
the ExUnit wrapper verifies the persisted `backfill_started` event and queued
historical workflow job. The wrapper then runs the queued job, opens the
completed lifecycle event in a second authenticated browser pass, and verifies
the completed inspector state, workflow explanation, sample-count field, and
late-data policy controls. That pass now switches the runtime limit mode to
`compare`, submits the late-data policy form from the browser, verifies the
latest-action metadata preserves the compare limit mode, and the ExUnit wrapper
asserts the persisted late-data policy lifecycle event carries the same durable
dashboard limit context. The wrapper also seeds completed lifecycle events with
durable `current` and `recomputed` dashboard contexts, reopens each event in the
browser, submits sample-execution late-data policy decisions against already
stored source samples, verifies latest-action metadata preserves the selected
limit mode, and asserts the persisted accepted policy event carries the same
dashboard context. It also opens a failed workflow event, verifies the rendered
event-timeline row exposes the failed workflow run id, job id, status, and
failure reason, clicks the browser retry action, and verifies that the retried
lifecycle event is selected, the latest-action metadata points at the retried
event, and the original failed job is requeued. The retry browser pass also
verifies the latest-action result handoff link, grouped recovery execution plan,
and grouped execution audit for retried and recovered items. It also opens a
non-retryable request-group
context event, verifies the active failed-item handoff, clicks that handoff into
the failed-item inspector and correction form, verifies the unresolved failed
audit step and correction execution plan, submits the corrected workflow request
form from the browser, verifies that the corrected lifecycle event is selected,
and checks the latest-action metadata, correction-source fields, and explicit
request group/mode/item metadata from the submitted correction form. When the
corrected request belongs to a request
group, the same browser pass verifies the latest-action result handoff link,
corrected/recovered/recovery-task execution audit rows, the replacement
advancement execution plan, the recovery-plan advancement command, the
browser-created approved replacement event, the rendered recovery handoff
replacement task, matching group approve-control correction-task metadata, and
the remaining replacement-work summary as it moves from approve to start to
complete to done. A separate closure-completion browser pass opens a seeded
recovery group whose corrected replacement is done and whose remaining workflow
job is completed, verifies the ready-to-complete closure contract, submits the
scoped completion form, and verifies the rendered latest-action metadata for the
browser-created group completion event.
Another grouped-job recovery browser pass seeds a mixed request group through the
public workflow lifecycle/job APIs, runs one background job to completion, records
one retryable failed job/event, and runs one worker job to a non-retryable
failure. It opens the worker-generated failed lifecycle event and verifies that
grouped job progress, execution audit, closure readiness, retry command
confirmation, and failed-item correction handoffs all reflect those mixed
outcomes. The same pass submits the group retry, verifies the retry latest-action
metadata and preserved non-retryable handoff, then follows that real worker
failure through browser-submitted correction, corrected replacement
approval/start/completion, and persisted lifecycle assertions. The fixture
carries a comparison-review origin, and the pass verifies the group recovery
panel, failed job panel, corrected event view, and persisted replacement
lifecycle events keep the review request and placement context.
A separate group-retry skipped browser pass seeds a retryable failed job plus a
retryable failed lifecycle event with no backing job row, submits the group
retry, and verifies the latest-action panel exposes skipped run id, event id,
item metadata, and `job_status_missing` reason alongside the successful retried
job.
Replacement-specific browser passes also verify a failed corrected replacement
can be retried with replacement-run scope, a stale running corrected replacement
can be requeued with an authoritative lifecycle event, and a corrected
replacement that has lifecycle progress but no backing job row renders as
missing job evidence. The missing-job pass asserts the replacement run, missing
action, missing/blocked counts, `inspect_job_state` closure status, and absence
of a completion submit while the evidence gap remains.
The live browser pass also switches into comparison
mode,
submits an open-findings review request, opens the explicit open-review queue,
resolves the request with a browser-entered reason, and verifies that the
rendered activity log and persisted lifecycle events agree on the request,
source placement, resolution event, disposition, and reason.
The repeat-render browser pass opens a dashboard whose default scope expands a
status matrix once per spacecraft, verifies the expanded `gs-id` values,
layout attributes, lifecycle attributes, and visibility, reloads the page, and
then proves the repeated items are attached to GridStack in edit mode.
Operational metric no-data browser passes wait for the full source-state
contract before assertions: widget lifecycle, source state, data state, empty
reason, source ids, body notice, and source badge all have to be present before
the harness samples DOM attributes. Focused component/model tests cover the same
source badge, row-widget empty body notices, and widget shell attributes so the
browser harness is not the only guard for that DOM contract.

This is intentionally a browser/viewport proof, not a replacement for LiveView
contract tests or JavaScript hook unit tests.

## Remaining Maturity Work

The harness now proves the browser runner, viewport invariants, compiled CSS
compatibility, asset bundle build health, rendered dashboard DOM structure,
comparison review request/resolution, comparison-review bulk correction decisions,
including degraded partial-failure outcomes,
revision-decision limit-mode preservation, historical workflow
request/approval/start/completion/retry/correction, corrected replacement group
control metadata, workflow latest-action handoff links, grouped execution audit
rows, grouped recovery execution-plan metadata, browser-executed corrected
replacement approval/start/completion with remaining-work pending/completed
state, ready-to-complete closure submission, real grouped worker completion/failure
recovery rendering through mixed retry/correction review-origin recovery and
corrected replacement completion, skipped group-retry disposition metadata,
replacement-scoped retry, stale replacement
requeue, missing replacement-job evidence blocking closure, repeated placement render identity,
selected data-link copy/deep-link payloads, direct source-endpoint no-data
evidence links plus data-table/status-matrix/state-timeline/event-timeline
`no_data` body notices, partial telemetry range lifecycle with returned-series
chart rendering, contact-scoped no-data evidence links, source-endpoint scoped
operational-resource row DataLinks, ground-station scoped
operational-resource row DataLinks, link-scoped operational-resource row
DataLinks, mission-scoped
command queue depth aggregate evidence, source-endpoint command queue value-tile
DataLinks plus query-scoped widget-frame evidence, mission-scoped operational
data-table aggregate evidence, source-endpoint scoped mixed operational
data-table row flattening with row DataLinks/frame evidence, source-endpoint
scoped ingress latency durable metric row DataLink plus frame evidence,
source-endpoint scoped ingress latency raw-series chart rendering with
point-level source-endpoint DataLink metadata and multi-scope query-scoped
widget-frame evidence,
replay-scoped managed-runtime mission timeline rows, replay-scoped contact
interval rows with contact inspector route/copy context, replay-scoped RF
SNR/transport-bitrate/mixed-unit metric history chart isolation plus chart
legend hide/show guarding, grouped/shared axis toggling, and chart-point
DataLink inspection, operational connection-state timeline interval evidence
handoffs,
and a live
authenticated route with mounted hooks, core
interactions, and real edit-mode layout mutation with reload persistence.
The next maturity steps are product workflow depth, not the browser harness
baseline itself.
