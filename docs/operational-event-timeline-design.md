---
title: Operational Event Timeline — Design
tags: [design, events, timeline, audit, catalog, dashboards, replay, operations]
status: draft
created: 2026-06-15
updated: 2026-06-29
---

# Operational Event Timeline — Design

> Status: **draft / proposed.** This document captures the event and timeline
> architecture that dashboards, catalog versioning, replay, audit, commanding,
> and mission operations all depend on. It is not a mandate to rewrite every
> existing event-like table immediately. Existing records such as
> `mission_events`, `contact_actions`, `telemetry_limit_events`,
> `mission_binding_set_activations`, `comms_routing_rule_events`, managed
> action/timer records, and application binding applied stamps are useful
> evidence. The open design question is which records become canonical
> operational events, which remain subsystem facts projected into timelines, and
> which are current-state projections only.

## 1. Purpose

Define a mission-scoped operational event model that can answer:

- what happened
- when it happened
- who or what caused it
- what runtime/catalog/source meaning was active
- which operational entity it affected
- how to reconstruct effective intervals for dashboards, replay, audit, and
  historical analysis

The immediate pressure comes from dashboard historical correctness: a chart
must know which catalog revision, runtime binding, source binding, limit
definition, data realm, contact, and transport/link state were active when data
was observed. That should not be invented as dashboard-only state.

## 2. Problem

Cadence already has several event-like concepts:

- `mission_events` — rebuildable mission timeline projection over selected
  canonical records.
- `contact_actions` — user/system actions against contacts.
- `telemetry_limit_events` — limit evaluation events.
- `mission_binding_set_activations` + `mission_active_binding_sets` — immutable
  activation history plus current active binding set.
- `comms_routing_rule_events` — append-only event family for routing-rule state
  changes.
- `dashboard_data_bindings` + `dashboard_data_binding_events` —
  dashboard-owned current source-binding projection plus registration/change/
  enable/disable/supersession lifecycle events.
- `dashboard_source_health_events` + `dashboard_source_health_statuses` —
  dashboard-owned source health transitions plus latest source health
  projection.
- `dashboard_source_credential_references` +
  `dashboard_source_credential_events` — dashboard-owned non-secret credential
  reference registry plus registration/rotation/enable/disable lifecycle
  events.
- managed action/timer requests and transport/action records — runtime activity.
- application binding `applied_at` stamps — current applied runtime state for an
  application such as Telemetry Decom.

These are valuable, but they are not yet one coherent operational event
architecture. Some are canonical facts, some are projections, some are current
state, and some are event-shaped but local to one subsystem.

Dashboards expose the gap because historical visualization needs to reconstruct
the **operational context at time T**, not only plot samples:

```text
sample S was observed
  under catalog revision R
  through telemetry-decom binding B
  during contact C
  via source binding DS
  while limit definition L was active
  in data realm flight/rehearsal/replay
```

## 3. Strategic Thesis

Cadence needs an **operational event spine**: an append-only, mission-scoped set
of facts from which timeline projections, effective-interval projections,
audits, dashboard overlays, and replay comparisons can be derived.

The mission timeline that operators see is a **projection**, not the source of
truth. Different consumers need different projections:

- dashboards need overlays and effective intervals
- audit needs causality and actor/approval trails
- replay needs deterministic comparison of expected vs observed events
- setup pages need current-state projections
- APIs need cursorable event feeds

The event spine should support all of those without forcing every subsystem to
throw away useful local records.

Dashboard mission-timeline frames should preserve that separation in their
evidence contract: a row projected from the canonical spine carries both the
projected `mission_event` evidence and a direct `operational_event` evidence
reference to the canonical fact that produced it. The canonical operational
event is also a first-class dashboard DataLink target, so operators can inspect
the durable source envelope directly from a projected mission-timeline row
instead of treating the projection row as the audit source.
Mission timeline projections for canonical runtime events should also preserve
scope fields such as `spacecraft_id` and `source_endpoint_ref`; otherwise
scoped dashboard event overlays can silently drop canonical facts that are
valid for the current operational context.

## 4. Event Taxonomy

Events should be classified by role, not only by table.

### 4.1 Canonical Operational Events

Append-only facts Cadence treats as historical truth. These should be directly
auditable and durable.

Examples:

- catalog revision applied to a runtime path
- binding set activated
- data source binding changed
- limit definition activated/superseded
- contact scheduled/canceled/started/ended
- command requested/approved/released/verified
- source degraded/recovered
- dashboard published

### 4.2 Subsystem Facts

Domain-owned records that are authoritative inside a subsystem and can project
into the operational timeline.

Examples today:

- `telemetry_limit_events`
- `contact_actions`
- managed action requests
- combined downlink records
- downlink diagnostics
- routing rule events
- dashboard source-health events

Some subsystem facts may later adopt the canonical event envelope directly; some
may remain local records with projection functions.

### 4.3 Current-State Projections

Mutable or upserted rows optimized for runtime reads. They are not the audit
trail.

Examples:

- active binding set row
- latest limit state row
- current value table
- application binding current config/applied stamp
- dashboard data-source binding current projection
- dashboard source-health status rows

Current-state projections must be derivable from canonical events or paired
with canonical events that explain changes.

### 4.4 Timeline Projections

Read models optimized for operator display and filtering.

`mission_events` already fits here: it is a rebuildable timeline projection over
selected canonical records. It should remain projection-shaped unless/until a
separate canonical event store makes parts of it redundant.

## 5. Event Envelope

The canonical event envelope should be broad enough to cover operator actions,
system observations, runtime activations, and derived transitions without
collapsing subsystem payloads into one rigid schema.

```elixir
%OperationalEvent{
  event_id: "op_event_...",
  organization_id: "...",
  mission_id: "...",

  occurred_at: DateTime.t(),
  recorded_at: DateTime.t(),
  effective_at: DateTime.t() | nil,

  category:
    :catalog | :runtime | :contact | :telemetry | :limits | :commanding |
    :comms | :data_source | :dashboard | :replay | :security,
  kind: :catalog_revision_applied,
  severity: :info | :warning | :error | :critical | nil,

  actor: %{
    kind: :user | :service | :system | :replay,
    id: "...",
    display_name: "...",
    auth_context: %{...}
  },

  subject: %{
    kind: :spacecraft | :contact | :ground_station | :transport | :link |
      :catalog_revision | :binding_set | :data_source | :dashboard |
      :telemetry_point | :command,
    id: "..."
  },

  scope: %{
    spacecraft_id: "...",
    contact_id: "...",
    source_endpoint_ref: "...",
    data_realm: :flight,
    data_source_id: "ds_..."
  },

  causality: %{
    correlation_id: "...",
    causation_event_id: "...",
    source_record_kind: :application_binding,
    source_record_id: "..."
  },

  payload: %{...},
  previous: %{...},
  current: %{...},
  metadata: %{...}
}
```

Required concepts:

- **occurred_at** — when the thing happened in mission/operation time.
- **recorded_at** — when Cadence recorded the event.
- **effective_at** — when a configuration becomes operational, if different
  from `occurred_at`.
- **actor** — user, service, system, or replay origin.
- **subject** — the main thing affected.
- **scope** — queryable denormalized context for dashboards and APIs.
- **causality** — links operator intent, subsystem records, jobs, replay runs,
  and projections.
- **payload** — event-specific data.
- **previous/current** — optional compact state diff for configuration events.

## 6. Current Implementation Status

Cadence now has the first durable operational-event spine slice:

- `operational_events` stores the canonical envelope with denormalized query
  columns for mission scope, category, kind, subject, causality, source record,
  replay, and time.
- `Cadence.OperationalEvents.Event` defines the first envelope contract and can
  convert binding-set activations into `:binding_set_activated` and dashboard
  lifecycle rows into dashboard operational-event kinds such as
  `:dashboard_published`.
- `Cadence.OperationalEvents` persists and reads operational events.
- `Cadence.Activations.activate_binding_set/5` persists the operational event
  in the same transaction that records activation/current state and then
  projects the operator-facing `mission_events` row.
- `Cadence.Projections.MissionEvents.rebuild/1` reads persisted operational
  events for runtime activation timeline entries instead of reconstructing them
  directly from `mission_binding_set_activations`.
- Catalog revision creation persists canonical `:catalog` operational events
  from the same insert boundary that writes `catalog_revisions`, giving each
  imported revision a queryable operational-event source record.
- Dashboard lifecycle mutations persist canonical operational events from the
  same lifecycle insert boundary that writes `dashboard_lifecycle_events`,
  giving publish/archive/restore/revert/review/health/readiness actions a
  queryable operational-event source record.
- Dashboard source-health and source-watermark transitions persist canonical
  `:data_source` operational events from the same transaction that writes the
  append-only transition row and latest-status projection, giving degraded/
  recovered/unavailable source states and watermark movement a queryable
  operational-event source record.
- Dashboard source capability posture decisions can be derived from
  `Cadence.Dashboards.SourceExecutionSemantics` and persisted as canonical
  `:data_source` operational events with source record kind
  `:source_capability_posture`. These events capture native/fallback/unsupported
  source capability status, selected data source/binding, dashboard/resolve/source
  request context, requested/executed time axes, supported axes, sampling,
  fallback details, and source-execution status so clock fallback and unsupported
  capability decisions are auditable outside the current dashboard render.
- Mission-scoped dashboard source-binding lifecycle events persist canonical
  `:data_source` operational events from the same transaction that writes
  `dashboard_data_binding_events`, giving source-binding registration/change/
  enable/disable/supersession a queryable operational-event source record.
- Limit definition lifecycle changes persist canonical `:limits` operational
  events from the same transaction that writes
  `limit_definition_lifecycle_events` and the active-definition projection,
  giving registered/activated/superseded definitions a queryable
  operational-event source record.
- Telemetry backfill/import lifecycle events and observation identity decision
  events persist canonical `:telemetry` operational events from the same
  transaction that writes their subsystem event rows, giving backfill/import/
  late-data transitions, stale replacement-job inspections and requeues, and
  correction/conflict decisions a queryable operational-event source record.
- Scheduled and realized contact persistence now refreshes canonical `:contact`
  interval operational events from the same row write or lifecycle update
  boundary, giving dashboards a canonical contact interval fact with source
  record identity, source endpoint refs, interval bounds, and current lifecycle
  state.
- `Cadence.Reads.Limits.definition_intervals/3` and `/4` derive dashboard-facing
  limit-definition intervals from canonical `:limit_definition_*` operational
  events while preserving the existing `Cadence.Limits.DefinitionInterval`
  contract and evidence refs.
- `Cadence.OperationalEvents.EffectiveInterval` defines the first generic
  interval read model, and `Cadence.OperationalEvents.binding_set_intervals/2`
  projects mission binding-set activation intervals from canonical events.
  `Cadence.OperationalEvents.application_binding_intervals/2` derives
  per-rule application/source-endpoint runtime intervals from those binding-set
  activation intervals and persisted governed binding sets.
  `Cadence.OperationalEvents.catalog_revision_intervals/2` projects
  catalog-database revision intervals from canonical `:catalog_revision_*`
  events.
  `Cadence.OperationalEvents.source_binding_intervals/2` projects source-binding
  lifecycle intervals from canonical `:source_binding_*` events.

This is intentionally narrow. The canonical store exists, but most event
families listed below still use subsystem-local tables or have not yet been
projected into dashboard/timeline reads. Binding-set intervals exist, but
catalog/application/source/limit interval projections are still planned.

## 7. Effective Intervals

Dashboards and replay do not only need point-in-time events. They need effective
intervals:

```text
from T1 until T2, catalog revision R interpreted spacecraft SC-001 telemetry
from T3 until T4, source binding DS-7 backed the flight telemetry source
from T5 until T6, contact C-123 was active
from T7 until T8, ground station DSS-14 connection state was degraded
from T9 until T10, limit definition L3 classified HK.battery_voltage
```

Effective intervals should be **projections** from append-only events, not
manually maintained dashboard state.

Candidate projections:

```elixir
%EffectiveInterval{
  interval_id: "effective_interval_...",
  organization_id: "...",
  mission_id: "...",
  kind: :catalog_revision | :binding_set | :source_binding | :limit_definition |
    :contact | :transport_state | :connection_state,
  subject_kind: :spacecraft,
  subject_id: "sc_001",
  starts_at: DateTime.t(),
  ends_at: DateTime.t() | nil,
  source_event_id: "op_event_...",
  superseded_by_event_id: "op_event_..." | nil,
  payload: %{...}
}
```

Projection rules:

- a new activation starts an interval
- the next activation for the same subject/scope closes the prior interval
- explicit disabled/superseded events close intervals
- open-ended intervals represent current active state
- replay/simulation realms have independent intervals from flight

## 8. Runtime Activation Events

Runtime activation is the first design driver because catalog versioning and
dashboard historical correctness depend on it.

Events to model:

- `catalog_revision_selected` — operator/config selected a revision for an app
  or spacecraft.
- `runtime_binding_compiled` — canonical catalog snapshot compiled into runtime
  artifacts.
- `binding_set_activated` — mission binding set basis activated.
- `application_binding_applied` — application-specific config applied, including
  spacecraft/app/source endpoint/revision context.
- `runtime_binding_superseded` — a new binding replaces an old one for a scope.
- `runtime_binding_disabled` — binding removed from active use.

Current state:

- `mission_binding_set_activations` is already immutable activation history.
- `mission_active_binding_sets` is the current-state projection.
- Telemetry Decom application bindings carry `catalog_revision_id`,
  `applied_binding_set_id`, `applied_binding_set_version`, and `applied_at`, but
  not a full event history for every applied/superseded interval.

Design pressure:

Telemetry samples and dashboard frames should be able to point to the semantic
context that interpreted them:

```text
catalog_revision_id
telemetry_snapshot_id
binding_set_id
binding_set_version
activation_id
application_binding_id
source_endpoint_id
```

If the current sample records cannot carry all of that yet, the event/interval
model should make it derivable by `(mission_id, spacecraft/source_endpoint,
receipt_time/generation_time, data_realm)`.

## 9. Limit Definition Events

Limit definitions can change without changing historical samples. The event
model must therefore capture **which limit definition was operationally active**
for a point/scope/realm at time T.

A versioned limit definition row answers "what threshold set exists?" It does
not answer "when did operators fly with it?" Dashboards, audit, and replay need
that second answer.

### 9.1 Canonical limit lifecycle events

Limit lifecycle and activation changes should be canonical operational events:

- `limit_definition_created` — definition imported or authored.
- `limit_definition_approved` — definition authorized for use, if approval is
  required.
- `limit_definition_activated` — definition becomes operational for a
  point/scope/realm.
- `limit_definition_superseded` — a newer or different definition replaces it.
- `limit_definition_disabled` — definition no longer applies and no replacement
  is active.
- `limit_definition_reverted` — operators intentionally return to an earlier
  definition/version.

The critical event is activation. It must include enough scope to project an
effective interval:

```elixir
%OperationalEvent{
  category: :limits,
  kind: :limit_definition_activated,
  subject: %{kind: :telemetry_point, id: "HK.battery_voltage"},
  scope: %{
    spacecraft_id: "sc_001",
    data_realm: :flight,
    limit_set_name: "ops"
  },
  occurred_at: ~U[2026-06-15 18:00:00Z],
  recorded_at: ~U[2026-06-15 18:00:02Z],
  effective_at: ~U[2026-06-15 18:00:00Z],
  previous: %{
    limit_definition_id: "battery_voltage_limits",
    version: 2
  },
  current: %{
    limit_definition_id: "battery_voltage_limits",
    version: 3,
    thresholds: %{
      "yellow_low" => 24.0,
      "red_low" => 23.5
    }
  }
}
```

From these events, Cadence projects limit-definition intervals:

```text
T1..T2 -> battery_voltage_limits v2
T2..nil -> battery_voltage_limits v3
```

The interval payload should include `limit_definition_id`, `version`,
`limit_set_name`, threshold metadata, the activation event id, and any
scope/mode/realm qualifiers used to resolve the definition.

### 8.2 Limit evaluation facts

Per-sample evaluations are different from lifecycle events.
`telemetry_limit_events` already captures the right kind of subsystem fact:

```text
sample S was evaluated
  using limit definition L version V
  with evaluated value X
  producing state red/yellow/green
```

These facts can be high volume, so they should not automatically become
canonical operational events in the global spine. Treat them as limit subsystem
facts with strong provenance:

- `limit_event_id`
- `sample_id`
- `source_sample_type`
- `limit_definition_id`
- `limit_definition_version`
- `limit_set_name`
- `evaluated_value`
- `limit_state`
- `normalized_state`
- `generation_time`
- `receipt_time`

Then project only operator-meaningful summaries into timeline read models:

- violation started
- violation cleared
- state changed severity
- sustained violation exceeded duration
- limit evaluation stale/incomplete
- backfilled sample changed historical limit state

This keeps the event spine from becoming a telemetry fact table while still
making important limit transitions visible in `mission_events`, dashboard
overlays, and audit feeds.

### 8.3 Observed versus recomputed limits

Dashboards need two answers:

- **Observed** — classify historical values using the limit definition active
  when the sample was evaluated/observed.
- **Recomputed/current** — classify historical values under a current or
  proposed definition.

Observed limit events are operational truth and should not be overwritten by
recomputation. Recomputed results should be separate derived facts or temporary
analysis frames, labeled with the definition used and the recomputation run or
request that produced them.

### 8.4 Time-axis decision

Late-arriving data makes limit activation resolution nontrivial. Cadence needs
an explicit policy for which clock selects the active limit definition:

- `generation_time` — source/onboard time.
- `receipt_time` — when Cadence received the sample.
- evaluation time — when the limit evaluator ran.

For console/audit truth, the default should likely be the **evaluation/receipt
context**: what did Cadence know and apply operationally when it evaluated the
sample? Generation-time analysis should remain available explicitly, especially
for replay, backfill, and scientific review.

Whatever policy is chosen must be written onto the limit evaluation provenance
and reflected in dashboard warnings.

## 10. Dashboard Dependencies

Dashboards should consume event-derived projections in three ways:

1. **Overlays** — contacts, commands, source degradation, catalog changes,
   runtime activations, limit transitions.
2. **Frame semantic context** — field/frame metadata that says which catalog,
   source, realm, runtime binding, and effective interval evidence produced
   the values.
3. **Warnings** — mixed catalog revisions, unknown activation, source degraded,
   replay/simulation data, late-arriving samples, data beyond retention.

Dashboard defaults:

- Historical telemetry uses **observed semantics**: the catalog/runtime meaning
  active when the sample was produced.
- Recomputed/current semantics must be opt-in and labeled.
- Multi-realm comparison must return separate frames and labels, not silently
  merged values.

### 10.1 Dashboard lifecycle events

Dashboard documents are mission-shared operational artifacts. Their immutable
version rows restore content, but publish/revert/archive actions still need
auditable operational events.

Canonical dashboard lifecycle events:

- `dashboard_created` — dashboard row and initial version created.
- `dashboard_draft_saved` — durable draft version saved.
- `dashboard_published` — version promoted to operator-facing default.
- `dashboard_publish_readiness_checked` — operator rechecked publish readiness
  against current mission source/catalog/runtime configuration before or after
  remediation.
- `dashboard_reverted` — older version copied into a new draft or published
  version.
- `dashboard_archived` — dashboard removed from active lists.
- `dashboard_restored` — archived dashboard returned to active lists.
- `dashboard_deleted` — administrative delete or retention action.
- `dashboard_document_migrated` — persisted JSON schema migrated.

The critical event for operations is publish. It should include enough state to
answer "what did operators see by default at this time?":

```elixir
%OperationalEvent{
  category: :dashboard,
  kind: :dashboard_published,
  subject: %{kind: :dashboard, id: "dashboard_power_thermal"},
  scope: %{
    mission_id: "mission_...",
    data_realm: :flight
  },
  occurred_at: ~U[2026-06-16 19:00:00Z],
  recorded_at: ~U[2026-06-16 19:00:01Z],
  previous: %{
    published_version: 6
  },
  current: %{
    published_version: 7,
    document_schema_version: 1
  },
  payload: %{
    dashboard_name: "Power and Thermal",
    change_summary: "Added battery trend",
    warning_count: 1
  }
}
```

Projection guidance:

- dashboard version rows remain the source for restoring document content
- current implementation stores publish/revert/archive/restore/review/health/
  readiness facts in `dashboard_lifecycle_events` and emits matching canonical
  operational events with `source_record_kind: :dashboard_lifecycle_event`
- the dashboard version-history panel reads those local lifecycle events for
  activity visibility; dashboard/timeline read models have not yet been moved
  to consume the operational-event projection directly
- canonical events are the audit/timeline source for who changed operational
  visibility and when
- `dashboard_draft_saved` may be lower priority for mission timelines than
  `dashboard_published`, but it matters for audit
- autosave/local recovery state should not emit operational events
- dashboard lifecycle events should not be used as data-source events; widget
  Frames still come from telemetry, limits, events, and operational observable
  sources

## 11. Replay And Simulation

Replay is not just a time filter over flight data. It is a separate event
context with its own outputs and causality.

Replay events should be able to express:

- replay run started/completed/failed
- replay source data selected
- replay catalog/runtime context selected
- replay generated telemetry sample/output
- replay managed action/timer/capability records
- divergence from observed flight or baseline rehearsal

Replay events must preserve causality back to the replay run and source records
so dashboards can distinguish:

- observed flight
- replayed flight
- simulated rehearsal
- AI&T lab stream
- imported/backfilled data

## 12. Relationship To Current `mission_events`

`mission_events` should remain a read projection for now.

Current implementation note: the first durable canonical spine is now
`operational_events`, and `mission_events` projects binding-set activation
timeline rows from that store. Other timeline families still project from
subsystem facts while they are migrated deliberately.
Replay-scoped dashboard mission-timeline reads now bypass the mission-scoped
`mission_events` table when `replay_run_id` is present: the Events source reads
canonical `operational_events`, filters by replay causality, projects through
`Cadence.Projections.MissionEvents.project_many/1`, and returns the same
mission-event Frame shape with `projection: :operational_events`. This keeps
flight mission timeline compatibility while avoiding replay data leakage through
a non-replay-aware projection.
Replay-scoped dashboard contact-interval reads use the same migration pattern
for canonical contact interval events: when `replay_run_id` is present, the
Events source reads `:contact` operational events, filters by replay causality,
and returns the existing contact-interval Frame shape with
`projection: :operational_events`. Those Frames attach typed evidence for the
contact identity, the projected effective interval, and the source operational
event. The contact subsystem now emits canonical events for scheduled/realized
contact interval facts and operator/system contact action audit facts; richer
runtime/link contact-state families remain migration targets.
Transport action-request writes now emit canonical `:comms` operational events
for transport-owned actions such as uplink requests, and transport timer
lifecycle writes now emit canonical scheduled/fired/canceled operational
events. Transport capability execution records also emit canonical
initialized/control-input/transport-event/timer transition facts. This gives
those durable transport capability/action/timer rows canonical event-store
source records, and the first transport execution interval read projects each
capability snapshot until the next snapshot for the same capability. The
dashboard operational-observable source consumes that interval read as
`comms.transport.execution_state` event-history Frames, preserving interval
end-times and typed evidence refs back to the projected transport-execution
interval plus the source operational event. Broader connection/link semantics
now have native read projections on top of typed state facts; richer
runtime-derived views remain to model from those intervals.
Operational-observable metric samples now use the same store boundary for
low-rate dashboard metrics such as `comms.transport.downlink_bitrate`,
`link.snr_db`, `link.eb_n0_db`, and `ingress.processing_latency_ms`. They are canonical event
facts, not high-volume telemetry samples: payloads preserve
observable/resource identity, scoped transport/link/source-endpoint/
spacecraft/ground-station context, observed time, unit/value aliases, and
optional replay causality. Dashboard default metric readers can therefore filter
live, selected replay-run, and unrelated replay data through the event store
without treating setup existence or optional runtime snapshots as authoritative
metric values. Dashboard latest and metric-history frames carry the selected
canonical metric sample events as operational-event evidence refs, so rendered
evidence panels can explain value tiles and charts from the same event spine
used by replay readers.
Successful telemetry ingress persistence now emits durable
`ingress.processing_latency_ms` metric sample events from the timed ingress
processing result, so dashboards can read ingress latency from the canonical
event store instead of depending only on the process-local runtime-health window.

It already has useful properties:

- mission-scoped timeline row
- denormalized filter columns
- source record identity
- rebuild flow
- operator-friendly title/summary/severity/status

It is not enough as the canonical event spine because:

- it is rebuildable and display-oriented
- it only projects selected record families
- it does not represent all configuration/runtime changes
- it does not derive effective intervals
- its enum-like `kind`/`category` set is timeline-oriented, not a full event
  contract

Long-term options:

1. Keep `mission_events` as projection over canonical operational events and
   selected subsystem facts.
2. Gradually migrate subsystem facts to emit canonical operational events, then
   project `mission_events`.
3. Leave high-volume data facts, such as telemetry samples, out of the event
   spine and project only meaningful transitions/annotations.

## 13. Event Families To Cover

Initial event families:

- **Catalog/runtime** — revision imported, revision selected, binding compiled,
  binding activated, binding superseded, application binding applied.
- **Data sources** — data source registered, credential reference registered,
  credentials rotated, source binding registered/changed/enabled/disabled/
  superseded, source degraded, source recovered, retention policy changed.
- **Contacts** — scheduled, canceled, started, ended, ended early, realized,
  replayed.
- **Comms/routing** — routing rule created/updated/enabled/disabled/materialized,
  transport connected/degraded/disconnected, link realized, low-rate
  operational metric sampled for dashboard-visible transport/link/source-endpoint
  observables.
- **Telemetry/limits** — limit definition created/approved/activated/
  superseded/disabled/reverted, limit transition, sustained violation, stale
  transition, quality degradation, late/backfilled data accepted.
- **Commanding** — command requested, approved, rejected, released, uplinked,
  accepted, verified, failed.
- **Replay/simulation** — replay run lifecycle, simulation run lifecycle,
  divergence events.
- **Dashboards** — dashboard created, draft saved, published, reverted,
  archived/restored, deleted, document migrated, template promoted.
- **Security/audit** — permission changed, operator session context, service
  credential use where operationally relevant, source credential material
  resolution succeeded/failed/denied with redacted authorizer/resolver,
  field-name, and denial evidence.

Dashboard runtime invalidations are adjacent to, but not identical with,
canonical operational events. `Cadence.Dashboards.RuntimeInvalidation.Event`
is the dashboard runtime-cache contract used for PubSub, runtime health, and
open-dashboard refresh decisions. It may be derived from canonical operational
events later, but v0 producers can emit runtime invalidations directly from
local writes such as dashboard document saves, catalog activations, limit
changes, source binding changes, source watermarks, historical corrections, and
source-health transitions. Source-health and source-watermark transitions now
also emit canonical operational events; their runtime invalidations remain the
cache/refresh consequence of those durable facts.

## 14. Open Questions

1. **Canonical store expansion** — the first shared `operational_events` table
   exists; decide which event families migrate to it next and which remain
   subsystem facts projected into common timelines.
2. **Event ownership** — which subsystem owns each event family and projection?
3. **Enum governance** — how to add event kinds without unsafe atom conversion
   or schema churn?
4. **Effective interval projection** — one generic interval table or
   domain-specific interval projections?
5. **Backfill/rebuild** — how to seed canonical events from existing subsystem
   records without losing source identity?
6. **Retention** — which events are permanent audit history, which are
   compactable projections, and which are high-volume observations outside the
   event spine?
7. **Replay semantics** — are replay events stored in the same event store with
   a replay realm/context, or in replay-specific tables projected into a common
   timeline?
8. **Permissions** — who can view sensitive audit events, data-source credential
   events, and dashboard edit history?
9. **API shape** — cursorable event feed, interval queries, and dashboard
   overlay queries.
10. **Causality model** — correlation IDs, causation IDs, job IDs, replay run
   IDs, import run IDs, and source record refs.
11. **Limit activation resolution** — whether active limits resolve by
   generation time, receipt time, evaluation time, or an explicit dashboard
   mode; how late-arriving samples are classified.
12. **Limit event volume** — which limit facts remain in
   `telemetry_limit_events`, which transitions project into `mission_events`,
   and whether recomputation runs need persistent derived facts.

## 15. Suggested Next Slice

Do not start by rewriting every event-like subsystem.

The shared operational-event store is now receiving binding-set activation,
catalog revision, dashboard lifecycle, source-binding lifecycle, source-health,
source-watermark, limit-definition lifecycle, telemetry backfill/import
lifecycle, telemetry observation identity decision, scheduled/realized contact
interval facts, contact action audit facts, transport capability execution
facts, transport action-request facts, and transport timer lifecycle facts.
Binding-set, application-binding, catalog-revision, source-binding,
transport-execution, and limit-definition interval reads now consume canonical
operational events or canonical-event-backed binding-set intervals, and replay
contact intervals
consume canonical contact operational events with frame evidence for the
displayed contact, projected interval, and source event.
Replay mission-timeline frames now also expose both the projected
`mission_event` identity and the canonical `operational_event` identity in
frame evidence, so downstream DataLinks, audit views, and replay comparisons do
not need to infer the canonical source from display-oriented projection IDs.
Mission-event inspectors now link to the canonical operational event as a
source-event handoff, and canonical operational-event links resolve to the
durable envelope fields, causality, payload, current-state snapshot, and
metadata under the same mission scope checks as other dashboard evidence. The
LiveView dashboard path now proves a rendered mission-event marker can open its
projected inspector, navigate to the canonical operational-event inspector, and
preserve copy/deep-link navigation context.
Source-capability posture, source-health, and source-watermark events now use
replay-scoped canonical event ids, and native transport capability/action/timer
operational events now use the same replay-scoped id boundary. Connection-state,
RF-lock, and frame-sync state snapshots now use typed canonical source-record
families under the shared operational-observable state projection, and RF-lock
plus frame-sync now project into native link RF intervals while transport and
ground-station connection states project into native connection intervals. The
operational-event source-record uniqueness boundary preserves one fact per
replay run, so replay source evidence cannot overwrite live or other-replay
facts that share the same source record id.
Continue with **frame semantic context wiring**, because many interval families
exist but dashboard frames still need to carry every selected interval family
consistently:

1. Source-bound dashboard frames now attach typed `EvidenceRef` values for
   selected source-binding intervals, active binding-set intervals,
   source-endpoint application-binding intervals, and telemetry
   catalog-revision intervals when the request has an explicit historical
   selection time and enough scope to select a unique interval. The frame
   evidence panel now summarizes the selected source-binding, binding-set,
   application-binding, and catalog-revision intervals as first-class detail
   rows instead of leaving operators to inspect raw frame metadata, and
   resolvable evidence refs render as DataLink handoffs. Direct canonical
   operational-event evidence, source-binding lifecycle evidence, and
   limit-definition lifecycle evidence now open first-class inspectors from the
   evidence panel; subsystem lifecycle inspectors link back to their canonical
   operational-event envelopes. Projected binding-set, application-binding,
   catalog-revision, source-binding, transport-execution, and limit-definition
   interval refs now open interval inspectors that show active windows,
   subjects, payload/metadata, and source-event handoffs instead of remaining
   display-only evidence. Where existing resource DataLink targets exist,
   application-binding intervals also link to their source endpoint and
   transport-execution intervals link to their transport/contact resources.
   Telemetry latest/history frames and value-field metadata now include
   selected source-binding interval, source-binding event, and source-binding
   refs when the binding is selected from an effective interval, so the selected
   telemetry corpus is visible at both frame and field evidence boundaries.
   The source registry also enriches telemetry and operational-observable
   frames with unique selected binding-set and source-endpoint
   application-binding interval refs when the selected request time and frame
   context identify one active endpoint; telemetry frames also include selected
   catalog-revision interval refs at the selected source-binding time. Transport
   execution event-history frames now carry source-endpoint, ground-station,
   and link fields from interval payloads so transport-scoped frames can resolve
   selected runtime application-binding evidence without pretending the
   transport id itself is an endpoint.
   The rendered evidence panel now proves those interval refs, plus
   operational-event, source-binding lifecycle, limit-definition, and transport
   execution refs, become clickable DataLink handoffs rather than display-only
   rows. Operational-observable connection-state, RF-lock, frame-sync, and
   transport-execution history frames now carry native interval ids, source
   operational-event ids, and typed interval evidence refs from their interval
   projections, with rendered browser coverage for RF, connection-state, and
   transport-execution frame-evidence handoffs.
2. Limit latest-state and event-history dashboard frames now attach selected
   limit-definition interval evidence for the observed limit events they
   render. Continue broadening selected interval evidence for catalog/runtime
   intervals when the request context is intentionally broad.
3. Decide whether telemetry samples need direct `catalog_revision_id` /
   `activation_id`/`limit_definition_lifecycle_event_id` fields or whether
   interval lookup is sufficient for the first implementation.
4. Keep projecting operator-relevant runtime/limit activation changes into
   timeline views so operators can see when interpretation changed.

The next adjacent slice is **limit semantic correctness**:

1. Preserve observed limit-event semantics end to end while adding clearly
   labeled current, recomputed, and compare analysis paths. Non-observed
   bounded event-history requests now produce synthetic analysis frames from
   telemetry samples and target limit-definition intervals; compare mode reads
   observed limit events only to report divergence. Time-series marker payloads
   now preserve those semantics and divergence flags, and decimated chart
   envelope metadata rolls those markers up by bucket. Decimated time-series
   limit overlays now also plan a source-native `:analysis_buckets` Limits
   product that carries bucket start/end, worst state, event counts, divergence
   counts, and rolled-up sample/event ids. Buckets split by limit-definition
   identity when a decimated bucket spans a definition change, and chart
   rendering shows those buckets as clickable worst-state spans.
   Limit-definition intervals now render shaded red/yellow threshold regions
   inside their active spans. Latest-state non-observed requests now produce
   synthetic current/recomputed/compare scalar frames from latest telemetry
   samples and target definition intervals; compare mode uses the observed
   latest projection only to report divergence. Runtime UI controls can select
   the supported observed/current/recomputed/compare modes, and bounded
   recomputed/compare history now selects effective definition intervals per
   sample receipt time. Incomplete recomputed analysis warnings now surface the
   selected clock and missing samples in dashboard warning/evidence UI.
   Selected-clock audit events now persist through canonical operational events
   with deterministic upsert semantics. Late-data policy and workflow handoff
   still need product wiring.
2. Source-binding interval ids now use the same `EvidenceRef` path as
   source-binding events and binding identities; active binding-set,
   source-endpoint application-binding, and telemetry catalog-revision intervals
   now use the same path when the source request can select them unambiguously.
   Keep source health/watermark overlays as event overlays rather than interval
   substitutes.
3. Decide which interval families are rebuilt directly from canonical
   operational events and which remain subsystem projections in this phase.
4. Keep `telemetry_limit_events` as subsystem facts, but project meaningful
   limit transitions into `mission_events`.
5. Define and test the selected limit clock for late-arriving samples, including
   the operational events and dashboard warnings that record when observed and
   recomputed interpretations diverge.
