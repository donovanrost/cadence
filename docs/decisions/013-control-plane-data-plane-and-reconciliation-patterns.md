---
title: "ADR-013: Control Plane, Data Plane, and Reconciliation Patterns"
aliases:
  [
    control plane data plane,
    level triggered reconciliation,
    runtime projection,
    postgres polling
  ]
tags: [adr, architecture, control-plane, data-plane, runtime, reconciliation, otp]
status: accepted
created: 2026-06-08
updated: 2026-06-09
---

# ADR-013: Control Plane, Data Plane, and Reconciliation Patterns

## Status

Accepted

This accepts the design pattern. It does not claim every existing subsystem
already follows the pattern; the adoption map below calls out current gaps.

## Context

This decision is based on the current `apps/cadence` and `apps/cadence_web`
implementation, not on legacy Cadence docs. Older ADRs are useful background,
but this review treats the code as the source of truth for current adoption.

Cadence currently has several different database access patterns:

- contact lifecycle scheduling uses mission-owned `Cadence.Contacts.Scheduler`
  processes under `Cadence.Runtime.MissionRuntime`; the global reconciler path
  remains explicit/manual or opt-in safety machinery
- jobs use a durable Postgres queue plus `Cadence.Jobs.Dispatcher`; enqueue
  signals and worker-exit monitors drive normal dispatch, while a slow safety
  scan remains as the recovery backstop
- command dispatch uses durable queue records, direct lane kicks after queue or
  contact availability changes, per-lane timers for delayed work, and a slow
  safety reconcile; command verifier timeout handling uses an in-memory timeout
  projection, notifications after verifier writes, and a slow safety reconcile
- telemetry current values and recent history can use ETS-backed runtime
  projections, while Postgres backends remain available for tests and durable
  query paths
- mission, contact, path, transport, provider ingress, and capability runtime
  modules already use OTP processes for ordered runtime work

The question is not whether Postgres is good or bad. Postgres should remain the
durable system of record for control-plane intent and lifecycle state. The
question is where we are accidentally using Postgres as a high-frequency timer,
queue, or hot runtime cache when the BEAM is a better fit.

## Definitions

**Control plane** is durable intent, configuration, policy, workflow state, and
operator-visible lifecycle state. It must survive process crashes and node
restarts. In Cadence this usually means Postgres.

**Data plane** is supervised runtime execution: live traffic, timers, ordered
lanes, backpressure, protocol state, active contact/path/transport processes,
and process-owned projections used by the hot path.

**Durable intent** is a record of what should happen. Examples include a
scheduled contact, staged command, queued release, catalog import job, or active
binding-set activation.

**Runtime projection** is state derived from durable intent or live input and
kept in process memory or ETS for fast runtime use. It can be rebuilt after a
crash.

**Level-triggered reconciliation** repeatedly compares desired durable state
with actual runtime state and converges them. It is the correctness backstop.

**Edge-triggered notification** is a signal sent after a successful write or
event to wake the owner that can act on it. It is the preferred steady-state
path when Cadence already knows what changed.

**Safety reconciliation** is a slower periodic scan that catches missed
notifications, process restarts, node restarts, or writes made outside the
normal runtime owner.

## Decision

Cadence will use a control-plane/data-plane split as the default design pattern
for new runtime features.

Postgres remains the durable source of truth for mission setup, contact
intent, command workflow state, background jobs, catalog state, and
operator-visible lifecycle records.

BEAM processes and ETS should own hot runtime state, timers, ordered execution,
local backpressure, and read projections that can be rebuilt.

Reconciliation should be level-triggered at correctness boundaries, but
steady-state runtime work should prefer explicit signals, process timers, and
process-owned schedule state over frequent Postgres polling.

ETS is acceptable for local runtime projections and bounded recent windows. ETS
is not a durable source of truth unless paired with a rebuild strategy from
Postgres or an archive.

High-rate telemetry history is not an ideal long-term fit for OLTP tables.
Current-value projections and bounded recent history fit ETS. Longer history
and high-rate analytical reads should move behind archive/TSDB-capable
interfaces when the operational need is clearer.

Mission control planes are an accepted specialization of this pattern. A
mission-scoped control-plane owner reconciles durable mission intent into the
mission data plane. In the current implementation this role is closest to
`Cadence.Runtime.MissionCoordinator` under `Cadence.Runtime.MissionRuntime`.

Tenant reconcilers are not accepted as a default requirement yet. A
tenant-level reconciler is appropriate when Cadence needs organization-level
startup, suspension, quota, placement, or cleanup behavior. Until then,
mission-scoped ownership is the default course-correction target.

## Approved Patterns

### 1. Durable Write, Signal, Safety Poll

Use this when work must be durable before execution, but Cadence knows exactly
when new work is inserted or changed.

The write path:

1. writes durable intent in Postgres
2. commits the transaction
3. signals the runtime owner or dispatcher
4. relies on a slower safety reconciler if the signal is missed

This is the preferred shape for durable queues and many lifecycle transitions.
`Cadence.Jobs.Dispatcher` is the current closest example: jobs are durable, new
work can notify the dispatcher, worker exits trigger more dispatch, and a slow
safety dispatch remains as the backstop.

### 2. Process-Owned Schedule With Durable Recovery

Use this when the important runtime operation is time based and the schedule is
known at write time.

The runtime owner:

- loads relevant durable intent on boot
- keeps the next transitions in process state or ETS
- uses `Process.send_after/3` or timer-service owned timers for the next due
  transition
- updates its projection after successful durable writes
- performs a slower safety reconcile to catch missed signals or external writes

This is the implemented pattern for contact scheduling. The current
`Cadence.Contacts.Scheduler` runs as a mission-owned process, keeps scheduled
contact wakeups in memory, uses timers for due transitions, and rebuilds from
Postgres on boot or safety reconciliation.

### 3. Ordered Executor With Async Projectors

Use this when input order, backpressure, and bounded runtime work matter more
than synchronous database writes.

The runtime executor owns ordering and may synchronously update hot-path-safe
projections. Durable or archival persistence should happen through explicit
projectors or batch writers unless correctness requires blocking the hot path.

`Cadence.Runtime.ProviderIngressExecutor` follows this shape for provider
ingress. It extracts telemetry samples, records current values only when the
configured store reports `hot_path_safe?/0`, and enqueues persistence batches
separately.

### 4. ETS Projection Backed By Rebuild

Use ETS for state that is:

- queried frequently by runtime or UI paths
- derived from durable state or live input
- cheap enough to rebuild or acceptable as a bounded recent window
- local to the node unless a distribution strategy has been explicitly chosen

Telemetry current values fit this model. Bounded recent telemetry history also
fits this model. Durable audit, long-term history, and replayable event streams
do not fit ETS alone.

### 5. Low-Rate Polling Reconciler

Polling is acceptable when the state changes at low rate, the query is indexed,
and the reconciler is a correctness boundary rather than the primary runtime
timer.

Command verifier timeout handling is currently in this category. Command
dispatch lane discovery is also in this category, but queued release writes
should continue moving toward direct lane kicks where the changed lane is known.

## Anti-Patterns

Avoid these in new feature work:

- polling Postgres at high frequency to discover ordinary timer expirations
- using a GenServer as the only record of durable intent
- writing durable state behind a runtime owner's back without notifying it or
  relying on a documented safety reconcile
- doing synchronous OLTP writes in hot ingress paths without a measured
  correctness reason
- putting a whole mission or fleet behind one global process when ownership can
  be scoped by mission, contact, path, lane, partition, or point
- adding a TSDB backend before the interface and retention/read requirements
  are clear

## Regression Guardrails

`Cadence.Telemetry.RuntimeHealth` subscribes to the runtime scheduler and
dispatcher telemetry events and keeps a process-local health view in memory.
This is the first operational surface for the BEAM-owned data plane; it is not
durable state and it does not write observations back to Postgres.

`apps/cadence/test/cadence/architecture_runtime_guard_test.exs` protects the
current DB-backed runtime owners from drifting back to tight Postgres polling.
The guard applies to contact scheduling, command dispatch, command lane
dispatch, command verifier timeout scheduling, and background jobs.

Those modules may still use:

- process timers for exact due work, `not_before` delays, and slow recovery
- `:safety_poll_interval_ms` as the durable missed-signal backstop
- compatibility reads of old `:poll_interval_ms` options only when they fall
  back to the safety interval

They should not add a new `@default_poll_interval_ms`, a tight numeric
`:poll_interval_ms` default, or application config that makes polling the
primary runtime path again.

## Failure Model

Every runtime feature that uses this pattern must state how it handles:

- **DB write succeeds, signal is lost:** safety reconciliation eventually sees
  the durable intent and acts
- **process crashes:** supervision restarts the owner and it rebuilds from
  durable state or archive state
- **application restarts:** boot reconciliation loads active intent and starts
  overdue work idempotently
- **duplicate signals:** handlers are idempotent and tolerate already-claimed,
  already-started, or already-completed records
- **multi-node runtime:** process-local state is valid only after ownership is
  explicit, for example through mission/partition ownership, advisory locks, or
  another single-owner mechanism

## Multi-Node Boundary

This ADR does not choose a distribution library, clustering strategy, lock
mechanism, or placement algorithm. Those decisions belong in a dedicated
runtime distribution ADR.

The control-plane/data-plane pattern must still remain valid when Cadence moves
from one node to many nodes:

- runtime projections, GenServer state, timers, and ETS tables are local to
  the node that owns the runtime scope
- before relying on process-owned state, Cadence must define a single-active
  ownership rule for that scope: mission, partition, contact scheduler, queue
  lane, path, transport, or another explicit key
- ownership transfer rebuilds process-local state from Postgres, archive state,
  or another durable source
- safety reconciliation must be scoped to ownership so two nodes do not act on
  the same durable intent concurrently
- signals remain an optimization; durable state plus ownership-scoped
  reconciliation remains the correctness path
- until distributed ownership exists for a subsystem, that subsystem should be
  treated as single-node operationally

## Current Adoption Map

### Strong Data-Plane Fit Today

- `Cadence.Runtime.MissionCoordinator` and `Cadence.Runtime.PartitionOwner`
  reconcile mission activation into supervised runtime owners.
- `Cadence.Runtime.ContactCoordinator`, `PathRuntime`, `TransportRuntime`, and
  `ProviderIngressExecutor` keep ordered runtime work in OTP processes.
- `Cadence.Telemetry.CurrentValueStore.ETS` provides a hot-path-safe runtime
  projection for latest values.
- `Cadence.Telemetry.HistoryStore.ETS` provides a bounded local recent-history
  window.

### Partial Fit Today

- `Cadence.Jobs.Dispatcher` uses durable Postgres jobs, enqueue signals,
  worker supervision, worker-exit monitors, and a slow safety dispatch. This is
  the durable queue reference shape.
- `Cadence.Commanding.Dispatcher` reconciles pending lanes as a safety
  backstop. Queue writes and release-target contact changes now kick affected
  lanes directly. `Cadence.Commanding.LaneDispatcher` uses immediate dispatch
  requests and exact `not_before` timers, with slow safety retries for blocked
  or transient-error cases.
- Mission runtime startup is currently lazy through `Cadence.Runtime` and the
  mission dynamic supervisor. This is enough for now; a tenant reconciler
  should wait for concrete tenant-level lifecycle requirements.
- `Cadence.Contacts.Scheduler` is now started under each mission runtime when
  contact scheduling is enabled. Contact writes notify the mission scheduler,
  which keeps an in-memory projection for scheduled contact wakeups. Postgres
  rebuilds the projection on boot and safety reconciliation. The global
  scheduler is no longer part of the default runtime path. The scheduler emits
  telemetry events for projection rebuilds, contact notifications, timer
  scheduling and firing, reconcile runs, stale timers, and safety
  reconciliation.
- `Cadence.Commanding.VerifierScheduler` now keeps an in-memory projection of
  pending verifier timeout deadlines. Release and verifier evaluation paths
  notify the scheduler after durable updates, timers handle due timeouts, and a
  slow safety reconcile rebuilds from Postgres.

### Needs Follow-Up

- Runtime dashboards and alerts should use the scheduler and dispatcher
  telemetry events documented in `docs/how-to/configuration-reference.md`;
  `Cadence.Telemetry.RuntimeHealth` now provides the process-local read model,
  while the architecture guard only prevents obvious polling regressions.
- A future ops/runtime UI or API surface should expose
  `Cadence.runtime_health_snapshot/0` for operators. That surface should be
  labeled as node-local/process-local, should not create a durable health table,
  and should remain separate from mission setup pages.
- Contact scheduling should wire dashboards or alerts from the scheduler
  telemetry events so missed signals, timer drift, reconcile volume, and safety
  reconciliation activity are visible in operations.
- Command verifier scheduling should wire dashboards or alerts from its
  scheduler telemetry events so timeout volume, stale timers, and safety
  reconciliation activity are visible in operations.
- Command dispatch should wire dashboards or alerts from dispatcher and lane
  dispatcher telemetry so blocked lanes, delayed work, release attempts, stale
  timers, and safety reconcile activity are visible in operations.
- Background jobs should wire dashboards or alerts from jobs dispatcher
  telemetry so queued-job latency, worker starts, worker-start failures, and
  safety dispatch activity are visible in operations.
- Long-term telemetry history should not be assumed to belong in Postgres. ETS
  covers local recent history; a future archive or TSDB adapter should cover
  high-rate historical reads.

## Contact Scheduler Target

The contact scheduler should be the first reference implementation for this
pattern because it is already a visible source of frequent queries and the
domain is naturally time based.

Current target shape:

- one scheduler owner per mission, or another explicit partition key if mission
  ownership becomes too coarse
- boot loads scheduled contacts and active realized contacts for that owner
- API paths that create, update, cancel, realize, or complete contacts commit to
  Postgres first, then signal the owning scheduler with the affected IDs
- the scheduler maintains an in-memory ordered set of next transitions
- the scheduler uses timers for the next due transition instead of polling
  Postgres every second
- a slow safety reconcile remains to catch missed signals, app restarts, manual
  database changes, or scheduler crashes
- all lifecycle actions remain idempotent because duplicate signals and overdue
  boot recovery are expected

This should reduce log noise and database scans while preserving the durable
control-plane record operators need.

## Guidance For Future Features

Before adding a new database query loop or runtime process, answer these
questions in the design or PR:

- Is this durable intent, live runtime state, high-rate stream data, or a read
  projection?
- Does correctness require a synchronous Postgres write before continuing?
- Who owns ordering and backpressure?
- Can the runtime state be rebuilt after a crash?
- What happens if the signal after the durable write is lost?
- What is the smallest safe ownership scope: mission, contact, path, transport,
  queue lane, partition, point, or global?
- Is the poll a correctness backstop or the primary timer?
- Is ETS enough because the data is rebuildable or bounded, or does the data
  need durable storage?
- If the data is high-rate history, are we designing an OLTP table, an archive,
  or a future TSDB-backed store?

## Consequences

This pattern makes the runtime more BEAM-native and should reduce avoidable
database chatter. It also makes failure handling more explicit: durable writes
provide recovery, process ownership provides fast runtime behavior, and safety
reconciliation covers missed edges.

The tradeoff is that features need clearer ownership boundaries. A runtime
owner that keeps local state must also document bootstrapping, idempotency,
multi-node ownership, and rebuild behavior. That extra design work is the cost
of avoiding accidental Postgres-as-runtime behavior.
