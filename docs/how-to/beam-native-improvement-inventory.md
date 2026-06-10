---
title: BEAM-Native Improvement Inventory
tags: [how-to, architecture, runtime, beam, operations, backpressure]
status: active
created: 2026-06-10
updated: 2026-06-10
---

# BEAM-Native Improvement Inventory

This inventory tracks places where Cadence can lean further into OTP process
ownership, local queues, explicit signals, ETS projections, and supervised
runtime state.

It is not a requirement to remove every timer, `GenServer.call/2`, or durable
Postgres query. The target is narrower:

- Postgres stores durable control-plane intent and audit state.
- Runtime processes own live ordering, timers, sockets, backpressure, and
  rebuildable projections.
- Normal steady-state paths prefer messages and state transitions over polling.
- Safety scans and retry timers remain acceptable as recovery backstops.

## Common Opportunity Patterns

### 1. Capacity Notification Instead of Queue Polling

Use this when one process pauses because another process owns a queue.

The better BEAM shape is:

1. producer sees downstream queue above a high watermark
2. producer registers interest in capacity below a low watermark
3. producer stops producing or stops reading external input
4. downstream owner notifies registered waiters as it drains
5. producer resumes, with a slow timeout only as missed-signal recovery

Current example:

- `Cadence.ProviderAdapters.TCPSocket` pauses passive TCP reads when
  `Cadence.Runtime.ProviderIngressExecutor` crosses the executor high
  watermark.
- The current working-tree slice adds
  `ProviderIngressExecutor.notify_when_below/4` so the TCP receiver waits for a
  capacity message instead of sleeping.

Current state:

- `Cadence.Runtime.ProviderIngressExecutor` still gates on
  `Cadence.Runtime.IngressPersistenceProjector.snapshot/1` before processing,
  then registers with `IngressPersistenceProjector.notify_when_below/4` and
  waits for a low-watermark message when the projector is backpressured.

Priority: high.

Status: implemented for the live ingress chain from TCP receiver to executor to
persistence projector.

### 2. Async Enqueue for Hot-Path Archive Writers

Use this when callers enqueue data into a process-owned buffer and do not need
the caller to wait for the buffer mutation.

Current examples:

- `Cadence.IngressArchive.FileSystem.Writer.enqueue/1`
- `Cadence.IngressArchive.FileSystem.Writer.enqueue_many/1`
- `Cadence.Protocol.RecordArchive.FileSystem.Writer.enqueue/3`
- `Cadence.Protocol.RecordArchive.FileSystem.Writer.enqueue_many/1`

Those currently use `GenServer.call/2`, while flush, stats, reset, and manual
flush operations also use `call`. The control operations should remain calls.
The hot enqueue path may be a better fit for `cast`, or for a bounded enqueue
API that returns `{:error, :backpressured}` when a queue limit is exceeded.

Priority: medium.

Why: this removes avoidable synchronous handshakes from archive hot paths, but
it must preserve visibility into archive queue growth and failure handling.

### 3. Bounded Queue Contracts

Use this when a process owns an in-memory queue fed by live ingress or durable
runtime work.

Current queue owners:

- `Cadence.Runtime.ProviderIngressExecutor`
- `Cadence.Runtime.IngressPersistenceProjector`
- `Cadence.IngressArchive.FileSystem.Writer`
- `Cadence.Protocol.RecordArchive.FileSystem.Writer`
- `Cadence.Jobs.Dispatcher`
- `Cadence.Commanding.LaneDispatcher`

Several queues expose `queue_depth`, but queue capacity contracts are not yet
consistent. Some queues use high/low watermarks. Some rely on flush count or
batch size. Some only expose snapshots.

Better shared pattern:

- each queue owner exposes `queue_depth`
- hot queues expose high/low watermark behavior when they can backpressure
- queue owners emit telemetry when they enter or leave backpressure
- queue owners can register capacity waiters when another process needs to
  pause
- snapshots use consistent names for `queue_depth`, `processing?`,
  `backpressured?`, and failure fields

Priority: high for ingress pipeline queues, medium elsewhere.

### 4. Retry Timers as Recovery, Not Main Coordination

Use this when a process retries after downstream failure or missed signal.

Current examples:

- `Cadence.Runtime.IngressPersistenceProjector` uses
  `Process.send_after(self(), :process_queue, state.retry_delay_ms)` after
  persistence failure.
- `Cadence.Runtime.ProviderIngressExecutor` uses short retry timers when the
  persistence projector is backpressured or when persistence batch enqueue
  fails.
- command dispatch, verifier scheduling, contact scheduling, and jobs now use
  slow safety timers as recovery backstops.

The command/contact/jobs shape is the preferred model. Short retry timers are
still reasonable for failure recovery, but they should not be the primary way
two healthy processes coordinate capacity.

Priority: medium.

### 5. Snapshot Calls as Diagnostics, Not Control Loops

Use this when one process calls another process for a full state snapshot.

Current examples:

- provider runtime snapshots include nested executor and projector snapshots
- path/contact/mission runtime snapshots aggregate child snapshots
- TCP receiver still samples `ProviderIngressExecutor.snapshot/1` before reads
  to decide whether it should pause or resume

Snapshots are appropriate for diagnostics and UI. In hot control paths, prefer
small dedicated APIs or messages:

- `notify_when_below/4` for capacity
- `dispatch_now/1` for lane dispatch
- targeted scheduler notifications for contact or verifier changes

Priority: medium.

Why: snapshot aggregation is useful but can become hidden synchronous coupling
if it drives hot behavior.

### 6. Runtime Health Standardization

Use this when operational visibility spans multiple runtime processes.

Current state:

- `Cadence.Telemetry.RuntimeHealth` collects scheduler and dispatcher telemetry
  in memory.
- ingress profiling separately captures mission-scoped ingress, DB, archive,
  and runtime component metrics.
- archive and runtime snapshots expose queue fields with similar but not fully
  standardized shapes.

Better shared pattern:

- common telemetry names for `:backpressure_entered`, `:backpressure_released`,
  `:queue_drained`, `:retry_scheduled`, and `:capacity_waiter_registered`
- `RuntimeHealth` includes queue/backpressure counters for provider,
  executor, projector, archive, jobs, and command lanes
- queue snapshots expose consistent fields

Priority: medium.

### 7. Config Naming Cleanup

Use this when old names obscure the intended runtime pattern.

Current state:

- converted schedulers and dispatchers require `:safety_poll_interval_ms`
- command lane scheduling requires `:lane_safety_poll_interval_ms`

Better shape:

- remove compatibility names in early development
- require `:safety_poll_interval_ms` and `:lane_safety_poll_interval_ms`
- keep the architecture guard that rejects new tight poll defaults

Priority: complete.

Why: this keeps recovery scans explicit and prevents old primary-polling names
from drifting back into runtime owners.

## Prioritized Slice Backlog

### Slice 1: Projector Capacity Notifications

Status: implemented.

Add `IngressPersistenceProjector.notify_when_below/4` and
`cancel_notify_when_below/2`, then have `ProviderIngressExecutor` wait on
projector capacity messages instead of using short backpressure retry timers.

Definition of done:

- projector snapshot includes `capacity_waiter_count`
- executor registers with the projector when projector queue depth crosses the
  high watermark
- projector notifies when queue depth drops below the low watermark
- short timeout remains only as missed-signal recovery
- focused runtime tests cover immediate notify, waiter registration,
  cancellation, and executor resume

### Slice 2: Backpressure Telemetry

Status: partially implemented.

Emit telemetry for executor/projector backpressure transitions and capacity
waiter registration/release.

Definition of done:

- `RuntimeHealth` collects these events
- snapshots expose current backpressure state
- operations docs describe which events indicate healthy throttling versus a
  stuck lane

### Slice 3: Archive Enqueue Contract

Status: deferred.

Evaluate whether filesystem archive writer enqueue paths should move from
`GenServer.call/2` to `GenServer.cast/2` or to an explicit bounded enqueue API.

Definition of done:

- hot-path enqueue behavior is documented
- tests cover queue depth and flush behavior
- any async enqueue path keeps failure visibility through stats/telemetry

### Slice 4: Queue Snapshot Vocabulary

Status: partially implemented.

Standardize queue snapshot keys across executor, projector, archive writers,
jobs, and command lanes.

Definition of done:

- consistent keys for queue depth, processing state, backpressure state, last
  error, and last completion time
- docs update the expected queue fields
- existing runtime UI/API callers keep working or are updated

### Slice 5: Config Cleanup

Status: implemented.

Remove old `:poll_interval_ms` compatibility fallbacks from converted
runtime schedulers and dispatchers.

Definition of done:

- only `:safety_poll_interval_ms` and `:lane_safety_poll_interval_ms` remain
- architecture guard is updated to reject compatibility fallback reintroduction
- config reference reflects the narrowed names

## Defer For Now

- Multi-node ownership implementation. ADR-013 names the boundary; concrete
  distributed ownership can wait until there is a real deployment requirement.
- QuestDB or TSDB adapters. Keep interfaces open, but do not add a TSDB backend
  before retention and query patterns are clearer.
- Runtime-health UI. The data is now available; the UI/API surface is future
  ops work and should stay separate from setup pages.
