---
title: Dashboards & Telemetry Visualization Engine — Design
tags: [design, dashboards, telemetry, visualization, tsdb, query-engine, ops-console]
status: draft
created: 2026-06-13
updated: 2026-07-02
---

# Dashboards & Telemetry Visualization Engine — Design

> Status: **draft / proposed.** This describes the target architecture for
> Cadence's telemetry-visualization surface. It is **not** the current
> implementation — today's ops dashboards (`Cadence.Dashboards.Engine`,
> `CadenceWeb.OpsDashboard*Live`) are iterative
> product evidence, not a compatibility constraint. See §15 for the gap between this
> design and what ships today. Where this doc and an accepted ADR disagree, the
> ADR wins. This is a **long-term technical vision**, not a single-slice
> implementation plan; §13 names sequencing, not a requirement to build every
> capability at once.

## 1. Purpose

Define the architecture that lets operators use **Cadence** for mission
telemetry visualization instead of reaching for **Grafana** — both for live
monitoring and for retrospective analysis — without re-implementing Grafana.

## 2. Problem

Grafana is exceptional at generic data visualization. A telemetry product that
makes operators keep Grafana open for analysis has lost the surface. But we
cannot out-feature Grafana on generic panels, query editors, or its data-source
ecosystem — that is thousands of person-years of work.

Two concrete limitations of the original Cadence dashboard prototype make the
point:

1. **Live-only.** Widgets were hardwired to the current-value table
   (`Reads.Telemetry.latest_value/3`). There was no historical scrub/replay,
   no global time control — the thing operators live in ("show me the last
   contact"). A dashboard that cannot explain history is a wallboard, not a
   Grafana replacement.
2. **Source is not a variable.** "Where the data comes from" is baked into the
   widget type, so live vs. historical reads as two separate code paths.

## 3. Strategic thesis

**Grafana is a dashboard you look *at*. Cadence is a console you operate
*from*.** A Grafana panel is a line over a metrics store. A Cadence widget is
bound to a **cataloged observable**, so it inherits meaning Grafana cannot have:
units, calibration, limit definitions, quality, staleness, packet provenance,
spacecraft identity, contact context, and mission time.

We win on the axes where Grafana is structurally weak *because* it is
domain-agnostic, and we deliberately cede generic BI:

- **Catalog-bound** — limits/units/quality/colors come from Cadence's semantic
  catalogs and cannot drift. Zero-config correctness on every panel. (The
  existing promise, *"a widget can never disagree with the alarm system,"*
  extended to the whole surface.)
- **Constellation-native** — one dashboard flown over any spacecraft, tiled
  across all of them, or compared across a set. The thing Grafana templating
  approximates badly and Cadence does natively.
- **Mission-time & history** — Live ↔ Replay as one continuum, with pass /
  eclipse / event overlays on every axis.

We explicitly do **not** build: arbitrary SQL/PromQL over non-telemetry infra,
generic BI, or a third-party panel-plugin marketplace. Cadence owns the
spacecraft; ground-segment infra metrics stay in Grafana.

### 3.1 The sovereignty moat: meaning vs. bytes

Cadence will offer multiple storage models — a **managed TSDB** and a
**bring-your-own TSDB** for customers who must own their data (see
`project_tsdb_strategy`). The catalog-bound design makes this a
differentiator rather than a complication:

> **The customer owns the bytes; Cadence owns the meaning.**

Limits, units, display policies, freshness policies, and state coloring resolve
from Cadence's catalogs — never from the storage backend — so correctness holds
no matter where the data physically lives. Observation facts such as sample
quality, receipt time, generation time, and transport health still come from the
source; Cadence owns their **meaning**, not the bytes.

### 3.2 Observable registry: not everything is spacecraft telemetry

"Dictionary-native" is too narrow for dashboards. Spacecraft telemetry points
come from an uploaded telemetry dictionary, but operators also dashboard
Cadence-produced data: link bit rate, antenna connection state, contact phase,
command queue depth, ingest latency, file-transfer progress, and platform
health.

The shared abstraction is a **catalog-bound observable**: a named thing Cadence
can evaluate over mission time and a scope, with enough metadata to render it
correctly.

```
Observable
  ├─ identity:     observable_id, name, owner subsystem, version
  ├─ kind:         metric | state | event | interval
  ├─ value:        number | enum | boolean | string | duration
  ├─ scope:        mission | spacecraft | contact | ground_station | transport | link
  ├─ semantics:    unit?, allowed_values?, value_type?, display_policy
  ├─ health:       freshness_policy?, quality_policy?, state_color_policy?
  ├─ limits:       limit_definition refs or limit policy refs
  └─ provenance:   source subsystem, backend/source hints, catalog revision refs
```

Examples:

```yaml
observable_id: comms.transport.ksat_tcp.downlink_bitrate
owner: comms
kind: metric
value: number
unit: bps
scope: [mission, transport, contact]
freshness_policy: { stale_after_ms: 5000 }
```

```yaml
observable_id: ground.station.dss_14.connection_state
owner: ground
kind: state
value: enum
allowed_values: [connected, connecting, degraded, disconnected]
scope: [ground_station, contact]
state_color_policy: connection_state
freshness_policy: { stale_after_ms: 30000 }
```

The dashboard engine binds to **observable ids**, not only telemetry point ids.
The telemetry dictionary remains the authoritative catalog for spacecraft
telemetry; operational subsystems register their own observables through the
same semantic contract. Not every observable is telemetry, but every
dashboarded value should be semantically registered.

#### 3.2.1 Operational observable registry v0 contract

The operational observable registry is the semantic catalog for Cadence-produced
values. It is not the telemetry dictionary and it is not a metrics free-for-all.
It is where Cadence subsystems publish dashboardable values with stable
identity, scope, value semantics, freshness policy, and resolver ownership.

v0 should be compiled, first-party definitions only. User-defined and
third-party observables come later, after Cadence proves the model with its own
subsystems.

Registry API:

```elixir
@callback list_observables(filters :: keyword()) :: [ObservableDefinition.t()]
@callback fetch_observable(observable_id :: binary()) ::
  {:ok, ObservableDefinition.t()} | {:error, :unknown_observable}
@callback resolve_source(observable_id :: binary()) ::
  {:ok, logical_source :: atom()} | {:error, :unknown_observable}
@callback validate_binding(observable_id :: binary(), ScopeContext.t(), DataContext.t()) ::
  :ok | {:error, term()}
```

Definition shape:

```elixir
%ObservableDefinition{
  observable_id: "comms.transport.downlink_bitrate",
  version: 1,
  name: "Downlink Bit Rate",
  description: "Observed downlink byte/bit throughput for a transport path",
  owner: :comms,
  logical_source: :operational_observables,
  family: :transport,
  kind: :metric | :state | :event | :interval,
  value: %{
    type: :number | :enum | :boolean | :string | :duration,
    unit: "bps" | nil,
    allowed_values: [:connected, :degraded, :disconnected] | nil
  },
  scope: %{
    required: [:mission],
    optional: [:spacecraft, :contact, :ground_station, :transport, :link],
    cardinality: :one | :many | :aggregate
  },
  semantics: %{
    display_policy: :rate | :state | :duration | :count,
    state_color_policy: :connection_state | nil,
    freshness_policy: %{stale_after_ms: 5_000},
    quality_policy: :source_reported | :derived | nil
  },
  storage: %{
    mode: :projection | :stream | :tsdb | :adapter,
    resolver: Cadence.Dashboards.Sources.OperationalObservables.Comms,
    supports_history?: true,
    supports_latest?: true
  },
  lifecycle: %{
    status: :active | :deprecated | :removed,
    introduced_at: "2026-06-16",
    superseded_by: nil
  }
}
```

v0 observable families:

| Family | Example observables | Likely owner |
| --- | --- | --- |
| Contacts | contact phase, time to AOS/LOS, active station | `Contacts` |
| Comms transport | connection state, bytes in/out, reconnect count | `Comms` / `Transports` |
| Link/RF | bit rate, lock state, frame sync state, SNR/EbN0, symbol rate, Doppler | `Comms` / future RF adapters |
| Commanding | queue depth, release rate, pending verifications | `Commanding` |
| Ingest/platform | ingest latency, decom errors, storage write rate | ingest/runtime subsystems |
| File transfer | transaction state, progress, retransmits | future CFDP/downlink subsystem |

Operational observables differ from telemetry points:

- they are owned by Cadence subsystems, not uploaded telemetry dictionaries
- they may describe ground systems, links, queues, or runtime state
- they can be produced by projections, streams, or adapters, not only packet
  decomposition
- they still use the same Frame, widget, scope, data, freshness, and warning
  contracts as telemetry

Lifecycle rules:

- observable ids are stable and should not be repurposed
- breaking semantic changes require a new version or new observable id
- deprecated observables remain resolvable for saved dashboards when possible
- removed observables render unknown/unavailable placeholders, not crashes
- owner subsystems are responsible for resolver implementation and freshness
  semantics
- every observable advertised as source-backed must have adapter capability
  metadata, widget-frame support, and at least one runtime scope path; tests
  should fail if the semantic registry, source adapter, widget contracts, or
  scope policy drift apart

### 3.3 Implementation posture: greenfield bounded context

The current ops dashboard implementation is a first-pass prototype. It validates
product direction, but it does not constrain the target architecture. Any and
all current dashboard code can be replaced.

Implementation should therefore start as a new bounded context:

```text
Cadence.Dashboards
Cadence.Dashboards.Document
Cadence.Dashboards.Engine
Cadence.Dashboards.ObservableRegistry
Cadence.Dashboards.WidgetRegistry
Cadence.Dashboards.Frame
Cadence.Dashboards.Sources.Telemetry
Cadence.Dashboards.Sources.Limits
Cadence.Dashboards.Sources.Events
Cadence.Dashboards.Sources.OperationalObservables
```

The early `Cadence.Ops.*` dashboard stack has been retired. Its prototype
shape should not force schema compatibility, module naming, widget enums, or
LiveView state shape.

## 4. Conceptual model: runtime contexts

A Cadence dashboard has three first-class runtime contexts; everything composes
from them. (Grafana effectively has one that matters — time — plus user-defined
template variables.)

- **Time context** — Live ↔ historical, with a scrubber and pass-aware quick
  ranges.
- **Scope context** — the operational entity focus: spacecraft, contact, ground
  station, transport, link, mission, or a set/aggregate of those.
- **Data context** — the corpus and lane: flight, rehearsal, AI&T, simulation,
  replay, lab, or shadow ingest, plus the source-selection mode.

A widget is then just *a catalog-bound visualization evaluated at
`(observables, scope-context, time-context, data-context)`*. The three pillars
fall out directly:

| Pillar | Reduces to |
| --- | --- |
| Catalog-bound widgets | the viz, inheriting semantic metadata for free |
| Constellation-native | the scope context in `each` / `all` mode |
| Mission-time & history | the time variable spanning Live and Replay |
| Rehearsal / AI&T / BYO support | the data context selecting an isolated corpus |

This is also the key **model change** from the prototype: time and spacecraft
scope should not live primarily on each widget. The target model makes
time/scope/data dashboard-level runtime contexts that widgets inherit and may
override. Current per-widget bindings are useful evidence for product behavior,
not an implementation constraint.

## 5. Architecture

```
Dashboard document
  → runtime contexts                             # time, scope, data
  → dashboard engine
       → plan                                    # batched source requests
       → logical source .resolve(...)
            → physical backend adapter           # capability-aware; pluggable
       → Frame(s) + Overlay Frame(s)             # normalized, metadata-rich
  → widget renderers
```

Two layers of abstraction, drawn deliberately:

- **Logical sources** — *closed*, domain-defined, catalog-bound. The
  *meaning* layer.
- **Physical backends** — *pluggable* per source. The *bytes* layer.

### 5.1 Dashboard engine responsibilities

The dashboard engine is the technical boundary between saved dashboard intent
and rendered widgets. It is **not** a charting library. Its job is to evaluate
catalog-bound observables over time, operational scope, and data context, then
hand widgets normalized frames.

The engine owns:

1. **Variable resolution** — merge dashboard defaults, URL/session state, and
   widget overrides into a concrete `time_context`, `scope_context`, and
   `data_context`.
2. **Planning** — walk placements, read each widget type's data contract, and
   build a batched source plan. Multiple widgets asking for the same observable
   over the same range should resolve once.
3. **Source resolution** — call logical sources (`Telemetry`, `Limits`,
   `Events`, operational observables, etc.) without exposing physical backend
   details to widgets.
4. **Frame construction** — normalize heterogeneous reads into Frame objects
   with semantic field metadata.
5. **Decimation and shaping** — request backend pushdown where available and
   apply in-engine fallbacks where safe.
6. **Overlay attachment** — attach host-owned overlays such as limits, contacts,
   command annotations, quality, and staleness according to the widget data
   contract and dashboard defaults.
7. **Degradation** — return explicit warnings and partial frames for slow,
   unavailable, truncated, stale, or capability-limited sources.

#### 5.1.1 Dashboard engine contract

The engine is a **query planner + semantic frame builder**. It accepts a
dashboard document, runtime context, and interaction hints; it returns frames,
overlays, warnings, and live subscriptions. Renderers never call domain stores
directly.

Top-level request:

```elixir
%DashboardResolveRequest{
  organization_id: "...",
  mission_id: "...",
  dashboard_id: "dashboard_...",
  document: %DashboardDocument{},
  resolve_mode: :initial | :context_change | :live_tick | :stream_append,
  time_context: %TimeContext{},
  scope_context: %ScopeContext{},
  data_context: %DataContext{},
  interaction_context: %{
    viewport_width_px: 1200,
    viewport_height_px: 520,
    placement_sizes: %{
      "placement_1" => %{width_px: 640, height_px: 240}
    },
    cursor_time: nil,
    selected_placement_id: nil
  }
}
```

Runtime contexts may enter the engine from two boundaries. UI/API callers send
JSON-safe values such as ISO-8601 time strings. Internal callers may pass typed
values such as `DateTime` structs. Engine normalization should normalize plain
map keys (`"from"` → `:from`, `"primary"` → `:primary`) without recursively
destructuring structs; source adapters should receive typed values unchanged
until a storage/API boundary requires serialization.

`interaction_context` is part of the request because decimation targets are
display-dependent. A time-series panel that is 320 px wide should not request
the same sample budget as a full-width chart.

Widget types declare data needs to the registry:

```elixir
%WidgetDataContract{
  widget_type_id: "cadence.time_series",
  version: 1,
  frames: [
    %FrameRequestSpec{
      role: :primary,
      accepted_field_kinds: [:number],
      temporal?: true,
      min_fields: 1,
      max_fields: 8,
      sampling: :decimated_envelope,
      value_type: :engineering
    }
  ],
  overlays: [:limits, :events, :quality],
  live_mode: :appendable
}
```

The engine resolves each placement by combining:

```text
DashboardDocument defaults
+ URL/session runtime context
+ placement overrides
+ widget data contract
+ viewport/interaction hints
→ PlannedSourceRequest(s)
```

Internal planned source request:

```elixir
%PlannedSourceRequest{
  request_id: "source_req_...",
  organization_id: "...",
  mission_id: "...",
  logical_source: :telemetry,
  observables: ["tlm.hk.battery_voltage"],
  scope_context: %ScopeContext{},
  time_context: %TimeContext{},
  data_context: %DataContext{},
  value_type: :engineering,
  sampling: %{
    mode: :decimated_envelope,
    target_points: 1200,
    preserve: [:min, :max, :worst_limit_state, :quality, :validity]
  },
  overlays: [:limits],
  consumers: [
    %{placement_id: "placement_1", role: :primary}
  ]
}
```

Equivalent requests are batched before source resolution. "Equivalent" means
same tenant, mission, logical source, observables, concrete scope, concrete time
range, concrete data realm/source mode, value type, sampling mode, and overlay
requirements. A batched request can have many placement consumers, but should
never cross an organization or mission boundary.

Source behaviour:

```elixir
@callback capabilities() :: SourceCapabilities.t()
@callback plan(PlannedSourceRequest.t()) ::
  {:ok, SourceQuery.t()} | {:error, SourceWarning.t()}
@callback resolve(SourceQuery.t()) :: SourceResolveResult.t()
@callback subscribe(SourceQuery.t()) ::
  {:ok, [LiveSubscription.t()]} | {:error, SourceWarning.t()}
```

v0 implementation split:

- `Engine.plan/1` remains pure: validate the dashboard document, produce batched
  `PlannedSourceRequest`s, and map placements to planned request ids.
- The planner checks the v0 source capability surface before emitting primary
  requests. Adapter-level capabilities are advertised through
  `SourceRegistry.capabilities/1`; request-aware capabilities are resolved
  through `SourceRegistry.capabilities/2`, which merges the logical adapter
  contract with the selected `DataSource.capabilities`. If no truthful product
  exists, the planner omits that request and returns a placement-scoped
  `:unsupported_source_capability` warning with `fallback: :none`; it does not
  silently substitute a different product.
- Source-backed widget overlays are planned as independent source requests.
  In v0, requested `:limits` overlays become `logical_source: :limits` requests;
  scalar/latest primaries request `products: [:latest_state]`, while temporal
  primaries request `products: [:event_history]`. Unresolved overlays such as
  `:quality` remain on the primary request as explicit capability fallbacks.
- `Engine.resolve/2` executes a plan by dispatching each planned request through
  `SourceRegistry`, collecting `SourceResult`s, and fanning returned frames and
  warnings back to each request consumer placement.
- `SourceRegistry` is the adapter seam. It maps logical sources such as
  `:telemetry` through `DataSourceRegistry` to a concrete source binding and
  physical data source. The resolved data source supplies the adapter module;
  registry failures return structured source warnings. Plan-time registry
  failures, such as missing bindings or unsupported adapters, become
  placement-scoped warnings before execution starts.
- `DataSourceRegistry` v0 keeps in-memory fallback defaults for local
  bootstrap: shared managed QuestDB-backed flight telemetry and the Postgres
  latest-limit projection. It also has a persisted path through
  `Cadence.Dashboards.DataSources`, which stores `DataSource` and `DataBinding`
  rows and can be enabled for source resolution.
- Source adapters receive the resolved binding so frames and queries carry
  `binding_id`, `data_source_id`, `realm`, and `dataset` metadata rather than
  relying only on the request's loose `data_context`.
- Historical archive/range requests resolve source bindings from
  `dashboard_data_binding_events`, not only from the current projection row.
  The engine derives a `source_binding_at` timestamp from the planned request's
  time context and the registry reconstructs the event interval that was active
  at that instant. Returned `SourceResult` and `Frame` metadata include
  `source_binding_version`, `source_binding_event_id`, and
  `source_binding_interval` so historical frames can explain which physical
  backend and dataset supplied them.
- Telemetry bounded-history requests can segment one historical range across
  multiple source-binding intervals. `SourceRegistry` clips the planned request
  to each interval, dispatches each segment to its resolved data source, and
  concatenates compatible wide frames. Merged results replace single-binding
  metadata with `source_binding_segments` so operators can see which TSDB,
  dataset, binding version, and event backed each time slice.
- Segment merging is deliberately conservative. Requests that cannot be
  segmented yet still fail closed with `:source_binding_interval_ambiguous`, and
  incompatible segment frame shapes fail with
  `:source_binding_segment_merge_unsupported` rather than silently combining
  incompatible source products.
- Placement fan-out uses each planned request's `consumers`; primary frames land
  in `PlacementFrames.primary`, while non-primary roles land in
  `PlacementFrames.overlays`.

Source resolve result:

```elixir
%SourceResolveResult{
  request_id: "source_req_...",
  frames: [%Frame{}],
  overlays: %{limits: [%Frame{}], events: [%Frame{}]},
  warnings: [%ResolveWarning{}],
  watermarks: [%SourceWatermark{}],
  subscriptions: [%LiveSubscription{}]
}
```

Top-level engine result:

```elixir
%DashboardResolveResult{
  dashboard_id: "dashboard_...",
  resolve_mode: :initial,
  frames_by_placement: %{
    "placement_1" => %PlacementFrames{
      primary: [%Frame{}],
      overlays: %{limits: [%Frame{}], events: [%Frame{}]},
      warnings: [%ResolveWarning{}]
    }
  },
  dashboard_warnings: [%ResolveWarning{}],
  watermarks: [%SourceWatermark{}],
  subscriptions: [%LiveSubscription{}],
  plan_metadata: %{
    source_request_count: 4,
    batched_consumer_count: 11,
    executed_source_request_count: 4,
    source_selection_by_request_id: %{
      "source_req_..." => %{
        strategy: :current_binding | :historical_binding | :historical_segment,
        logical_source: :telemetry,
        requested_realm: :flight,
        requested_source_binding_id: "binding_..." | nil,
        requested_data_source_id: "managed_questdb_primary" | nil,
        requested_dataset: "flight" | nil,
        selected_source_binding_id: "binding_...",
        selected_data_source_id: "managed_questdb_primary",
        selected_dataset: "flight",
        candidate_count: 3,
        eligible_candidate_count: 1,
        candidates: [
          %{
            binding_id: "binding_...",
            data_source_id: "managed_questdb_primary",
            decision: :selected | :eligible | :not_selected | :rejected,
            reasons: [:logical_source_mismatch | :data_source_filter_mismatch | ...]
          }
        ]
      }
    },
    returned_frame_count: 9,
    degraded?: false
  }
}
```

Every source-backed frame and source result carries the same `source_selection`
map in `meta`. This is intentionally diagnostic rather than adapter input:
operators and tests can explain which binding/data source was selected, which
filters were requested, which candidates were rejected, and why. The explanation
must not include raw connection configuration, credentials, or backend-specific
query text.

Warnings are structured, not strings:

```elixir
%ResolveWarning{
  code:
    :source_unavailable | :source_degraded | :partial_data | :stale_data |
    :capability_fallback | :retention_gap | :mixed_semantics |
    :unknown_catalog_revision | :unknown_limit_definition |
    :unknown_limit_activation | :stale_limit_state |
    :incomplete_limit_evaluation | :mixed_limit_definitions |
    :unsupported_semantics_mode | :unsupported_time_axis |
    :unsupported_event_family | :partial_event_coverage |
    :event_projection_stale | :event_scope_ambiguous |
    :event_time_axis_mismatch | :event_limit_truncated |
    :unknown_observable | :unsupported_observable_scope |
    :observable_resolver_unavailable | :observable_projection_stale |
    :realm_mismatch | :recomputed_values |
    :source_binding_interval_ambiguous |
    :source_binding_segment_merge_unsupported,
  severity: :info | :warning | :error,
  scope: :dashboard | :placement | :frame | :field,
  placement_id: "placement_1" | nil,
  frame_id: "frame_..." | nil,
  field_name: "battery_voltage" | nil,
  message: "Human-readable fallback for logs/API clients",
  details: %{...},
  evidence: [%EvidenceRef{}],
  links: [%DashboardDataLink{}]
}
```

Source watermarks are part of the contract even before every source can provide
authoritative completeness:

```elixir
%SourceWatermark{
  logical_source: :telemetry,
  request_id: "source_req_...",
  source_binding_id: "binding_...",
  data_source_id: "ds_...",
  realm: :flight,
  dataset: "telemetry_latest",
  scope: %{spacecraft_id: "sc_001"},
  complete_through: DateTime.t() | nil,
  latest_receipt_time: DateTime.t() | nil,
  retention_starts_at: DateTime.t() | nil,
  confidence: :authoritative | :best_effort | :unknown,
  freshness_state: :fresh | :stale | :unknown | :retention_gap,
  freshness_policy: %{stale_after_ms: non_neg_integer()} | %{},
  freshness_checked_at: DateTime.t()
}
```

`request_id` and `source_binding_id` are operational correlation fields: they
let the engine explain which planned request produced a freshness marker and
which resolved source binding supplied it. They should not be used as freshness
semantics themselves.

Freshness classification is engine-owned, not UI-owned. Source adapters return
raw watermark facts; the engine resolves the effective freshness policy from
source defaults, dashboard defaults, request context, and widget/placement
overrides, then annotates each watermark with `freshness_state`. `:stale_data`
and `:retention_gap` are emitted as structured `ResolveWarning`s and fanned out
to affected placements. The LiveView source-health strip only presents the
engine state.

Cached source results have an additional freshness preflight before the engine
may reuse them. The preflight compares the cached source-result key and cached
watermarks against current source facts: request identity, source binding, data
source, freshness policy, watermark cursor/confidence/state, data revision,
correction cursor, backfill cursor, and source health. A cache entry is usable
only when the preflight returns no stale reasons; otherwise the engine must
resolve the source again and surface the stale reason as cache provenance.

Current source facts are fetched before frame resolution. `SourceFacts` captures
the selected source binding, physical data source, watermark, data revision,
correction/backfill cursors, source health, and request-local capability posture.
Source adapters expose a narrow facts callback so the runtime can build the
current source-result cache key without calling latest/history/range frame
readers.

Initial QuestDB-backed telemetry watermarks are `:best_effort`: the reader can
compute latest and earliest receipt times for the filtered tenant/mission/source
data, but it cannot yet prove upstream ingestion completeness, late-arrival
closure, or transport gap closure. A data source should advertise
`watermarks?: true` only when its adapter can supply that best-effort freshness
marker; otherwise the engine keeps returning `confidence: :unknown` with a
`:watermark_unknown` warning.

Initial limits watermarks are also `:best_effort`: the projection can report
freshness across latest limit-state rows and limit-event history for the
filtered point/scope, but it does not prove that limit definitions, activation
intervals, or upstream telemetry completeness are authoritative.

Resolve modes:

| Mode | Trigger | Engine behavior |
| --- | --- | --- |
| `:initial` | dashboard mount or hard refresh | build full plan, resolve all frames, establish subscriptions |
| `:context_change` | time/scope/data/limit mode changed | rebuild plan and replace affected frames |
| `:live_tick` | periodic refresh for non-streaming latest sources | resolve only latest/scalar requests that cannot stream |
| `:stream_append` | source-pushed live data | append to appendable frames without rebuilding the whole dashboard |

The v0 engine should support `:initial`, `:context_change`, and a conservative
`:live_tick`. `:stream_append` is the target live model, but does not need to
block the first engine cut.

The initial `:live_tick` implementation is intentionally narrow. Planning still
builds the full request set so placement mappings remain stable, but execution
filters to latest-style requests only:

- telemetry `sampling.mode == :latest`
- limits `sampling.mode in [:latest, :latest_state]`

Historical telemetry requests, native decimated envelopes, limit event history,
and future event/archive sources are skipped on tick until the cache and
subscription model can update them without replaying archive queries. The engine
reports skipped request counts in plan metadata so callers can distinguish a
partial live tick from a full resolve.

Cache keys, if used, must include:

- organization and mission
- dashboard version
- widget type/version and widget binding
- concrete time/scope/data context
- limit semantics mode
- source binding id / data source id / realm
- value type and sampling mode
- target point count or bucket width
- catalog/runtime/limit activation context when known

The engine may cache source results or shaped frames, but cache invalidation is
driven by domain facts: catalog activation, limit activation, source-binding
changes, data-management corrections/backfills, and source watermark movement.

#### 5.1.2 Runtime cache, refresh, and backpressure contract

The engine should behave like a dashboard-level planner with short-lived
runtime caches, not a permanent semantic store. Durable truth stays in the
source systems, catalog/runtime activation records, limit records, data
management layer, and operational event spine.

Cache layers:

```elixir
%DashboardRuntimeCache{
  dashboard_id: "dashboard_...",
  dashboard_version: 7,
  session_id: "session_...",
  plan_cache: %{cache_key => %ResolvedPlan{}},
  source_result_cache: %{cache_key => %SourceResolveResult{}},
  frame_cache: %{cache_key => [%Frame{}]},
  expires_at: DateTime.t()
}
```

| Layer | What it caches | Typical TTL | Invalidated by |
| --- | --- | --- | --- |
| Plan cache | planned source requests for document + context | session / document version | document version, widget registry version, source capability change |
| Source result cache | source responses before widget placement fanout | seconds to minutes | source watermark movement, source binding change, data correction/backfill |
| Frame cache | shaped/decimated Frames for display size | seconds to minutes | viewport bucket change, source result invalidation, limit/catalog context change |
| Latest cache | scalar latest values for live ticks | sub-second to refresh interval | newer source timestamp, freshness policy, source degraded/recovered |

Cache keys must include the fields listed above in §5.1.1, plus:

- resolve mode where behavior differs (`:initial`, `:context_change`,
  `:live_tick`, `:stream_append`)
- source capability fingerprint
- widget registry version or widget type version
- document schema version
- data-management view (`:canonical`, `:as_recorded`, `:all_revisions`,
  `:recomputed`)
- source watermark cursor when the source exposes one

Current implementation status: `Cadence.Dashboards.RuntimeCacheKey` defines
the v0 key contract for plan, source-result, and frame layers, and
`Cadence.Dashboards.Engine` emits those keys as cache provenance in
`DashboardResolveResult.plan_metadata.cache`. Plan keys now include explicit
dependency fingerprints for dashboard document schema version, widget registry
version, and source capability version; these dependency values are also exposed
in plan cache metadata. Planned source requests also carry capability
provenance in request metadata, including selected binding/data-source identity,
supported capability surfaces, a request-local capability fingerprint, and a
`capability_posture` summary. The posture is the planner/runtime vocabulary for
native support, configured fallback, and unsupported capability: for example, a
generation-time telemetry request on a receipt-only data source records
`status: :fallback`, `requested_time_axis: :generation_time`, and
`executed_time_axis: :receipt_time`. The same provenance is copied into
unsupported-capability warnings so degraded plans can be explained without
	re-resolving registry state. Source facts and source-result cache entries retain
	the same posture metadata, while resolved source results, materialized frames,
	and frame cache provenance entries retain capability provenance as runtime
	metadata; provenance is intentionally observability/audit context and not part
	of cache identity.
Runtime diagnostics render the same posture as an operator-facing source
capability section with status counts and per-request evidence, so fallback
clocks and unsupported capabilities are visible without inspecting raw
frame/source metadata. Each posture row is also an evidence control: it opens the
source inspector with selected source request, logical source, realm, binding,
data-source, capability status, requested/executed time axes, supported axes,
sampling, fallback, and unsupported-capability context. This keeps capability
fallbacks auditable even when no degraded source incident exists for the current
runtime result. The same source execution summary can now be converted into
canonical operational events through
`Cadence.Dashboards.dashboard_source_capability_posture_events/2` and persisted
with `record_dashboard_source_capability_postures/2`; those events use source
record kind `:source_capability_posture` and preserve dashboard, resolve,
request, binding, data-source, clock-axis, sampling, fallback, unsupported, and
source-execution status context. The Events source exposes the same records as
the `:source_capability_postures` product, with `:source_capability`,
`:source_capabilities`, and string/dash variants normalized to the same product
so dashboards can overlay fallback/unsupported posture changes on operational
timelines. Posture DataLinks resolve through the canonical operational-event
inspector and render semantic posture rows for dashboard, resolve, source request,
logical source, binding, capability status, requested/executed clock axes,
sampling, fallbacks, unsupported capability, and source-execution status instead
of requiring operators to parse raw event payloads.
`Cadence.Dashboards.RuntimeCache` now provides
ETS-backed plan-cache storage with explicit hit/miss provenance and targeted
plan invalidation by dashboard, organization, mission, document version,
document schema version, widget registry version, source capability version,
and logical source. It also stores explicit source-result entries and can
invalidate them by mission, logical source, source binding, data source,
realm/dataset, request id, observable, and watermark cursor/confidence. Segmented
source-result and frame entries are indexed by all segment binding ids, data
binding event ids, data source ids, realms, and datasets so the same invalidation
filters evict historical ranges that crossed a source-binding transition. Engine
consumption of cached source results is gated by
`Cadence.Dashboards.SourceResultPreflight`, which returns `:usable` only when
current source facts still match the cached source result. `SourceFacts` and
`DataSourceRegistry.facts/2` provide those current source facts for telemetry
and limits without resolving frames. The engine now has an opt-in
`source_result_cache?: true` path that fetches facts, builds the current
source-result key, runs preflight, serves usable cached results, and records
per-request cache provenance. For segmented historical telemetry reads,
`SourceFacts` and source-result cache keys carry `source_binding_segments`
instead of a single binding/source pair, so preflight can reuse a cached
snapshot only when the same binding events, TSDBs, datasets, and clipped
intervals still describe the request. `Cadence.Dashboards.RuntimeCache` also
stores explicit frame entries and can invalidate them by source-result fingerprint,
placement, placement size bucket, logical source, observable, limit context, and
catalog revision. `Cadence.Dashboards.FrameMaterializer` now owns the boundary
that turns source results plus placement/display context into placement-scoped
frames and matching frame cache keys. The engine has an opt-in `frame_cache?: true`
path that checks materialized frame keys, serves cached frames on hits,
writes frames on misses, and records placement/request cache provenance. Richer
frame freshness policy and event-driven invalidation wiring remain future.
`Cadence.Dashboards.RuntimeInvalidation` defines the dashboard-facing
invalidation boundary for domain changes that affect cached runtime artifacts;
it maps dashboard version, catalog revision, limit definition, data-source
binding, source-watermark, historical-data, and source-health changes onto the
current plan/source-result/frame cache invalidators without requiring a full
event architecture yet. Each boundary call emits
`[:cadence, :dashboards, :runtime_invalidation, :invalidate]` with numeric plan,
source-result, frame, total, and duration measurements plus metadata for the
boundary/domain fact, affected layers, normalized filters, per-layer match
filters, and runtime cache target. Audit-only fields such as `reason`,
`revision`, and `evidence_ref` remain in the normalized event filters but are
not copied into the per-layer match filters.
`Cadence.Dashboards.DocumentStore` now provides an initial canonical document
persistence path backed by the existing `ops_dashboards` table: new writes store
`Cadence.Dashboards.Document` JSON, assign document versions in metadata, fetch
documents directly for engine planning/resolution, and invalidate dashboard
plans after successful document writes. The first ops create/show/edit path now
uses this canonical document API. Ops
dashboard navigation and list surfaces now read lightweight canonical
`DashboardSummary` values derived from documents instead of full legacy
dashboard structs. Add/edit/remove/layout editor mutations now target canonical
document placements; the current form writes through
`Cadence.Dashboards.PlacementEditor`. The ops dashboard grid now iterates canonical placement
render items from
`Cadence.Dashboards.RenderItem`; active components consume
`Cadence.Dashboards.RenderWidget` presenters. Engine presenter caches and chart append events now
also use canonical placement ids from render items for active-item and frame
lookup state. Widget configuration open/edit fallback paths also resolve
through render items and internally track `{:edit_placement, placement_id}` while preserving stable
widget-oriented DOM events for the current component surface. The ops show page
now uses the
canonical document for dashboard metadata, routing ids, rename, delete, and
persistence refresh state instead of keeping a legacy dashboard assign as a
shadow source of truth. Canonical document updates now enforce expected document
versions and return a dashboard-version conflict instead of silently overwriting
newer shared edits; the ops show page reloads the latest document when a stale
write conflicts. Dashboard LiveView tests now seed dashboards through
canonical document fixtures instead of legacy ops-dashboard widget fixtures.
The legacy ops dashboard compatibility bridge has been retired, so the current
storage and runtime path has one dashboard representation:
`Cadence.Dashboards.Document`. Immutable `dashboard_versions` snapshots are now
written transactionally on create/update and can be listed/fetched for audit and
future rollback. The mutable dashboard row now carries version pointers
(`latest_version`, `draft_version`, `published_version`) and lifecycle columns
for listing, locking, revert, and archive flows. Current writes maintain
`latest_version` and `draft_version`; API-level publish validates a saved
version, advances `published_version`, records `published_by/at`, and clears or
retains `draft_version` depending on whether a newer unpublished draft remains.
Operator-view resolution now prefers the published document, while edit mode
opens the latest draft; unpublished dashboards still use a draft-preview
fallback for newly created dashboards. The ops dashboard toolbar now includes a
publish action that promotes the latest saved draft and returns the runtime to
operator-view published mode. Archive/restore now uses row lifecycle state:
archive removes dashboards from active list/nav surfaces without deleting
versions, and the ops dashboard list can restore archived dashboards.
Publish/revert/archive/restore also append dashboard lifecycle event rows in
the same transaction as the pointer or lifecycle change. These rows are the
subsystem audit source for dashboard lifecycle facts until they are projected
into the broader operational event spine.

Invalidation events:

- dashboard version changed
- widget type/options/layout/drilldown contract changed
- observable definition changed
- catalog/runtime binding activated or superseded
- limit definition activated, superseded, disabled, or reverted
- data source registered/changed
- source binding registered, changed, enabled, disabled, or superseded
- source watermark advanced or regressed
- data correction, supersession, or backfill accepted
- source health degraded/recovered
- replay run state changed

Current v0 runtime invalidation coverage:

| Domain fact | Runtime boundary | Cache layers | Default cache policy | Producer status |
| --- | --- | --- | --- | --- |
| dashboard version changed | `dashboard_version_changed/2` | plan | n/a | wired from `Cadence.Dashboards.DocumentStore` |
| catalog revision activated/superseded | `catalog_revision_changed/2` | plan, source result, frame | n/a | wired from `Cadence.Catalog` |
| limit definition activated/superseded/disabled/reverted | `limit_definition_changed/2` | plan, source result, frame | n/a | wired from `Cadence.Governance` |
| data source or binding changed | `data_source_binding_changed/2` | plan, source result, frame | n/a | wired from `Cadence.Dashboards.DataSources`; binding writes record `dashboard_data_binding_events` |
| source watermark advanced/regressed | `source_watermark_changed/2` | source result, frame | live | wired from `Cadence.Telemetry.Storage` |
| data correction/backfill accepted | `historical_data_changed/2` | source result, frame | snapshot | wired from `Cadence.Telemetry.Storage` |
| source health degraded/recovered | `source_health_changed/2` | source result, frame | live | wired from `Cadence.Dashboards.SourceHealth` |

Runtime invalidation event contract:

`Cadence.Dashboards.RuntimeInvalidation.Event` is the canonical runtime
invalidation payload. Boundary functions still return the compact invalidation
count map (`%{plans:, source_results:, frames:}`), but internally they build a
typed event once and derive telemetry metadata and PubSub payloads from it:

```elixir
%Cadence.Dashboards.RuntimeInvalidation.Event{
  boundary: :source_watermark_changed,
  domain_fact: :source_watermark_changed,
  layers: [:source_result, :frame],
  filters: %{
    organization_id: "...",
    mission_id: "...",
    logical_source: :telemetry,
    realm: :flight,
    data_source_id: "managed_questdb_primary",
    source_binding_id: "default_flight_telemetry",
    observable: "HK.counter",
    cache_policy: :live
  },
  layer_filters: %{
    source_result: %{...},
    frame: %{...}
  },
  measurements: %{
    plans: 0,
    source_results: 1,
    frames: 1,
    total: 2,
    duration: native_time
  },
  occurred_at: ~U[...]
}
```

Telemetry remains map-compatible for `Cadence.Telemetry.RuntimeHealth`, but the
runtime-health collector reconstructs and stores the typed event as
`:runtime_event` on recent dashboard invalidation records. `RuntimeHealth`
therefore becomes a typed dashboard-invalidation source, not only a telemetry
log.

Dashboard relevance is a domain policy, not LiveView glue.
`Cadence.Dashboards.RuntimeInvalidationRelevance` consumes
`RuntimeInvalidation.Event` values and applies the dashboard refresh contract:

- scope must match organization, mission, or dashboard
- logical source must be relevant to the document's primary source or overlays
- observable filters must match a placement observable when present
- realm filters must match the active dashboard data realm
- source watermark and source health invalidations must match the active source
  identity (`data_source_id`/`source_id` and
  `source_binding_id`/`binding_id`) from current watermarks or source-result
  cache metadata
- `data_source_binding_changed` still honors document scope and realm, but it
  intentionally does **not** require the new data-source id to match the
  dashboard's currently resolved source identity, because the purpose of that
  event is to move the dashboard from the old binding/source to the new one
- live dashboards refresh only for live-safe boundaries: events, limits,
  data-source binding, source health, and source watermark
- archive dashboards refresh for `historical_data_changed` only when the
  invalidated time range overlaps the active archive context; malformed or
  under-specified ranges fail open so corrections are not missed
- invalidations older than the active runtime context are ignored

The ops dashboard diagnostics panel exposes this typed contract for debugging.
It shows scoped invalidation counts, boundary summaries, last refresh reason,
and a recent-invalidation list containing boundary, logical source, realm,
data-source id, source-binding id, observable, artifact count, event time,
durable source/cache evidence, source-execution summaries, and upstream
source-dependency evidence when one logical source depends on another source's
runtime result.
This is intentionally an operator/developer diagnostic surface rather than a
new dashboard workflow.

Invalidation should be event-driven when the event spine/source layer can emit
facts. v0 can combine conservative TTLs with explicit invalidation hooks from
known local writes. The engine must surface stale/unknown cache provenance as
warnings rather than silently presenting old semantic context as current truth.
Segmented historical cache entries use the same invalidation boundaries; their
segment identities are searchable cache metadata, not only opaque fingerprint
inputs.

Refresh behavior:

- dashboard runtime has one scheduler per mounted dashboard/session, not one
  timer per widget
- live tick builds a dashboard-level plan and resolves only requests affected by
  latest/scalar refresh
- equivalent source requests are batched before execution
- historical/archive ranges do not refresh unless the user changes context or a
  correction/backfill invalidation arrives
- replay mode refreshes according to replay-run progress, not flight live tick
- source errors degrade the affected placements while the rest of the dashboard
  continues rendering

Backpressure and circuit breaking:

- cap concurrent source requests per dashboard/session
- cap raw samples per request before decimation
- prefer source-side decimation when capability exists
- cancel obsolete resolves when the user changes time/scope/data context
- drop or coalesce live ticks when a previous tick is still resolving
- mark a source `:source_degraded` after repeated timeout/failure and use a
  cooldown before retrying aggressively
- never allow a slow BYO source to block unrelated managed/local sources

Current implementation status: `Cadence.Dashboards.RuntimeCoordinator` defines
the pure dashboard-session state machine for refresh/backpressure policy. It
decides when to start a resolve, coalesce repeated live ticks, suppress refresh
while the dashboard is not in a live-refreshable state, cancel obsolete resolves
on context changes, ignore stale completions, and record source failure/backoff
inputs. It does not execute work or own processes; the ops dashboard LiveView
now applies `:start_resolve` decisions through LiveView async tasks, accepts
results only through coordinator completion decisions, records failed async
exits as runtime degradation input, and pushes chart appends only after an
accepted live-tick result. It also applies `:cancel_obsolete` decisions to
cancel superseded in-flight async tasks while retaining stale completion checks
as a second line of defense.

Source execution now has a first in-memory circuit-breaker layer through
`Cadence.Dashboards.SourceCircuitBreaker`, wired at `SourceRegistry` after a
logical request resolves to a concrete source binding. Adapter exceptions/exits
and error-severity source results increment the circuit for that concrete
tenant/mission/logical-source/data-source/realm/dataset key. Once the threshold
opens the circuit, matching requests receive a structured `:source_degraded`
result without invoking the adapter until the backoff permits a half-open retry.
Source execution is also bounded by `Cadence.Dashboards.SourceExecutionPolicy`:
the engine executes planned source requests with `Task.async_stream/3`, caps
per-resolve source concurrency, and converts task timeouts/exits into structured
`:source_unavailable` results that feed the same source circuit breaker. The
dashboard-level concurrency cap remains global, but timeout and circuit-breaker
policy are now resolved per concrete source from app defaults,
`DataSource.metadata.dashboard_policy`, `DataBinding.metadata.dashboard_policy`,
and explicit runtime/test opts. Per-request policy metadata is exposed in
`plan_metadata.source_execution_policies_by_request_id`, including provenance
for the selected source identity.

Source selection is also explicit. For each executed source request, the engine
records `plan_metadata.source_selection_by_request_id` and copies the same
selection map into source result/frame metadata. Selection explanations include
the strategy used (`:current_binding`, `:historical_binding`, or
`:historical_segment`), requested source filters, selected binding/source ids,
requested time mode/axis, replay run id, candidate counts, and per-candidate
decisions/rejection reasons. Replay-run requests that do not explicitly set a
data realm resolve against replay bindings instead of inheriting document-level
flight defaults; explicit runtime or placement data realms still win. This makes
"why did this widget read from this database/dataset?" answerable from the
dashboard result without querying the source registry separately.

Persisted `dashboard_policy` metadata now has a narrow validated contract. Both
data sources and bindings may carry:

```yaml
dashboard_policy:
  execution:
    max_concurrency: 4        # positive integer; dashboard-level cap remains global
    timeout_ms: 5000          # non-negative integer or "infinity"
  circuit_breaker:
    failure_threshold: 3      # positive integer
    backoff_ms: 30000         # non-negative integer
```

Legacy flat aliases remain accepted for bootstrap/test metadata
(`source_execution_timeout_ms`, `timeout_ms`,
`source_circuit_failure_threshold`, `failure_threshold`,
`source_circuit_backoff_ms`, `backoff_ms`). Persistence rejects invalid known
fields and malformed nested sections before rows are stored; unknown metadata
keys, including unknown keys under `dashboard_policy`, are preserved for
adapter-specific or future UI extensions but do not affect runtime policy until
explicitly supported. Runtime policy resolution still falls back to configured
defaults if it receives malformed in-memory policy from tests or transient code
paths, but persisted source configuration should fail fast.

The first BYO isolation boundary is also enforced at the source registry:
`DataSource.credentials_ref` is an indirect reference to a registered
non-secret credential descriptor, never embedded credential material.
`:byo_tsdb` rows must be customer-owned, organization-scoped,
`isolation_level: :customer_owned`, carry a non-empty `credentials_ref`, and
that reference must resolve to an active scope-compatible record in
`dashboard_source_credential_references`. Metadata is rejected if it embeds
obvious credential/secret keys. `DataSourceRegistry` applies the same
data-source configuration validation before dispatching an in-memory or
persisted source to an adapter, so tests and future admin tools cannot bypass
the persisted changeset by constructing ad hoc source records.

`Cadence.Dashboards.SourceCredentials` is the first credential-registry stub.
It stores no secret material. It records a current non-secret reference row with
scope, owner, provider, status, version, and metadata, plus append-only
`dashboard_source_credential_events` for registration, rotation, enable, and
disable actions. The resolver returns `ResolvedSourceCredential` descriptors
with `secret_material?: false`. `SourceCredentials.resolve_material/2` is the
secret-manager boundary: it accepts an injected or configured material resolver,
keeps descriptor scope/status checks as the front door, and returns an
ephemeral `SourceCredentialMaterial` value for adapter IO only. Source-health
payloads and UI evidence continue to receive only a redacted connection profile
that records `secret_material?: true` and the material field names present, not
the values. Each mission-scoped material-resolution attempt also writes a
canonical `:security` operational event with subject kind
`:source_credential`. The audit event records the actor, credential reference,
data source, authorizer identity, resolver identity, success/failure/denial
result, material field names, and redacted failure or denial class; it does not
persist endpoint, token, password, header, or other material values.

Credential material resolution also has a narrow authz seam:
`credential_material_authorizer` may be supplied per call or configured as
`material_authorizer`. It receives the already scope-checked
`ResolvedSourceCredential` descriptor plus org/mission/data-source context.
Returning `:ok` allows resolver/backend access; returning `:deny`, `false`, or
`{:deny, reason}` fails closed before secret backend access and records
`:source_credential_material_resolution_denied` with a redacted denial reason.
The default path currently allows and is marked `todo(authz)` for the future
RBAC-backed policy engine.

The production-shaped resolver boundary is now
`Cadence.Dashboards.SourceCredentials.SecretMaterialResolver`. It delegates to a
configured secret backend implementing
`Cadence.Dashboards.SourceCredentials.SecretBackend`, then applies shared
material policy before any adapter receives the values. That policy normalizes
allowed material fields, rejects unsafe HTTP endpoints with userinfo, rejects
ambiguous bearer/basic auth material, fails closed on empty material, and keeps
unknown backend fields out of the adapter handoff. The first concrete backend is
`Cadence.Dashboards.SourceCredentials.EnvSecretBackend`, with
`EnvMaterialResolver` retained only as a compatibility entry point for older
configuration and local tests. Credential metadata may carry a non-secret
`material_env_profile` pointer; runtime configuration maps that profile to
environment variable names such as `http_endpoint_env`, `bearer_token_env`,
`username_env`, `password_env`, and `headers_env`. The backend reads those
environment variables only during adapter IO and keeps the resolved
endpoint/auth/header values out of persisted rows and operator-visible
evidence. A later external secret-management backend, such as Vault/KMS, can
replace the env backend through the same resolver boundary without changing
source-binding or adapter contracts. Remaining production work is connecting
the material authorizer to a real RBAC/user-permission model and adding a real
deployment-backed Vault/KMS-style backend.

Source bindings are now durable subsystem lifecycle facts as well:
`dashboard_data_bindings` is the current projection and
`dashboard_data_binding_events` records registration, change, enable, disable,
and supersession events. Each event captures previous/current binding facts such
as data source, dataset, realm, priority, active interval, status, version,
actor, and payload. Binding writes invalidate affected runtime plan,
source-result, and frame caches after the transaction commits.

Dashboard source health is now durable as subsystem state:
`Cadence.Dashboards.SourceHealth` records append-only
`dashboard_source_health_events`, maintains latest
`dashboard_source_health_statuses`, and emits `source_health_changed/2`
invalidation on actual health transitions. `SourceRegistry.facts/2` overlays
the latest durable status into `SourceFacts`, so source-result cache preflight
uses the subsystem projection instead of only adapter-local health hints. The
source-health key is a stable fingerprint over organization, mission, logical
source, concrete data source, source binding, realm, and dataset, so
rehearsal/BYO/flight source health is isolated the same way source resolution is
isolated. Data-source probes also persist a capability snapshot in source-health
payloads: adapter capability, physical data-source capability claims, effective
sampling/watermark support, and a capability fingerprint. This makes each probe
an auditable record of both reachability and what Cadence believed the selected
source could support at probe time. Probes also record explicit
`connection_test_result`, `connection_test_kind`, and
`connection_test_message` payload fields, so operator surfaces can distinguish
succeeded adapter IO, failed adapter IO, unsupported active tests, and
descriptor/preflight blocks without reverse-engineering generic probe metadata.
Later probes compare the capability fingerprint to the latest status payload for
the same concrete source-health key and annotate capability drift, so operator
surfaces can show when effective source capabilities changed even if health
remains healthy. Adapters may also report capabilities discovered during the
probe itself, separate from persisted configuration claims; Cadence records the
reported snapshot, fingerprint, and mismatch flag without letting discovered
claims silently change planning behavior. The QuestDB telemetry adapter now
reports backend-derived capabilities from a bounded `telemetry_observations`
schema probe, so a reachable database with a missing or incompatible schema
degrades source health instead of appearing operational. The QuestDB telemetry
probe can use resolved ephemeral HTTP material for adapter IO while persisting
only the redacted connection profile. Remaining work is a production
secret-manager implementation behind the resolver, additional adapter-specific
BYO connection implementations, richer policy validation/UI, and projection of
these subsystem facts into the future operational event spine.

Performance targets for v0 should be explicit but conservative:

| Operation | Target |
| --- | --- |
| Initial dashboard resolve on Tier 0 data | usable first render under 1 s for typical dashboards |
| Live scalar refresh | under configured `refresh_ms` without overlapping ticks |
| Bounded historical query | returns decimated result or explicit truncation warning |
| Context change | cancels stale work and renders replacement frames atomically per placement |
| Failed/degraded source | warning visible in one refresh interval |

These are product targets, not hard real-time guarantees. If a target is missed,
the engine should make degradation visible through watermarks, warnings, and
partial-frame metadata.

The engine does **not** own:

- telemetry observation identity, correction, or deduplication policy
- catalog/runtime activation truth
- limit lifecycle policy
- physical TSDB query languages
- client renderer implementation details
- user-authored widget grammar

Minimum v0 contract:

- `Cadence.Dashboards.Engine.resolve/1`
- concrete `DashboardResolveRequest` / `DashboardResolveResult`
- concrete `Frame` / `Field` structs
- first-party widget registry with data contracts
- Telemetry source for latest + bounded history
- Limits source for latest limit state overlay
- dashboard-level time/scope/data contexts
- source warnings and watermarks, even if initially sparse
- no user-authored widget grammar
- no BYO adapter required yet
- no requirement to preserve the retired `Cadence.Ops.*` storage shape

Planning example:

```yaml
time_context:
  mode: archive
  from: 2026-06-14T01:00:00Z
  to: 2026-06-14T01:30:00Z
  axis: generation_time
scope_context:
  primary:
    kind: spacecraft
    mode: one
    ids: [sc_001]
data_context:
  realm: flight
  source_mode: primary
source_requests:
  telemetry:
    observables: [tlm.hk.battery_voltage, tlm.hk.bus_current]
    sampling: decimated_envelope
    target_points: 1200
    overlays: [limits]
  events:
    kinds: [contact, command]
    overlays_for: [cadence.time_series]
```

### 5.2 The Frame contract (the portability seam)

Borrowed from Grafana's data frames. A **Frame** is a set of columnar **Fields**
sharing one time field (**wide format** — efficient for multi-series). Each
Field carries **semantic metadata** that auto-drives the viz:

- `observable_id`, `unit`, `point_id`, `point_name`, `spacecraft_id`
- `limit_definition` reference (for bands/coloring)
- `quality_state`, `staleness`
- value type rendered (`raw` vs `engineering`)

"Field config auto-drives visualization" is exactly Grafana's mechanism — we
just source it from the catalog instead of hand-set config. The Frame is what
normalizes heterogeneous backends into one shape the widgets consume:
**backends differ; Frames don't.** Long format is available for table/SQL-shaped
results.

The LiveView chart presenter turns one placement's primary telemetry Frames into
an explicit versioned chart payload:

```elixir
%{
  version: 1,
  series: [
    %{
      id: "tlm.hk.battery_voltage",
      label: "tlm.hk.battery_voltage",
      observable_id: "tlm.hk.battery_voltage",
      unit: "V",
      source: :telemetry,
      frame_id: "source_req_...:tlm.hk.battery_voltage",
      field: "tlm.hk.battery_voltage_value",
      time_axis: :receipt_time,
      sampling: :decimated_envelope,
      decimation: :native_min_max_envelope,
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry",
      envelope: %{
        kind: :min_max,
        lower_field: "tlm.hk.battery_voltage_min",
        upper_field: "tlm.hk.battery_voltage_max",
        sample_count_field: "tlm.hk.battery_voltage_sample_count",
        points: [[1_781_568_000_000, 11.5, 12.75, %{sample_count: 120}]]
      },
      points: [[1_781_568_000_000, 12.25, %{sample_id: "..."}]]
    }
  ]
}
```

That payload is the browser chart seam: the client aligns all returned series and
optional min/max envelopes on a shared time axis, keeps per-series point metadata
for data-link inspection, renders native decimation as an envelope band plus a
representative line, groups series by unit into y-axis scales, renders a compact
series legend with units, lets operators toggle individual series and switch
between unit-grouped and shared value axes, and keeps overlays/markers outside
the series payload.
Older flat point arrays are only a compatibility input at the browser hook
boundary.

Concrete shape:

```elixir
%Frame{
  frame_id: "frame_...",
  source: :telemetry,
  shape: :wide,
  time_axis: :generation_time,
  scope: %{
    organization_id: "...",
    mission_id: "...",
    spacecraft_ids: ["sc_001"]
  },
  fields: [
    %Field{name: "time", kind: :time, values: [...]},
    %Field{
      name: "battery_voltage",
      kind: :number,
      values: [...],
      metadata: %{
        observable_id: "tlm.hk.battery_voltage",
        point_id: "HK.battery_voltage",
        unit: "V",
        value_type: :engineering,
        quality_state: :good,
        stale?: false,
        limit_definition_id: "limit_def_...",
        evidence: [%EvidenceRef{}],
        links: [%DashboardDataLink{}]
      }
    }
  ],
  overlays: %{
    limits: [%Frame{source: :limits, shape: :intervals}],
    events: [%Frame{source: :events, shape: :intervals}]
  },
  meta: %{
    data_source_id: "ds_managed_timescale_primary",
    binding_id: "binding_...",
    realm: :flight,
    dataset: "flight_ops",
    decimated?: true,
    bucket_width_ms: 1500,
    evidence: [%EvidenceRef{}],
    links: [%DashboardDataLink{}],
    warnings: []
  }
}
```

For client transport, this can serialize to compact JSON with columnar values;
the Elixir struct is a design contract, not necessarily the wire format.

### 5.3 Logical source taxonomy (closed)

| Source | Returns | Powers | Backing (today) |
| --- | --- | --- | --- |
| **Telemetry** (live + history + derived) | sample series / latest | time series, value tiles, grids | `CurrentValueStore`, `HistoryStore`, `DerivedTelemetry` |
| **Limits** | limit-state, transitions over time | limit bands, state timelines, status matrices | `telemetry_latest_limit_states`, `telemetry_limit_events` (full history) |
| **Events** | mission-timeline intervals | pass shading, annotation tracks, "LOS not anomaly" | `ScheduledContact`/`RealizedContact`, `MissionEvents` |
| **Operational observables** | metrics / states from Cadence subsystems | link status, bit-rate, queue depth, platform health | subsystem projections or streams |
| **Commands** *(future)* | command events | command log, chart annotations | needs a projection (see §12) |

Derived telemetry folds into **Telemetry** — the limits layer already treats it
uniformly (`source_sample_type: :derived_telemetry_sample`).

Operational observables are intentionally separate from spacecraft telemetry.
Some may later be stored in the same TSDB as telemetry samples, but their source
contract is subsystem-owned rather than dictionary-upload-owned.

#### 5.3.1 Telemetry source v0 contract

The Telemetry source is the first logical source the engine should implement. It
is responsible for turning catalog-bound telemetry observable requests into
Frame(s). It is not responsible for widget rendering, data-management policy, or
physical TSDB-specific query language.

Source identity:

```elixir
%SourceCapabilities{
  logical_source: :telemetry,
  supported_sampling: [:latest, :raw_series, :bounded_history, :bounded_raw_series],
  supported_products: [
    :latest_value,
    :bounded_receipt_time_history,
    :bounded_generation_time_history
  ],
  supported_time_axes: [:generation_time, :receipt_time],
  supported_value_types: [:raw, :engineering],
  supported_shapes: [:scalar, :wide],
  supports_watermarks?: false,
  completeness: :unknown
}
```

That capability set is intentionally modest for v0. The source contract should
support the target shape now, while the first implementation only claims the
store capabilities it can actually execute:

- `CurrentValueStore` satisfies `:latest` requests as scalar Frames, with the
  latest sample timestamp reported as `generation_time` when available and
  `receipt_time` otherwise.
- `:latest` uses the shared telemetry latest/current projection policy:
  `generation_time || receipt_time`, then `receipt_time`, then stable sample id.
  Late-arriving older source-time samples remain queryable in history but do not
  replace the scalar latest value solely because they arrived later.
- `HistoryStore` satisfies `:raw_series` / `:bounded_raw_series` requests by
  `receipt_time` or source/onboard time as wide Frames. Source-time reads use
  the storage `observed_at` contract (`generation_time || receipt_time`) for
  range filtering and ordering, while frame metadata preserves the selected
  dashboard axis.
- decimated envelopes are a data-source capability, not a blanket telemetry
  adapter promise. A selected source that advertises `native_decimation?: true`
  can plan and execute `:decimated_envelope` through a native min/max envelope
  query. The managed QuestDB path uses `ObservationReader.decimated_history_result/3`
  with `SAMPLE BY` buckets; otherwise v0 planning emits
  `:unsupported_source_capability` with `fallback: :none` instead of silently
  returning raw history.
- watermarks can return `confidence: :unknown` until the telemetry data
  management/source-binding layer provides real completeness.

Telemetry source query:

```elixir
%TelemetrySourceQuery{
  request_id: "source_req_...",
  organization_id: "...",
  mission_id: "...",
  observables: ["tlm.hk.battery_voltage"],
  scope: %{
    kind: :spacecraft,
    ids: ["sc_001"]
  },
  time: %TimeContext{
    mode: :live | :archive | :replay_run,
    axis: :generation_time | :receipt_time,
    from: DateTime.t() | nil,
    to: DateTime.t() | nil
  },
  data: %DataContext{
    realm: :flight,
    source_mode: :primary,
    view: :canonical | :as_recorded | :all_revisions | :recomputed
  },
  value_type: :engineering,
  sampling: %{
    mode: :latest | :raw_series | :decimated_envelope,
    target_points: 1200,
    max_raw_points: 10_000
  }
}
```

Telemetry source output shapes:

- **Latest** — one row per observable/scope member, shaped as a scalar Frame.
- **Raw series** — one time field plus one value field per observable/scope
  member when possible; long format is acceptable for mixed types or sparse
  multi-scope results.
- **Decimated envelope** — time bucket plus `min`, `max`, representative
  `value`/`mean`, and metadata such as `worst_quality_state`,
  `worst_validity_state`, and `sample_count`.

Latest scalar frame:

```elixir
%Frame{
  source: :telemetry,
  shape: :scalar,
  time_axis: :generation_time,
  fields: [
    %Field{name: "time", kind: :time, values: [~U[2026-06-16 12:00:00Z]]},
    %Field{
      name: "battery_voltage",
      kind: :number,
      values: [27.4],
      metadata: %{
        observable_id: "tlm.hk.battery_voltage",
        point_id: "HK.battery_voltage",
        unit: "V",
        value_type: :engineering,
        quality_state: :good,
        validity_state: :canonical,
        freshness_state: :fresh,
        observation_identity_id: "obs_id_...",
        revision_kind: :initial,
        superseded_by: nil,
        sample_id: "sample_...",
        evidence_id: "evidence_...",
        catalog_revision_id: "catalog_rev_..." | nil,
        data_realm: :flight
      }
    }
  ],
  meta: %{
    source_request_id: "source_req_...",
    data_source_id: "ds_...",
    binding_id: "binding_...",
    warnings: []
  }
}
```

Bounded history frame:

```elixir
%Frame{
  source: :telemetry,
  shape: :wide,
  time_axis: :generation_time,
  fields: [
    %Field{name: "time", kind: :time, values: [...]},
    %Field{name: "battery_voltage", kind: :number, values: [...], metadata: %{...}}
  ],
  meta: %{
    sampling: :raw_series,
    value_type: :engineering,
    returned_points: 600,
    truncated?: false,
    watermark: %SourceWatermark{confidence: :unknown},
    warnings: []
  }
}
```

Decimated envelope frame:

```elixir
%Frame{
  source: :telemetry,
  shape: :wide,
  time_axis: :generation_time,
  fields: [
    %Field{name: "bucket_start", kind: :time, values: [...]},
    %Field{name: "bucket_end", kind: :time, values: [...]},
    %Field{name: "battery_voltage_min", kind: :number, values: [...]},
    %Field{name: "battery_voltage_max", kind: :number, values: [...]},
    %Field{name: "battery_voltage_value", kind: :number, values: [...]},
    %Field{name: "battery_voltage_sample_count", kind: :number, values: [...]}
  ],
  meta: %{
    sampling: :decimated_envelope,
    decimation: :native_min_max_envelope,
    bucket_width_ms: 1500,
    warnings: [%ResolveWarning{code: :capability_fallback}]
  }
}
```

Telemetry warnings:

- `:unsupported_time_axis` — requested `generation_time` range on a backend that
  only filters by `receipt_time`. The warning must carry the requested axis, the
  supported source axes, and the executed fallback axis so operators can tell
  whether the graph is using source time or ground receipt time.
- `:unsupported_source_capability` — the planner could not emit a truthful
  source request for the requested product or sampling mode.
- `:capability_fallback` — source could not push down decimation or watermarks;
  engine fallback was used.
- `:partial_data` — raw point cap or backend limit truncated the response.
- `:retention_gap` — requested range extends beyond known retention.
- `:source_degraded` / `:source_unavailable` — source binding or backend cannot
  serve the request cleanly.
- `:mixed_semantics` — returned rows span multiple known catalog/runtime
  contexts.
- `:unknown_catalog_revision` — rows lack enough semantic context for observed
  historical rendering.

Telemetry source v0 should not fake features. If the current backing store
cannot answer a request with the requested semantics, it should return partial
frames plus warnings, or no frame plus an error warning. This is what makes the
dashboard engine trustworthy during the transition to managed TSDB and BYO
adapters.

#### 5.3.2 Limits source v0 contract

The Limits source is the first overlay source the engine should implement. It
turns telemetry observables and time/scope/data context into limit-state
overlays, warning metadata, and eventually effective limit-definition bands.

The source has three distinct products:

1. **Evaluation events** — observed results for concrete samples:
   sample S evaluated under definition L version V produced state red/yellow/
   green.
2. **Definition intervals** — effective limit bands/policies over time:
   definition L version V was active for point/scope/realm from T1 to T2.
3. **Latest state** — the fast latest observed state projection for live tiles
   and status widgets.

v0 supports latest observed state, observed event history, and effective
definition intervals derived from `limit_definition_lifecycle_events`.
Mission-wide lifecycle rows, where scope/realm are unset, act as wildcard
intervals for concrete dashboard scopes/realms.

Source identity:

```elixir
%SourceCapabilities{
  logical_source: :limits,
  supported_sampling: [:latest_state, :latest, :event_history, :definition_intervals, :analysis_buckets],
  supported_products: [:latest_state, :event_history, :definition_intervals, :analysis_buckets],
  supported_time_axes: [:receipt_time],
  supported_value_types: [:raw, :engineering],
  supported_shapes: [:scalar, :events, :intervals],
  supports_watermarks?: false,
  completeness: :unknown
}
```

Limits source query:

```elixir
%LimitsSourceQuery{
  request_id: "source_req_...",
  organization_id: "...",
  mission_id: "...",
  observables: ["tlm.hk.battery_voltage"],
  scope: %{
    kind: :spacecraft,
    ids: ["sc_001"]
  },
  time: %TimeContext{
    mode: :live | :archive | :replay_run,
    axis: :generation_time | :receipt_time,
    from: DateTime.t() | nil,
    to: DateTime.t() | nil
  },
  data: %DataContext{
    realm: :flight,
    source_mode: :primary
  },
  semantics_mode: :observed | :current | :recomputed | :compare,
  products: [:latest_state | :event_history | :definition_intervals | :analysis_buckets],
  align_to: %{
    telemetry_request_id: "source_req_telemetry_...",
    sample_ids: ["sample_..."] | nil,
    bucket_width_ms: 1500 | nil
  }
}
```

`align_to` is important. A limit overlay is not just a free-standing time
series; it is usually attached to a telemetry frame. The engine should pass
enough information for the Limits source to align states to telemetry samples,
buckets, or a chart time range.

Latest limit-state overlay:

```elixir
%Frame{
  source: :limits,
  shape: :scalar,
  time_axis: :generation_time,
  fields: [
    %Field{name: "time", kind: :time, values: [~U[2026-06-16 12:00:00Z]]},
    %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
    %Field{name: "limit_state", kind: :enum, values: [:yellow_low]},
    %Field{name: "violation", kind: :boolean, values: [true]}
  ],
  meta: %{
    observable_id: "tlm.hk.battery_voltage",
    point_id: "HK.battery_voltage",
    sample_id: "sample_...",
    limit_event_id: "limit_event_...",
    limit_definition_id: "battery_voltage_limits",
    limit_definition_version: 3,
    limit_set_name: "ops",
    semantics_mode: :observed,
    warnings: []
  }
}
```

Limit event-history overlay:

```elixir
%Frame{
  source: :limits,
  shape: :events,
  time_axis: :generation_time,
  fields: [
    %Field{name: "time", kind: :time, values: [...]},
    %Field{name: "sample_id", kind: :string, values: [...]},
    %Field{name: "normalized_state", kind: :enum, values: [...]},
    %Field{name: "limit_state", kind: :enum, values: [...]},
    %Field{name: "violation", kind: :boolean, values: [...]}
  ],
  meta: %{
    observable_id: "tlm.hk.battery_voltage",
    semantics_mode: :observed,
    returned_events: 120,
    truncated?: false,
    warnings: []
  }
}
```

Future definition-interval overlay:

```elixir
%Frame{
  source: :limits,
  shape: :intervals,
  time_axis: :generation_time,
  fields: [
    %Field{name: "starts_at", kind: :time, values: [...]},
    %Field{name: "ends_at", kind: :time, values: [...]},
    %Field{name: "lower", kind: :number, values: [...]},
    %Field{name: "upper", kind: :number, values: [...]},
    %Field{name: "normalized_state", kind: :enum, values: [...]}
  ],
  meta: %{
    observable_id: "tlm.hk.battery_voltage",
    limit_definition_id: "battery_voltage_limits",
    limit_definition_version: 3,
    semantics_mode: :observed,
    activation_event_id: "op_event_..." | nil,
    warnings: []
  }
}
```

Definition intervals are the shape time-series charts need for shaded bands.
Until activation events exist, v0 should either omit this product or return a
best-effort current-definition interval with `:unknown_limit_activation`
warning. It must not pretend current definitions were historically active.

Limits warnings:

- `:unknown_limit_definition` — no limit event or active definition can be found
  for the requested observable/scope/time.
- `:unknown_limit_activation` — a definition exists, but no activation interval
  proves when it was active.
- `:stale_limit_state` — latest limit state is older than the latest telemetry
  sample or freshness policy.
- `:incomplete_limit_evaluation` — telemetry samples exist without matching
  limit events.
- `:mixed_limit_definitions` — returned events span multiple definition
  versions.
- `:unsupported_semantics_mode` — requested a semantics mode outside the
  supported observed/current/recomputed/compare set.
- `:capability_fallback` — source returned latest/event overlays but could not
  provide definition intervals or bucket-aligned state.

v0 implementation boundary:

- **Supported:** latest state overlays from `telemetry_latest_limit_states`.
- **Supported:** planning limits as separate `:limits` source requests and
  fanning returned frames into `PlacementFrames.overlays.limits`.
- **Supported:** capped observed event history from `telemetry_limit_events`.
- **Supported:** active limit-definition provenance for newly persisted governed
  limit definitions through lifecycle events and a current active projection.
- **Supported:** bounded event-history analysis for non-observed semantics.
  `:current` and `:recomputed` read telemetry samples and a complete target
  definition interval, classify values through the governed evaluator, and
  return synthetic analysis frames. `:compare` also reads observed limit events
  to expose observed-vs-recomputed divergence.
- **Supported:** recomputed/current/compare limit analysis keeps separate source
  identities for its inputs. Telemetry sample reads use the telemetry source
  context when one is explicit, or resolve the primary telemetry binding for the
  same realm/replay context from the source registry; limit projections and
  definition intervals stay on the limits source binding.
- **Supported:** planned Limits source requests expose their telemetry input as
  `source_dependencies` when limit semantics are `current`, `recomputed`, or
  `compare`. Latest-state analysis declares a telemetry `latest_sample`
  dependency; historical/bucket analysis declares a telemetry `sample_history`
  dependency. That dependency participates in request batching and source-result
  cache identity instead of living only inside adapter-local option handling.
  Runtime diagnostics and dashboard root attributes expose the dependency
  summary. Source-execution diagnostics also join each dependency to the
  upstream request status, runtime/operator action, cache evidence, and
  watermark freshness when those facts are present, so a degraded Limits panel
  can explain that it is waiting on stale or degraded telemetry input instead of
  only naming the dependent logical source. The runtime diagnostics panel renders
  that explanation as a source-dependency cause row with an evidence action that
  opens the upstream telemetry source execution evidence. The replay-limits
  browser smoke asserts the rendered diagnostics panel contains that dependency
  cause row and that activating it opens source evidence for the upstream
  telemetry request.
- **Supported:** time-series marker payloads preserve recomputed/compare limit
  semantics, synthetic-analysis marker identity, observed-vs-recomputed state,
  divergence flags, and sample/observed-event links through render and live
  append paths.
- **Supported:** decimated chart envelope points roll up limit analysis markers
  that fall inside each bucket, including worst recomputed state, divergence
  count, sample ids, event ids, semantics modes, analysis basis metadata,
  selected-clock evidence, and selected limit-definition interval evidence.
- **Supported:** decimated time-series limit overlays plan a source-native
  `:analysis_buckets` Limits product. The product returns events-shaped bucket
  frames with bucket start/end, worst state, event counts, divergence counts,
  and rolled-up sample/event ids so limit excursions can survive decimated
  telemetry display without depending only on presenter-local aggregation. A
  bucket that spans a definition change splits by limit-definition identity, and
  the chart hook renders those bucket markers as clickable worst-state spans.
- **Supported:** limit-definition interval overlays render shaded red/yellow
  threshold regions inside the active interval span, while retaining threshold
  lines for exact boundaries.
- **Supported:** latest-state non-observed semantics read latest telemetry
  samples and target definition intervals to produce synthetic
  current/recomputed/compare scalar frames. Compare mode reads observed latest
  limit projection only to expose divergence metadata.
- **Supported:** bounded historical recomputed/compare analysis selects the
  complete limit-definition interval active at each telemetry sample's receipt
  time, while `:current` intentionally applies the newest selected complete
  definition. Samples without an active complete interval are skipped and
  surfaced through `:incomplete_limit_evaluation` warnings with missing sample
  ids.
- **Supported:** source-result and frame cache identity include limit semantics
  mode, so observed, current, recomputed, and compare requests cannot reuse each
  other's cached artifacts.
- **Supported:** runtime context controls expose observed/current/recomputed/
  compare limit modes and route supported selections into the engine limit
  context; unsupported future modes still fall back to observed with explicit
  fallback metadata.
- **Supported:** incomplete recomputed limit analysis warnings render with
  operator-facing selected-clock, limit-mode, and missing-sample presentation in
  the dashboard warning/evidence surfaces.
- **Supported:** selected-clock and selected-definition-interval evidence now
  survives downstream chart interpretation. Limit marker payloads carry the
  selected clock and interval evidence, decimated envelope point metadata rolls
  it up with the worst-state bucket, and rendered limit-analysis bucket DOM
  attrs expose the same evidence for browser-level inspection. The live
  authenticated dashboard browser smoke seeds real limit overlay data and
  asserts rendered limit-analysis buckets preserve that selected-clock and
  selected-definition-interval evidence.
- **Supported:** non-observed dashboard limit analysis can persist canonical
  `:dashboard_limit_selected_clock` operational events with deterministic ids.
  Operator runtime resolves opt into this side effect; direct engine callers
  remain side-effect-free unless they explicitly request audit persistence.
- **Partial:** late-arrival policy and workflow UI still need product wiring.
- **Future:** proposed-definition comparison mode.

The Limits source should preserve the observed-vs-recomputed distinction. An
observed event from `telemetry_limit_events` is operational truth; recomputation
under a current/proposed definition must return a separate frame with
`semantics_mode: :current` or `:compare` and explicit warnings/provenance. The
bounded source-frame path now does this for telemetry sample history. New widget
or overlay behavior must consume those frames directly rather than mutating
observed limit events in place.

#### 5.3.3 Events source v0 contract

The Events source provides operator context over the dashboard time axis:
contacts, timeline annotations, replay markers, source degradation, catalog/
runtime changes, commands, and other operational intervals. It is the source
that lets a chart explain "this drop happened during LOS" instead of leaving a
bare telemetry line.

The source has two shapes:

1. **Intervals** — events with duration, such as scheduled contacts, realized
   contacts, source degradation windows, eclipse windows, or active replay
   ranges.
2. **Instants** — point annotations, such as command release, limit transition,
   catalog activation, dashboard publish, or anomaly records.

v0 should support what exists today:

- flight contact/pass intervals from `ScheduledContact` / `RealizedContact`
- replay-scoped contact/pass intervals from canonical `operational_events`
  projected into the same contact-interval Frame shape
- flight mission timeline annotations from the `mission_events` projection
- replay-scoped mission timeline annotations from canonical `operational_events`
  projected through the same mission-event presenter contract
- source-health transition annotations from `dashboard_source_health_events`
- source-health, source-watermark, telemetry revision-decision, and
  backfill/import lifecycle rows with companion canonical `operational_event`
  evidence/DataLinks where those dashboard-owned projections already persist
  durable canonical envelopes

The canonical operational event spine now exists for selected families
(`docs/operational-event-timeline-design.md`). The Events source remains
contracted so dashboards can consume today's projections while specific paths
move to canonical operational events without changing widget contracts. Replay
mission-timeline and contact-interval reads already use this migration path:
when `replay_run_id` is present, the Events source reads canonical
`operational_events`, filters by replay causality, projects mission timeline
events through `MissionEvents.project_many/1`, projects contact interval events
into the existing contact-interval Frame shape, and marks the frame
`projection: :operational_events`. Replay contact Frames also attach typed
evidence for the contact identity, projected effective interval, and source
operational event so the inspector can explain both the displayed interval and
the canonical event that produced it.
Scheduled and realized contact row writes now also refresh canonical contact
interval operational events, so the canonical replay path has a production
emission boundary for interval facts. Contact action writes also emit canonical
contact operational events for cancellation and early-end audit facts. Transport
action-request writes now emit canonical `:comms` operational events for
transport-owned actions such as uplink requests, and transport timer lifecycle
writes emit canonical scheduled/fired/canceled timer events. Transport
capability execution records also emit canonical initialized/control-input/
transport-event/timer transition facts, and the operational-event read layer
projects those snapshots into transport execution intervals. Runtime/link
states and higher-level connection/transport semantics still need deliberately
modeled read projections on top of those facts.

Source identity:

```elixir
%SourceCapabilities{
  logical_source: :events,
  supports_intervals?: true,
  supports_instants?: true,
  supported_families: [:contacts, :mission_timeline, :source_health],
  unsupported_families: [:commands, :catalog_runtime, :replay],
  event_time_field: :occurred_at,
  supports_effective_intervals?: false,
  completeness: :best_effort
}
```

Events source query:

```elixir
%EventsSourceQuery{
  request_id: "source_req_...",
  organization_id: "...",
  mission_id: "...",
  scope: %{
    kind: :spacecraft | :contact | :ground_station | :transport | :link | :mission,
    ids: ["sc_001"]
  },
  time: %TimeContext{
    mode: :live | :archive | :replay_run,
    axis: :generation_time | :receipt_time,
    from: DateTime.t() | nil,
    to: DateTime.t() | nil
  },
  data: %DataContext{
    realm: :flight,
    source_mode: :primary
  },
  families: [:contacts, :mission_timeline, :source_health],
  kinds: [:scheduled_contact, :realized_contact, :limit_violation, :source_degraded],
  severity: [:warning, :error, :critical] | nil,
  products: [:intervals, :instants],
  limit: 500
}
```

Contact interval overlay:

```elixir
%Frame{
  source: :events,
  shape: :intervals,
  time_axis: :generation_time,
  fields: [
    %Field{name: "starts_at", kind: :time, values: [...]},
    %Field{name: "ends_at", kind: :time, values: [...]},
    %Field{name: "kind", kind: :enum, values: [:scheduled_contact, :realized_contact]},
    %Field{name: "status", kind: :enum, values: [:scheduled, :active, :completed]},
    %Field{name: "label", kind: :string, values: ["DSS-14 pass"]},
    %Field{name: "contact_id", kind: :string, values: [...]}
  ],
  meta: %{
    family: :contacts,
    scope: %{spacecraft_id: "sc_001"},
    warnings: []
  }
}
```

Mission timeline annotation frame:

```elixir
%Frame{
  source: :events,
  shape: :events,
  time_axis: :receipt_time,
  fields: [
    %Field{name: "occurred_at", kind: :time, values: [...]},
    %Field{name: "category", kind: :enum, values: [:health, :runtime]},
    %Field{name: "kind", kind: :enum, values: [:limit_violation]},
    %Field{name: "severity", kind: :enum, values: [:warning]},
    %Field{name: "title", kind: :string, values: [...]},
    %Field{name: "source_record_id", kind: :string, values: [...]}
  ],
  meta: %{
    family: :mission_timeline,
    projection: :mission_events | :operational_events,
    cursor: %{occurred_at: "...", mission_event_id: "..."} | nil,
    warnings: []
  }
}
```

Source-health transition annotation frame:

```elixir
%Frame{
  source: :events,
  shape: :events,
  time_axis: :occurred_at,
  fields: [
    %Field{name: "occurred_at", kind: :time, values: [...]},
    %Field{name: "category", kind: :enum, values: [:source_health]},
    %Field{name: "kind", kind: :enum, values: [:degraded, :recovered]},
    %Field{name: "severity", kind: :enum, values: [:warning, :info]},
    %Field{name: "title", kind: :string, values: [...]},
    %Field{name: "source_record_id", kind: :string, values: [...]},
    %Field{name: "source_health", kind: :enum, values: [:degraded, :healthy]},
    %Field{name: "previous_source_health", kind: :enum, values: [:healthy, :degraded]},
    %Field{name: "logical_source", kind: :enum, values: [:telemetry, :limits]},
    %Field{name: "data_source_id", kind: :string, values: [...]}
  ],
  meta: %{
    family: :source_health,
    product: :source_health_transitions,
    projection: :dashboard_source_health_events,
    cursor: %{observed_at: "...", source_health_event_id: "..."} | nil,
    warnings: []
  }
}
```

Source-capability posture annotation frame:

```elixir
%Frame{
  source: :events,
  shape: :events,
  time_axis: :occurred_at,
  fields: [
    %Field{name: "occurred_at", kind: :time, values: [...]},
    %Field{name: "category", kind: :enum, values: [:source_capability]},
    %Field{name: "kind", kind: :enum, values: [:source_capability_fallback]},
    %Field{name: "severity", kind: :enum, values: [:warning]},
    %Field{name: "source_record_id", kind: :string, values: [...]},
    %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
    %Field{name: "capability_status", kind: :enum, values: [:fallback]},
    %Field{name: "requested_time_axis", kind: :enum, values: [:generation_time]},
    %Field{name: "executed_time_axis", kind: :enum, values: [:receipt_time]},
    %Field{name: "source_execution_status", kind: :enum, values: [:resolved]}
  ],
  meta: %{
    family: :source_capability,
    product: :source_capability_postures,
    projection: :operational_events,
    cursor: %{
      occurred_at: "...",
      source_capability_posture_id: "...",
      capability_status: :fallback
    } | nil,
    warnings: []
  }
}
```

Event filtering:

- family filters select backing projection families (`:contacts`,
  `:mission_timeline`, `:source_health`, `:source_capability`, later `:commands`,
  `:catalog_runtime`, `:replay`)
- kind filters select event kinds within a family
- severity filters apply to event-like annotations, not neutral intervals unless
  the family defines severity
- scope filters should use the dashboard `scope_context` by default
- data realm and replay-run filters must keep replay/simulation events separate
  from flight; replay mission-timeline and contact-interval reads should prefer
  canonical `operational_events` when `replay_run_id` is present because legacy
  mission/contact projections are not replay-scoped consistently

Events warnings:

- `:unsupported_event_family` — requested event family is not available in v0.
- `:partial_event_coverage` — returned events come from projections that do not
  cover all operational event families.
- `:event_projection_stale` — `mission_events` or contact projection may be
  behind source records.
- `:event_scope_ambiguous` — event cannot be cleanly associated with the
  requested spacecraft/contact/source scope.
- `:event_time_axis_mismatch` — event timestamps are operational/receipt time
  while the chart uses generation time.
- `:event_limit_truncated` — query hit the requested limit.

v0 implementation boundary:

- **Supported:** contact/pass shading from scheduled/realized contacts.
- **Supported:** flight mission timeline annotations from `mission_events`.
- **Supported:** replay-scoped mission timeline annotations from canonical
  `operational_events` projected into mission-event Frame shape.
- **Supported:** source-health transition annotations from
  `dashboard_source_health_events`.
- **Partial:** limit-violation annotations through `mission_events`, while rich
  limit overlays remain the Limits source.
- **Future:** command annotations.
- **Partial:** catalog/runtime/source-binding interval evidence from the
  operational event spine; source-bound historical frames carry selected
  source-binding, active binding-set, source-endpoint application-binding, and
  telemetry catalog-revision interval refs when request context selects them
  unambiguously.
- **Future:** richer source-health intervals from the operational event spine.
- **Partial:** replay/simulation lifecycle overlays; replay mission timeline has
  canonical operational-event backing, while broader contact/runtime event
  segregation is still maturing.
- **Future:** eclipse, ephemeris, maneuver, and derived flight-dynamics events.

The Events source should prefer intervals for durable context and annotations
for operational moments. Widgets should not infer event semantics from raw
tables; they consume event Frames and host-provided styling helpers.

#### 5.3.4 Operational Observables source v0 contract

The Operational Observables source resolves Cadence-produced observables from
the registry (§3.2.1). It is intentionally not named "metrics" because many
values are states or intervals, not numeric samples.

The source is a router over subsystem-owned resolvers. The dashboard engine sees
one logical source; each subsystem owns the projection/stream/adapter that
produces its values.

Source identity:

```elixir
%SourceCapabilities{
  logical_source: :operational_observables,
  supports_latest?: true,
  supports_bounded_history?: true,
  supports_intervals?: true,
  supports_live_tail?: false,
  supported_kinds: [:metric, :state, :interval],
  supported_time_axes: [:receipt_time, :occurred_at],
  completeness: :best_effort
}
```

Source query:

```elixir
%OperationalObservableSourceQuery{
  request_id: "source_req_...",
  organization_id: "...",
  mission_id: "...",
  observables: [
    "comms.transport.downlink_bitrate",
    "ground.station.connection_state"
  ],
  scope: %{
    kind: :transport | :contact | :ground_station | :spacecraft | :mission,
    ids: ["transport_ksat_tcp"]
  },
  time: %TimeContext{
    mode: :live | :archive | :replay_run,
    axis: :receipt_time | :occurred_at,
    from: DateTime.t() | nil,
    to: DateTime.t() | nil
  },
  data: %DataContext{
    realm: :flight,
    source_mode: :primary
  },
  sampling: %{
    mode: :latest | :raw_series | :state_timeline | :intervals,
    target_points: 1200
  }
}
```

Latest metric/state frame:

```elixir
%Frame{
  source: :operational_observables,
  shape: :scalar,
  time_axis: :receipt_time,
  fields: [
    %Field{name: "time", kind: :time, values: [~U[2026-06-16 12:00:00Z]]},
    %Field{
      name: "downlink_bitrate",
      kind: :number,
      values: [1_250_000],
      metadata: %{
        observable_id: "comms.transport.downlink_bitrate",
        owner: :comms,
        unit: "bps",
        scope: %{transport_id: "transport_ksat_tcp"},
        freshness_state: :fresh,
        quality_state: :good,
        state_color_policy: nil
      }
    }
  ],
  meta: %{
    resolver: Cadence.Dashboards.Sources.OperationalObservables.Comms,
    data_realm: :flight,
    warnings: []
  }
}
```

State timeline frame:

```elixir
%Frame{
  source: :operational_observables,
  shape: :events,
  time_axis: :occurred_at,
  fields: [
    %Field{name: "time", kind: :time, values: [...]},
    %Field{name: "state", kind: :enum, values: [:connected, :degraded, :disconnected]},
    %Field{name: "reason", kind: :string, values: [...]}
  ],
  meta: %{
    observable_id: "ground.station.connection_state",
    allowed_values: [:connected, :connecting, :degraded, :disconnected],
    state_color_policy: :connection_state,
    warnings: []
  }
}
```

Interval frame:

```elixir
%Frame{
  source: :operational_observables,
  shape: :intervals,
  time_axis: :occurred_at,
  fields: [
    %Field{name: "starts_at", kind: :time, values: [...]},
    %Field{name: "ends_at", kind: :time, values: [...]},
    %Field{name: "state", kind: :enum, values: [...]},
    %Field{name: "label", kind: :string, values: [...]}
  ],
  meta: %{
    observable_id: "contacts.current_phase",
    family: :contacts,
    warnings: []
  }
}
```

Resolver rules:

- the observable registry selects the logical source and subsystem resolver
- resolver output must be normalized into Frames before reaching widgets
- resolver-specific payloads stay in field/frame metadata, not widget code
- missing resolver capabilities produce warnings rather than silent omission
- operational observables must respect `scope_context` and `data_context`
  exactly like telemetry

Operational observable warnings:

- `:unknown_observable` — observable id is not registered.
- `:unsupported_observable_scope` — requested scope is invalid for the
  observable definition.
- `:observable_resolver_unavailable` — owner subsystem cannot satisfy the
  request.
- `:observable_projection_stale` — projection exists but freshness policy says
  it is stale.
- `:unsupported_time_axis` — resolver cannot evaluate the requested time axis.
- `:partial_data` — resolver returned incomplete history or unsupported
  aggregation.

v0 implementation boundary:

- **Supported:** compiled first-party definitions.
- **Supported:** latest values for a small set of contact/comms/runtime health
  observables backed by existing projections or in-memory state.
- **Partial:** bounded history when a subsystem already has records.
- **Future:** customer-defined operational observables.
- **Future:** plugin-defined observable families.
- **Future:** external metrics adapters.
- **Future:** governed lifecycle events for observable definition activation.

This source is the guardrail that keeps dashboards from becoming telemetry-only:
widgets bind to observable ids, and the engine resolves the right logical source
without exposing subsystem storage.

### 5.4 Data contexts, realms, and source bindings

The engine must not assume a mission has exactly one TSDB. Flight missions,
rehearsals, AI&T, simulation, shadow ingest, and replay can all contain values
for the same observable ids. The observable catalog defines **what** a value
means; the **data context** defines which corpus is being evaluated.

Four concepts stay separate:

- **Logical source** — domain source such as `Telemetry`, `Limits`, `Events`, or
  operational observables.
- **Physical data source** — managed Timescale/Postgres, customer QuestDB,
  ClickHouse, object archive, or another adapter-backed store.
- **Data realm / lane** — flight, rehearsal, AI&T, simulation, lab, shadow
  ingest, archive, or replay.
- **Binding policy** — which physical source backs a logical source for a
  mission, realm, time range, and mode.

Same observable, different realm:

```yaml
observable_id: tlm.hk.battery_voltage
semantics: spacecraft bus battery voltage
realms:
  - flight
  - rehearsal
  - ait
  - simulation
  - replay
```

Dashboard/runtime data context:

```yaml
data_context:
  realm: flight
  source_mode: primary
  allowed_realms: [flight, rehearsal, ait, simulation]
```

Rehearsal context:

```yaml
data_context:
  realm: rehearsal
  rehearsal_id: reh_2026_06_15_countdown
  truth_model: simulated
  isolation: no_flight_mixing
```

The safety rule is explicit: **realms do not mix unless the dashboard or widget
opts into comparison.** A flight dashboard defaults to flight data. A rehearsal
dashboard cannot silently read flight data. A multi-realm comparison returns
separate frames per realm/source so the renderer can label them honestly.

#### 5.4.1 Data source registry

Data sources are registered resources, not hardcoded adapter modules:

```elixir
%DataSource{
  data_source_id: "ds_...",
  owner: :cadence | :customer,
  kind: :managed_tsdb | :byo_tsdb | :postgres | :object_archive | :projection,
  adapter: Cadence.Dashboards.Sources.Telemetry,
  organization_id: "..." | nil,
  mission_id: "..." | nil,
  isolation_level: :shared | :org_isolated | :mission_isolated | :customer_owned,
  credentials_ref: "secret_..." | nil,
  capabilities: %{
    latest?: true,
    range_scan?: true,
    bounded_history?: true,
    native_decimation?: false,
    watermarks?: false
  }
}
```

v0 persistence stores these in `dashboard_data_sources`. The row is intentionally
adapter-oriented, not UI-oriented: it records physical backend identity,
organization/mission scope, isolation level, adapter module, capabilities, and
metadata. Credentials remain referenced indirectly through `credentials_ref`.
The row does not store passwords, tokens, connection strings with secrets, or
provider credentials.

The first enforced BYO rule is intentionally conservative:

- `kind: :byo_tsdb` requires `owner: :customer`.
- `kind: :byo_tsdb` requires `isolation_level: :customer_owned`.
- customer-owned/BYO sources require `organization_id`.
- customer-owned/BYO sources require a non-empty `credentials_ref`.
- source metadata must not contain obvious credential or secret keys; connection
  details that are not secret can be referenced with metadata IDs such as
  `endpoint_ref`.

The broader enforced isolation contract is:

- `isolation_level: :org_isolated` requires `organization_id`.
- `isolation_level: :mission_isolated` requires both `organization_id` and
  `mission_id`.
- `DataSource.isolation_profile/1` emits a redacted physical-isolation profile
  with the isolation level, physical boundary, semantic scope, storage kind, and
  non-secret topology references such as `endpoint_ref` or `topology_ref`.
- source-health and credential connection profiles carry that isolation profile
  so dashboard warnings, diagnostics, and operator readiness views can explain
  whether a value came from a shared filtered store, an organization-isolated
  backend, a mission-isolated backend, or a customer-owned backend.

Managed QuestDB provisioning now has a first operational seam:
`Cadence.Dashboards.ManagedQuestDBProvisioning`. It accepts an organization or
mission isolation intent, applies the versioned Cadence QuestDB schema through
`QuestDB.SchemaMigrator`, persists the managed telemetry data source, and records
redacted provisioning evidence in the data-source lifecycle event payload. The
public plan/result surfaces expose endpoint/topology refs, physical isolation,
and migration versions, but not raw passwords, executable migration functions,
or endpoint credentials. `Cadence.Dashboards.ManagedQuestDBProvisioningJobs`
wraps the same operation in the durable `Cadence.Jobs` runner: the job payload
stores only redacted provisioning intent, execution receives runtime-only
migration material from deployment config, success persists the same
data-source/provisioning evidence, and failure/retry use normal background-job
state. This is not yet a full infrastructure allocator; it is the product-owned
operation that future deployment automation and admin UI can call.
`mix cadence.dashboards.managed_questdb_provision` provides the current
ops-facing command path with explicit `--plan` and `--apply` modes, redacted
output, and nonzero failure semantics for deployment automation.

Adapters receive the resolved source binding and a redacted connection profile.
When a material resolver is configured, probes may also receive ephemeral
`source_connection_material` in process for adapter IO. That material is not
copied into events, health payloads, dashboard documents, logs, or UI assigns.
`SourceCredentials.resolve/2` remains the non-secret descriptor path;
`SourceCredentials.resolve_material/2` is the exchange point where
the material authorizer can deny access before `SecretMaterialResolver`
delegates to a configured secret backend and validates connection material.
Mission-scoped material resolution is audited as a canonical security event
with redacted success, failure, or denial metadata, while the current
env-profile backend remains intentionally simple: durable credential metadata
stores at most a profile pointer, runtime config maps that profile to
environment variable names, and adapter IO receives only an ephemeral material
struct.

The engine treats this capability map as a physical-source constraint layered on
top of the logical adapter contract. For example, a telemetry adapter may know
how to return bounded history, but a selected BYO source with
`range_scan?: false` must remove history sampling from the planned capability
surface. Conversely, a QuestDB-backed source can advertise
`native_decimation?: true` to make `:decimated_envelope` a valid plan product.
The merged capability record is also copied into request metadata as capability
provenance and capability posture so warnings, frames, source facts, cache
diagnostics, and runtime execution summaries can explain which physical source
shaped the plan and whether the plan is native, fallback, or unsupported.

Cadence bootstraps one idempotent default managed source when configured:

```elixir
%DataSource{
  data_source_id: "managed_questdb_primary",
  owner: :cadence,
  kind: :managed_tsdb,
  adapter: Cadence.Dashboards.Sources.Telemetry,
  isolation_level: :shared,
  metadata: %{bootstrap_default?: true}
}
```

#### 5.4.2 Source bindings

A source binding selects which data source backs a logical source in a realm:

```elixir
%DataBinding{
  binding_id: "binding_...",
  organization_id: "..." | nil,
  mission_id: "...",
  realm: :flight | :rehearsal | :ait | :simulation | :replay,
  logical_source: :telemetry,
  data_source_id: "ds_managed_timescale_primary",
  dataset: "flight_ops",
  priority: 0,
  status: :active,
  binding_version: 3,
  current_event_id: "dashboard_data_binding_event_...",
  active_from: nil,
  active_to: nil
}
```

v0 persistence stores the current projection in `dashboard_data_bindings`.
`Cadence.Dashboards.DataSources` also records append-only
`dashboard_data_binding_events` for registration, real changes, enable,
disable, and supersession. Repeated identical upserts are no-ops, which keeps
bootstrap/default writes idempotent instead of creating noisy event history.

The resolver chooses the most specific active binding by organization, mission,
realm, and logical source, then uses priority to break ties within the same
specificity. Bindings with `status: :disabled`, `status: :superseded`, future
`active_from`, or expired `active_to` are not selected. Missing bindings and
bindings that reference unknown data sources produce structured source warnings
rather than falling back silently once persisted scoped rows exist.

The matching bootstrapped binding is global flight telemetry:

```elixir
%DataBinding{
  binding_id: "default_flight_telemetry",
  realm: :flight,
  logical_source: :telemetry,
  data_source_id: "managed_questdb_primary",
  dataset: "flight",
  metadata: %{bootstrap_default?: true}
}
```

`config :cadence, :dashboard_data_sources` controls whether persisted bindings
are used for resolution and whether these defaults are bootstrapped on
application startup.

Binding examples:

```yaml
source_bindings:
  telemetry:
    source_id: managed_timescale_primary
    dataset: flight_ops
  operational_observables:
    source_id: managed_timescale_primary
    dataset: flight_ops
  events:
    source_id: cadence_postgres
```

```yaml
source_bindings:
  telemetry:
    source_id: customer_questdb_rehearsal
    dataset: oasis_rehearsal_12
  events:
    source_id: cadence_postgres
    dataset: rehearsal_events
```

The planner resolves:

```
observable + time_context + scope_context + data_context
  → logical source
  → binding policy
  → physical adapter
  → Frame(s)
```

#### 5.4.3 Multi-source merge policy

If more than one source can satisfy the same logical request, Cadence must not
guess. The data context declares the merge mode:

- **primary** — read exactly one selected binding.
- **fallback** — use secondary sources only when the primary is unavailable.
- **compare** — return separate frames per source/realm; never merge values.
- **federated** — stitch only when binding windows are non-overlapping and
  explicitly marked safe to combine.

Every returned frame carries `data_source_id`, `realm`, `dataset`, and
`binding_id` metadata so operators can tell whether they are looking at flight,
AI&T, rehearsal, customer BYO, managed, replay, or simulated data.

### 5.5 Physical backend adapters (multi-TSDB)

Each logical source resolves through a **pluggable backend adapter**. This is a
*generalization of an existing pattern*, not net-new architecture:
`Cadence.Telemetry.CurrentValueStore` and `HistoryStore` are already behaviours
with ETS / Postgres / Noop adapters (`child_spec` + callbacks). Multi-TSDB adds
more adapters, per-mission backend selection, and capability metadata.

**Capability negotiation.** Backends advertise what they can do; the engine
adapts and panels degrade gracefully (as Grafana grays out options per source):

- range scan
- server-side time-bucketing
- extrema-preserving decimation (min/max per bucket)
- native LTTB (e.g. Timescale Toolkit `lttb()`)
- live tail / streaming

Backend capability examples: Timescale (`time_bucket`, continuous aggregates,
`lttb()`), QuestDB (`SAMPLE BY ... ALIGN TO CALENDAR`), ClickHouse
(`toStartOfInterval`), plain Postgres today (`date_bin` + manual min/max), or a
customer BYO store that may support little of this.

**v1 imperative:** ship only the managed/Postgres adapter, but **behind the
capability-aware interface**, so BYO arrives as an adapter, not a rewrite.

### 5.6 Structured queries, not a query language

A "query" is a structured, catalog-bound binding —
`{observables, scope-context, time-context, data-context, aggregation, value-type,
source}`
— **never** raw SQL/PromQL/Flux. The observable catalog is the query builder.
This is validated by COSMOS, whose streaming "query" is a structured key
(`MODE__TLM__TARGET__PACKET__ITEM__VALUETYPE[__REDUCEDTYPE]`), not a language.
No query language is *why* correctness is free.

### 5.7 Operational & ground-segment data (partially designed)

Dashboards are not only spacecraft telemetry. Operators also watch the state of
the **ground system and the links** — data Cadence itself produces, not decom
from a spacecraft. Captured here so it is not forgotten; the observable framing
is decided, but the per-subsystem catalog and storage contracts are not.

Examples (not exhaustive — this list almost certainly under-scopes it):

- **Link / RF** — uplink & downlink bitrate, symbol rate, lock / frame-sync
  status, Eb/N0, SNR, AGC, Doppler.
- **Connection / transport** — interface up/down, transport-binding state, bytes
  in/out, reconnect counts.
- **Contacts / passes** — current contact state, time-to-AOS/LOS, station,
  elevation.
- **File transfer (CFDP / downlink)** — download progress, transaction state,
  retransmits, downlink-record assembly.
- **Command pipeline** — queue depth, release rate, pending acks, verification
  counts.
- **Pipeline / platform health** — ingest rate, decom errors, frame gaps,
  latency, storage / TSDB write rate.

Most of these are **time-series + state** — the same shape the engine already
handles — and have natural homes in existing subsystems (`Transports`,
`Contacts`, `Commanding`, ingest, derived telemetry).

**Resolved framing for now:** these are catalog-bound operational observables,
not fake spacecraft telemetry. Some may be materialized into the same physical
store as telemetry samples for performance, but the semantic owner remains the
subsystem that produces them. This preserves one dashboard engine without
flattening antenna state, command queue depth, and spacecraft packet values into
one misleading noun.

## 6. Live ↔ Replay (hiding the seam)

The defining feature, and the part we copy almost verbatim from COSMOS's
Streaming API (`openc3-cosmos-cmd-tlm-api/app/models/streaming_api.rb`,
`logged_streaming_thread.rb`).

The operator-facing time controller should feel continuous, but the engine must
carry a precise `time_context`:

```elixir
%TimeContext{
  mode: :live | :archive | :replay_run,
  axis: :generation_time | :receipt_time,
  from: DateTime.t() | nil,
  to: DateTime.t() | nil,
  replay_run_id: binary() | nil,
  playback_rate: float() | nil
}
```

That controller is the display/runtime context, not necessarily the execution
axis for every logical source. During planning, source requests should normalize
to source-native axes where needed: telemetry and limits history execute against
receipt time, events execute against occurrence time, and latest/non-temporal
reads may preserve the dashboard display axis. The returned Frame and metadata
must expose the actual source request axis so diagnostics and data links remain
honest.

For live/archive telemetry, **`from` and `to` decide the behavior:**

| from | to | behavior |
| --- | --- | --- |
| null | — | realtime only |
| set | null | historical playback, then **seamless handoff to live** |
| set | past | bounded historical |

The historical → live handoff bridges the store read into the live stream with
a small **overlap buffer and source-level reconciliation**, so the client sees
one unbroken sequence. The reconciliation policy should come from telemetry
data management, not widget code. This is the "drag the scrubber back; release
to *now*" experience. The seam is hidden **inside the Telemetry source** —
callers never branch on live vs. historical.

Cadence already models replay at the contact level: `RealizedContact.clock_mode`
is `:live | :replay`. Dashboard replay should **align with that existing
concept**, not invent a parallel one. Replay-run mode, however, is not selected
by time alone: it requires a `replay_run_id` or equivalent replay context
because replay outputs are a distinct data product from the mission's canonical
archive.

**BYO wrinkle:** live ingest and historical archive may be *different backends*
(e.g. managed live + customer-owned history), so the handoff can span a backend
— and possibly an org — boundary. The seam contract lives at the source level so
it works regardless.

Terminology:

- **Live** — current stream, anchored to now.
- **Archive** — canonical mission history produced by real ingestion.
- **Replay run** — a specific reprocessing/simulation run with its own identity,
  telemetry outputs, managed capability records, timers, and action requests.

The UX can present these as one mission-time control. The engine should not
collapse their data semantics.

## 7. Decimation

The one genuinely net-new engine primitive: **nothing under the engine provides
server-side downsampling today** (`HistoryStore` returns raw rows). A wide
Replay window on a high-rate point would otherwise return unbounded samples.

**Resolved direction — query-time, extrema-preserving, capability-aware:**

- **Query-time, not precompute.** COSMOS *deleted* its precompute reducer
  (`migrations/20260204000000_remove_decom_reducer.rb`) in favor of query-time
  TSDB aggregation. We start query-time; precompute only if proven necessary.
- **Preserve extrema (min/max per bucket), never average.** Averaging and
  every-Nth smooth away spikes — a red-limit excursion across 2–3 samples
  vanishes into the mean (MinMaxLTTB paper). The reduced representation is a
  **min–max envelope band + mean line**, bucketed to ≈ panel pixel width, so
  limit excursions *survive* decimation and stay colored. COSMOS keeps
  `MIN/MAX/AVG/STDDEV` per `SAMPLE BY` bucket for exactly this reason.
- **Bucket count ≈ target pixel width** (~1–2k), derived from
  `time-range ÷ pixels` (Grafana's `maxDataPoints`/`$__interval`).
- **MinMaxLTTB is the portability strategy.** Its two stages map onto the
  capability split: the cheap **MinMax preselection is the portable pushdown**
  (every backend can do min/max-per-coarse-bucket, or the engine caps-and-scans),
  and the **LTTB refinement is the portable in-engine step**. One decimation
  path spans a managed TSDB and a "dumb" customer store without branching the
  semantics. Use a backend's native `lttb()`/`SAMPLE BY` when advertised;
  otherwise fall back in-engine.

## 8. The clock model (open decision)

Spacecraft telemetry has **two clocks**: `generation_time` (onboard/source) and
`receipt_time` (ground). This is *the* "telemetry ≠ server metrics" decision.

- COSMOS timelines on packet/onboard time (`PACKET_TIMESECONDS`), with ground
  time also stored — arguing the default x-axis should be **onboard
  `generation_time`, with `receipt_time` selectable**.
- **Implemented engine contract:** bounded telemetry history supports both
  ground-time (`from/to_receipt_time`) and source-time
  (`from/to_observed_at`) reads. Managed QuestDB uses its `observed_at`
  timestamp (`generation_time || receipt_time`), ETS mirrors that behavior, and
  the Postgres fallback filters on `generation_time || receipt_time`.
- **Data-source capability narrowing:** adapter capabilities are the logical
  contract, but a selected physical data source may advertise fewer
  `supported_time_axes` and `supported_products`. A receipt-only source may
  still serve a generation-time dashboard by falling back to a receipt-time
  query, but the resulting frame and warning metadata must identify
  `executed_time_axis: :receipt_time` and
  `supported_time_axes: [:receipt_time]`. Product narrowing is a hard source
  contract constraint: for example, an operational-observables store can
  advertise RF metric history without also claiming transport-bitrate history.
  Ops Data Sources exposes the effective sampling, source products, backing
  products, and product families so operators can choose a source that matches
  the dashboard's requested latest, state-history, or raw-series contract.
- **Operator-facing dashboard contract:** URL/runtime state carries `time_axis`
  when the selected mode needs a non-default clock. Live and replay-run
  dashboards default to `generation_time`; archive snapshots default to
  `receipt_time` so historical ground-received investigation remains explicit.
  Operators can switch between `generation_time` and `receipt_time` in the
  runtime toolbar, and the selected axis is exposed in dashboard/engine
  diagnostics, copied URLs, data links, source requests, frame metadata, and
  overlay evidence.

**Recommendation:** keep the mode-specific defaults above, expose both clocks,
and retain adapter capability warnings when a backing source cannot answer the
selected axis.

Dashboard clock behavior depends on the broader telemetry data-management model:
late arrivals, backfills, corrections, source watermarks, and latest-value
projection policy should be defined outside this document. See
`docs/telemetry-data-management-design.md`.

## 8.1 Catalog versioning and operational event dependency

Historical correctness depends on knowing which catalog/runtime/source meaning
was active when data was observed. Dashboards should default to **observed
semantics**: render samples with the catalog revision, runtime binding, source
binding, limit definition, and data realm that applied at observation time.

That requires a broader operational event/timeline model, not dashboard-specific
state. Runtime activation intervals, catalog revision applications,
source-binding changes, limit-definition changes, contact state, command events,
replay runs, and source degradation should be derived from an auditable event
model. See `docs/operational-event-timeline-design.md` for the dependency and
event-spine direction.

## 8.2 Limit semantics across time

Limits are not just chart decoration. A limit definition is governed operational
policy that can change independently from the telemetry samples it classifies.
That creates a dashboard-specific correctness problem:

```text
sample value V at time T is immutable
limit definition L1 classified it as green when observed
limit definition L2 would classify the same value as yellow today
```

Both answers are useful, but they are not the same answer. Dashboards therefore
need an explicit **limit semantics mode**:

- **Observed limits** *(default)* — render samples and transitions using the
  limit definition that was active when the sample was evaluated/observed. This
  is the operational truth: "what did the console know at the time?"
- **Current limits / recomputed** — reclassify historical values against the
  currently active definition. This is useful for analysis after a threshold
  change, but it must be opt-in and labeled as recomputed.
- **Definition comparison** — show old/new bands or old/new states side by side
  so operators can review the impact of a proposed or newly activated limit
  change.

The existing model already points in the right direction:

- governed limit definitions are versioned (`limit_definition_id`, `version`)
- `telemetry_limit_events` snapshot the evaluated definition id/version onto
  each event
- `telemetry_latest_limit_states` is a current-state projection for fast live
  widgets

The missing architectural concept is **activation/effective interval**. A
versioned limit definition existing in the database is not enough; dashboards
need to know when that version became active for a mission, spacecraft,
operational scope, data realm, and sometimes mode/phase. Limit activation,
supersession, disablement, and evaluation runs should therefore become part of
the operational event/interval model (§8.1).

### 8.2.1 What the Limits source returns

The Limits source should return three related but distinct products:

1. **Definition intervals** — bands/policies active over time. If a threshold
   changed halfway through a chart, the band is segmented at the activation
   boundary.
2. **Evaluation events / transitions** — observed classifications for samples,
   including `limit_event_id`, `sample_id`, `limit_definition_id`,
   `limit_definition_version`, `limit_set_name`, `normalized_state`, and
   `violation`.
3. **Analysis buckets** — limit-aware summaries for decimated displays,
   including bucket start/end, worst limit state, event counts, divergence
   counts, and rolled-up sample/event ids.

Widgets consume both through host overlays:

```elixir
%Frame{
  source: :limits,
  shape: :intervals,
  fields: [
    %Field{name: "active_from", kind: :time, values: [...]},
    %Field{name: "active_to", kind: :time, values: [...]},
    %Field{name: "limit_definition_id", kind: :string, values: [...]},
    %Field{name: "limit_definition_version", kind: :number, values: [...]},
    %Field{name: "limit_set_name", kind: :string, values: [...]},
    %Field{name: "red_low", kind: :number, values: [...]},
    %Field{name: "yellow_low", kind: :number, values: [...]},
    %Field{name: "yellow_high", kind: :number, values: [...]},
    %Field{name: "red_high", kind: :number, values: [...]}
  ],
  meta: %{
    sampling: :definition_intervals,
    semantics_mode: :observed,
    activation_evidence: [%{limit_definition_lifecycle_event_id: "..."}],
    incomplete_intervals?: false
  }
}
```

For live value tiles, the fast path can still read the latest-state projection.
For historical charts, the engine should prefer event history and effective
definition intervals over the latest projection.

### 8.2.2 Limit changes and decimation

Limit-aware decimation cannot be value-only. A min/max envelope preserves value
spikes, but the dashboard also needs to preserve **state excursions**:

- a red/yellow excursion inside a bucket must survive even if the displayed
  representative value is green
- a limit-definition boundary inside a bucket must split or annotate the bucket
  *(source-native analysis buckets now split by definition identity)*
- mixed-state buckets should carry `worst_normalized_state`, transition counts,
  and event refs
- recomputed/current-limit mode must never overwrite observed limit events in
  place; it produces a separate overlay/frame
- late-data policy decisions that originate from a dashboard data-link
  inspector preserve the selected dashboard limit mode in the policy form,
  durable lifecycle payload, action metadata, and resolved workflow handoff rows
  so a recomputed/current/compare review is not flattened back to observed
  semantics after the operator decides how to treat late samples; replay-run
  completed-workflow inspectors also preserve dashboard time mode and replay run
  id through the rendered policy handoff, force event-only policy application,
  and reject replay-context sample execution so replay review cannot implicitly
  write canonical flight data
- revision/correction-authority decisions that originate from a dashboard
  data-link inspector also preserve the selected dashboard limit mode through
  the decision form, durable evidence ref, observation-identity state payload,
  and latest-action handoff metadata so conflict decisions remain tied to the
  limit semantics the operator was reviewing
- source-frame recomputation, time-series marker payloads, source-native
  analysis buckets, chart-rendered bucket spans, threshold-region fills, and
  presenter-level decimated envelope rollups exist for bounded sample history

This is why limits remain a logical source rather than a renderer concern. The
engine asks for limit-aware bucket metadata; widgets only color what the host
hands them.

### 8.2.3 Scope and conditional limits

The future limit model should not assume one mission-wide definition per point.
Real systems often need scope- or mode-conditioned limits:

- spacecraft-specific thresholds
- contact/ground-station/link specific thresholds
- launch/commissioning/nominal/safe-mode threshold sets
- thermal configuration or payload-mode dependent thresholds
- rehearsal/AI&T definitions that deliberately differ from flight

The dashboard implication is that `scope_context` and `data_context` participate
in limit resolution. The same observable and timestamp can resolve to different
limit intervals depending on operational scope and realm. Multi-realm or
multi-scope dashboards must label those definitions and avoid silently merging
limit states.

### 8.2.4 Dashboard warnings

The engine should surface explicit warnings when limit semantics are not clean:

- no active limit definition for a point/time/scope
- multiple candidate definitions match the same point/time/scope
- a chart spans a limit-definition change
- historical values are being recomputed under current limits
- latest limit state is older than the latest sample
- limit evaluation is incomplete for a backfilled or late-arriving sample
- comparison mode mixes flight/rehearsal/AI&T definitions

## 8.3 Data Revision and Validity Warnings

Telemetry data-management owns duplicate, conflict, correction, supersession,
and backfill policy. The dashboard engine owns carrying those facts into frames
and making them visible.

Telemetry-backed frames should preserve these fields when the source can provide
them:

- `observation_identity_id`
- `sample_id`
- `validity_state`
- `revision_kind`
- `supersedes_sample_id`
- `superseded_by`
- `data_realm`
- `data_source_id`
- correction/backfill/import run id when applicable

Dashboard warning codes should be source supplied and widget agnostic:

| Warning | Meaning | Typical UI treatment |
| --- | --- | --- |
| `:corrected_range` | selected range includes values superseded by corrections | badge + drilldown link |
| `:conflicting_observations` | selected range contains unresolved conflicts | high-salience warning |
| `:advisory_backfill` | data is present but not authoritative for canonical flight history | badge + realm/source label |
| `:late_arrival` | values arrived after the viewed time range was first observed | subtle badge on archive views |
| `:mixed_revisions` | frame contains multiple semantic revisions or catalog contexts | badge + split/inspect affordance |
| `:as_recorded_view` | view intentionally shows pre-correction history | view-mode label |
| `:all_revisions_view` | view intentionally shows all revisions instead of a canonical projection | warning badge + evidence detail |
| `:recomputed_values` | view intentionally uses recomputed read semantics | warning badge + provenance label |

Widgets should not decide which value wins. They render the `Frame` they are
given, surface warnings, and expose data links for audit. The source layer
selects `DataContext.view` as `:canonical | :as_recorded | :all_revisions |
:recomputed` and records that selected view in request/cache/link provenance and
frame metadata. Telemetry sources normalize this through
`Cadence.Telemetry.SelectionPolicy`; the default dashboard view is `:canonical`,
while investigative views must opt into broader revision sets. Source-specific
data contexts can override the selected view for one logical source without
changing the whole dashboard request.
The latest/current projection feeding dashboard scalar reads is populated from
storage-enriched observation samples so the same validity and identity metadata
drives live, historical, and rebuilt latest reads.

For identity-level revision state, dashboards should use
`Cadence.Telemetry.Storage.fetch_observation_identity_state/1` and
`Cadence.Telemetry.Storage.list_observation_identity_states/2`; frame enrichment
may use `Cadence.Telemetry.Storage.fetch_observation_identity_states/2` for bulk
lookups. Bulk lookups must pass tenant/source context from the planned source
request and resolved binding so revision-state metadata cannot cross
organization, mission, realm, data-source, or binding boundaries. The
`telemetry_observation_identity_states` table is a private current-state
projection; dashboard sources may translate it into frame metadata and warning
codes, but widgets should not query or interpret the table directly.

Revision-state enrichment is part of the dashboard cache contract. Telemetry
frames should include a `telemetry_revision_dependency` fingerprint in frame
metadata, and materialized frame cache keys should include that dependency.
When the identity-state projection changes because of a duplicate, conflict,
correction, supersession, or advisory import, the producing write/event path
must invalidate matching source-result and frame artifacts. Otherwise widgets
can serve stale conflict/correction badges even when the underlying sample rows
have not changed.

Use `Cadence.Dashboards.RuntimeInvalidation.telemetry_revision_state_changed/2`
for identity-state projection changes. Supported filters include tenant/source
identity (`organization_id`, `mission_id`, `data_source_id`,
`source_binding_id`, `realm`), dashboard data identity (`logical_source:
:telemetry`, `observable`), and revision identity (`observation_identity_id` or
`telemetry_revision_dependency`). This boundary intentionally does not default
to live-only cache policy because correction and resolution workflows can affect
both live and snapshot dashboard artifacts.

The first decision surface is
`Cadence.Telemetry.Storage.apply_observation_identity_decision/3`. Dashboard
sources should only observe its effects through the storage read model,
revision-state dependency fingerprints, and runtime invalidation; widgets should
not call decision APIs directly. Decision history is preserved through
`Cadence.Telemetry.Storage.list_observation_identity_decision_events/2`.
Revision decision events are resolvable dashboard data links, and the data-link
inspector can now submit follow-up correction-authority decisions against the
same observation identity. Frame resolution should continue to depend on the
current-state projection, not on replaying decision events in the widget layer.

## 9. Spacecraft scope variable

Modes: **one / all / by-type / compare-set**. Cadence already has a native
grouping primitive — `SpacecraftType` (`spacecraft_type_id`) — so "all OASIS-type
buses" is a real query, not freeform tagging.

- `each` (repeat) → **small-multiples wall**: the same dashboard tiled across the
  selected spacecraft (Grafana's repeat-by-variable, made native).
- `all` (aggregate) → constellation rollups / status matrix.
- `compare` → multiple spacecraft overlaid on one chart (e.g. bus voltage on
  SC-1/2/3).

Large constellations need **virtualization**: you cannot render 500 charts. The
constellation rollup is the zoomed-out view that drills into detail (Grafana's
"max panels" instinct, done domain-first). Surface any truncation explicitly.

## 10. Widget system & extensibility

Today first-party widget types live in `Cadence.Dashboards.WidgetRegistry`, with
per-type validation, pattern-matched rendering, and a bespoke edit form in
`FormComponents` — every new widget still touches several files. The product
goal is an ever-growing, eventually user-/third-party-extensible widget set, so
the compiled registry is only the near-term shape this design evolves beyond.

Sequencing note: the **registry + data contract + generic options schema** are
near-term engine requirements. The declarative mark grammar and user-authored
widget specs are long-term extensibility mechanisms that should follow several
first-party widgets, not block the dashboard engine.

### 10.1 What a widget is

The dashboard engine owns *where data comes from* (source, backend,
live-vs-historical, decimation) and normalizes everything to Frames. So a
widget no longer touches storage or queries. It collapses to:

> **A pure function `(Frame(s), options, theme, interaction) → visual`.**

A widget cannot reach the database, issue queries, or see other tenants — it
consumes frames the host handed it. That narrow surface is what makes
extensibility tractable and safe.

### 10.2 Widget registry v0 contract

The registry should exist from day one, even if every widget is first-party and
compiled into Cadence. This prevents the new dashboard engine from recreating a
closed widget enum.

Registry API:

```elixir
@callback list_types() :: [WidgetType.t()]
@callback fetch_type(widget_type_id :: binary(), version :: pos_integer() | :latest) ::
  {:ok, WidgetType.t()} | {:error, :unknown_widget_type | :unsupported_version}
@callback validate_widget_def(WidgetDef.t()) :: :ok | {:error, [WidgetValidationError.t()]}
@callback migrate_options(widget_type_id :: binary(), from_version :: pos_integer(), map()) ::
  {:ok, version :: pos_integer(), options :: map()} | {:error, term()}
```

Widget type:

```elixir
%WidgetType{
  widget_type_id: "cadence.time_series",
  version: 1,
  name: "Time Series",
  category: :telemetry,
  icon: "hero-chart-line",
  trust: :first_party,
  data_contract: %WidgetDataContract{},
  binding_schema: %WidgetBindingSchema{},
  options_schema: [%WidgetOption{}],
  layout_contract: %WidgetLayoutContract{},
  drilldown_contract: %WidgetDrilldownContract{},
  renderer: %WidgetRenderer{
    locus: :client_hook | :server_component,
    module: CadenceWeb.Dashboards.Widgets.TimeSeries,
    hook: "DashboardTimeSeries" | nil
  }
}
```

Widget definition stored in a dashboard:

```elixir
%WidgetDef{
  widget_type_id: "cadence.time_series",
  widget_type_version: 1,
  title: "Battery Voltage",
  binding: %{
    observables: ["tlm.hk.battery_voltage"],
    scope_mode: :context,
    data_mode: :context,
    value_type: :engineering,
    sampling: :decimated_envelope,
    overlays: [:limits]
  },
  options: %{
    "show_min_max_band" => true,
    "legend" => false,
    "line_width" => 1.5
  }
}
```

The engine reads `data_contract` and `binding`; the renderer reads Frames and
`options`. The renderer does not interpret source bindings, query storage, or
decide limit semantics.

Current v0 also makes widget/source compatibility explicit at document
validation and again before any source request is planned. A binding can select
a non-default logical source only when the primary frame spec declares a
`source_overrides` entry for that source. That keeps source polymorphism out of
presenters: value tiles can accept the `operational_observables` transport
bit-rate product, status matrices can accept operational state/metric products,
state timelines keep telemetry limit history point-bound while accepting
multiple operational state observables, and time-series widgets reject
operational latest-only data until a historical operational product exists.

Data contract:

```elixir
%WidgetDataContract{
  frames: [
    %FrameRequestSpec{
      role: :primary,
      source: :telemetry,
      accepted_shapes: [:wide],
      accepted_field_kinds: [:number],
      temporal?: true,
      min_fields: 1,
      max_fields: 8,
      sampling: :decimated_envelope,
      required_metadata: [:observable_id, :unit, :quality_state]
    },
    %FrameRequestSpec{
      role: :primary,
      source: :telemetry,
      accepted_shapes: [:scalar],
      temporal?: false,
      sampling: :latest,
      source_overrides: [
        %{
          source: :operational_observables,
          accepted_shapes: [:matrix],
          temporal?: false,
          sampling: :latest,
          products: [:transport_bitrate],
          observable_value_kinds: [:metric]
        }
      ]
    }
  ],
  overlays: [
    %OverlayRequestSpec{
      role: :limits,
      source: :limits,
      products: [:latest_state, :event_history, :definition_intervals],
      required?: false
    }
  ],
  live_mode: :static | :poll_latest | :appendable
}
```

Binding schema:

```elixir
%WidgetBindingSchema{
  observable_count: 1..8,
  observable_kinds: [:metric],
  scope_modes: [:context, :override, :repeat],
  data_modes: [:context, :override],
  value_types: [:engineering, :raw],
  sampling_modes: [:latest, :raw_series, :decimated_envelope],
  allowed_overlays: [:limits, :events, :quality]
}
```

Options schema:

```elixir
%WidgetOption{
  key: "line_width",
  type: :number,
  label: "Line width",
  default: 1.5,
  constraints: %{min: 0.5, max: 4.0, step: 0.5},
  show_if: nil
}
```

The generic editor renders options from this schema. Widget-specific config
forms should be an exception, not the norm.

Renderer handoff:

```elixir
%WidgetRenderInput{
  placement_id: "placement_1",
  widget_type_id: "cadence.time_series",
  title: "Battery Voltage",
  frames: [%Frame{}],
  overlays: %{limits: [%Frame{}], events: []},
  options: %{...},
  warnings: [%ResolveWarning{}],
  theme: %DashboardTheme{},
  interaction: %{cursor_time: nil, selected?: false}
}
```

Unknown widget behavior:

- unknown type id → render unavailable placeholder
- unsupported version → render unavailable placeholder with migration warning
- invalid binding/options → render configuration error placeholder
- missing optional overlay → render widget with warning badge
- missing required primary frame → render no-data/error placeholder

Unknown or invalid widgets must not crash dashboard rendering.

First-party v0 widgets:

| Widget | Primary frame | Overlays | Live mode |
| --- | --- | --- | --- |
| `cadence.value_tile` | scalar telemetry latest | latest limits, quality/staleness | `:poll_latest` |
| `cadence.time_series` | numeric temporal telemetry | limits, events later | `:appendable` target; `:poll_latest` acceptable v0 |
| `cadence.status_matrix` | enum/state or latest limit rollup | limits | `:poll_latest` |
| `cadence.data_table` | latest telemetry/operational rows | limits, quality/staleness | `:poll_latest` |
| `cadence.state_timeline` | point-bound limit event-history or multi-observable operational state segments | quality/staleness | `:appendable` target; static refresh acceptable v0 |
| `cadence.event_timeline` | mission/contact/source/data-management events | none | `:poll_latest` |
| `cadence.constellation_health` | spacecraft x worst-state rollup | limits | `:poll_latest` |

Deferred from v0:

- user-authored spec grammar
- third-party/widget marketplace distribution
- sandboxed WASM widgets
- custom renderer upload
- library-widget persistence, unless horizontal reuse is needed immediately
- renderer primitives beyond the first-party set

### 10.3 Render locus (decided): client-side, on Frames

Widgets render **client-side** (JS hook / canvas-SVG) fed normalized Frames
over the wire — matching where the rich/interactive viz already lives
(`TelemetryChart`/uPlot). Server-rendered HEEx remains for chrome and
trivially-static cases. The plugin boundary is client-side.

### 10.4 Extensibility tiers (long-term)

"Users add widget types" does **not** require "users upload code." Three tiers,
kept as the long-term model:

| Tier | What | Trust | Adds a new *primitive* (e.g. a globe)? | Authors |
| --- | --- | --- | --- | --- |
| **Spec / grammar** | declarative marks+encodings over Frame fields, drawn by a trusted client interpreter | data, safe | No — composes existing marks only | users / third parties / first-party |
| **Code widget** | Elixir behaviour (HEEx) + JS hook | compiled-in, vetted | Yes | Cadence / partners |
| **Sandboxed (WASM)** *(future)* | sandboxed compute → scene | sandboxed | Yes | third parties |

The spec tier delivers Grafana's "add the widget I need" strength **as data** —
safe to author, share, version, tenant-isolate — while the host enforces
catalog-bound invariants on it. Code widgets cover the primitives and genuinely
novel renderers. WASM is the eventual third-party escape hatch for novel
rendering (already contemplated on Cadence's roadmap via the managed-application
framework; see `project_application_framework`).

Build order should be:

1. First-party code widgets with explicit data contracts.
2. Generic options schemas rendered by the host.
3. A widget registry that tolerates unknown/removed types.
4. Extraction of a declarative grammar after the common widget shapes are proven.
5. User-authored specs and, later, sandboxed code.

### 10.5 The renderer-ownership model

Cadence owns **one renderer**: the client-side spec interpreter plus its mark
library (`line, area, rect, rule, bar, cell, value, caption, badge, …`). A spec
*composes* those marks; it cannot introduce a new *kind* of primitive. Adding a
new primitive (globe/geomap, mimic board, 3D attitude) is **renderer code,
written once** — either as a new host mark (after which that whole family
becomes spec-authorable) or as a one-off code-tier widget.

This is the same line Grafana draws — its Geomap panel is a code plugin; nobody
expresses a globe in dashboard JSON either. The grammar only **shrinks how
often** renderer code is needed by making the long tail (charts/tiles/grids/
matrices) data. Novel primitives always cost renderer code *somewhere*; the only
question is whether that somewhere is Cadence (code tier) or a sandboxed third
party (WASM tier). A user-uploaded **spec can never bring a new primitive** —
that property is exactly why specs are safe.

### 10.6 The widget-type contract

A widget *type* (spec or code) declares six things to the registry:

1. **Identity** — type id, name, icon, version.
2. **Data contract** — accepted frame shapes (e.g. *"1–8 numeric temporal
   fields"*, *"one enum field"*, *"a scalar"*, *"a spacecraft×point grid"*) plus
   opt-in overlays (`limits`, `events`). Drives the editor's binding UI and tells
   the engine raw-vs-decimated and which sources to fetch.
3. **Options schema** — typed, declarative config descriptors
   (`{key, type, label, default, show_if}`), rendered **generically** with
   `<.input>`. This kills bespoke per-widget forms and is the precondition for
   any plugin.
4. **Layout contract** — minimum/preferred size, resize axes, and compact
   rendering support (§11.5).
5. **Drilldown contract** — supported selection modes and link targets
   (§11.10).
6. **View / renderer** — the spec (marks + encodings), or the code module/hook.

Encoding accessors bind channels to `field:NAME`, `opt:KEY`, literals, host
tokens (`token:warning`), or **host helper functions** that enforce
catalog-bound rules and cannot be redefined by a spec (`state_color(…)`,
`enum_color(…)`, `format(…)`).

### 10.7 Worked examples

**Time series** — multi-series overlay, decimated min/max band, limit bands,
pass shading, command annotations (exercises the whole grammar):

```yaml
type_id: cadence.time_series
data:
  series:   { role: primary, field_kinds: [numeric], temporal: true,
              min: 1, max: 8, sampling: decimated_envelope }
  overlays: [limits, events]
options:
  - { key: show_min_max_band, type: boolean, default: true }
  - { key: line_width,        type: number,  default: 1.5, range: [0.5, 4] }
  - { key: legend,            type: boolean, default: false }
view:
  marks:
    - mark: rect                       # limit band (host overlay), behind
      from: { overlay: limits }
      encode: { x: full, y0: "field:lower", y1: "field:upper",
                fill: "state_color(field:normalized_state)", opacity: 0.12 }
    - mark: rect                       # ground-pass shading (Events source)
      from: { overlay: events, kind: contact }
      encode: { x0: "field:starts_at", x1: "field:ends_at", y: full,
                fill: "token:base-300", opacity: 0.25 }
    - mark: area                       # min/max envelope when decimated
      when: "opt:show_min_max_band and frame.decimated"
      from: { series: primary }
      encode: { x: "field:time", y0: "field:min", y1: "field:max",
                fill: "series_color()", opacity: 0.15 }
    - mark: line                       # one line per bound series
      from: { series: primary }
      encode: { x: "field:time", y: "field:value",
                stroke: "series_color()", width: "opt:line_width" }
    - mark: rule                       # command annotations
      from: { overlay: events, kind: command }
      encode: { x: "field:time", stroke: "token:warning" }
      annotation: { label: "field:command_name" }
```

**Value tile** — scalar, latest, limit-colored, stale badge:

```yaml
type_id: cadence.value_tile
data:
  scalar:   { role: primary, field_kinds: [numeric, string], sampling: latest }
  overlays: [limits]
options:
  - { key: precision, type: precision, default: 2 }
  - { key: show_unit, type: boolean,   default: true }
view:
  layout: tile
  marks:
    - mark: value
      from: { scalar: primary }
      encode: { text: "format(field:value, opt:precision)",
                color: "state_color(overlay:limits.normalized_state)",
                unit: "field:unit" }
    - mark: caption
      encode: { text: "strftime(field:time, '%H:%M:%S UTC')", muted: true }
    - mark: badge
      when: "overlay:limits.stale"
      encode: { text: "'Stale'", status: attention }
```

Status matrix, discrete-state timeline, sparkline, and constellation rollup
express in the same mark vocabulary. Geomap/globe, mimic boards, and
bespoke-interaction widgets fall to the code tier (§10.4).

### 10.8 Invariants survive plugins (the moat)

Limit bands, pass shading, command annotations, and quality/staleness badges are
**host-provided overlays**, fed from the Limits/Events sources — not
reimplemented per widget. A widget declares "I'm temporal" and the host attaches
the limit band; the widget **cannot override the limit definition** (it lives in
the catalog). So *every* widget — spec, code, or uploaded — is catalog-bound
by construction. Grafana cannot guarantee this; a panel plugin does whatever it
wants.

### 10.9 Registry, versioning, lifecycle

- **Registry** — built-in types compiled in; spec widgets stored (org-private
  and/or a shared catalog), resolved at render time.
- **Versioning** — dashboards persist `widget_type_id` + `version` + `options`;
  type evolution needs explicit option/document migration.
- **Graceful unknown** — an unknown/removed type renders an "unavailable"
  placeholder, **not** a raise.
- **Governance** — trust levels, approval, signing for anything beyond
  first-party.

### 10.10 Taxonomy by tier

Confirmed against COSMOS's widget set (note how pervasively limit-state is baked
in):

- **Spec tier** — value tile / stat, time series (multi-series + overlays),
  telemetry grid / packet view, status / limit matrix, discrete-state timeline,
  sparkline, constellation / fleet rollup, XY / distribution / gauge.
- **Code tier** — geomap / ground-track, mimic / schematic boards, 3D attitude,
  packet hexdump, brush-to-command.

(COSMOS analogs: `Limitsbar`, `Limitscolor`, `Limitscolumn`, `Sparkline`,
`Linegraph`, `Arrayplot`, `Rollup`, `Matrixbycolumns`, Canvas/mimic widgets.)

## 11. Dashboard data model

Storage shape **decided**: a dashboard is a **row with a JSON document**
(settings + embedded placements), with reusable widgets and their usages as
**separate rows** — mirroring Grafana's implementation and Cadence's existing
`Cadence.Persistence.JsonDocument` pattern. The **reuse axis to prioritize is an
open question** (§16); the model below is the same either way, because the
placement `content` union reserves the library seam.

### 11.1 Reuse axes

- **Vertical — across operational scope.** The scope context + context binding
  (§4, §9). A dashboard is inherently a template: retarget the scope context and
  the whole screen follows. Spacecraft is the default case, but contact, ground
  station, transport, link, and mission-level dashboards should use the same
  mechanism. **No new entity** — a view-time parameter.
- **Horizontal — across dashboards.** The same configured widget referenced by
  many dashboards (Grafana's "library panel"). **The only axis that needs a
  stored, referenced entity.**
- **Realm — across data corpora.** The same dashboard evaluated against flight,
  rehearsal, AI&T, simulation, or replay data. **No new dashboard entity** unless
  the product wants named rehearsal/AI&T dashboard variants; otherwise this is a
  data-context parameter.

Grafana has only the horizontal axis and partly invented library panels to
compensate for weak templating. Cadence gets the vertical axis natively, so
horizontal reuse is a *secondary*, opt-in concern.

### 11.2 Three levels (don't conflate)

1. **Widget type** — the spec/code kind in the registry (§10). Reusable by
   definition.
2. **Configured instance ("widget def")** — type + options + query binding. The
   *what*. No layout.
3. **Placement** — an instance on a dashboard at `{x,y,w,h}`. The *where*.

Principle (cleaner than Grafana, which pins `gridPos` onto the panel):
**placement owns layout; content is embedded or referenced.**

### 11.3 Entities

```
Dashboard (aggregate / JSON document + row)
  ├─ identity:   dashboard_id, org_id, mission_id, name, description
  ├─ time:       { default_range, live?, refresh }      # time context defaults (§4)
  ├─ scope:      { kind, mode, members, filters }       # scope context defaults (§4, §9)
  ├─ data:       { realm, source_mode, allowed_realms } # data context defaults (§5.4)
  ├─ overlays:   { passes?, commands?, limits? }        # default event overlays
  ├─ limits:     { semantics_mode }                     # observed | current | compare
  ├─ grid:       { columns }
  └─ placements: [ Placement, … ]                       # ordered

Placement                                               # embedded in the document
  ├─ placement_id
  ├─ layout:     { x, y, w, h }
  ├─ content:    {kind: :embedded, widget_def}
             |   {kind: :library,  library_widget_id, version, overrides?}
  ├─ scope_override?    # pin one widget even if the dashboard follows context
  ├─ data_override?     # compare or pin one widget to a specific realm/source
  └─ limit_override?    # opt into current/recomputed or comparison semantics

WidgetDef                                               # the "what", no layout
  ├─ widget_type_id (+ version)        → type registry (§10)
  ├─ title
  ├─ binding/query: { observables, scope_mode, data_mode, value_type, aggregation }
  └─ options:      map conforming to the type's options schema (§10.2, §10.6)

LibraryWidget                                           # reuse entity — its own row
  ├─ library_widget_id, org_id, mission_id|null, name, description
  ├─ widget_def, version
  └─ usage via connection table

DashboardVersion                                        # snapshot per save → rollback
  └─ dashboard_id, version, document, snapshot_kind, change_summary,
     created_by, created_at
```

Deliberate choices:

- **Embedded by default, library by opt-in** (Grafana). Widgets start inline;
  "extract to library" promotes one to a `LibraryWidget` row and turns its
  placement into a reference. Self-contained dashboards stay the common case.
- **Bindings are relative to the dashboard contexts** (`scope_mode: context`,
  `data_mode: context`), not absolute — what keeps a dashboard a template and a
  library widget portable across operational scopes and data realms.
- **`mission_id` nullable on `LibraryWidget`** lets a reusable widget be
  mission-scoped or org-wide (a customer's widget library across missions).
- **Graceful unknown** — a missing library widget or unknown type renders a
  placeholder, never a raise (§10.2, §10.9).

### 11.4 Dashboard document v0 contract

The engine reads a concrete dashboard document. The editor writes the same
document. Persistence wraps it in rows/snapshots, but lifecycle state and
published/draft pointers live outside the document so the engine contract does
not depend on database shape.

```elixir
%DashboardDocument{
  schema_version: 1,
  dashboard_id: "dashboard_...",
  organization_id: "...",
  mission_id: "...",
  name: "Power and Thermal",
  description: nil,

  defaults: %DashboardDefaults{
    time: %TimeContext{
      mode: :live,
      axis: :generation_time,
      range: %{kind: :relative, duration_ms: 1_800_000},
      refresh_ms: 1_000
    },
    scope: %ScopeContext{
      primary: %{kind: :spacecraft, mode: :context, ids: []}
    },
    data: %DataContext{
      realm: :flight,
      source_mode: :primary,
      allowed_realms: [:flight]
    },
    limits: %LimitContext{
      semantics_mode: :observed
    },
    overlays: %{
      limits?: true,
      events?: false,
      quality?: true
    }
  },

  grid: %{
    columns: 12,
    row_height_px: 64,
    gap_px: 8
  },

  placements: [%Placement{}],

  metadata: %{
    created_by: "user_...",
    updated_by: "user_...",
    labels: []
  }
}
```

Placement:

```elixir
%Placement{
  placement_id: "placement_...",
  layout: %{x: 0, y: 0, w: 6, h: 4},
  content: %PlacementContent{
    kind: :embedded | :library,
    widget_def: %WidgetDef{} | nil,
    library_widget_id: "library_widget_..." | nil,
    library_version: 3 | nil,
    overrides: %WidgetOverrides{} | nil
  },
  repeat: %PlacementRepeat{} | nil,
  scope_override: %ScopeContext{} | nil,
  data_override: %DataContext{} | nil,
  limit_override: %LimitContext{} | nil
}
```

Widget definition aligns with the registry contract (§10.2):

```elixir
%WidgetDef{
  widget_type_id: "cadence.time_series",
  widget_type_version: 1,
  title: "Battery Voltage",
  binding: %WidgetBinding{
    observables: ["tlm.hk.battery_voltage"],
    scope_mode: :context,
    data_mode: :context,
    value_type: :engineering,
    sampling: :decimated_envelope,
    aggregation: nil,
    overlays: [:limits]
  },
  options: %{
    "show_min_max_band" => true,
    "legend" => false
  }
}
```

v0 should store embedded widget definitions only. The `:library` content shape
is reserved so the document model does not change when horizontal reuse lands,
but library-widget persistence can be deferred.

#### 11.4.1 Runtime context override order

Dashboard runtime contexts are resolved in this order:

```text
dashboard defaults
→ URL/session/runtime context
→ placement overrides
→ interaction-specific overrides
```

Examples:

- dashboard default scope is "current spacecraft"; URL selects `sc_001`
- one placement pins `scope_override` to `sc_002`
- user switches data realm to `rehearsal`; placements without `data_override`
  follow, pinned placements do not
- a compare interaction can add temporary interaction-specific scope/data
  context without mutating the saved document

The saved document contains defaults and explicit placement overrides. It does
not store transient operator session state.

#### 11.4.2 Validation rules

Document validation should happen before save and before engine resolve:

- `schema_version` is supported.
- `dashboard_id`, `organization_id`, `mission_id`, and `name` are present.
- `grid.columns`, row height, and placement dimensions are positive.
- placement ids are unique.
- placement layouts fit within the grid and have positive width/height.
- placement layouts satisfy the widget type's `WidgetLayoutContract`.
- repeated placements declare a supported repeat axis and bounded maximum
  instance count.
- embedded widget defs reference a known widget type/version or are retained as
  unknown placeholders.
- widget bindings satisfy the widget type's `WidgetBindingSchema`.
- widget options satisfy the widget type's `options_schema`.
- document default realms are allowed for the mission.
- placement `data_override` realms are allowed by the dashboard defaults unless
  the dashboard explicitly enables comparison.
- `limit_override` cannot request unsupported semantics without producing a
  validation warning.
- unknown widget/library references do not invalidate the whole dashboard; they
  become placement-level warnings.

Validation result:

```elixir
%DashboardDocumentValidation{
  valid?: true,
  errors: [%DashboardDocumentError{}],
  warnings: [%DashboardDocumentWarning{}]
}
```

Errors block save/resolve when the document itself is malformed. Warnings allow
save/resolve but surface placeholders, badges, or editor notices.

#### 11.4.3 Versioning and lifecycle

Rows and snapshots should wrap the document. The important product distinction
is **saved draft** versus **operator-facing published version**. A dashboard may
have an unpublished draft without changing what operators see in view mode.

```elixir
%DashboardRow{
  dashboard_id: "dashboard_...",
  organization_id: "...",
  mission_id: "...",
  name: "Power and Thermal",
  lifecycle_state: :active | :archived | :deleted,
  latest_version: 8,
  draft_version: 8 | nil,
  published_version: 7 | nil,
  document: %DashboardDocument{},
  lock_version: 14,
  published_at: DateTime.t() | nil,
  published_by: "user_..." | nil,
  inserted_at: DateTime.t(),
  updated_at: DateTime.t()
}

%DashboardVersion{
  dashboard_version_id: "dashboard_version_...",
  dashboard_id: "dashboard_...",
  version: 8,
  document: %DashboardDocument{},
  snapshot_kind: :draft_save | :publish | :revert | :migration,
  parent_version: 7 | nil,
  based_on_version: 4 | nil,
  schema_version: 1,
  change_summary: "Added battery trend",
  created_by: "user_...",
  created_at: DateTime.t()
}
```

Version rules:

- version numbers are monotonically increasing per dashboard
- version rows are immutable
- the dashboard row is a pointer/index record for listing, locking, and fast
  access to the current draft/head document
- `published_version` is the version resolved by operator view mode
- `draft_version` is the latest saved editor version when it differs from
  `published_version`
- every operator-initiated save should populate `created_by` from the current
  authenticated user and a short `change_summary`
- v0 summaries can be system-generated from the edit action (`Added widget`,
  `Updated layout`, `Renamed dashboard`, etc.); free-text release notes can wait
  until publish governance exists
- archiving is the normal user-facing removal action; it changes row lifecycle
  state and does not delete versions
- hard delete, if allowed, should be an administrative retention action, not the
  normal user-facing delete

Lifecycle transitions:

| Action | Effect |
| --- | --- |
| Create | inserts a row, writes version `1`, sets `draft_version: 1`; may publish immediately for simple flows |
| Save draft | validates, writes a new version, updates `latest_version`, `draft_version`, `document`, and `lock_version` |
| Publish | validates a saved target version, sets `published_version`, clears or retains `draft_version` depending on whether an unpublished newer draft remains, and records `published_by/at` |
| Revert to version | copies the old snapshot into a **new draft** version; never moves `latest_version` backward |
| Archive | removes dashboard from active lists while preserving versions and audit trail |
| Restore | returns archived dashboard to active lists, preserving prior published/draft pointers |

Suggested context API:

```elixir
Cadence.Dashboards.get_dashboard(scope, dashboard_id, mode: :view | :edit)
Cadence.Dashboards.save_draft(scope, dashboard_id, document, opts)
Cadence.Dashboards.publish(scope, dashboard_id, version, opts)
Cadence.Dashboards.revert(scope, dashboard_id, to_version, opts)
Cadence.Dashboards.archive(scope, dashboard_id, opts)
Cadence.Dashboards.list_versions(scope, dashboard_id)
Cadence.Dashboards.get_version(scope, dashboard_id, version)
```

All mutating calls should require a mission/org scope and should accept
`expected_lock_version` or `base_version` for optimistic concurrency. On
conflict, the editor should show "this dashboard changed" and offer reload,
compare, or save-as-new-draft. v0 can avoid collaborative editing while still
preventing silent last-write-wins overwrites.

`todo(authz)`: when Cadence has a real authorization model, these calls need
explicit view/edit/publish/archive permissions. Until then, keep authorization
checks localized at the context/API boundary rather than baking permissions into
the dashboard document.

Publish gate:

- document validation errors block publish
- unsupported widget/observable errors block publish only when the editor is
  creating invalid new content
- pre-existing unknown widgets, library references, or observables may be
  retained as warnings so older dashboards survive registry/catalog changes
- source availability does not block publish; it becomes runtime warnings
- publishing should record who published which version and from what base
  version

Schema and widget migration:

- `schema_version` on `DashboardDocument` is the document shape version
- `widget_type_version` is independent and migrates through the widget registry
- read paths may migrate documents in memory for rendering
- save paths write the current schema version
- migration should create a new `DashboardVersion` with `snapshot_kind:
  :migration` when it changes persisted JSON
- old version snapshots remain byte-for-byte auditable unless a deliberate
  data-retention migration rewrites them

#### 11.4.4 v0 boundaries

v0 includes:

- one document row per dashboard
- JSON document with contexts, grid, placements, embedded widget defs
- document validation
- version snapshots with actor metadata and action-level change summaries
- unknown widget placeholders
- draft/published pointers
- optimistic locking

v0 defers:

- library widget rows/connections
- org-wide widget libraries
- user-authored widget specs
- collaborative editing and real-time merge
- general template variables beyond time/scope/data/limits
- dashboard marketplace/template promotion

### 11.5 Dashboard layout and responsive behavior

The dashboard document stores a **logical layout**, not absolute pixels. The
renderer maps that logical layout onto an ops console, laptop, wall display, or
small viewport deterministically.

v0 should use one canonical saved layout:

```elixir
%DashboardGrid{
  columns: 12,
  row_height_px: 64,
  gap_px: 8,
  density: :comfortable | :compact,
  responsive_policy: :single_layout_collapse
}

%PlacementLayout{
  x: 0,
  y: 0,
  w: 6,
  h: 4,
  min_w: 3,
  min_h: 2
}
```

Grid rules:

- `x`, `y`, `w`, and `h` are grid units.
- `x + w <= grid.columns`.
- placements are ordered by `{y, x, placement_id}` for deterministic render,
  keyboard navigation, and responsive collapse.
- overlapping placements are invalid for newly saved dashboards.
- legacy/imported overlaps, if ever supported, render with warnings instead of
  crashing.
- layout belongs to `Placement`; widget defs stay portable and layout-free.

Widget type layout contract:

```elixir
%WidgetLayoutContract{
  min_w: 2,
  min_h: 2,
  preferred_w: 6,
  preferred_h: 4,
  max_w: nil,
  max_h: nil,
  resize: :both | :horizontal | :vertical | :fixed,
  compact_rendering?: true
}
```

The widget registry should expose layout constraints alongside data and option
schemas. Validation uses them to prevent unreadable charts:

- a placement smaller than `min_w/min_h` is a validation error for new content
- a placement below `preferred_w/preferred_h` is allowed but may trigger compact
  rendering
- a widget may declare `resize: :fixed` for shapes that cannot sensibly resize
- unknown widget types keep their saved placement but cannot be resized until
  the type is known again
- title bars, warning badges, legends, and empty states must fit inside the
  declared minimum size

Responsive policy:

- v0 stores **one** layout, not separate breakpoint layouts.
- wide/desktop/ops-console view renders the 12-column grid directly.
- narrow view collapses placements into a single column ordered by `{y, x}`.
- medium view may use a deterministic derived column count, but the saved
  document remains 12-column.
- collapsed view preserves widget order and context; it does not rewrite
  placement coordinates.
- edit mode is allowed to require a minimum practical width. Small viewports can
  remain view-only in v0.

Wall displays:

- wallboard/full-screen mode uses the same document and grid
- the renderer may scale row height and typography within bounded density rules
- no widget should depend on hover-only interactions for critical state
- warning badges and stale/source-degraded states must remain visible at a
  glance

Repeat/small-multiple layout:

Repeat-by-scope should be a runtime expansion, not N saved placements. A
placement can declare:

```elixir
%PlacementRepeat{
  axis: :scope,
  over: :spacecraft | :contact | :ground_station | :transport | :link,
  layout: :row | :column | :wrap_grid,
  max_instances: 24
}
```

At resolve/render time, the engine/editor expands one template placement into
stable virtual placements:

```text
placement_1::sc_001
placement_1::sc_002
placement_1::sc_003
```

Repeat rules:

- repeated instances inherit widget binding/options from the template placement
- each virtual placement gets a scoped runtime context
- source requests should be batched across repeated instances where possible
- repeated placements participate in responsive collapse as a group
- saved documents store the repeat declaration, not the expanded instances
- v0 can support repeat-by-spacecraft first and leave other scope kinds for
  later

Editor behavior:

- resize/reorder changes the draft document and therefore participates in
  versioning
- snap-to-grid is mandatory; freeform pixel placement is not part of v0
- editor previews should use real widget layout contracts, not generic boxes
- if a resize would violate a widget minimum, the editor blocks the resize
- layout validation should run before save and publish

### 11.6 Persistence

- **Dashboard** — a pointer row; bulk content (settings + embedded placements)
  in a JSON document via `JsonDocument`. `name`, `description`,
  `lifecycle_state`, `published_version`, `draft_version`, `latest_version`,
  and `lock_version` stay columns for listing, filtering, and concurrency.
- **Library widgets** *(future)* — `dashboard_library_widgets` rows referenced
  by id.
- **Usage** *(future)* — `dashboard_library_widget_connections`
  (library_widget_id ↔ dashboard_id) for find-usages and safe deletes
  ("3 dashboards use this — detach or delete?"). Mirrors Grafana's
  `library_element_connection`.
- **Versions** — `dashboard_versions` immutable snapshots. Store the full
  document plus author, parent/based-on version, snapshot kind, and change
  summary. Version rows are the rollback and audit trail for a mission-shared
  artifact.
- **Autosave** *(optional)* — separate recovery storage keyed by user/session.
  It should not create durable dashboard versions until the user intentionally
  saves.
- **Lifecycle events** — `dashboard_lifecycle_events` append publish/archive/
  restore facts with actor, timestamp, affected version, previous/current
  lifecycle state, and previous/current published pointer. These are
  dashboard-specific audit rows today; projection into the canonical
  operational event spine remains future. Version rows remain the source for
  restoring document content.

### 11.7 Implementation path

Do not contort this model around the current `ops_dashboards` JSON shape. The
prototype can be replaced.

Recommended path:

1. Create new `Cadence.Dashboards` tables and document structs around the target
   model: contexts, placements, widget defs, dashboard versions.
2. Build the engine contract (§5.1.1) and first-party widget registry before
   adding editor polish.
3. Reimplement the current value tile, time-series, and constellation-health
   behavior against Frames as first widgets.
4. Add library widgets only when horizontal reuse is actually needed; the
   placement content union reserves the seam.
5. Follow the test/cutover strategy in §11.11; keep the retired `Cadence.Ops.*`
   dashboard model out of new persistence/runtime contracts.

### 11.8 Deferred

- **General template variables** (arbitrary user-defined, Grafana templating).
  The built-ins (time, scope, data context) are first-class and special; model
  them concretely now, leave the door open.

### 11.9 Dashboard runtime and editor UX contract

The dashboard product has two coupled surfaces:

- **Runtime console** — operators monitor, scrub, compare, and drill into
  mission data.
- **Editor** — authorized users compose dashboard documents from registered
  widgets and validated bindings.

Both surfaces use the same `DashboardDocument`. They differ in which state they
are allowed to mutate.

#### 11.9.1 Modes

| Mode | Purpose | Mutates document? | Engine behavior |
| --- | --- | --- | --- |
| `:view` | operational monitoring | no | resolve from published/saved document + URL/session context |
| `:edit` | compose layout, widgets, options, defaults | yes, draft document | validate document and resolve preview frames |
| `:explore` | ad-hoc scrub/compare from a dashboard starting point | no by default | temporary runtime context and bindings |
| `:replay` | evaluate dashboard against replay/simulation context | no by default | context change to replay data realm/run |

`Explore` should not become a generic SQL/PromQL console. It is a dashboard-free
or dashboard-adjacent way to bind cataloged observables quickly, inspect
history, and optionally promote a useful view into a dashboard widget later.

#### 11.9.2 State ownership

State should have a clear home:

| State | Owner | Persisted in document? |
| --- | --- | --- |
| dashboard defaults | `DashboardDocument` | yes |
| placements/layout | `DashboardDocument` | yes |
| widget defs/options | `DashboardDocument` or library widget | yes |
| selected spacecraft/contact/realm | URL/session runtime context | no, unless saved as default |
| time scrubber position | URL/session runtime context | no |
| cursor/crosshair | client interaction state | no |
| chart zoom/brush | client interaction state; promotable to runtime context | no |
| edit form draft values | LiveView/editor state | not until save |
| resolved Frames | engine/runtime cache | no |
| source warnings/watermarks | engine result | no |

This keeps dashboards shareable and stable. A URL can reproduce a runtime view,
but transient operator actions do not dirty the saved document.

#### 11.9.3 Global controls

The first row of the dashboard runtime should be operational controls, not
Grafana-style variable clutter:

- **Time** — live, quick ranges, custom range, scrubber, replay run.
- **Scope** — spacecraft/contact/ground station/transport/link/mission focus.
- **Data realm** — flight by default; rehearsal/AI&T/simulation/replay only when
  allowed.
- **Limit semantics** — observed by default; current/recomputed/compare only
  when supported and clearly labeled.

Changing a global control creates a new `DashboardResolveRequest` with
`resolve_mode: :context_change`. Widgets inherit the global context unless a
placement override pins them.

#### 11.9.4 Widget editing flow

The editor should be registry-driven:

1. User selects a widget type from `WidgetRegistry.list_types/0`.
2. The editor renders binding controls from `WidgetBindingSchema` and derives
   binding-source choices from the widget frame contract, not from a hardcoded
   widget enum.
3. Observable pickers query the observable registry, filtered by widget data
   contract, declared frame products/value kinds, and current scope/data
   context.
   Operational time-series pickers additionally group Cadence-produced
   metric-history observables by the source-advertised `metric_history_contracts`
   capability metadata, so RF SNR, transport bit-rate, and ingress-latency
   history choices follow the same source product/product-family contract that
   engine planning and frame resolution use.
4. The editor renders options from `options_schema`.
5. The draft `WidgetDef` is validated with `validate_widget_def/1`.
6. The engine resolves a preview using the draft document/context.
7. Save writes the document and creates a version snapshot.

Widget-specific edit forms should be exceptional. Most widgets should be
configurable through registry-provided binding and option schemas.
The save boundary must re-run the same widget-frame source/product/value-kind
checks as the picker, because users and imports can submit stale or crafted form
payloads that bypass visible options.
Validation failures should preserve the requested source/observables, the
unsupported observables, and the supported frame products/value kinds so import,
publish, and operator-facing diagnostics can explain the mismatch without
requiring registry knowledge.

#### 11.9.5 Warning presentation

Warnings should be visible without making the console noisy:

- dashboard-level warning summary for source outages, realm mismatches, or
  unsupported global context
- placement-level badges for partial/stale/recomputed/unknown semantics
- field-level affordances in legends/tooltips for quality, validity, and limit
  semantics
- editor validation warnings inline next to the problematic binding/option
- no modal warning spam during live operations

Widget presenters now attach an explicit lifecycle object to engine-backed
widget data. The current state vocabulary is `:ready`, `:no_data`, `:stale`,
`:partial`, `:error`, and `:unsupported`; it is derived from frame warning
codes, placement warnings, source-execution failures, and whether meaningful
primary data was returned. Widget bodies use that lifecycle to distinguish
empty data from unsupported source capability and source failure, while
diagnostic panels still expose the underlying warning/evidence details. Empty
row-oriented widgets (`status_matrix`, `data_table`, `state_timeline`, and
`event_timeline`) render lifecycle-tagged body notices, so component and
browser harnesses can assert `no_data` separately from unresolved or failed
states. The rendered browser proof currently covers the source-endpoint
no-data data-table, status-matrix, state-timeline, and event-timeline paths,
including the absence of placeholder rows. Bounded telemetry history now emits
the same `:partial_data` lifecycle warning as native decimated range reads when
a multi-observable request returns some series and leaves others empty; rendered
browser coverage proves the chart remains usable with only the returned series,
while the widget shell, source badge, and body notice expose `:partial`.

Severity guidance:

- `:error` — widget cannot render meaningful primary data.
- `:warning` — widget rendered but semantics are degraded, partial, stale, or
  recomputed.
- `:info` — context labels, fallback notices, or unsupported optional overlays.

Operators should be able to inspect details, but the normal scan path should
remain fast.

#### 11.9.6 Live, historical, and replay behavior

Runtime behavior:

- Live view starts with `resolve_mode: :initial`, then uses `:live_tick` or
  `:stream_append` depending on source capability.
- During migration from the current ops dashboard renderer, first-party widgets
  should render from engine Frames as soon as their frame presenter exists. The
  current ops dashboard now renders `cadence.value_tile`, `cadence.time_series`,
  and `cadence.constellation_health` from engine Frames; constellation health is
  served by the `:operational_observables` source as a latest limit-state rollup
  matrix. Timer-driven refreshes should still invoke the engine with
  `resolve_mode: :live_tick` and merge only returned live frames, leaving
  skipped historical placements intact.
- The first migration target is `cadence.value_tile`: value tiles can render
  from engine scalar frames. The next bridge is `cadence.time_series` initial
  backfill/context-change data from engine wide frames. Timer-driven appends can
  use the widget registry's `live_mode: :poll_latest` contract: on
  `resolve_mode: :live_tick`, temporal chart placements resolve latest scalar
  telemetry and latest limit-state overlays instead of replaying bounded
  history. A later `:stream_append` source can replace polling without changing
  the renderer contract.
- Scrubbing to a bounded historical range uses `:context_change`; live updates
  pause unless the time range follows now.
- Releasing a historical range back to now creates the live/archive handoff
  described in §6.
- Replay mode is a data-context/time-context change with explicit
  `replay_run_id`; it must label frames as replay/simulation, not flight.
- A widget can be non-appendable even if another widget streams; resolve mode is
  per source request, not only per dashboard.

Client-side chart state can keep short-lived buffers for smooth interaction,
but the engine remains the authority for semantic frames after context changes.

#### 11.9.7 Save, publish, revert

Recommended lifecycle:

- **Autosave/local draft** *(optional)* — editor-only recovery state.
- **Save draft** — validates and writes `DashboardDocument`; creates an
  immutable version snapshot and advances `draft_version`.
- **Publish** — marks a validated version as the operator-facing default by
  advancing `published_version`.
- **Revert** — copies an older version into a new draft; it does not reuse or
  mutate the old version row. Publishing the restored draft remains explicit.
- **Archive** — removes from active lists; audit/event trail preserved. Physical
  delete belongs to future administrative retention policy, not normal editor UI.

Editor behavior:

- opening edit mode starts from `draft_version` when one exists, otherwise
  `published_version`
- view mode resolves `published_version` unless the user explicitly opens an
  editor preview
- leaving edit mode with unsaved local changes should warn, but should not write
  durable versions implicitly
- concurrent saves use `lock_version`/`base_version`; a conflict requires reload
  or explicit save-as-new-draft
- publish should show validation warnings and make the version number visible in
  the confirmation path

Publish/revert/archive should eventually emit operational dashboard events
(`docs/operational-event-timeline-design.md`). v0 can start with version rows
and add event projection later.

#### 11.9.8 v0 UX boundaries

v0 includes:

- view mode
- edit mode
- global time/scope/data controls
- registry-driven widget add/edit
- engine preview during edit
- placement resize/reorder
- widget layout contracts and deterministic responsive collapse
- save/version snapshots
- warning badges and details
- context-preserving data links and basic drilldowns

v0 defers:

- collaborative editing
- real-time edit broadcasting
- dashboard marketplace/templates
- full Telemetry Explore surface
- advanced replay comparison workflows
- user-authored widget grammar
- library widget extraction UI

### 11.10 Navigation and drilldown contract

Dashboards should not be dead-end displays. A widget that shows a bad value,
stale source, limit violation, pass annotation, or connection transition should
lead operators to the underlying evidence without losing operational context.

Navigation has three layers:

1. **Runtime URL state** — reproduces the dashboard view.
2. **Data links** — typed links from widgets, fields, warnings, annotations, and
   source metadata to other Cadence surfaces.
3. **Evidence references** — stable pointers to records that explain why the
   widget rendered what it rendered.

Runtime URL state:

```elixir
%DashboardUrlState{
  dashboard_id: "dashboard_...",
  version: 7 | :published | :draft_preview,
  mode: :view | :edit | :explore | :replay,
  time: %TimeContext{},
  scope: %ScopeContext{},
  data: %DataContext{},
  selected: %{
    placement_id: "placement_1" | nil,
    observable_id: "tlm.hk.battery_voltage" | nil,
    timestamp: DateTime.t() | nil,
    event_id: "mission_event_..." | nil,
    warning_id: "warning_..." | nil
  }
}
```

URL/runtime rules:

- every drilldown carries time, scope, and data context forward
- dashboard URLs can select a placement, observable, timestamp, event, or
  warning without mutating the saved document
- view mode defaults to `published_version`
- edit preview links should carry `version: :draft_preview` and must not imply
  the draft is published
- replay links must preserve `replay_run_id`/data realm and label the target as
  replay/simulation, not flight

Data link shape:

```elixir
%DashboardDataLink{
  link_id: "link_...",
  label: "Open telemetry point",
  target:
    :telemetry_point | :telemetry_sample | :limit_event | :limit_definition |
    :mission_event | :source_health_event |
    :telemetry_revision_decision_event | :telemetry_backfill_lifecycle_event |
    :contact | :command | :data_source | :operational_observable |
    :replay_run | :explore,
  target_id: "record_..." | nil,
  route: "/missions/.../telemetry/points/...",
  context: %{
    time: %TimeContext{},
    scope: %ScopeContext{},
    data: %DataContext{},
    placement_id: "placement_1" | nil,
    observable_id: "tlm.hk.battery_voltage" | nil
  },
  presentation: :side_panel | :navigate | :new_tab | :explore,
  source: :widget | :field | :warning | :annotation | :frame
}
```

Evidence reference shape:

```elixir
%EvidenceRef{
  kind:
    :telemetry_sample | :telemetry_point | :limit_event |
    :limit_definition | :limit_definition_interval |
    :limit_definition_lifecycle_event | :mission_event | :source_health_event |
    :telemetry_revision_decision_event | :telemetry_backfill_lifecycle_event |
    :source_watermark_event | :source_binding_event | :source_binding |
    :source_binding_interval | :binding_set_interval |
    :application_binding_interval | :catalog_revision_interval |
    :operational_interval | :contact | :scheduled_contact | :realized_contact |
    :data_source | :source_request,
  id: "record_...",
  observed_at: DateTime.t() | nil,
  source: :telemetry | :limits | :events | :operational_observables,
  confidence: :direct | :projected | :derived | :best_effort
}
```

Widget type drilldown contract:

```elixir
%WidgetDrilldownContract{
  primary_action: :inspect | :explore | :navigate | nil,
  supported_targets: [:telemetry_point, :limit_event, :mission_event, :explore],
  selection_modes: [:placement, :field, :timestamp, :event, :warning],
  preserve_context?: true
}
```

Source ownership:

- Telemetry source attaches point/sample/catalog/runtime evidence when known.
- Limits source attaches limit event, definition, activation, and selected
  limit-definition interval evidence when known.
- Events source attaches mission event, contact, source-health,
  source-watermark, telemetry revision-decision, and backfill/import lifecycle
  evidence. For dashboard-owned event projections that also persist canonical
  envelopes, the source carries companion `operational_event` evidence and
  DataLinks so explainability can open the durable event spine directly.
- Operational Observables source attaches subsystem-owned evidence and resolver
  provenance.
- Widgets may choose how to present links, but they should not synthesize record
  identity that the source did not provide.

Interaction rules:

- single-click selects within the dashboard
- double-click or explicit action opens the primary drilldown
- annotations open event/contact/command details with the chart time range
  preserved
- warning badges open a side panel with warning details, source watermarks,
  evidence refs, and suggested data links
- "Explore" starts from the selected observable/frame/time/scope/data context,
  not from an empty query builder
- external routes must be generated by Cadence route helpers or a central link
  builder, not string-concatenated inside widgets

v0 includes:

- URL/session state for time, scope, data, selected placement, and selected time
- side-panel warning/evidence details
- links from telemetry fields to point detail or Explore
- links from limit warnings/events to limit event/detail views when available
- links from event annotations to mission event/contact detail
- replay/data realm preservation in generated links

v0 defers:

- full graph navigation across all operational events
- user-configurable data links
- cross-application deep-link marketplace
- browser history for every hover/crosshair movement
- multi-select drilldown workflows

### 11.11 Testing and migration strategy

The dashboard engine should be built behind contracts that can be tested before
the full editor is polished. The goal is to prove historical correctness,
source normalization, persistence/version behavior, and prototype parity without
preserving the retired `Cadence.Ops.*` implementation shape.

Test layers:

| Layer | Proves |
| --- | --- |
| Engine contract tests | `DashboardDocument` + runtime context produce the expected planned source requests, Frames, warnings, watermarks, and links |
| Source contract tests | Telemetry, Limits, Events, and Operational Observables normalize their backing stores into Frames with explicit capability warnings |
| Document/fixture tests | saved JSON documents validate, migrate, publish, revert, and tolerate unknown widgets/observables |
| Widget registry tests | type lookup, option migration, binding validation, layout contract, drilldown contract, and graceful unknown behavior |
| Runtime tests | cache keys, invalidation hooks, coalesced live ticks, cancellation, backpressure, circuit breaker states |
| LiveView/UX tests | view/edit/publish/revert flows, resize validation, warning badges, side-panel evidence, context-preserving drilldowns |
| Migration/parity tests | current prototype dashboard scenarios render equivalent Tier 0 operational value through `Cadence.Dashboards` |

Engine contract fixtures should be small and explicit:

```text
test/fixtures/dashboards/
  value_tile_latest.v1.json
  time_series_with_limits.v1.json
  unknown_widget_retained.v1.json
  draft_published_versions.v1.json
  repeated_spacecraft_status.v1.json
  replay_context.v1.json
```

Golden fixtures should assert semantic shape, not pixel output:

- planned source requests are batched as expected
- Frames contain required field metadata, evidence refs, and data links
- warnings are structured with stable codes
- limit overlays distinguish observed/current/recomputed semantics
- time-series fixtures cover raw/history and native-decimated aggregate Frames
  through the presenter, not only through the source adapter
- unknown widgets/observables render placeholders without corrupting the
  document
- document migrations create new version snapshots when persisted JSON changes

At least one golden harness should cross the application boundary, not just the
engine module boundary: load a checked-in dashboard JSON fixture, validate the
document, plan the request, resolve through real source adapters with injected
read functions, and run the resulting `PlacementFrames` through the same
presenter code the LiveView uses. That harness should assert the stable contract
summary: planned source requests, frame fields, frame metadata, watermarks,
links, structured warnings/actions, and rendered widget data.

Source adapter contract tests should be shared. Each logical source should pass
the same base assertions:

```elixir
assert_source_contract(source,
  supports: [:latest, :bounded_history],
  query: source_query,
  expected_frame_shape: :wide,
  required_metadata: [:observable_id, :quality_state],
  allowed_warnings: [:capability_fallback, :partial_data]
)
```

Migration strategy:

1. Build `Cadence.Dashboards` as the dashboard bounded context.
2. Recreate the current value tile, time-series, and constellation-health
   workflows as golden dashboard documents.
3. Implement engine/source/widget contracts until those golden dashboards render
   through Frames.
4. Add canonical document persistence and route new dashboard writes through
   `Cadence.Dashboards`. Initial implementation stores document JSON on
   `ops_dashboards`, writes immutable `dashboard_versions` snapshots, and
   maintains row pointers for latest/draft version state.
5. Optionally write a best-effort importer from existing `ops_dashboards` JSON
   into v1 dashboard documents, but do not let importer quirks shape the target
   model.
6. Cut over the ops dashboard routes once parity and focused UX tests pass.
7. Retire the old dashboard compatibility path once the new bounded context owns
   the runtime path and old dashboards have either been imported or intentionally
   discarded. *Status: complete for the current early-development prototype.*

Cutover criteria:

- Tier 0 telemetry latest/history and latest limit overlays work through the
  engine
- first-party v0 widgets render from Frames, not direct domain reads
- draft/publish/revert/version snapshots are covered by tests
- dashboard-level resolve replaces per-widget polling
- unknown widget/source degradation paths are tested
- context-preserving links work for telemetry point and limit/event evidence
- `mix precommit` passes with the new routes and old prototype route either
  removed or clearly hidden

This testing strategy should be part of phase 1, not a final hardening step.
The engine contract is only real once fixtures can exercise it without a
browser.
As the dashboard surface grows, browser-level tests should stay deliberately
scarce and product-facing: one full-stack proof per user-visible wiring
contract, with permutations pushed into async engine/source/presenter/component
tests. The current monolithic `ops_dashboard_live_test.exs` is useful evidence
but an expensive default target; future maturity slices should split new
full-stack proofs by workflow area instead of continuing to add every dashboard
case to that serial module. Replacement-recovery browser proofs are the first
example of that direction: they now live in a workflow-specific LiveView test
file so local recovery work can run that surface without traversing the full
dashboard console suite.

## 12. Source readiness tiers (grounds the phasing)

- **Tier 0 — engine seed.** Spacecraft telemetry latest + archive series and
  latest limits. Net-new: the query/Frame contract, time/scope/data contexts,
  source resolver, data source registry, source bindings, limit semantics mode,
  and decimation.
- **Tier 1 — data exists, needs engine-shaped reads.** Derived telemetry
  history, limit transition history, effective limit-definition intervals,
  Events/Contacts source (pass windows from `ScheduledContact.starts_at/ends_at`
  + `MissionEvents`), and first operational observables.
- **Tier 2 — needs new projections or catalogs.** Commands-as-history, file
  transfer progress, platform/ingest health, richer RF/link observables beyond
  first-pass lock state and SNR,
  conditional/mode-aware limit activation, eclipse / ephemeris / maneuver
  events.

The full engine can prove itself end-to-end on **Tier 0 alone** — which is where
the "instead of Grafana" value lives.

Operational readiness is evaluated separately from these data-family tiers.
`Cadence.Dashboards.SourceReadiness` now classifies fresh source-health facts
and explicit connection-test results against a policy. The default policy blocks
fresh `:unavailable` source health plus fresh `failed` or `blocked` connection
tests, while leaving unsupported/skipped/missing active tests non-blocking. Ops
Data Sources surfaces the active policy and per-source readiness reasons so an
operator can distinguish an unavailable source from a healthy source whose
adapter IO check failed.

Publish readiness consumes the same source-selection diagnostics: failed or
blocked connection tests become publish blockers with explicit
`source_connection_failed` evidence, connection-test payload fields, and a
return link into Ops Data Sources focused on the affected source-health
evidence.
Unsupported source-capability blockers now carry requested observables,
requested sampling, frame products, source products, product families, and
supported source capability fields. Operational-observable capability blockers
route back into the widget editor with those fields as editor-focus metadata, so
the picker can highlight the affected observable and explain which latest,
state-history, aggregate, or raw-series source capability is missing.
Publish readiness validates both sampling mode and requested source products,
so a source that supports `:raw_series` for transport bit-rate history does not
silently satisfy an RF SNR history widget. Capability provenance now marks those
product mismatches as unsupported posture instead of reporting native support.
The same source-product and product-family fields are accepted by Ops Data
Sources focus links. Inventory remediation renders them as capability mismatch
rows, uses them to classify candidate replacement sources, and filters binding
changes so a source that only advertises another operational history family is
not offered as a valid replacement for the blocked widget request.

Readiness activity stores remediation in two forms. `remediation_targets` remains
the flattened, route-ready payload used by the current web UI, while
`typed_remediation_actions` preserves the underlying route-free
`DashboardAction` contract (`action_id`, target, kind, query, context, and issue
correlation) so future activity replay, audit review, and non-web operators do
not have to reverse-engineer intent from URL parameters.

The publish-readiness issue/action presentation boundary is domain-owned:
`Cadence.Dashboards.PublishReadinessPresentation` derives issue IDs, messages,
summary rows, flattened remediation targets, and typed `DashboardAction`
metadata. Web modules may wrap or render that contract, but lifecycle payload
generation does not depend on LiveView presentation code.

The publish-readiness lifecycle payload itself is also a domain contract:
`Cadence.Dashboards.PublishReadinessPayload` derives freshness state, issue
summaries, source evidence contexts, flattened remediation targets, and typed
remediation actions. `Cadence.Dashboards.record_dashboard_publish_readiness_check/7`
accepts the dashboard document, validation result, and current summary, then
builds the persisted payload before writing the lifecycle event. LiveView owns
when to record the check and who performed it; the dashboard domain owns the
persisted payload semantics.

## 13. Phased delivery

1. **Engine spine + parity.** New `Cadence.Dashboards` bounded context,
   `DashboardDocument`, `DashboardResolveRequest` / `DashboardResolveResult`,
   Frame/Field structs, first-party widget registry, and dashboard-level
   time/scope/data contexts (Live + quick ranges + custom + replay scrubber;
   primary flight realm by default) and shared crosshair. Resolve through a
   **batched, dashboard-level engine** against the source layer. Include
   contract fixtures and golden parity dashboards from the first slice (§11.11).
2. **Constellation.** Scope context with repeat-by-spacecraft small multiples +
   compare overlays; generalize health into the status matrix.
3. **Widget system (§10).** Stand up the widget registry, explicit data
   contracts, and generic options editor; ship first-party code widgets for
   multi-series charts, limit bands, annotations, telemetry grid, state
   timeline, and status matrix. Prototype the declarative grammar after these
   widgets prove the common surface.
4. **Limit change semantics.** Add effective limit-definition intervals,
   observed/current/compare limit modes, limit-change annotations, and
   limit-aware decimation metadata. This can land before the full event spine if
   backed by a narrow projection, but the long-term owner is the operational
   event model (§8.1).
5. **Operational observables.** Register and resolve first Cadence-produced
   observables: transport bit-rate, RF lock state, frame sync state, RF SNR,
   RF Doppler, connection state, contact phase, command queue depth, ingest
   latency.
6. **Steal-the-polish.** Full Telemetry Explore (dashboard-free ad-hoc
   plotting), reusable panel library, richer data links/drilldown.

Backend portability (data source registry + capability-aware adapter interface)
is built into the spine in phase 1; additional TSDB adapters, realms, and BYO
sources land incrementally behind it.

## 14. Cross-cutting concerns

- **Tenancy & auth.** Queries stay org/mission-scoped even *into* a customer
  store; the existing scoping (`MissionAuth.load_mission`) extends to the source
  layer.
- **Failure isolation.** A slow/broken BYO backend must not take down the
  console: circuit-breaking + first-class **"source degraded / stale"** UX
  states.
- **Credentials.** Per-mission/org backend connection registry, with Cadence
  storing only non-secret credential references and append-only rotation events;
  adapter IO receives secret material only through the secret-backend resolver
  seam that emits redacted security audit events and still needs a
  deployment-backed Vault/KMS-style backend plus RBAC-backed authorizer.
- **Realm isolation.** Flight, rehearsal, AI&T, simulation, replay, and lab data
  must not silently mix. Multi-realm dashboards use compare/federated modes that
  label source and realm explicitly.
- **External-query safety.** Generating queries against an outside system:
  injection surface, timeouts, capability detection.
- **Performance.** Batched dashboard-level resolve (columnar, decimated),
  runtime caches, backpressure, and source circuit breaking replace per-widget
  polling (§5.1.2). A per-mission telemetry stream is a target optimization,
  not a v0 requirement.
- **Concurrency / live sync.** Dashboards are mission-shared; optimistic locking
  prevents silent overwrites, but v0 does not need live collaborative editing.
  Decide deliberately whether shared edits broadcast over PubSub later.

## 15. Implementation Baseline And Maturity Gaps

The execution checklist for turning this target architecture into a mature
product feature lives in
[`docs/dashboard-feature-maturity-checklist.md`](dashboard-feature-maturity-checklist.md).
Keep this section focused on architectural baseline and gaps; use the checklist
for slice ordering, evidence requirements, and completion gates.

Implementation status as of 2026-06-25: the dashboard feature is no longer a
live-only wallboard prototype. It has a canonical dashboard document model, a
query-planning engine, persisted source bindings, runtime cache boundaries,
source health/watermark facts, and URL-backed runtime context controls. The
remaining work is about determinism, explainability, source maturity, and widget
coverage.

Current implementation baseline:

| Area | Exists today |
| --- | --- |
| Document model | `Cadence.Dashboards.Document` is the canonical dashboard representation. `DocumentStore` persists document JSON through `ops_dashboards`, writes immutable `dashboard_versions`, tracks latest/draft/published pointers, supports publish/revert/archive/restore lifecycle flows, and records dashboard lifecycle events. The legacy dashboard compatibility bridge has been retired. |
| Editing and presentation | Ops list/new/show LiveViews use canonical dashboard APIs. Layout/widget mutations go through `PlacementEditor`; render paths use `RenderItem` and `RenderWidget`; version history and lifecycle activity are visible in the dashboard toolbar. |
| Runtime contexts | Engine planning normalizes document defaults, URL/session runtime state, and placement overrides into `TimeContext`, `ScopeContext`, `DataContext`, and `LimitContext`. `DataContext.view` is the typed data-management read view (`:canonical`, `:as_recorded`, `:all_revisions`, `:recomputed`) and participates in cache identity, telemetry selection policy, data-link provenance, telemetry explore links, source-overlay evidence, frame metadata, non-canonical view warnings, and URL-backed runtime controls. The ops show page has URL-backed live/archive/replay-run time modes, data realm/source-binding controls, data-view controls, limit semantics controls, and a generic `scope_kind`/`scope_id` URL contract. Planned source requests normalize execution axes per logical source: temporal telemetry and limits use receipt time, events use occurrence time, and non-temporal latest reads preserve the dashboard display axis. `ScopeContext` carries typed mission, spacecraft, contact, ground-station, source-endpoint, transport, and link ids. Legacy spacecraft context remains supported through `spacecraft_id`; explicit mission and contact scopes are validated against the current mission before reaching the engine. `replay_run` requires `replay_run_id`, defaults implicit data realm resolution to replay instead of document-level flight defaults, is exposed in engine/runtime diagnostics, appears in data-link inspector context, is preserved in dashboard copy/explore links, and is treated as a snapshot/non-appendable mode. |
| Engine and contract | `Engine.plan/1` and `Engine.resolve/2` batch placement source requests, execute logical sources through `SourceRegistry`, fan results back to placement frames, and can opt into strict dashboard contract validation for planned requests and source results. `WidgetFrameContract` resolves registry primary-frame specs against placement bindings during document validation and planning; source overrides are allowed only when the widget contract declares the source, accepted shape, sampling mode, and logical products. |
| Runtime cache and refresh | `RuntimeCacheKey`, `RuntimeCache`, `SourceResultPreflight`, `FrameMaterializer`, `RuntimeCoordinator`, and `RuntimeInvalidation` provide plan/source-result/frame cache identity, cache storage, freshness preflight, materialized-frame caching, refresh/backpressure decisions, and explicit invalidation boundaries. |
| Source bindings and TSDBs | `DataSources` persists data sources and data bindings, records binding/source events, supports managed and BYO TSDB configuration policy, and uses non-secret `SourceCredentials` references for customer-owned sources. `ManagedQuestDBProvisioning` can plan and apply org/mission-isolated managed QuestDB data-source provisioning through the QuestDB schema migrator while recording redacted physical-isolation evidence; `ManagedQuestDBProvisioningJobs` queues the same operation as a durable redacted background job with normal failure/retry state; and the `cadence.dashboards.managed_questdb_provision` Mix task exposes direct plan/apply execution for ops automation. QuestDB is the first concrete managed TSDB target for local telemetry storage and native decimation. |
| Source health, watermarks, revision decisions, and backfills | Source health events/status, source watermark events/status, telemetry observation identity decision events, and telemetry backfill/import lifecycle events exist. `SourceRegistry.facts/2` can fetch current source facts before frame resolution; telemetry and limits expose best-effort freshness/watermark information and cache preflight evidence. Source-health transition events, source-watermark movement events, telemetry revision decision events, and backfill/import lifecycle events can be queried by source identity and observed/source-time window for dashboard overlays. |
| Logical sources | Telemetry supports latest, bounded history, source-binding provenance, segmented historical binding intervals, typed data-management read views, and native QuestDB decimated envelopes when the selected source advertises the capability. Limits supports latest state, observed event history, governed definition intervals, and non-observed semantics guardrails. Events supports contact intervals, mission timeline annotations, source-health transition event overlays, source-watermark movement event overlays, telemetry revision decision event overlays, and telemetry backfill/import lifecycle overlays. Operational observables exist as a first-party logical source seam with a v0 semantic registry for Cadence-produced observables such as transport bit rate, transport execution state, RF lock state, frame sync state, RF SNR, RF Doppler, connection state, antenna pointing state, contact phase, command queue depth, and ingress latency; the registry distinguishes semantic definitions from currently backed ids. `contacts.phase` resolves as a latest matrix from contact projections and as event-history state segments from scheduled/realized contact lifecycle rows; it is selectable as an operational-observable status-matrix, data-table, or state-timeline binding and renders with contact-aware phase/kind/status presentation plus contact DataLinks where available. `comms.transport.execution_state` resolves from canonical operational-event transport execution intervals as an event-history Frame with explicit start/end times, normalized execution states, transport/contact/path context, and transport-execution interval evidence for state timelines. `comms.transport.connection_state` and `ground.station.connection_state` are backed through configured transport/source-endpoint resources plus canonical operational-observable state events or optional runtime snapshots; they render with connection-aware state/adapter/status/target presentation, can emit event-history state segments from timestamped facts, carry link identity when a transport/source-endpoint fact is tied to a link assignment, and preserve unknown state rather than confusing setup existence with live connectivity. `ground.station.antenna_pointing_state` is backed through configured ground-station/source-endpoint resources plus canonical generic operational-observable state events; it emits latest and event-history Frames with pointing/acquisition state, normalized antenna-state coloring, source-endpoint/link context when available, and native antenna-pointing interval evidence. `link.rf_lock_state` and `link.frame_sync_state` are backed through configured transport/link resources plus canonical operational-observable state events or optional timestamped RF snapshots; they emit generic operational-state latest and event-history Frames with `state`/`normalized_state`, link-state coloring, and link/source-endpoint/ground-station context. Link RF metrics including `link.snr_db`, `link.eb_n0_db`, `link.symbol_rate_sps`, and `link.doppler_hz` are backed through configured transport/link resources plus canonical operational-observable metric sample events or optional RF metric snapshots; they emit link-scoped latest metric Frames with metric-specific units and raw-series wide Frames for metric history. `comms.transport.downlink_bitrate` and `comms.transport.uplink_bitrate` resolve from configured transports plus canonical operational-observable metric sample events or optional metric snapshots as latest rows and raw-series wide Frames, carrying link identity when available and keeping directional series distinct. `commanding.queue_depth` resolves from pending command queue entries with mission, source-endpoint, spacecraft, contact, and multi-id scoped counting; multi-scope rows are represented as aggregates over the full scope-id set instead of being mislabeled as the first selected id. `ingress.processing_latency_ms` resolves from canonical operational-observable metric sample events with process-local runtime-health ingress profiler samples overlaid for live reads. Connection-state, antenna-pointing-state, RF-lock-state, frame-sync-state, RF metrics, transport-bit-rate, ingress-latency, and transport-execution operational Frames can filter rows by link scope as well as mission, spacecraft, contact, ground-station, source-endpoint, and transport scope where the backing rows carry those identities. Latest operational-observable rows carry `freshness_state`, `age_ms`, `freshness_policy`, `freshness_checked_at`, and stale/unknown warning metadata, so old or missing contact, connection, metric, queue, and runtime samples render as stale/unknown instead of current. Value tiles, time-series charts, status matrices, and data tables can render these backed operational metrics through declared widget-frame source overrides; state timelines can render backed operational event-history state Frames, including contact phase, connection/RF state, antenna pointing state, and transport execution state. Time-series bindings are metric-only and render operational wide Frames through the same chart presenter used for telemetry. Operational latest metric Frames and metric-history Frames carry resource DataLinks on the frame and value field, a primary `resource_link_id` where a chart series needs one, and operational-event frame evidence for canonical metric samples, so chart series and individual points can drill into the backing transport/source-endpoint/ground-station while the frame evidence panel can explain which event facts produced the series even when there is no telemetry sample id. Status matrices and data tables can bind mixed latest operational observables, with the source returning separate contact, connection, metric, and generic state product frames that the presenter flattens into one widget model. Unsupported widget/source pairings become `unsupported_widget_frame_contract` warnings, and missing snapshots stay `nil`/no-data rather than being coerced to `0 bit/s`. |
| UI diagnostics | The dashboard shows engine degraded state, placement warnings, source-health/freshness summaries, source execution/circuit details, runtime invalidation diagnostics, cache provenance, data links, evidence panels, widget lifecycle states (`ready`, `no_data`, `stale`, `partial`, `error`, `unsupported`), data-management view/revision badges, multi-series time-series payloads rendered from all primary telemetry Frames, decimated min/max envelope bands, unit-aware chart legend/axis grouping, chart point clicks for telemetry samples and operational resource links, operator controls for series visibility and grouped/shared value axes, first-party data-table rows for latest telemetry and operational-observable Frames, row-level product/source diagnostics for mixed operational latest Frames, row-level operational resource inspector links for transport, source-endpoint, and ground-station identities carried by connection/metric/generic-state Frames and operational state-timeline rows, operational resource inspectors with cross-resource related links plus source-inventory/source-health actions, data-source inventory deep links that preserve transport/source-endpoint/ground-station/link focus context and render a visible operational-resource context panel with setup links where setup routes exist, resolved setup names where the referenced transport/source-endpoint/ground-station/link still exists, routing-rule setup navigation for materialized link-assignment focus, first-class ground-station setup navigation plus inferred/missing/unverified fallback for legacy metadata-backed station context, first-party state-timeline lanes for Limits event-history Frames with row-level limit-event/definition/sample/point inspector links where resolvable, first-party state-timeline lanes for operational contact-phase, connection-state, generic-state, and transport-execution event Frames with contact/resource inspector links where resolvable, first-party event-timeline rows for Events source event/interval Frames with row-level mission/contact/source/data-management inspector links where resolvable, and chart overlays for limit-definition intervals, source-binding intervals, source-health transitions, source retention gaps, frame-derived source watermark cursors, persisted source-watermark movement events, persisted telemetry revision decision events, persisted backfill/import lifecycle events, and telemetry correction/backfill ranges derived from frame revision metadata. |

Recent rendered command-queue coverage proves `commanding.queue_depth` across
aggregate and scoped operational paths: two pending queue entries and one
released entry render as a mission-scoped value of `2`, the aggregate row
intentionally exposes no resource DataLink, and frame evidence/copy routes
preserve placement, source request, logical source, data source, source binding,
and mission scope. Source-endpoint scoped status-matrix, value-tile, and
data-table coverage now prove queue-depth filtering counts only pending commands
for the selected endpoint, including a fresh `0 commands` row when another
endpoint has pending commands and the selected endpoint only has released
commands. Scoped rows and value tiles expose a source-endpoint DataLink and
preserve source-endpoint scope through the resolved inspector, route, copy
payload, source status, and frame evidence. The value-tile presenter also keeps
source request, logical source, data source, source binding, and dashboard query
scope context on operational point-shaped data so widget-level frame evidence is
both source-bound and scoped to the active query. Single selected scopes travel
as `scope_id`/`selected_scope_id`; multi-selected dashboard scopes use
`scope_ids`/`selected_scope_ids` so the selected resource and comparison set
remain distinct.
Selected refs also preserve related operational-resource context carried by the
clicked row or frame, such as transport rows that include source-endpoint,
ground-station, and link identities, so follow-on evidence panels, copy links,
and comparison handoffs do not have to infer those relationships from the
current route alone. The same context is serialized into the selected-ref query
params when a side panel opens, so copy/deep links can restore the selected
resource without dropping its related endpoint, station, or link identity. When
the runtime query changes to the same concrete scope kind, restored selections
are kept only if the selected resource id still belongs to the current scope set;
mission or other aggregate scopes can still inspect child resources without
pretending the route itself is scoped to that child. If the selected resource
leaves the active same-kind scope set, stale-selection cleanup clears the
selected-resource query keys while preserving the new runtime scope.
Source and presenter coverage also proves stale source-endpoint command-queue
rows retain their scoped resource link and stale lifecycle instead of dropping
back to a mission aggregate or losing the row-level resource identity.

Recent source coverage distinguishes an empty command queue from missing backing
evidence: a successful command-queue read with no pending entries renders a
fresh `0 commands` aggregate, while command-queue reader failures fail closed as
`source_unavailable` instead of being coerced into an empty queue. Multi-id
command-queue scopes are also treated as aggregate rows over the selected scope
set, so a multi-spacecraft dashboard does not label a two-spacecraft count as
only the first spacecraft. The engine/presenter contract now proves that failure
path produces no command queue frame, emits dashboard and placement
`source_unavailable` warnings, and renders the data-table widget with an
unavailable source status instead of a misleading zero-count row.

Recent source coverage distinguishes no current contact phase rows from missing
backing evidence: successful scheduled/realized contact reads with no rows
produce an empty latest `contacts.phase` Frame with no warnings, while contact
reader failures fail closed as `source_unavailable` instead of being coerced
into an empty contact-phase result.

Recent rendered contact-phase coverage proves `contacts.phase` as an
operational state-timeline under contact scope: a realized scheduled contact
renders scheduled and realized phase rows in the same contact lane, unrelated
contacts are filtered out, the realized row opens the resolved contact
DataLink while preserving the selected contact scope, and frame evidence/copy
routes preserve placement, source request, logical source, data source, source
binding, and contact scope.
Replay-rendered contact-phase coverage now proves the same contact-projection
timeline can run under a replay data context: rows, realized-contact DataLinks,
frame evidence, route params, and copy payloads preserve replay realm, selected
replay run, operational data source, replay operational-observables binding,
dataset, and contact query scope. This is a replay-context propagation proof
for scheduled/realized contact projections; it does not yet make contact
projection rows durable replay-run products the way canonical operational-event
contact intervals are.
Mission-scoped rendered coverage now proves the default operator view can show
contact-phase lanes without a contact-specific URL: scheduled and realized
contacts for the active mission render together, a different mission's contact
is absent, scheduled-contact DataLinks resolve from the mission query, and row
frame evidence/copy routes preserve mission scope plus operational source
context.
Recent multi-contact coverage extends that state-timeline contract beyond
single-contact scope. The source now filters latest and event-history
`contacts.phase` rows through the full selected contact id set, and rendered
browser coverage proves alpha and beta contact lanes render while gamma is
filtered out. Clicking a non-primary beta contact DataLink now keeps the
dashboard query as contact `scope_ids` while selecting beta as the clicked
contact, and row frame evidence/copy routes preserve
`scope_ids`/`selected_scope_ids` without collapsing the comparison scope back to
the primary contact.
Recent spacecraft-scoped contact-phase coverage proves that contact phase does
not have to be directly dictionary-bound or spacecraft-keyed to participate in
spacecraft dashboards. The source resolves setup-backed source endpoints for
the selected mission, filters scheduled/realized contact rows through each
contact path's `source_endpoint_refs`, and admits only contacts whose endpoint
is owned by the selected spacecraft. Rendered browser coverage opens the same
state-timeline under a spacecraft route, verifies the beta spacecraft contact
lane is absent, opens the realized contact DataLink, and proves row frame
evidence/copy routes preserve the spacecraft query via legacy `spacecraft_id`
while the clicked contact remains represented by the selected-scope metadata.
Recent operational-resource contact-phase coverage closes the same loop for
source-endpoint and ground-station scopes. Direct source-endpoint scope filters
contact rows by the contact's declared endpoint refs; ground-station scope first
resolves setup-backed endpoints and then admits only contacts whose endpoint
metadata points at the selected station. Rendered browser coverage proves both
scopes preserve normal `scope_kind`/`scope_id` query context through realized
contact DataLinks, row frame evidence, and copy payloads.
Multi-resource contact-phase coverage now proves the comparison version of the
same contract. Alpha+beta source-endpoint and ground-station scopes render both
selected contact lanes, filter out gamma, and preserve the full operational
resource set as `scope_ids`/`selected_scope_ids` when opening a non-primary beta
contact DataLink or row frame evidence.

Recent source coverage for link-scoped RF metrics proves configured links with
no current RF metric snapshot produce degraded `nil` metric rows with
`missing_snapshot` evidence and setup-resource DataLinks instead of being
coerced to `0 dB` or disappearing from the latest matrix.

Recent source coverage for operational metric history proves configured RF SNR,
RF Eb/N0, and transport bit-rate series preserve metric-specific wide Frames,
and that no-sample windows produce zero-point wide Frames that still preserve
chart metadata and transport/source-endpoint/ground-station DataLinks, while
metric-history reader failures fail closed as `source_unavailable` instead of
being coerced into empty series.
Mixed metric-history requests with some populated series and some empty series
are treated as partial data: the source keeps the returned point series, keeps
empty series out of the chart payload, stamps `:partial_data` warning metadata,
and preserves frame evidence back to the canonical metric sample events that did
produce data.

The operational-observables source capability contract now advertises explicit
metric-history bindings: `link.snr_db`, `link.eb_n0_db`, and
`link.symbol_rate_sps` resolve to `:link_rf_metric_history`/`:link_rf`;
transport bit-rate ids resolve to
`:transport_bitrate_history`/`:transport_bitrate`; and
`ingress.processing_latency_ms` resolves to
`:ingress_processing_latency_history`/`:runtime_ingress`. Mixed operational
metric-history requests can still enter through the generic
`:operational_metric_history` capability, but the source returns
product-specific wide Frames so renderers, DataLinks, and future source
registries do not have to infer product family from an observable string.
The dashboard editor now consumes the same capability metadata for operational
time-series pickers, grouping raw-series choices by source product family and
emitting stable product/product-family DOM attributes for selected and available
observables.
Publish-readiness actions now round-trip unsupported operational source
capabilities back into the same picker metadata, preserving requested source
products and product families so source capability loss is visible at the
affected raw-series option instead of only in a generic source warning.
Rendered unsupported-scope coverage now proves the planner's
`unsupported_observable_scope` guard reaches the operator surface: mission-scoped
value-tile and raw time-series widgets requesting transport bit-rate are blocked
before source execution, render unsupported lifecycles and lifecycle-tagged body
notices with the warning code on the widget and dashboard warning strip, and
expose no chart hooks, chart-point links, or value DataLinks for the mis-scoped
observable.
Context-bound point widgets now also preserve blocking source failures before
any primary frame exists. A retention-gap source warning returns an
engine-backed point-shaped widget contract with `retention_gap`
lifecycle/source status instead of falling through to unresolved or generic
no-data presentation. Telemetry source execution failures on latest and
bounded-history paths return engine-backed value-tile, data-table,
status-matrix, and time-series contracts with widget lifecycle `error` and
source state `unavailable`, keeping those semantics distinct while rendering a
blocked source failure notice. Rendered browser coverage proves those shells
preserve source evidence routing/copy context, avoid leaking nil
source-empty-reason attributes, and still avoid invented values, sample
DataLinks, placeholder rows, row frame-evidence controls, chart hooks, chart
markers, or synthetic point series. Partial bounded-history time-series reads
render only returned observable series, keep missing observables absent, and
preserve chart-point telemetry-sample DataLinks for the returned points with
selected placement, source binding, and data source context. The rendered telemetry time-series path also
proves degraded source health remains a source-status concern, not a data
suppression concern: fresh bounded-history data still mounts a chart and source
evidence/copy routes preserve the degraded source state. Chart point clicks in
that degraded state still resolve to persisted telemetry-sample DataLinks with
the selected placement, source binding, and data source intact. Stale bounded-history
ranges with an explicit freshness policy keep chart data rendered while chart
point DataLinks still resolve to persisted telemetry samples with source binding
and data source context; the widget lifecycle, source badge, and evidence/copy
routes preserve the stale source state. Unknown source-watermark reads follow
the same chart and chart-point DataLink preservation rule but keep the source
state `unknown`, with `watermark_unknown` warnings and evidence/copy routes
preserving unknown freshness instead of mislabeling it as fresh or stale. Retention-gap bounded-history ranges also
keep returned chart data and chart-point telemetry-sample DataLinks rendered,
but the widget lifecycle, source badge, markers, and evidence/copy routes
preserve `retention_gap` because the requested window begins before available
source retention. Healthy empty
bounded-history ranges render as explicit `no_data` time-series widgets with
source evidence and no chart hooks, point links, markers, or synthetic series.

Recent rendered browser, golden, and presenter coverage proves those zero-point
operational metric-history Frames remain engine-backed chart inputs: time-series
backfill emits no point series, but widget data keeps a `no_data` lifecycle with
operational source, binding, data-source, replay-run or archive time mode, and
link/transport scope context instead of treating the frame as unsupported or
absent. The rendered browser path now also opens no-data query and source
evidence for link-scoped RF SNR, Eb/N0, and mixed SNR/symbol-rate metric
histories, transport-scoped bitrate history, and source-endpoint-scoped
ingress-latency history, preserving logical source, data source, source binding,
replay run when present, source state, active dashboard scope, execution scope
where the placement overrides context, and copy/deep-link context.
The same browser-backed replay fixture now proves partial mixed RF and transport
bit-rate metric history: a replay run containing SNR samples but no symbol-rate
samples renders the mixed RF widget with `partial` lifecycle/source status, and
a replay run containing downlink bit-rate samples but no uplink samples renders
the transport bit-rate widget with the same partial semantics. Both paths return
only the populated chart series, omit the missing series instead of fabricating
points, and keep operational-resource chart DataLinks plus operational-event
frame evidence for the returned metric samples.
Focused presenter and render-model coverage now also proves the complementary
populated-stale case: RF metric-history Frames with stale freshness still emit
raw-series chart points and operational resource DataLinks, while widget data and
shell attributes preserve `stale` lifecycle/source status, replay/source-binding
and data-source identity, link scope, freshness state, and source-endpoint
context for diagnostics and browser assertions.

Recent source coverage for ground-station connection state proves configured
source endpoints with no current connection snapshot produce degraded
`unknown` ground-station rows with `missing_snapshot` evidence and
source-endpoint/ground-station DataLinks instead of implying live connectivity
from setup existence.

Recent source coverage for transport connection state proves configured
transports with no current connection snapshot produce degraded `unknown`
transport rows with `missing_snapshot` evidence, link context, and
transport/source-endpoint/ground-station DataLinks instead of implying live
connectivity from setup existence.

Recent rendered connection-state coverage proves mission-scope aggregation for
`comms.transport.connection_state` and `ground.station.connection_state` state
timelines. The operational-observable catalog now declares mission as a valid
aggregate scope for both ids, and the engine admits a mission-scoped request
instead of producing `:unsupported_observable_scope`. A rendered browser smoke
seeds multiple transports and ground-station endpoints in the same mission,
renders all transport and ground-station lanes in one state-timeline widget,
keeps resource DataLinks on the individual rows, and preserves mission scope,
source request, logical source, data-source, and source-binding context through
frame evidence and copy payloads.

Recent rendered connection-state coverage also proves transport-scope filtering
for the same state-timeline widget. The browser smoke seeds alpha and beta
transport/station connection facts, ties the selected ground-station connection
facts to the selected transport id, opens the dashboard with
`scope_kind=transport`, and verifies that beta transport/station lanes are
filtered out while the selected transport and ground-station lanes keep row
DataLinks, native interval evidence, source request, logical source,
data-source, source-binding, and transport-scope route/copy context.

Recent rendered connection-state coverage now proves source-endpoint-scope
filtering as well. The browser smoke seeds alpha and beta source endpoints,
transport connection facts, and ground-station connection facts, opens the
dashboard with `scope_kind=source_endpoint`, and verifies that only rows tied to
the selected endpoint remain. The selected transport and ground-station lanes
preserve row DataLinks, native interval evidence, source request, logical
source, data-source, source-binding, and source-endpoint-scope route/copy
context.

Recent rendered connection-state coverage now also proves link-scope filtering.
The browser smoke seeds alpha and beta link assignments through transport and
ground-station connection facts, opens the dashboard with `scope_kind=link`, and
verifies that only rows tied to the selected link remain. The selected transport
and ground-station lanes preserve row DataLinks, native interval evidence,
source request, logical source, data-source, source-binding, and link-scope
route/copy context.

Recent rendered connection-state coverage now proves multi-transport scope
filtering through `scope_ids` as well. The browser smoke opens the dashboard
with two selected transport ids, verifies that both selected transport and
ground-station lanes render, verifies that a third unselected
transport/ground-station pair is filtered out, and preserves the multi-id scope
through the rendered root attributes, frame evidence, native interval evidence,
source request, logical source, data-source, source-binding, and route/copy
context. Multi-select route context intentionally carries `scope_ids` and omits
single `scope_id`, so evidence consumers can distinguish one selected resource
from a comparison set.

The same rendered path now covers multi-source-endpoint scopes. Browser smoke
opens `scope_kind=source_endpoint` with alpha and beta endpoint ids, proves the
selected endpoints' transport and ground-station connection lanes render while a
gamma endpoint is filtered out, and verifies non-primary beta transport and
ground-station row DataLinks, frame evidence, and native interval evidence
preserve the dashboard `scope_ids` set separately from the clicked
transport/ground-station selected resource identity.

Recent runtime-control coverage now makes that multi-entity scope model
operator-reachable. The dashboard context selector can search scheduled
contacts and setup-backed operational resources, expose a batch action for the
visible results of a kind, patch the route with `scope_kind` plus
comma-delimited `scope_ids`, render the selected multi-scope badge/root
attributes, and clear back to the dashboard default context. This keeps the URL
grammar, engine scope context, visible control state, and clear/deep-link
behavior aligned for multi-spacecraft, multi-contact, multi-ground-station,
multi-link, multi-transport, and multi-source-endpoint scope sets.

Recent DataLink/evidence preservation work closes the main follow-on edge case
for multi-scope dashboards. Rendered DataLink controls now derive event attrs
from `ScopeContext.primary`, selected refs for operational-resource links use
the clicked resource as `selected_scope_id`, and the surrounding dashboard route
continues to carry the full `scope_ids` set. Query-restored selections match
against that set instead of treating non-primary resources as stale. Browser
coverage now opens a beta transport row inside an alpha+beta transport scope and
proves the side panel remains active while the URL/copy payload preserve both
`scope_ids` and `selected_scope_ids`. State-timeline row frame-evidence actions
also carry the active dashboard query scope separately from the row's operational
resource identity, so a non-primary row can open evidence without collapsing the
route/copy payload back to a single primary scope. Evidence root attrs, widget
source evidence params, widget-level point/time-series frame evidence actions,
status-matrix/data-table row evidence actions, and source-context actions also
preserve the comma-delimited scope set where the dashboard query is multi-scope,
so copy links and evidence inspectors can distinguish a single selected
transport/link/source endpoint from a selected comparison set.

Recent source coverage for frame-sync state proves configured links with no
current frame-sync snapshot produce degraded `unknown` rows with
`missing_snapshot` evidence and transport/source-endpoint/ground-station
DataLinks instead of implying synchronized state from setup existence.

Recent rendered ingress-latency coverage proves
`ingress.processing_latency_ms` as an ingress/runtime operational observable:
telemetry ingress persistence emits durable metric samples for two source
endpoints and the rendered dashboard shows only the selected endpoint under
source-endpoint scope, the row opens a source-endpoint DataLink inspector and
copy payload, and frame evidence/copy routes preserve placement, source
request, logical source, data source, source binding, and source-endpoint scope.
Latest ingress latency also preserves endpoint row identity under
multi-spacecraft scope: source and rendered browser coverage seed alpha, beta,
and unselected gamma endpoint samples through the telemetry write path, filter
latest rows to the selected spacecraft set, keep rows keyed to source endpoints
rather than spacecraft aggregates, and preserve the surrounding spacecraft
`scope_ids`/`selected_scope_ids` through endpoint DataLinks, frame evidence,
routes, and copy payloads.
Contact-scoped ingress latency is now an explicit source and rendered contract.
Telemetry ingress can promote contact ids from raw-evidence metadata into the
canonical operational-observable metric sample event, the source filters latest
and raw-series history frames by contact id, and status-matrix rows preserve both
the endpoint resource identity and `contact_id`. Rendered browser coverage opens
a dashboard with `scope_kind=contact`, proves unrelated contact samples are
filtered out, exposes the row contact DataLink inspector, and preserves contact
scope through selected URL state, frame evidence, and copy payloads. Latest
contact DataLinks can survive as URL-selected refs even when the row does not
carry a timestamp selection; contacts remain scope-bound, but they are not
treated as timestamp-bound observation refs.
Ingress latency is also backed as metric history: source, golden, and rendered
browser coverage now prove a multi-source-endpoint scoped raw-series time-series
widget resolves durable ingress latency samples from the telemetry write path,
filters non-selected endpoints out of the chart backfill, mounts uPlot,
preserves flight source/binding context, carries point-level source-endpoint
DataLink metadata, opens the rendered source-endpoint DataLink inspector/copy
payload, and preserves source-bound plus query-scoped widget-level frame
evidence through `scope_ids`/`selected_scope_ids` route and copy parameters.
Rendered replay and archive no-data coverage also proves a source-endpoint
scoped ingress-latency history widget blocks chart mounting when no samples
exist in the selected time window, renders `no_data` lifecycle/source state with
`scope_no_data`, and preserves operational source, data source, source binding,
realm, replay-run context when present, source-endpoint execution scope, query
evidence, source evidence, and copy/source-inventory routes without inventing
point DataLinks.
Rendered degraded-source replay coverage proves the complementary populated
case: ingress-latency history still mounts a chart and renders returned
source-endpoint samples while the widget reports degraded source health, keeps
source data state `ready`, renders the degraded source badge, and exposes a
source-health transition marker with source-health event DataLink context for
the replay source binding/run.
Rendered source-unavailable archive coverage proves the hard-failure case:
when the ingress-latency history reader cannot answer, the widget reports
`error` lifecycle and unavailable source state, blocks chart hooks, uPlot,
markers, point links, and backfill series, preserves source-endpoint execution
scope plus operational source/data-source/source-binding context, and keeps
query/source evidence routes and copy payloads anchored to the failing source
request.
The same rendered path now proves partial multi-source-endpoint semantics:
when the selected scope set includes an endpoint with no ingress-latency samples,
the source emits an empty series for that endpoint, the widget renders
`partial` lifecycle/source state with ready returned data, the chart keeps only
the populated endpoint series, and chart point DataLinks do not invent targets
for the missing endpoint.
That rendered path also proves the widget shell source-status attrs and query
diagnostics carry logical source, data source, binding, realm, archive
receipt-time axis, source-endpoint scope kind, and the full selected
`scope_ids` set, while query evidence normalizes a selected
`source_endpoint` scope into `selected_source_endpoint_id` for evidence panel
routes and copy payloads.
The default reader now
also consumes durable operational-observable metric sample events for live and
replay reads, keeping selected replay-run source contexts isolated from live and
unrelated replay metric samples; focused source coverage also proves live reads
overlay process-local runtime-health ingress samples onto durable metric samples
by choosing the newest sample per ingress resource, older live samples do not
hide fresher durable samples, and absent durable/live samples produce an empty
no-data frame instead of an invented missing metric row, while replay reads
remain durable-only. Successful
telemetry ingress persistence now emits those durable metric sample events with
source-endpoint, spacecraft, evidence, and timing metadata.

Remaining maturity gaps:

1. **Replay is context-aware, not a full replay workflow.** Dashboard URLs can
   carry `time_mode=replay_run` and `replay_run_id`, and the engine preserves
   replay context through runtime diagnostics, data-link inspectors, dashboard
   copy links, telemetry explore links, source freshness warnings, and source
   resolution/execution warnings, frame metadata, and source overlay markers.
   Source watermark adapters now receive replay identity, frame-derived
   watermark objects carry replay identity, and source evidence URLs/copy links
   preserve replay/time/requested-source context from overlay clicks. Source
   selection, source-result cache keys, and frame cache keys treat replay-run
   data as snapshot replay data rather than flight data when no explicit data
   realm overrides the request. Runtime
   controls now expose a persisted replay-run selector, replay window/progress
   metadata, replay-run status/sample-count metadata, unlisted deep-link
   fallback, and a replay-preserving scrub-to-selected-datum command. Browser
   coverage now proves replay mode, replay-run id, persisted replay-run
   metadata, replay window metadata, copy/deep-link hydration, and scrubbed
   route patches survive the live authenticated route. Telemetry latest/history
   execution now carries `replay_run_id` into source filters and resolves replay
   latest values from replay-scoped history rather than live current values.
   Source selection now treats replay mode as an explicit replay contract:
   missing `replay_run_id`, explicit flight realm/source selection, and missing
   replay bindings produce replay-specific warnings with source-readiness
   actions that preserve replay context. Limits latest/history/compare requests
   now carry replay identity through source options, and replay latest limits
   read replay-scoped event history instead of the live latest-state projection.
   Events contact/timeline requests now carry replay realm, data source, source
   binding, dataset, and replay-run identity through frame metadata and reader
   options. Operational-observable requests carry the same replay identity
   through frame metadata, DataLink context, and reader options, including
   connection-state, RF-lock, and frame-sync state-history readers. The
   default transport execution, connection-state, RF-lock, and frame-sync source
   readers now scope canonical operational events by replay run while excluding
   replay rows from live history. Completed replay runs now project
   managed capability/action/timer runtime records into
   replay-scoped canonical operational events, and replay mission-timeline reads
   project those managed runtime facts through the canonical mission-event
   projector. Browser smoke coverage now proves replay-specific limit-analysis
   buckets expose selected replay-run clock evidence in the live authenticated
   dashboard, and separately proves replay-managed runtime mission timeline rows
   preserve selected replay-run/source context through the rendered event
   timeline, projected mission-event inspector, and canonical operational-event
   handoff.
   Browser coverage also proves replay contact interval rows preserve selected
   replay-run/source context through the rendered event timeline and resolved
   contact and canonical operational-event inspectors, including patched
   route/copy payloads that preserve selected contact, operational event,
   replay run, and source binding identity. Rendered `contacts.phase`
   state-timeline coverage now separately proves replay context propagation for
   contact projection rows, realized-contact DataLinks, and frame evidence while
   keeping the stronger replay-isolation claim with canonical operational-event
   contact intervals. Source-capability
   posture rows in the event timeline now carry the canonical operational-event
   id and filter their widget DataLinks against that id instead of treating the
   posture source record as a mission event; LiveView coverage proves those
   rendered row links open the canonical operational-event inspector and preserve
   route/copy selected-ref context. Source-capability posture, source-health,
   source-watermark, and native transport capability/action/timer canonical
   event ids are now replay-scoped, and source-record uniqueness is
   replay-scoped, so the same source record can be preserved independently for
   live and multiple replay runs instead of being overwritten at the event-store
   boundary. Operational-observable event-history Frames now carry source
   operational-event DataLinks alongside resource DataLinks, and rendered replay
   RF, connection-state, and transport-execution state-timeline rows can open the
   canonical source event directly while preserving replay/source-binding route
   and copy context.
   Transport execution interval projections now also preserve replay-scoped
   source event ids. Connection-state, RF-lock, and frame-sync
   state snapshots now use typed canonical source-record families while keeping
   the existing operational-observable state Frame contract. RF-lock and
   frame-sync facts now also project into native link RF intervals that close
   within each RF state family, and transport/ground-station connection facts
   project into native connection-state intervals. The default dashboard
   connection-state, RF-lock, frame-sync, and transport-execution history frames
   now preserve interval ids, source operational-event ids, and typed interval
   evidence refs for those native projections, so operators can follow
   projected connection/RF/transport rows back to the interval and source event
   that produced them. Transport-execution frames also carry source-endpoint,
   ground-station, and link context from interval payloads so selected runtime
   application-binding evidence can be resolved from frame fields when the
   dashboard request is transport scoped. Runtime ingress-latency history frames
   use the same source-endpoint inference path, so source-endpoint scoped runtime
   metric histories can attach selected binding-set and application-binding
   evidence without becoming telemetry-catalog reads; rendered browser coverage
   now proves those selected runtime-ingress interval refs survive into the frame
   evidence panel. Browser coverage now proves replay RF state-timeline, replay
   antenna-pointing state-timeline, live connection-state timeline, and live
   transport-execution timeline frame evidence render native interval refs as
   clickable DataLink handoffs that preserve replay/source-binding,
   ground-station/source-binding, or transport/source-binding context. The
   remaining replay gap is deriving richer runtime-derived views.
2. **Scope is broader but not yet a full product surface.** The runtime URL and
   engine path now accept generic `scope_kind`/`scope_id` values, with validated
   mission/contact scopes and legacy spacecraft selection. The visible picker
   can select mission, spacecraft, contact, source-endpoint, ground-station,
   transport, and link contexts. Widget authoring can now either follow the
   dashboard context, use the legacy fixed-spacecraft override, or pin the
   current dashboard context as a placement-level scope override, including
   non-spacecraft scopes. Connection-state and transport-bit-rate operational
   observable rows now carry link identity where available and can be filtered
   by link scope. The remaining product work is broader source-specific
   semantics for ground station, transport, link, mission aggregate,
   multi-entity, and comparison scopes.
3. **Widget coverage is still product-thin.** Value tiles, time series, status
   matrix/constellation health, a first data-table widget, a Limits-backed
   state-timeline widget, operational contact/connection state timelines, an
   event-timeline widget, lifecycle badges/notices, and supporting chrome exist,
   and time-series charts can render multiple primary telemetry series with
   decimated min/max envelope bands, unit-aware legend/axis grouping, series
   visibility toggles, grouped/shared value-axis controls, and lane-grouped
   state timelines that can bind multiple operational state observables and
   close segments independently per resource. Rendered browser coverage now
   proves multi-series chart legend hide/show behavior, including the guard that
   keeps the last visible series rendered, and mixed-unit chart axis toggling
   between grouped and shared value axes. Latest status matrices/data
   tables and state timelines now accept generic operational-state fields, so
   products such as RF lock or frame-sync state do not need connection-specific
   presenter branches. Time-series charts can bind metric operational
   observables such as RF SNR, transport bit rate, and ingress latency as
   raw-series wide Frames, and the editor groups those raw-series choices by the
   source-advertised metric-history product family instead of relying on
   observable id naming.
   RF lock, frame sync, RF SNR, and transport bit rate now have first backed source paths;
   the mature surface still needs richer grid/table variants, backed
   projections/streams for additional operational-state and RF metric products,
   richer event annotation lanes, and richer rendering when multiple lifecycle
   conditions are true at once.
4. **Historical explanation has broad coverage but shallow workflow integration.** Time-series charts can now expose
   limit-definition intervals, source-binding interval changes, source-health
   transitions, source retention gaps, frame-derived source watermark cursors,
   persisted source-watermark movement events, persisted telemetry revision
   decision events, persisted backfill/import lifecycle events, and telemetry
   correction/backfill ranges from frame metadata. Watermark cursor and
   correction/backfill range markers route into the existing source/frame
   evidence panels with request, source, data-view, and revision context.
   Historical source-binding misses now distinguish a missing binding from a
   binding that exists but was not effective at the requested archive time; the
   warning details carry the requested binding timestamp, miss reason, nearest
   binding/data-source interval, and source-selection candidates, and the
   diagnostics strip renders candidate interval windows beside rejection
   reasons.
   Rendered-browser coverage now clicks frame-derived corrected revision and
   advisory/backfill range markers, including both warning codes coexisting on
   the same chart frame and a counter-only dashboard filtered out of a mixed
   revision context. Source-binding and canonical/all-revisions browser coverage
   proves corrected-range markers stay scoped to the selected binding and data
   view. Replay/flight browser coverage proves corrected-range and advisory
   backfill markers stay scoped to the selected realm and replay run, and replay
   telemetry revision evidence now preserves the replay `generation_time` axis
   end to end. Together these flows prove the fallback frame-evidence route
   preserves source request, source identity, time/data-view context, replay
   context, warning code, revision state, dependency fingerprint, frame
   warning/dependency rows, and shareable copy-link context without leaking
   unrelated revision markers.
   Rendered-browser coverage now clicks retention-gap and frame-derived
   source-watermark cursor markers from archive and replay charts and proves
   source evidence preserves source request, logical source, realm, data-source,
   source-binding, selected time context, replay run, requested data context,
   retention-gap state, and shareable copy-link context. Archive coverage also
   proves durable source-watermark status can feed the same cursor path,
   retention-gap intervals render even when they occur before the first returned
   telemetry sample, and persisted source-watermark event overlays are filtered
   by selected source binding and dataset.
   Source-health transition and persisted source-watermark movement markers
   now route directly into durable DataLink inspectors and retain selected
   placement/time plus replay source context.
   Revision decision and backfill/import lifecycle event markers carry typed
   dashboard data links and open the durable event inspector directly when a
   link is available. Rendered-browser coverage now clicks a telemetry
   revision-decision marker from a chart and proves the durable inspector,
   selected decision event, dashboard limit mode, and shareable copy-link
   context survive the handoff. Events source frames also attach companion canonical
   operational-event evidence/DataLinks for source-health, source-watermark,
   telemetry revision-decision, and backfill/import lifecycle rows, so the
   frame evidence panel can open the durable event envelope without inferring it
   from projection ids. Frame evidence inspectors now summarize selected
   source-binding, binding-set, application-binding, and catalog-revision
   intervals as stable rows, so semantic context selected by the engine is
   visible without reading raw frame metadata. Resolvable frame evidence refs
   render as DataLink handoffs, allowing direct canonical operational-event,
   source-binding lifecycle, and limit-definition lifecycle evidence to open
   from the frame evidence panel while subsystem lifecycle inspectors link back
   to their canonical operational-event envelopes. Projected binding-set,
   application-binding, catalog-revision, source-binding,
   transport-execution, and limit-definition interval refs open interval
   inspectors that show active windows, subjects, payload/metadata, and
   source-event handoffs. Application-binding intervals can hand off to their
   source endpoint, and transport-execution intervals can hand off to their
   transport/contact resources when the interval payload carries existing
   resource ids. Telemetry latest/history frames and value-field metadata now
   also carry selected source-binding interval, source-binding event, and
   source-binding refs when the binding is selected from an effective interval,
   so source-corpus evidence survives field-level inspection and chart
   interactions. The source registry enriches telemetry frames with unique
   selected binding-set, source-endpoint application-binding, and telemetry
   catalog-revision interval refs at the selected source-binding time, so frame
   evidence can explain the runtime/catalog semantics active for the displayed
   telemetry values. The same source-registry interval contract now covers the
   Limits latest-state path with selected telemetry catalog-revision interval
   refs, so observed limit states can explain the catalog/runtime meaning of
   the telemetry point they classify in addition to the selected limit
   definition; the frame evidence presenter renders those selected
   limit-definition and catalog-revision intervals as stable detail rows, both
   for Limits-primary frames and telemetry-primary frames with Limits overlays.
   The live browser smoke now seeds canonical catalog-revision evidence and
   proves the authenticated frame evidence inspector exposes selected threshold
   and catalog context from that overlay path. It also covers the generic operational metric-history path for RF
   SNR, transport bit-rate, and runtime ingress-latency Frames when the source
   endpoint is uniquely recoverable from frame context. Frame evidence aggregation reads evidence refs from both
   frame and value-field metadata, and the LiveView-facing `open_evidence` path
   now proves selected interval refs survive from `dashboard_engine_result`
   through event params, evidence-query state, and the assigned evidence panel.
   The rendered evidence panel now proves operational-event, binding-set,
   application-binding, catalog-revision, source-binding, transport-execution,
   limit-definition, and lifecycle refs become clickable DataLink handoffs, and
   that Limits frames expose selected limit-definition interval,
   limit-definition lifecycle event, catalog-revision interval, and
   catalog-revision source-event detail rows in the inspector DOM
   instead of display-only rows. The
   operator-facing chart/explainability surface now labels non-canonical,
   replay/simulation, corrected, late, partial, and backfill states from the
   same metadata. The canonical telemetry storage write path emits
   backfill/import/late-data lifecycle events for identified historical writes,
   including failed write attempts. A workflow-facing API can also record
   backfill/import request, approval, rejection, start, completion, and failure
   events before storage writes occur, and a narrow workflow runner can wrap a
   write operation with that sequence while suppressing duplicate write-outcome
   rows. Product-level APIs can also record individual historical-data workflow
   stages (`requested`, `approved`, `rejected`, `started`, `completed`,
   `failed`) without immediately writing samples, so UI/job orchestration can
   expose request/approval state before execution. Product-level sample
   backfill/import entrypoints now derive lifecycle scope from samples and call
   the runner before writing through canonical telemetry storage. Revision
   decision and backfill/import lifecycle overlay frames attach typed
   `EvidenceRef` and `DashboardDataLink` values. Product telemetry
   data-management APIs now expose an operator/system correction authority
   boundary for observation identity decisions; it requires tenant, realm,
   data-source, and source-binding context, records durable observation identity
   decision events, and carries correction-workflow evidence into the dashboard
   inspector. The dashboard inspector can resolve those durable events into
   scoped rows plus related telemetry-point/sample links, and backfill/import
   lifecycle inspectors show workflow, stage, and run identity as first-class
   rows. Backfill/import lifecycle inspectors now expose the first visible
   operator controls for request, approval, rejection, start, completion, and
   failure transitions; each action records a new durable historical-data
   workflow event and opens that resulting event in the inspector. These
   controls now submit through an editable workflow form for operator reason
   and source-window overrides, and the server rejects unconfirmed workflow
   transitions before recording lifecycle state. The form still inherits durable
   source identity from the inspected lifecycle event. Confirmed `started`
   transitions enqueue a durable historical-data workflow job through the
   existing `Cadence.Jobs` runner. The job executor reads the selected
   point/source-time window from the configured history store, writes matching
   samples through canonical telemetry storage with duplicate write-outcome
   lifecycle rows suppressed, then records completed or failed workflow lifecycle
   state with job/source diagnostics. The dashboard lifecycle inspector now
   resolves the associated durable job and exposes its id, status, attempt
   count, and failure reason alongside the workflow lifecycle rows; once a job
   exists for a run, the inspector prevents duplicate start submissions. Failed
   jobs can be requeued from the same inspector without creating a second job
   for the run, preserving the durable attempt count for the next execution.
   Failed job lifecycle events now carry structured failure diagnostics,
   including failure code/detail, retryability, retry blockers, recovery action,
   source selector, and requested source window; the dashboard inspector exposes
   those as first-class rows and suppresses retry when the recorded failure says
   the workflow request must be corrected first. Non-retryable failures expose a
   corrected-request form that records a new durable `requested` event with a new
   run id, corrected source identity/window/point fields, and evidence linking
   back to the failed run/event/job. Lifecycle inspectors now include a
   workflow-explanation section that summarizes current state, source
   identity/window, request-group progress, durable job status, retry/correction
   requirements, and late-data policy source-event relationships so operators
   do not have to infer the chain from raw event rows. Late-data policy events
   now carry the execution effect the dashboard should explain: accepted data is
   canonical/current-projection-eligible, while rejected data is advisory
   history-only and suppresses latest/current refresh. The product API can also
   execute that policy against source samples selected by source identity and
   source/receipt window, then record the selected sample count in the policy
   lifecycle event for dashboard inspection. The Events source projects that
   policy execution summary into telemetry-backfill lifecycle Frames as
   `selected_sample_count`, `projection_effect`, `write_validity_state`,
   `record_current_values`, and `refresh_latest_value`, so dashboard event rows,
   data-management badges, and time-series markers can explain the operational
   effect without resolving the inspector first. Late-data badges and chart
   marker hover titles summarize the same execution effect compactly, including
   selected sample count, write validity, and whether current/latest projections
   were refreshed. The lifecycle inspector's late-data policy control now
   previews accept/reject projection consequences before submission and labels
   whether the action will execute against selected samples or only record an
   auditable event. That execution mode now comes from telemetry data management
   and is submitted explicitly with the dashboard command; sample-execution
   submissions do not silently fall back to event-only recording when source
   fields are incomplete. Replay-run completed-workflow inspectors preserve
   dashboard time mode, replay run id, and selected limit mode through the
   rendered late-data policy handoff, force event-only audit recording, and
   reject replay-context sample execution so a replay review cannot implicitly
   write canonical flight telemetry. Frame metadata can also carry
   `historical_workflows` and `active_historical_workflows`, which the dashboard
   data-management presenter turns into the same chart/table badge contract used
   for event rows. Telemetry source frames now populate active workflow badge
   metadata from durable backfill/import lifecycle events when resolved through
   the dashboard runtime, and badges carrying lifecycle event ids open the same
   data-link inspector as lifecycle event rows. Revision decision inspector
   controls preview the canonical/conflict/superseded/advisory effect before
   applying an operator decision, so correction-authority actions are not
   presented as opaque event logging. Those revision decisions also preserve the
   selected dashboard limit mode through form submission, durable decision
   evidence, observation-identity state payload, and latest-action metadata so
   the operator handoff remains tied to the same observed, current, recomputed,
   or compare semantics that framed the review. The rendered browser harness
   now drives this revision-decision path against a live route and verifies the
   persisted decision evidence and state payload preserve compare-mode context.
   Dashboard-created historical
   backfill/import requests now preserve originating dashboard id, dashboard
   version, time mode, and data-management view in the durable lifecycle event
   payload so request creation can be audited back to the exact operational
   view that produced it. Historical workflow actions now cross a named
   dashboard → data-management handoff boundary before calling product APIs:
   request creation packages normalized workflow kind, requested stage, command
   attrs, selected point ids, and selection-state params separately from the
   presentation form; stage transitions, group approval/start transitions, and
   correction requests package their workflow/stage, command attrs, group id, or
   correction refs through the same handoff boundary; job and failed-group
   retry commands package retry ids and actor attrs through retry handoffs before
   calling data-management APIs. The workflow controls presenter now exposes
   first action-policy records for individual stage transitions, group stage
   transitions, retry job, retry failed group items, and correction request
   actions. Eligibility, disabled state, eligible counts, and reason vocabulary
   now come from a telemetry data-management product API; the dashboard policy
   layer only decorates those decisions with preview text, operator-facing
   explanation, and availability conditions. The lifecycle inspector now renders
   unavailable-action explanations from those same policy records instead of
   deriving disabled button rationale in the component. Selected-event
   single-stage submissions now go through a guarded data-management transition
   API that re-evaluates the same action policy against the source lifecycle
   event before recording the next stage, so stale or forged dashboard params
   cannot skip prerequisites. The lifecycle explanation summary also uses
   telemetry data-management semantics for state, severity, badge, and reason,
   while the dashboard owns display text, rows, and styling. Individual and
   group workflow stage eligibility now share the same ordered transition model:
   requested can move to approve/reject, approved can move to start/reject, and
   started or retried can move to complete/fail, preventing dashboard group
   actions from skipping prerequisite lifecycle
   states. Workflow submit results now pass through the same presenter boundary
   as structured action outcomes with action, status, reason, kind, message, and
   relevant ids/counts before becoming operator flashes, and the latest
   normalized outcome is retained in LiveView state and
   rendered as workflow action metadata in the lifecycle inspector. The generic
   data-link action outcome card also promotes normalized
   decision/runtime/request/result/target handoff fields into stable attributes,
   so dashboard late-data policy, revision-decision, and workflow recovery
   submissions can be asserted and inspected without treating metadata JSON as
   the only contract. A shared action-outcome presentation helper now owns this
   stable attribute mapping with component-specific prefixes/aliases, so new
   action surfaces do not need to reimplement the metadata-to-DOM contract. The
   historical workflow latest-action presenter likewise owns its stable DOM
   attributes for action state, retry disposition, result/target handoffs, and
   handoff counts so the component does not duplicate normalized outcome-field
   mapping. The hidden workflow-controls action outcome uses the same
   presenter-owned mapping, keeping submit feedback and latest-action evidence
   aligned on retry/result/target fields. Historical workflow action outcomes
   now also preserve the originating dashboard id/version, time mode, replay
   run, data view, and limit mode through those stable latest-action and hidden
   submit-feedback attributes, making the operator handoff self-contained at
   the same runtime context boundary as the durable event payload. Rendered
   LiveView workflow proof now verifies those attributes through actual
   replay-backed stage-transition and correction-request submissions, plus
   live/archive direct request and grouped request/group-stage submissions.
   Retry and replacement-recovery latest-action outcomes now derive the same
   dashboard runtime context from the selected lifecycle inspector, keeping
   single-job retry and grouped retry handoffs anchored to the dashboard
   id/version, time mode, data view, and limit mode that produced the inspected
   failure. Correction-created replacement request events now persist submitted
   dashboard context too. Missing replacement-job inspection has rendered proof
   for that same context handoff from the corrected replacement event. Stale
   replacement inspection/requeue now have rendered browser proof that recovery
   controls submit the exact replacement run/job/event, durable
   inspection/requeue events preserve dashboard context, requeue returns the
   stale job to queued, and latest-action outcomes retain dashboard context plus
   replacement run scope. The workflow
   controls presenter also composes that latest outcome into a visible
   last-action status panel with status styling and normalized reason/stage
   fields, so success, failed, blocked, and no-op submissions use the same
   vocabulary as action policy. The dashboard request panel also renders a
   read-only preview of workflow kind, effect, points, source identity, source
   window, and originating dashboard runtime context before the operator
   confirms the request. Recovery policy now treats `correct_workflow_request`
   as exclusive with retry: correction-required failures are excluded from
   retryable group counts, direct retry APIs reject them, and the inspector
   presents correction as the available recovery path. Correction requests now
   validate their failed source event in the caller's organization/mission
   context, require that the source is a correction-required failed
   backfill/import event, and inherit source group/item/job provenance into the
   new request event. Request-group summaries also distinguish correction
   requested/started/completed from correction superseded, where superseded means
   a completed correction lifecycle event now resolves the original failed item.
   Correction lifecycle stage transitions now route through a guarded product
   transition API that validates the correction request and failed source event
   before recording approved/started/completed stages. Telemetry
	   data-management now also owns a bulk correction-authority decision API:
	   callers provide one shared workflow context plus per-identity canonical
	   candidate/evidence fields, and the product layer writes per-identity decision
	   events with consistent workflow item evidence and a partial-failure summary.
	   Dashboard comparison-review activity now uses that API for eligible open
	   findings, preserving the originating review request as the shared correction
	   workflow id and storing each finding as per-item evidence.
	   Remaining work is richer UI/job orchestration for these workflows, stronger
	   approval/start/correction/retry policy semantics, a more complete new-request
	   creation surface, and multi-point/bulk source-window execution.
5. **Data management view comparison exists, but is still a first workflow.**
   `DataContext.view` can select canonical, as-recorded, all-revisions, or
   recomputed read semantics, and telemetry/cache/link/explore/evidence paths
   preserve that choice. Telemetry frames record the selected view, and
   non-canonical views produce warning badges/evidence details. Operators can
   choose a primary view and a compare view for the current dashboard runtime
   context; value tiles show numeric deltas, time-series widgets render a
   secondary comparison series, and widgets label the primary-vs-compare view
   pair. Widget headers now expose a first comparison summary contract: scalar
   widgets summarize delta state, chart widgets summarize primary/compare point
   coverage, and missing comparison data is visible instead of silent. The page
   model also exposes dashboard-level comparison rollup attributes so tests,
   future UI, and workflow handoffs can count delta, unchanged, coverage, and
   missing comparison states without scraping widget markup. A dashboard-level
   comparison strip now makes those counts visible to operators when comparison
   mode is active, with rollup drilldowns linking each count category back to
   the affected widgets and carrying primary/compare sample ids and data-link
   inspector actions when that provenance is available. The page model also
   emits a first versioned comparison investigation preset payload containing
   dashboard identity, normalized runtime query, current path, rollup counts,
   affected groups, and per-widget sample/link references so the active
   investigation can be copied without scraping UI state. That payload can now
   be persisted as a named dashboard-scoped investigation preset with list,
   fetch, and delete APIs, and the dashboard comparison strip exposes first
   save/list/reload/delete controls for those presets. Applying a saved preset
   restores runtime comparison context only; transient panel and selected-data
   state remains part of the current operator session. Comparison rollup rows
   can also open a first `comparison_finding` inspector handoff carrying the
   affected placement, widget, primary/compare sample ids, view pair, counts,
   delta, and related sample links. Remaining work is richer comparison
   orchestration. Comparison findings now enrich that handoff with observation
   identity, storage provenance, and primary/compare canonical sample context
   when the linked samples still resolve in the mission scope, and the data-link
   panel can open the same revision-decision correction controls used by
   telemetry revision events. Submitted comparison-finding decisions persist the
   source placement, widget, view pair, primary/compare samples, and comparison
   state into the revision decision event evidence ref, and the resulting
   decision-event inspector renders that trail after submission. The comparison
   rollup now uses those persisted decision events to mark handled findings,
   expose open/handled workflow groups alongside the existing delta/missing
   groups, and link directly to the applied decision event. The same
   deterministic `dashboard_comparison_open_findings.v1` payload can be copied
   for external workflow creation or submitted in-app as a
   `dashboard_comparison_review_request.v1` dashboard lifecycle event, preserving
   the operator-visible open-findings set, placement ids, actor, version, and
   lifecycle pointers in the dashboard audit trail. The activity panel renders
   those review-request details back to the operator, including request kind,
   open count, affected placements, and individual finding rows. Operators can
   mark the request resolved from the activity trail with an optional
   resolution note, producing a paired
   `dashboard_comparison_review_resolution.v1` lifecycle event that references
   the original request event and records disposition/reason, selected review
   placement, and affected placement ids. The persistence boundary rejects
   duplicate resolution events for the same request and rejects resolution
   placement context that no longer belongs to the source request, while the UI
   refreshes to the already-resolved or changed-context state if an operator
   submits stale activity.
   The main dashboard toolbar surfaces the open-review count on the versions
   control and opens version history in an open-review activity focus when
   unresolved review requests exist. The activity panel exposes aggregate
   open-review count, request ids, affected placements, and the active
   activity filter, with a clear-filter control back to the full activity log,
   and the focused dashboard grid marks the affected placement shells while
   activity placement/finding rows link to and select their corresponding
   widgets. That toolbar, activity-panel, and grid behavior is derived from a
   shared comparison-review focus contract: open requests, request ids,
   placement ids, request detail summaries, finding summaries, and resolution
   summaries are normalized once before UI surfaces render badges, hidden
   resolution context, widget focus attributes, or activity rows. That selected
   review placement is URL-backed with
   `panel=versions`, `activity_filter=open_comparison_reviews`, and
   `selected_placement`, so review handoffs can be shared or refreshed without
   losing the operator's place. The versions panel builds an explicit activity
   view model for this mode: normal activity renders as the full ordered event
   history, while open-review focus renders a review queue backed by unresolved
   request events and keeps the supporting lifecycle detail attached to each
   queue item. The queue model exposes explicit states for active open work,
   fully resolved/empty queues, and stale selected-placement context after a
   refresh, so stale submit outcomes render as queue state instead of only as
   generic empty activity. Comparison-review request and resolution lifecycle
   events are translated into row models before rendering, and those row models
   feed a dedicated activity presenter boundary. This keeps review-specific
   payload interpretation and hidden resolution form context out of both the
   generic lifecycle activity shell and the presenter template. Open request
   rows with affected point ids now expose a prepare-workflow action that opens
   the existing historical backfill/import request form prefilled from the
   review findings, preserving the same source identity, source-window,
   dashboard context, confirmation, and command path as direct dashboard
   workflow requests. Submitting that form records grouped
   `backfill_requested` lifecycle events with `request_mode=bulk_points`, so
   comparison-review intent has a first executable handoff into the durable
   historical workflow model. Those workflow requests and their later
   approval/start/retry/correction lifecycle events preserve a compact
   `comparison_review_origin` payload with source request event id, request
   kind, open count, placement ids, workflow kind/action/selection metadata, and
   the primary/compare data-view pair; the lifecycle inspector and group
   summary, started job panel, and recovery handoff panel expose that origin as
   typed rows, stable UI attributes, and route-preserving links back to the
   open-review activity focus and individual affected placements; the rendered
   browser recovery workflow now proves those compact origin fields remain
   visible after real worker completion/failure outcomes. Job and
   recovery panels also surface policy-derived next actions, retry/correction
   eligibility, policy reasons, previews, and available-when explanations
   directly beside the job or recovery evidence. Approved grouped review
   requests expose a start-orchestration panel that turns the `started` group
   action policy into an explicit operator plan: eligible item count, expected
   job fanout, review request id, review kind, open finding count, affected
   placements, policy reason, preview, state summary, and available-when text.
   Group status panels also render an ordered execution audit derived from
   lifecycle and job evidence: requested, approved, started, job progress,
   completed, failed, retried, corrected, correction progress, recovered
   failure count, and pending recovery tasks. This gives operators a compact
   audit trail for grouped jobs while keeping the raw rows available for
   inspection.
   Latest action outcomes expose normalized result handoffs for request, stage,
   retry, and correction actions: each target/result lifecycle event is rendered
   as a stable link back into the data-link inspector while preserving the
   current dashboard runtime query. This keeps outstanding review work visible
   and reachable without scanning the full event log, manually searching the
   grid, or correlating action policy against a separate panel. The browser
   smoke harness now verifies those handoff links and grouped execution-audit
   rows for retry and correction paths. Recovery handoff panels also expose an
   execution plan with next action, retry batch size, correction count,
   unresolved count, expected effect, blockers, retry command metadata, and a
   scoped recovery-plan command that advances corrected replacements through
   approval, start, and completion without advancing unrelated group items.
   Corrected replacement recovery also exposes a remaining-work summary with
   pending/completed counts, pending replacement runs, and next group actions,
   and the browser smoke harness verifies those values across approve, start,
   complete, and done transitions. LiveView coverage also proves mixed-stage
   replacement groups keep command targeting scoped to the tasks eligible for
   the selected transition while still rendering the full remaining-work set.
   Recovery plans now also publish closure readiness as a derived operator
   contract: unresolved failures, pending/completed replacements, active/blocked
   jobs, completion eligibility, status, and recommended action are rendered
   together so the group can be scanned as action-required, monitor-jobs, or
   ready-to-complete without cross-reading multiple audit rows. When readiness
   reaches ready-to-complete, the recovery panel publishes a scoped completion
   submit contract that uses the same auditable group-stage transition path as
   the primary group action grid. Browser smoke coverage now opens a seeded
   ready-to-complete recovery group, submits that closure form, verifies the
   latest-action result, and asserts the persisted completion event keeps the
   request group, ready run, and dashboard context intact.
   Group recovery plans also expose active failed item lifecycle event ids as
   direct data-link handoffs, so retry leaves only the remaining non-retryable
   failures linked to their failed-item inspector and correction form. The
   rendered browser smoke now proves that click-through from a different event
   in the same request group into the failed-item correction flow, and that the
   correction form submits explicit request group/mode/item metadata into the
   corrected lifecycle event instead of relying only on source-event inheritance.
   Group start outcomes also expose queued and failed job-dispatch counts in
   the latest-action panel, and retry-group outcomes expose retried,
   non-retryable, skipped, and retry-error disposition counts. Worker-generated
   historical workflow completion/failure events now preserve request-group,
   dashboard, and comparison-review context from their source workflow attrs, so
   grouped recovery panels can render real completed/failed job outcomes instead
   of relying only on seeded lifecycle rows. The browser smoke harness now follows
   a mixed review-origin group through a confirmed group retry for the retryable
   failure, preserved correction handoff for the non-retryable worker-generated
   failure, corrected request creation, and corrected replacement
   approval/start/completion, with browser assertions for the review-origin
   handoffs and persisted lifecycle assertions for the retry and replacement
   events. Focused product and presentation tests also cover larger grouped
   recovery contracts: multiple retryable failed jobs are retried in one group
   action with per-item retry metadata preserved, and multiple correction tasks
   are split by their next eligible group-stage action so approve/start batches
   remain distinct. The grouped recovery panel also matches corrected replacement
   runs back to their workflow job rows and exposes per-item follow-up state for
   queued/running, failed, and completed replacement jobs, including active job
   run ids and active job summaries. Queued and running replacement jobs now
   produce distinct follow-up actions, so the recovery panel can distinguish
   waiting for a queued job to start from monitoring an already running job.
   Grouped job-item evidence now preserves job start/completion timestamps, and
   long-running replacement jobs are surfaced as stale with stale run ids,
   summaries, an `inspect_stale_replacement_job` audit follow-up action, and a
   `requeue_stale_replacement_job` recovery action. Stale inspection remains an
   advisory telemetry backfill/import lifecycle event that references the exact
   replacement lifecycle event, corrected run, running job, job start time/age,
   and stale threshold while intentionally omitting a workflow `stage` payload
   so inspection does not advance recovery progress. Stale requeue records a
   separate authoritative lifecycle event, reuses the same replacement job id
   instead of creating a second job for the corrected run, clears running
   timestamps, and moves the job back to queued with structured requeue reason
   metadata. Stale inspection and requeue are now covered by rendered browser
   proof: the dashboard clicks the rendered recovery controls, verifies durable
   stale events and job state, and asserts latest-action
   dashboard-context/replacement-run handoff attributes.
   Failed corrected
   replacements can be retried through a replacement-run-scoped group retry
   command; the product API filters the retry candidate set by those replacement
   run ids before applying retry policy. The browser smoke harness now proves a
   failed corrected replacement job can be retried from that replacement-scoped
   command, with the clicked button, LiveView event payload, latest-action
   metadata, persisted retry event, and requeued job all agreeing on the corrected
   replacement run. It also proves stale corrected replacement requeue from the
   rendered panel, including clicked button payload, latest-action outcome,
   selected authoritative event, persisted lifecycle-event payload, and queued
   replacement job state. The LiveView command layer now treats retry,
   stale-job inspection, and stale-job requeue as an explicit job-recovery
   action contract with a shared handoff carrying action, job id, event id, and
   actor context before dispatching to the product APIs; the older action-specific
   wrappers remain thin aliases over that contract. Latest-action
   outcomes preserve retry scope, replacement run
   ids, and retry-error item details next to the retry disposition counts, so
   degraded replacement-batch retries remain attributable to the affected run,
   source failure event, job id, and retry error reason after the selected
   lifecycle event changes. Product-level data-management coverage now also
   proves degraded replacement-run-scoped retry batches preserve skipped running
   replacement attribution, including corrected run id, source event id, job
   id/status, and skip reason, while retrying the failed replacement in the same
   scoped request. Stale running replacement job evidence now also drives group
   closure readiness to `inspect_job_state` with an
   `inspect_stale_replacement_jobs` action, stale count, and stale run ids before
   generic pending replacement advancement is considered. Focused component
   coverage and the rendered browser stale-replacement workflow both prove stale
   closure evidence remains visible until the operator inspects or requeues the
   job. `HistoricalWorkflowReplacementRecovery` now derives replacement entries,
   counts, run-id lists, job summaries, closure-readiness status/action/summary,
   and group recovery next-action, guidance, expected-effect, retry-count,
   correction-count, blocker, group-retry action metadata,
   corrected-replacement advancement action, and group-completion action
   decisions as a typed projection outside the LiveView component, with direct
   tests covering pending, complete, stale, missing, failed, ready-to-close,
   retry, correction, replacement-advancement, group-completion, and
   blocked-inspection states.
   `HistoricalWorkflowJobRecoveryPresentation` now derives job-level
   next-action, guidance text, policy state, availability text, and normalized
   retry/correction action attributes plus retry-button and correction-form
   visibility/action metadata outside the LiveView components, with direct
   tests covering retry, correction, active-job monitoring, completed-job
   inspection, and fallback inspection states.
   `HistoricalWorkflowGroupStartPresentation` now derives group start
   orchestration presence, next-action, eligible/expected job counts, guidance,
   policy reason, preview, state, and availability metadata outside the group
   form component, with direct tests covering eligible, wait-for-eligibility,
   blocked-inspection, and absent-start states.
   `HistoricalWorkflowGroupStageHandoff` now carries group transition scope,
   correction-task text, and parsed replacement run ids for
   corrected-replacement advancement, so command execution uses a typed
   transition-target contract instead of re-parsing raw LiveView form params.
   `HistoricalWorkflowGroupRecoveryFormPresentation` now carries the executable
   submit-form contracts for corrected-replacement advancement and
   recovered-group completion, including dashboard context hidden fields,
   submit reasons, confirmation flags, replacement-correction scope, and
   correction-task payloads outside the status component.
   `HistoricalWorkflowGroupRecoveryPresentation` now derives recovery-panel
   visibility, unresolved count math, recovery item lists, handoff summary text,
   execution-audit rows, and audit summary text outside the status component.
   `HistoricalWorkflowStatusNavigationPresentation` now derives latest-action
   lifecycle handoff links, comparison-review origin links with placement
   deep-links, and failed-item recovery handoff parsing/link generation outside
   the status component. Latest-action result labels now count result handoffs
   independently from selected target/result events, so the first additional
   result remains `Result 1` even when the selected event is also a result.
   `HistoricalWorkflowActionExplanationComponents` now owns the
   unavailable-action explanation surface directly, and rendered workflow-status
   surfaces are split into focused modules instead of routing through a
   compatibility wrapper.
   `HistoricalWorkflowLatestActionComponents` now owns the latest-action
   summary, retry-disposition details, and result-handoff links, with the
   controls surface calling that focused surface directly. The shared DataLink
   action outcome metadata and hidden workflow-controls action outcome now carry
   the same retry scope, retry/non-retryable/skipped/error item lists, and
   queued/failed job counts as the visible latest-action card.
   `HistoricalWorkflowGroupStatusComponents` now owns the group-status and
   group recovery rendered surface, including review-origin links, failed-item
   handoffs, replacement work rows, closure readiness, and recovery form
   controls.
   `HistoricalWorkflowJobStatusComponents` now owns the workflow-job rendered
   surface, including job guidance policy metadata, review-origin links,
   diagnostic rows, and retry action controls. `HistoricalWorkflowControlComponents`
   now calls each focused rendered-status module directly.
   `DashboardRuntimeControlsComponents` now owns the toolbar runtime controls for
   live/archive/replay time, replay metadata, data realm/source binding, data
   view, compare view, limit mode fallback, and selected datum commands.
   `DashboardRuntimeContextPresentation` now owns context search result
   preparation, selected-scope labels, resource match grouping, and empty-state
   decisions, leaving `DashboardRuntimeContextComponents` as HEEx over a
   prepared context selector contract.
   Replacement tasks that should have workflow job evidence now surface
   missing job rows as explicit blocked follow-up work, and group closure
   readiness remains in inspect-job-state until that evidence gap is resolved.
   Focused component coverage also proves blocked replacement evidence takes
   precedence over active queued/running jobs, so mixed follow-up work does not
   collapse into a passive monitor state while an evidence gap remains. The
   rendered browser harness now proves that state with a
   corrected replacement that has lifecycle progress but no background job row:
   missing run/action metadata is visible, blocked counts drive closure
   readiness to `inspect_job_state`, and the completion submit is withheld.
   Closure readiness now also splits blocked replacement evidence into failed
   and missing job counts/run ids. Missing replacement evidence drives
   `inspect_missing_replacement_jobs`, failed replacement evidence drives
   `inspect_failed_replacement_jobs`, and failed replacement jobs promote to
   `retry_failed_replacement_jobs` when a scoped retry action is eligible. The
   rendered group recovery surface exposes those failed/missing counts and run
   ids as stable DOM metadata next to the blocked rollup, giving browser
   workflows and future orchestration a precise recovery branch instead of a
   generic `inspect_job_state` bucket.
   Missing replacement-job inspection is now an advisory audited workflow
   action instead of render-only evidence: the row-level control is scoped by
   request group and corrected run id, the product API emits
   `backfill_missing_replacement_inspected`/`import_missing_replacement_inspected`
   only while no replacement job exists, DataLink exposes the missing
   replacement payload, and the browser workflow clicks the control through to a
   normalized latest-action outcome. Focused operational-event and DataLink
   resolver tests now lock the canonical event kinds and inspection-panel rows,
   including the explicit missing workflow-job status. Mixed replacement-job
   recovery now exposes both the primary closure action and a stable ordered
   action queue, so a group with missing, failed, and stale replacement jobs can
   guide the next operator click without hiding the remaining blocked branches
   from browser workflows or future orchestration. Rendered LiveView proof now
   seeds real corrected replacement events plus missing, failed, and stale job
   states in one request group, then verifies the queue, per-branch counts/run
   ids, optional group retry metadata when retry is eligible, and row-level
   missing, failed-job inspection, stale-inspect, and stale-requeue controls.
   Remaining work is richer recovery orchestration around multi-job
   follow-up actions once grouped workflow jobs are running and failing in
   realistic operator scenarios.
6. **BYO TSDB is modeled before it is fully operational.** Ownership,
   isolation, credential references, policy validation, source health, and
   binding lifecycle facts exist. Actual customer-owned adapter execution,
   secret retrieval, connection testing, and noisy-neighbor isolation hardening
   remain future work.
7. **Operational events are still subsystem-local.** Dashboard lifecycle,
   source binding, source health, watermarks, limits, contacts, telemetry
   corrections, transport runtime facts, managed runtime replay facts, and
   replay facts exist in subsystem tables/projections. The common operational
   event spine now exists for selected families, but coverage is not yet broad
   enough to treat every dashboard timeline/read path as one unified event
   model. Event-source replay requests now carry replay identity to the relevant
   readers; operational-observable transport execution plus connection/RF state
   history plus transport-bitrate/RF-SNR/ingress-latency metric history now prove default
   canonical-event readers keep live and replay timelines isolated. Replay
   transport-execution timelines, replay connection-state timelines, replay RF
   state timelines, and replay RF-SNR/transport-bitrate metric history charts now
   have live browser proof through the default event-backed
   operational-observable readers, including chart-point DataLink inspection and
   selected-interval frame-evidence inspection for the replay RF-SNR and
   transport-bitrate history paths. Connection/RF and antenna-pointing
   state-history frames now also carry native interval/source-event evidence
   refs through the source boundary, and the replay RF state-timeline, live
   connection-state browser paths, plus live and replay antenna-pointing
   browser paths prove native interval refs render as clickable
   evidence/DataLink handoffs.
   Remaining work is broader runtime-derived metric/link views beyond the backed ingress, bitrate, and RF metric families.
8. **Governance and permissions are intentionally punted.** Dashboard actions
   should continue to leave `todo(authz)` markers where RBAC/approval policy
   will matter, but full dashboard governance should wait for the broader authz
   model.

Next maturity slices:

1. **Historical explanation workflow integration.** Build richer UI/job
   orchestration around the product-level backfill/import workflow-stage API,
   correction-authority decision API, and late-data policy decisions now
   connected to durable lifecycle/decision events. The dashboard now has a
   request creation surface with multi-point/bulk execution, lifecycle-inspector
   stage controls, retry/correction controls for failed runs, data-management
   view/revision badges, an initial revision-decision inspector action, an
   auditable late-data policy event action for lifecycle inspectors, and first
   handoff boundaries for request, stage, group-stage, correction-request, job
   retry, and group retry command execution. Stage, group-stage,
   retry/correction controls also expose first action-policy records whose
   eligibility and reason vocabulary come from telemetry data management, while
   the dashboard owns presentation copy around those decisions. Lifecycle
   explanation summaries likewise use product-owned semantic reasons for
   late-data policy events, retry/correction relationships, failure, completion,
   and default recorded states. Workflow and comparison-review bulk-decision
   submit feedback is derived from structured action outcomes rather than ad-hoc
   strings in event handlers. Comparison-review bulk-decision action cards expose
   source request id, workflow id, result event ids, target id, requested count,
   applied count, and failed count as stable metadata for operator handoff and
   tests.
   Request-creation and group-stage action outcomes now preserve request-group
   scope on accepted, blocked, and confirmation-required submissions, so the
   rendered latest-action panel stays aligned with the grouped lifecycle events
   and command boundary. The
   late-data policy command also dispatches on an explicit product execution
   mode, separating sample execution from auditable event-only recording instead
   of retrying a failed sample execution as an event-only write. Replay-context
   late-data handoff now preserves the replay clock and run id through the
   inspector/form boundary and constrains replay-context application to an
   audit-only event, with sample execution rejected server-side. Selected
   single-stage workflow submissions also enforce the product action-policy
   decision on the server, while the group transition engine rejects skip-ahead
   stage transitions using the same ordered lifecycle model as individual
   dashboard action policy. Single-job retry commands now bind the submitted job
   id to the selected lifecycle event's workflow run before retrying, and group
   retry commands reject zero-eligible groups with the same product policy reason
   instead of returning a successful no-op summary. Import failed-job recovery
   now follows the same contract as backfill recovery: individual and grouped
   retries preserve request-group metadata, source failure event ids, import
   workflow payloads, requeued job evidence, and `import_retried` lifecycle
   events through the shared dashboard handoff. Corrected import requests also
   follow the shared correction contract: non-retryable import failures can
   create `import_requested` replacement requests from the lifecycle inspector,
   and corrected import group approval/start preserves correction provenance
   while queuing import-shaped replacement jobs. Worker completion for those
   replacement jobs records `import_completed` with the copied sample count,
   job id/status, request-group metadata, correction source evidence, and
   dashboard context intact. Failed corrected replacement jobs record
   `import_failed` with the same correction/request/job/dashboard evidence and
   can be retried through replacement-run-scoped group retry, emitting
   `import_retried` without losing correction provenance; the lifecycle
   inspector renders completed corrected events with job status plus
   correction-source event/job evidence. The latest
   normalized action outcome is also retained in the dashboard session, exposed
   as lifecycle-inspector metadata, and composed by the workflow controls
   presenter into a visible latest-action status panel. Correction-required
   failures are now modeled as a
   mutually exclusive recovery path from retry: they are not counted as retryable
   group failures, direct retry APIs reject them, and dashboard policy explains
   that a corrected workflow request is required. Correction request creation
   now validates both the source failed event and the matching durable failed
   workflow job before recording a corrected request; a handcrafted failed event
   without failed job state is treated as an ineligible command. Accepted
   correction requests record inherited correction provenance, including source
   event type and group/item context, for inspector drilldown. The dashboard
   correction-request action outcome also preserves request-group scope on
   accepted, blocked, and confirmation-required submissions, so grouped recovery
   work keeps its operator feedback and handoff metadata aligned with the stored
   correction event. Group inspectors now show correction superseded separately from
   correction requested/started/completed so operators can tell pending
   correction work from a failed item superseded by a completed correction.
   Dashboard single-stage and group-stage correction actions now use the same
   correction-transition product boundary, preserving correction provenance and
   group-action provenance while rejecting invalid correction events, skip-ahead
   correction stage changes, and stale correction requests after another
   correction has completed the same failed source event.
   Remaining work is richer workflow execution/explanation orchestration,
   late-data automation/sample execution, approval/start/correction/retry policy
   semantics, dashboard wiring for bulk correction-authority decisions, and a
   clearer distinction between data-management operational controls and
   dashboard presentation.
2. **Generalized scope product surface.** Extend the generic runtime scope
   contract beyond the current visible selector and widget "pin current context"
   override into source adapters, chart/annotation semantics, mission aggregate
   scopes, and multi-entity comparison scopes for ground station, transport,
   link, and related operational resources. Runtime query hydration now accepts
   those operational-resource scope kinds behind the same explicit URL scope
   contract. The LiveView dependency path now wires that validation to
   mission-scoped setup/resource fetches, so product route hydration and runtime
   controls can reject stale ground-station, source-endpoint, transport, and
   link scopes before source execution; link scope validation accepts either a
   persisted link assignment or the link identity carried by setup-resource
   metadata.
3. **Widget maturity pass.** Add richer grid/table variants, additional
   operational-state timeline products beyond contact phase and connection
   state, richer event annotation lanes, and richer lifecycle composition using
   the existing Frame contract.
4. **Data-management view comparison and revision badges.** Extend the current
   primary/compare runtime workflow, persisted investigation preset UI, and
   visible widget/sample discrepancy drilldowns into bulk correction-authority
   handoffs. A first transient comparison-finding inspector handoff exists for
   one discrepancy at a time, and telemetry data-management now has a
   multi-identity correction-authority API for applying selected decisions with
   shared workflow evidence. Comparison-review bulk decisions now retain a
   structured dashboard activity action outcome, so partial failures preserve
   requested/applied/failed counts, workflow/request ids, decision reason, and
   degraded status in visible operator-facing activity details and DOM metadata;
   the real LiveView and browser bulk-decision paths now prove the successful
   outcome after open-review queue submission, and the real LiveView product path
   now proves the degraded partial-failure outcome when one selected identity is
   missing. The remaining product work is turning
   comparison context packages into selectable dashboard workflows that call that
   API.
   Continue enriching source warnings/provenance and frame badges that explain
   corrected, late, partial, replay, and simulation states.
5. **Operational observable backing adapters.** The v0 semantic registry now
   defines first-party subsystem metrics such as transport bit rate, RF lock
   state, frame sync state, RF SNR, RF Eb/N0, RF Doppler, connection state,
   antenna pointing state, contact phase, command queue depth, and ingest latency; it also marks
   which ids are currently backed. `contacts.phase` can resolve as a latest
   matrix from contact projections and can be selected as a status-matrix
   operational-observable binding in the dashboard editor. Transport and
   ground-station connection state can resolve from configured transport/source
   endpoint resources and canonical operational-observable state events or
   optional runtime snapshots, with unknown state kept explicit. Operational
   state timelines can bind contact phase plus
   transport/ground-station connection state and ground-station antenna
   pointing state together and resolve them as separate product frames for
   lane-grouped rendering. `ground.station.antenna_pointing_state` resolves from
   configured ground-station/source-endpoint resources and generic
   operational-observable state events as latest and timestamped state-history
   rows, with acquisition/pointing state coloring and native interval evidence.
   `link.rf_lock_state` and
   `link.frame_sync_state` resolve from configured transport/link resources and
   typed canonical operational-observable state events or optional RF snapshots
   as both latest rows and timestamped state-history rows, with replay source
   context preserved through the default event-backed reader, native link RF
   interval projection, and snapshot override contract.
   `link.snr_db`, `link.eb_n0_db`, `link.symbol_rate_sps`, and
   `link.doppler_hz` resolve from
   configured transport/link resources and canonical operational-observable
   metric sample events or optional RF metric snapshots as latest link-scoped
   metric rows and raw-series metric history wide Frames with RF-appropriate
   units. `comms.transport.downlink_bitrate` and
   `comms.transport.uplink_bitrate` can resolve from configured transports and
   canonical metric sample events or optional metric snapshots as latest rows
   and raw-series history wide Frames, with directional series kept distinct.
   The operational-observables source advertises these metric-history families
   as first-class capability metadata, binding RF SNR/EbN0/symbol rate/Doppler,
   directional transport bitrate, and ingress processing latency to their source
   products and product families while allowing mixed requests to plan through
   the generic operational metric-history capability.
   The saved-dashboard golden contract now includes uplink bitrate and RF Eb/N0
   value-tile fixtures that prove the engine, DataLinks, selected-ref payload,
   and point presenter data preserve those operational metrics. The rendered browser
   harness now also proves canonical operational metric events preserve
   directional downlink/uplink fields plus RF Eb/N0, symbol-rate, and Doppler aliases
   through the write/read path into side-by-side transport bitrate and
   link-scoped RF metric value tiles, including Doppler,
   with transport/source context, into replay raw-series RF Eb/N0 charts that
   exclude live/off-link/other-replay samples, and into replay raw-series
   transport-bitrate charts where downlink and uplink remain separate
   selected-run series with chart-point DataLinks preserving selected
   placement/time and replay source context. Replay
   transport-bitrate chart coverage now also proves degraded
   operational-observable source health is surfaced as a warning source badge
   without suppressing directional history data or chart-point inspection, and
   that source-health transition plus source-watermark event overlays are
   serialized into the chart marker contract and rendered as clickable markers
   on operational metric-history charts. Those markers open durable
   source-health/source-watermark DataLink inspectors with selected placement,
   selected time, replay run, data-source, source-binding, and copy-link
   context intact.
   Latest connection/RF/antenna state frames now preserve selected interval ids,
   source event ids, operational-event DataLinks, and interval evidence refs
   when the current row comes from a canonical operational interval, so
   row-widget frame evidence can explain the event that produced the current
   state instead of only the resource that currently owns it. Rendered
   status-matrix and data-table coverage proves source-endpoint and link-scoped
   connection rows, plus link-scoped RF lock/frame-sync rows, can open those
   frame evidence refs, preserve dashboard query context, expose the rendered
   link DataLink alongside related transport/source-endpoint/ground-station
   resource links in status-matrix rows, and hand off to the native canonical
   interval DataLink.
   Multi-transport browser coverage also proves non-primary
   latest connection data-table rows preserve their row resource identity while
   keeping the full multi-resource query scope, selected-scope copy payloads,
   resolved resource DataLinks, and canonical interval/source-event evidence
   handoffs intact. Replay connection-state browser coverage proves the same
   latest data-table row path preserves replay run, replay dataset/source
   binding, non-primary row identity, resolved resource DataLinks, and canonical
   replay interval/source-event evidence. Replay RF-state browser coverage also
   proves data-table RF lock/frame-sync rows preserve replay run, replay
   dataset/source binding, row identity, and canonical replay interval/source
   event evidence. Multi-link RF browser coverage proves non-primary RF
   data-table rows preserve link row identity, resolved transport DataLinks,
   full `scope_ids` query context, selected-scope copy payloads, and canonical
   RF-lock interval/source-event evidence. The rendered antenna-pointing
   browser paths prove live and replay ground-station scoped state timelines can
   open source-endpoint/ground-station DataLinks plus generic
   operational-observable interval evidence specialized to an antenna-pointing
   DataLink target while preserving replay source binding, dataset, and run
   context.
   `comms.transport.execution_state`
   resolves from operational-event-backed transport execution intervals as
   state-timeline event history with explicit interval end times, normalized
   execution states, transport/contact/source-endpoint/ground-station/link
   resource-scope filtering, multi-link browser proof with non-primary
   transport-execution rows, resolved transport DataLinks, full `scope_ids`
   query context, selected-scope copy payloads, frame evidence, and valid
   link-scoped no-data lifecycle/source metadata without invented lanes, rows,
   or row DataLinks, plus source-unavailable lifecycle/source-badge proof when
   the operational source cannot answer, and degraded source-health proof where
   live and replay rows continue rendering while the widget source status and
   source badge warn and row source-health badges open the backing source-health
   event with replay run/source binding context preserved,
   default-reader replay-scoped canonical-event filtering, and
   transport-execution evidence refs; `commanding.queue_depth` can resolve from
   pending command queue entries at mission or source-endpoint scope; and
   `ingress.processing_latency_ms` can resolve from canonical operational-observable metric sample events keyed by mission/source endpoint as both latest rows and raw-series history wide Frames, with runtime-health ingress profiler samples overlaid for live reads and preserving promoted transport, source-endpoint, ground-station, and link context when profiler metadata provides it. Latest contact,
   connection, antenna-pointing, transport-metric, command-queue, and ingress rows now evaluate
   their observation time against dashboard freshness policy and propagate
   `freshness_state`, `age_ms`, `freshness_policy`, `freshness_checked_at`, and
   stale/unknown warning codes to frames and flattened widget rows. Value tiles
   accept one backed operational metric, time-series charts accept backed
   metric operational raw-series bindings, and status matrices/data tables
   accept mixed backed latest operational observables through declared
   widget-frame source overrides.
   Unsupported
   widget/source pairings now fail closed with an
   `unsupported_widget_frame_contract` warning, and missing metric snapshots
   remain `nil`/no-data instead of being presented as zero throughput.
   Status-matrix rows now carry contact-specific source, phase, kind, and link
   semantics, connection-specific resource, adapter, scope, link, and state
   semantics, generic operational-state resource/scope/state semantics,
   metric-specific value/unit/observed-time/link semantics, and row-level
   freshness semantics for latest operational frames. Mixed latest rows also
   carry the frame observable id, product family, supported source capability,
   source request, realm, data source, source binding, and dataset. Connection,
   generic state, and metric Frames now emit resource DataLinks for transport,
   source-endpoint, and ground-station identities, and both latest-row widgets
   and operational state timelines attach only the resource links relevant to
   each flattened row. The inspector resolves persisted transport, source-endpoint,
   and ground-station setup records; mission comms setup now exposes
   ground-station create, edit, show, list, and archive flows for those
   identities. Metadata-only ground-station context remains available as a
   fallback when no setup record exists. The source-backed observable contract is
   now exposed by the adapter capabilities and covered by registry/source/widget
   scope invariants, so adding a future operational observable requires updating
   semantic definition, backing support, widget support, and scope support
   together. Adapter capabilities also expose source-backed contracts that bind
   observable groups to sampling modes, source products, product families, and
   frame shapes; the source advertises every concrete product it can emit,
   including latest, state-history, aggregate state-history, and raw-series
   metric families. Publish validation, runtime capability posture, and
   source-remediation candidate matching now consume the same contracts, so an
   operator sees concrete source-product requirements for latest, state-history,
   aggregate, and raw-series capability mismatches instead of metric-history-only
   guidance. The next slice is to add backing projections/streams for future
   observable families and extend similarly rich widget-specific presentation
   semantics as they become backed.
6. **Source adapter hardening.** Turn the BYO/managed TSDB model into an
   operational adapter contract: production secret-manager backing for the
   credential-material resolver, additional adapter-specific BYO connection
   implementations, richer policy UI, health-transition operations, failure
   isolation, and adapter-reported capability discovery for BYO/customer-specific
   backends beyond the managed QuestDB schema probe.

Implementation stance: the current code is useful product evidence and the
active implementation path, but it remains subordinate to this target model.
Where the current implementation and this document diverge, prefer the model
that makes dashboard history, source identity, replay context, and operator
explainability more deterministic.

## 16. Open questions (to ratify)

1. **Clock capability and UX depth** — bounded telemetry can execute
   onboard/source (`generation_time`/`observed_at`) and ground (`receipt_time`)
   axes, and the dashboard runtime exposes the mode-specific operator switch
   (§8). Remaining work is adapter capability surfacing, source-specific
   fallback UX, and richer explanations when a selected axis cannot be served
   natively.
2. **Scope context promotion** — confirm promoting scope from per-widget
   spacecraft binding to a dashboard-level operational scope context with
   per-widget override (§4). *Working assumption: yes.*
3. **Decimation envelope shape** — min/max band + mean as the canonical reduced
   series; how limit-state, definition boundaries, and quality aggregate at
   bucket boundaries.
4. **Live sync** — optimistic locking exists for v0 persistence; decide later
   whether mission-shared dashboard edits also broadcast over
   PubSub (§14).
5. **Data source and backend capability surface** — the exact source registry
   fields, binding policy fields, capability flags an adapter advertises, and
   the in-engine fallback contract.
6. **Widget grammar scope & sequencing (§10)** — the exact mark/helper-function
   vocabulary and serialization format; and whether to build the interpreter up
   front or *extract* the grammar after shipping a few code-tier widgets (so the
   grammar reflects real commonality rather than a guess).
7. **Widget distribution & governance (§10.9)** — org-private widget types vs. a
   shared catalog/marketplace; trust levels and signing for non-first-party
   widgets.
8. **Reuse axis priority (§11.1)** — dashboard-templating-first vs.
   library-widgets-first vs. both. The data model is the same either way (the
   placement `content` union reserves the library seam), so this decides *build
   sequencing*, not schema. Resolve from design-partner workflows: do operators
   reuse panels across dashboards, or dashboards across spacecraft?
9. **Operational observable registry and source (§3.2.1, §5.3.4)** —
   ownership, lifecycle, and governance for subsystem-registered observables;
   naming conventions; whether observables are versioned globally, per mission,
   or per subsystem release.
10. **Operational observable storage (§5.7)** — per-subsystem choice of stream,
   projection table, TSDB materialization, or adapter-backed external source.
   The semantic model is catalog-bound observables; the physical storage path is
   deliberately not uniform.
11. **Realm and source-binding policy (§5.4)** — canonical realm names, whether
   realms are mission-local or org-global, who may bind BYO data sources, how
   binding windows are audited, and when federated stitching is allowed.
12. **Limit activation model (§8.2)** — whether active limit definitions are
   mission-wide, scope-conditioned, mode-conditioned, or realm-specific; whether
   activation intervals are projected from canonical operational events or a
   narrower limit-specific event table first.
13. **Limit recomputation policy (§8.2)** — when dashboards may recompute
   historical values under current/proposed definitions, how those recomputed
   results are labeled, cached, audited, and compared with observed limit
   events.
14. **Runtime performance thresholds (§5.1.2)** — exact timeout values,
   dashboard/session concurrency caps, source-specific TTL defaults, and when to
   graduate from conservative live ticks to pushed stream subscriptions.

## 17. Prior art

- **OpenC3 COSMOS** (local clone at `../cosmos`): `streaming_api.rb`,
  `logged_streaming_thread.rb` (live/historical handoff); `questdb_client.rb`
  (`SAMPLE BY` min/max/avg/stddev reduction); `migrations/2026…remove_decom_reducer.rb`
  (precompute reducer removed in favor of query-time aggregation); screen widget
  set (`openc3-vue-common/src/widgets`).
- **Grafana** — [data frames](https://grafana.com/developers/plugin-tools/key-concepts/data-frames)
  (Field/FieldConfig, wide vs long); maxDataPoints/`$__interval` pixel-width
  decimation; repeat-by-variable; shared crosshair; annotations; Explore.
- **Downsampling** — [MinMaxLTTB](https://arxiv.org/pdf/2305.00332) (extrema
  preservation; two-stage MinMax→LTTB); LTTB; M4.

## 18. Cadence modules referenced

`Cadence.Dashboards.{Engine,Document,ObservableRegistry,WidgetRegistry,Frame,TimeContext,ScopeContext,DataContext,LimitContext}` ·
`Cadence.Dashboards.Sources.{Telemetry,Limits,Events,OperationalObservables}` ·
`Cadence.Telemetry.{Sample,CurrentValueStore,HistoryStore}` ·
`Cadence.Reads.{Telemetry,Limits}` ·
`Cadence.Limits.Event` (+ `telemetry_limit_events`, `telemetry_latest_limit_states`) ·
`Cadence.DerivedTelemetry` · `Cadence.Contacts.{ScheduledContact,RealizedContact}` ·
`Cadence.MissionEvents` · `Cadence.Spacecraft` / `Cadence.SpacecraftType` ·
`CadenceWeb.OpsDashboard*Live`.
