---
title: "ADR-019: Telemetry Data-Plane Persistence and Projection Topology"
aliases:
  [telemetry persistence topology, ingress sinks, operational event boundary]
tags: [adr, architecture, telemetry, ingress, persistence, archive, metrics, events]
status: accepted
created: 2026-07-31
updated: 2026-07-31
---

# ADR-019: Telemetry Data-Plane Persistence and Projection Topology

## Status

Accepted; implementation migration required

This ADR accepts the target responsibility, storage, acknowledgement, and
recovery boundaries for telemetry ingress. It does not claim that the current
`Cadence.Runtime.IngressPersistenceProjector` already implements them.

The exact archive and time-series products, production batch sizes, and
deployment-specific storage profiles remain evidence-driven implementation
choices. They may change without revisiting this decision as long as they
preserve the contracts below.

This ADR complements the capture and cursor decision in
[ADR-018](018-capture-first-telemetry-ingress-journal.md). ADR-018 remains
validation-gated; this ADR applies whether capture is supplied by that journal
or by another source that satisfies the same ordered provenance contract.

## Context

Cadence historically routed a processed ingress result through one generic
persistence function and one path-local persistence projector. That boundary
combined:

- raw-evidence archival;
- transfer-frame and packet archival;
- telemetry history and current-value writes;
- protocol anomaly persistence;
- operational-event persistence; and
- publication of downstream runtime facts.

Those effects have different rates, query patterns, durability requirements,
recovery sources, and failure policies. Calling them all persistence hid those
differences and encouraged one acknowledgement to stand for several guarantees.

The full-flow load harness made the cost visible. In the 2026-07-31 passing
500 Mb/s capture-first run, Cadence accepted 9.375 GB as 102,634 journal entries
and produced 150,000 frames. The ingress profiler attributed 307,902 Ecto Repo
commands to persistence:

| Classified operation | Count |
| --- | ---: |
| `INSERT` | 102,634 |
| `SELECT` | 0 |
| `UPDATE` | 0 |
| `DELETE` | 0 |
| other | 205,268 |

The exact three-to-one ratio came from one transaction per effective projector
batch: `BEGIN`, an `INSERT ... ON CONFLICT` into `operational_events`, and
`COMMIT`. Each inserted row represented one
`ingress.processing_latency_ms` measurement. The two high-rate archive adapters
were counting acknowledgements and the telemetry-history writer was a no-op, so
the result isolated the operational-event write amplification.

This transaction did not make the whole processing result atomic. Archive and
telemetry-storage calls occurred outside the Repo transaction. Cadence was
therefore paying per-entry transaction cost without gaining a cross-store
atomicity guarantee.

The earlier fixed-message runs showed the same classification error at frame
granularity: 150,001 `operational_events` rows occupied 427 MiB in the 500 Mb/s
run, and 300,001 rows occupied 820 MiB in the 1 Gb/s probe. A numerical latency
observation was being treated as an individually auditable domain event and
Postgres was being used as a high-rate time-series store.

## Decision

Cadence will separate telemetry data-plane effects by the question they answer,
their authoritative source, and their required durability. No generic
"persistence succeeded" acknowledgement may collapse these distinct
guarantees.

### 1. Data Classes Have Distinct Storage Boundaries

| Data class | Examples | Authoritative boundary | Default write shape |
| --- | --- | --- | --- |
| Captured evidence | Provider bytes, datagrams, delivery objects | Ingress journal and canonical raw archive | Sequential segments |
| Derived history | Frames, packets, telemetry samples, dispatch records | Protocol archive or time-series/history backend | Bounded bulk append |
| Latest runtime state | Current values, current queue state, recent health | ETS or another rebuildable runtime store | In-memory update |
| Numerical observability | Throughput, latency, lag, batch size, resource use | OpenTelemetry metrics and a metrics backend | Counters, gauges, histograms |
| Operational events | State transitions, anomalies, gaps, lifecycle and operator actions | Operational event store | Sparse batched facts |
| Management and control state | Missions, policy, contacts, approvals, queues | Postgres contexts owned by those planes | Relational transactions |

Storage technology does not determine semantic ownership, but a storage choice
must fit the class. In particular, Postgres is not the default sink for a fact
whose cardinality scales with bytes, journal entries, frames, packets, or
telemetry samples.

### 2. Capture Is Independent Of Interpretation And Projection

The first Cadence-owned custody operation is an ordered append of provider data
with stable stream identity and absolute provenance. Successful capture says
only that the bytes reached the configured durability boundary.

Capture does not wait for:

- framing or packet extraction;
- telemetry interpretation;
- dashboard projection;
- operational-event insertion; or
- a Postgres transaction.

ADR-018 defines the proposed filesystem journal that supplies this boundary,
including its durability profiles, cursors, fencing, capacity, and reclamation
rules.

### 3. Processing Uses Explicit Commit Contracts

The semantic processor reads ordered byte blocks and emits deterministic result
batches. Every derived record identity uses stable source provenance such as:

```text
stream epoch + absolute byte range + decoded record index or content identity
```

Each output class declares whether it is:

- **required before the processing cursor advances**;
- **safe to retry asynchronously from a durable source**; or
- **best-effort and rebuildable**.

The processing cursor advances only when its configured required outputs are
durably complete or have been handed to another durable, replayable boundary.
Updating ETS or publishing a live notification is not a durable completion.

Required output sets may vary by mission policy, but the meaning of each
acknowledgement is fixed and observable. The system will not claim exactly-once
effects across a journal, archive, time-series backend, Postgres, and process
memory. Recovery is at-least-once with deterministic, idempotent writes.

### 4. Sink Ownership Is Narrow And Independently Observable

The target topology replaces the generic persistence projector with explicit
sink responsibilities:

```text
provider
  -> capture journal
       -> raw archive replicator -> sealed objects + coarse discovery index
       -> semantic processor
            -> latest-value/runtime projection
            -> protocol archive writer
            -> telemetry history writer
            -> sparse operational-event projector
```

These responsibilities may initially share a process or supervision subtree,
but their APIs, queues, acknowledgements, retry state, and metrics remain
separate. Process consolidation is an optimization, not permission to merge
their contracts.

The raw archive consumer is independent of semantic processing. A semantic
failure cannot prevent raw evidence from reaching its canonical archive, and an
archive outage cannot be reported as successful archive completion merely
because semantic processing finished.

### 5. High-Rate Sinks Are Batch-Native

A high-rate sink accepts a non-empty batch and reports the source range or
deterministic record identities it durably accepted. Its implementation must
support thresholds by bytes, item count, and maximum dwell time.

Batching is intentional rather than only opportunistic. A sink may wait for a
short bounded dwell interval to form an efficient write even when its queue is
temporarily shallow. Queue size, batch size, dwell time, write duration, retry
count, and oldest uncommitted age are observable.

For relational stores, one bulk statement and one transaction per batch is the
expected shape. Iterating one transaction per input item inside a nominal batch
does not satisfy this contract.

### 6. The Operational Event Store Contains Sparse Facts

An operational event must have individual semantic value for audit, incident
reconstruction, replay explanation, or state-transition projection.

Appropriate ingress-related operational events include:

- source gaps or discontinuities;
- journal high-watermark, full, and recovery transitions;
- poisoned input quarantine and operator-authorized skip decisions;
- frame synchronization lost or restored;
- a required sink becoming degraded or recovering; and
- a sustained service-level breach entering or leaving an alarm state.

Raw latency, throughput, queue-depth, or lag samples are not operational events.
Specifically, Cadence will stop inserting one
`ingress.processing_latency_ms` operational event per processing result.

If a numerical series needs durable product history, Cadence will use a
time-series/history boundary or persist bounded interval summaries. If a
numerical condition becomes operationally significant, a stateful detector may
emit a sparse transition event when the condition begins or clears.

### 7. Metrics Are Not Part Of The Custody Chain

Ingress throughput, processing latency, persistence latency, batch size,
consumer lag, backpressure, and resource utilization are exported through
OpenTelemetry metrics. High-rate latency distributions use histograms rather
than one durable row per observation.

Metric dimensions remain bounded. Mission, contact, provider, evidence,
segment, and trace identifiers belong in resource attributes, logs, traces, or
result artifacts when their cardinality is not bounded enough for metric
labels.

Product-scoped numerical history is a separate batch-native data contract. It
may retain organization, mission, source-endpoint, spacecraft, contact, and
other query scope as indexed columns or series metadata in a dedicated history
backend. Those identifiers do not automatically become labels on every
OpenTelemetry SRE metric. Bounded interval aggregates are preferred when raw
per-result history has no demonstrated product need.

Metrics may be sampled, delayed, or temporarily unavailable without changing
whether telemetry bytes or derived records are durable. Loss of observability
is itself detectable, but the observability backend is not in the byte-custody
acknowledgement path.

### 8. Postgres Work Is Decoupled From Ingress Cardinality

For a corpus with no anomalies, transitions, or management/control changes,
steady-state ingress produces no `operational_events` rows.

Postgres may still receive:

- coarse archive discovery indexes, preferably one bulk operation per segment
  batch;
- batched consumer checkpoints when the selected recovery design requires
  them;
- sparse anomalies and operational transitions; and
- ordinary management- and control-plane transactions.

Consequently, data-plane Postgres work scales with segments, checkpoint
batches, and sparse facts. It does not scale directly with journal entries,
frames, packets, or telemetry samples.

### 9. Cross-Store Atomicity Comes From Replay, Not A Distributed Transaction

Cadence will not introduce a distributed transaction across the journal,
filesystem or object archive, telemetry history, Postgres, and runtime state.

Instead it uses:

- a durable authoritative input;
- stable provenance and deterministic derived identities;
- idempotent batch writes;
- monotonic per-consumer checkpoints;
- explicit required-output acknowledgements; and
- replay after a crash between an effect and checkpoint commit.

A Repo transaction remains appropriate when several Postgres rows form one
relational invariant. It must not be used as a symbolic wrapper around effects
that actually commit in other stores.

### 10. Dashboard Reads Follow The Data Class

Dashboards read:

- latest operational values from runtime/current-value projections;
- numerical history from a metrics or time-series source;
- frames, packets, and telemetry history from their archive/history sources;
  and
- individually meaningful transitions and audit facts from the operational
  event spine.

`ingress.processing_latency_ms` therefore resolves from runtime health for a
live bounded view and from the configured metrics/history backend for durable
history. It is not backed by per-result operational events.

Operational-event evidence remains attached to points or intervals that really
were produced by a sparse event, such as a backpressure transition. A chart
does not manufacture an event identity for every numerical sample merely to
support evidence navigation.

## Meaning Of Completion Signals

The following terms are deliberately distinct:

- **captured:** the source range reached the configured journal durability
  boundary;
- **raw archived:** the source range is discoverable in the canonical raw
  archive;
- **processed:** ordered semantic execution completed and all outputs required
  by the processing policy are durable or safely handed off;
- **projected:** a rebuildable latest-value, dashboard, or query projection was
  updated; and
- **observed:** metrics or traces describing the work were exported.

APIs, metrics, logs, and result artifacts use these terms rather than a generic
`persisted` status when more than one meaning is possible.

## Migration

Migration proceeds in bounded, independently testable steps:

1. Stop producing per-result `ingress.processing_latency_ms` operational
   events. Preserve latency visibility through OTEL histograms and bounded
   runtime health.
2. Change dashboard ingress-latency history to read a metrics/history boundary;
   retain operational-event reads only for sparse transitions.
3. Split `Cadence.Runtime.Persistence.persist_processing_results/2` into
   batch-native sink contracts with explicit completion meanings.
4. Give raw archive export an independent journal consumer and cursor.
5. Batch protocol archive, telemetry history, anomaly, and other required
   derived outputs, with deterministic IDs and failure injection at each
   checkpoint boundary.
6. Replace generic projector queue and acknowledgement metrics with per-sink
   lag, batch, failure, and recovery metrics.
7. Remove the generic ingress persistence projector after all callers use the
   explicit sink contracts.

Compatibility implementations may remain for tests and migrations, but they
must be named as compatibility paths and cannot define the production hot-path
architecture.

### Migration Evidence: Independent Raw Archive Consumer

The 2026-07-31 raw-archive slice completes migration step 4 and the
raw-archive portion of steps 3 and 6:

- `Cadence.Runtime.IngressArchiveConsumer` reads bounded contiguous journal
  ranges independently of semantic processing;
- a deterministic archive batch identity addresses the same object and index
  rows after retry;
- explicit `:durable` and `:accepted` receipts prevent an archive cursor from
  advancing below its configured completion policy;
- filesystem publication writes and synchronizes the deterministic object
  before publishing its discovery index, while Postgres uses a batch insert;
- the consumer retains a failed batch for ordered exponential-backoff retry and
  exposes batch, byte, duration, failure, retry, queue, and age metrics; and
- the processing path no longer invokes raw archival or advances the archive
  cursor.

Focused tests cover accepted-versus-durable completion, effect failure and
deterministic retry, object-before-index recovery, idempotent replay, cursor
independence, hard process exit before checkpoint, and bounded dwell
coalescing. The full repository gate passed after this slice.

The bounded tmpfs load profile then produced these results:

| Signal | 500 Mb/s | 1 Gb/s |
| --- | ---: | ---: |
| Cadence receive rate | 499,108,260 bit/s | 1,004,251,331 bit/s |
| Journal entries | 112,997 | 114,379 |
| Raw-archive batches | 5,140 | 4,221 |
| Average entries per archive batch | 21.98 | 27.10 |
| Peak processing lag | 812,500 bytes | 916,649,616 bytes |
| Peak archive lag | 2,125,000 bytes | 607,943,256 bytes |
| Peak journal utilization | 7.82% | 99.95% |
| Journal-full events | 0 | 98 |
| Repo commands | 0 | 0 |
| Final drain | 6 ms | 1 ms |

Every byte, frame, packet, cursor, archive, and anomaly invariant passed, with
zero archive failures. A 25 ms bounded dwell reduced the 500 Mb/s archive batch
count from 71,856 in the initial independent-consumer run to 5,140 without
material archive lag.

These runs use ephemeral counting archives and therefore qualify the topology,
coordination, batching, and observability contracts, not durable filesystem or
Postgres archive throughput. The 1 Gb/s result is functional but marginal: a
transient consumer stall exhausted nearly all of the 900 MiB journal and
activated bounded transport backpressure before recovery. It is not evidence
of comfortable sustained 1 Gb/s headroom.

### Migration Evidence: Bounded Capture Records

The next candidate slice removed the accidental coupling between kernel TCP
receive size and semantic work size. `recv(0)` remains free to return any
available bytes, but one batch append now publishes at most 256 KiB logical
capture records under one admission decision and one synchronous commit. The
semantic consumer processes one record at a time and the framer emits the list
of complete frames found in that bounded block. Absolute byte ranges and stable
capture-batch identity survive recovery.

Repeating the same checked-in tmpfs profiles produced:

| Signal | 500 Mb/s | 1 Gb/s |
| --- | ---: | ---: |
| Cadence receive rate | 499,178,020 bit/s | 997,705,278 bit/s |
| Journal entries | 111,637 | 134,538 |
| Largest capture record | 262,144 bytes | 262,144 bytes |
| Largest semantic work item | 262,144 bytes | 262,144 bytes |
| Peak processing lag | 812,500 bytes | 2,312,500 bytes |
| Peak archive lag | 2,187,500 bytes | 5,562,500 bytes |
| Peak journal utilization | 7.67% | 7.89% |
| Journal-full events | 0 | 0 |
| Repo commands | 0 | 0 |
| Final drain | 1 ms | 1 ms |

Every byte, frame, packet, cursor, archive, boundedness, and anomaly invariant
passed. At 1 Gb/s, peak processing lag fell from 916,649,616 bytes to 2,312,500
bytes, roughly a 396-fold reduction, while journal-full events fell from 98 to
zero. Grafana's provisioned API and live GreptimeDB series reported a TCP
receive p99 of about 846,371 bytes and a capture-record p99 of about 258,855
bytes, directly showing that transport coalescing no longer expands the
processing quantum.

This qualifies the bounded-record topology in the volatile laptop profile. It
does not yet qualify a durable backing volume or establish failure-free burst
headroom beyond the tested 1 Gb/s steady-state rate.

### Migration Evidence: Async Checkpoints And Bounded Semantic Batches

A 1.375 Gb/s breakpoint probe isolated two additional per-journal costs. First,
cursor checkpoint `fsync` ran inside the journal GenServer and blocked all
calls for more than five seconds. Cursor files now write in one monitored
worker; only successful publication and segment reclamation return to the
ordered journal process. A blocked-writer test proves appends and snapshots
remain responsive while durability is in flight.

After that correction, the source delivered every planned byte but required
157.073 seconds and achieved only 1.313 Gb/s. All 149,091 capture records still
became separate semantic work items. The next slice retained 256 KiB capture
records while grouping up to eight compatible records and 2 MiB per semantic
work item. Capture-batch identifiers remain ordered provenance rather than a
reason to split otherwise compatible processing ranges.

Repeating the identical 25.78125 GB tmpfs workload produced:

| Signal | One record per work item | Bounded semantic batches |
| --- | ---: | ---: |
| Source accepted rate | 1,313,086,350 bit/s | 1,374,994,766 bit/s |
| Journal records | 149,091 | 157,053 |
| Semantic work items | 149,091 | 29,149 |
| Average records per work item | 1.00 | 5.39 |
| Largest semantic work item | 262,144 bytes | 2,097,152 bytes |
| Journal-full retries | 1,302 | 147 |
| Post-receive drain | 2,542 ms | 1 ms |
| Throughput gate | failed | passed |

Every byte, frame, packet, cursor, archive, batch-bound, and anomaly invariant
passed in the batched run. It processed 412,500 frames and packets with zero
executor, projector, or archive failure.

This is a steady-state laptop-profile qualification, not a burst-headroom
claim. One transient slowed receive, semantic processing, and raw archive
together, briefly drove the 900 MiB journal to 99.99% utilization, and then
recovered without missing the source rate. BEAM memory remained about 129 MB,
so a follow-up should observe container/cgroup memory and tmpfs page-cache
pressure before attributing the excursion to another Elixir hot path.

Migration steps 5 and 7 remain open. Step 6 is complete for raw archive but
remains open for the generic semantic projector and its derived sinks.

## Acceptance Criteria

Implementation of this ADR is complete only when:

1. The no-anomaly full-flow corpus produces zero per-entry or per-frame
   operational-event inserts.
2. Database profiling distinguishes transaction-control commands from data
   operations and reports batch-size distributions.
3. Data-plane Postgres command growth is proportional to segment/checkpoint
   batches and sparse facts, not input record cardinality.
4. Every sink has bounded queueing, intentional batch thresholds, oldest-work
   age, retry, failure, and recovery observability.
5. Raw archive and semantic processing advance independently and the reclaimer
   honors every required cursor.
6. Crash tests at every effect/checkpoint boundary prove at-least-once recovery
   without missing or semantically duplicated derived records.
7. A slow or unavailable optional sink cannot block byte capture; a slow
   required sink produces explicit bounded backpressure and capacity signals.
8. Dashboard ingress-latency panels remain live and historically useful without
   per-result operational-event rows.
9. The 500 Mb/s full-flow scenario passes correctness and throughput gates with
   database, disk, memory, and queue headroom reported.
10. The 1 Gb/s scenario reports whether its limiting resource is capture,
    semantic processing, or an individual sink rather than a generic
    persistence stage.

## Consequences

### Positive

- Byte custody is no longer coupled to Postgres or dashboard projection.
- High-rate work uses storage systems and write shapes designed for its
  cardinality.
- Each acknowledgement has a precise failure and recovery meaning.
- A slow sink is identifiable instead of disappearing behind one projector
  backlog.
- Raw evidence remains sufficient to rebuild derived projections.
- The operational event spine remains queryable because it contains sparse,
  meaningful facts rather than every numerical observation.

### Negative

- Cadence gains more explicit sink interfaces, queues, checkpoints, and failure
  tests.
- Dashboard numerical history needs a metrics/history read boundary rather than
  relying on one Postgres event query.
- Reprocessing and deterministic-identity rules become mandatory for every
  required derived sink.
- Operators must reason about several named completion and lag states instead
  of one generic persistence status.

### Constraints Introduced

- No high-rate per-input Postgres write may be added without a new ADR and load
  evidence showing why archive, time-series, aggregation, or runtime state is
  insufficient.
- Operational events represent individually meaningful facts or transitions,
  not arbitrary metric samples.
- Required sink acknowledgements are explicit and independent.
- Cross-store recovery relies on deterministic replay, not an implied global
  transaction.
- Batch size and dwell behavior are measurable production contracts.

## Alternatives Considered

### Tune The Existing Projector Only

Larger opportunistic batches would reduce transactions under sustained queue
backlog, but a shallow queue would still collapse to one transaction per input.
It would also retain the generic acknowledgement and incorrect data
classification.

### Keep Metric Samples In Operational Events But Batch Them

Bulk insertion would reduce command count but would still grow Postgres storage,
indexes, retention work, and dashboard queries with ingress cardinality. It
optimizes the symptom while preserving the architectural error.

### Put Every Derived Output In One External Log

A shared durable log could provide useful fan-out and replay, but choosing
Kafka, Pulsar, or another product is an operational decision not established by
the current evidence. Explicit sink contracts and deterministic provenance are
required regardless of whether a future implementation uses such a log.

### Make All Sinks Best-Effort Because Raw Bytes Are Archived

This minimizes live latency but can violate mission requirements for timely or
durable derived products. Each output therefore declares whether it is required
before checkpoint advancement instead of receiving one global best-effort
policy.

## See Also

- [ADR-015: Management Plane, Control Plane, and Data Plane Architecture](015-management-control-data-plane-architecture.md)
- [ADR-018: Capture-First Telemetry Ingress Journal](018-capture-first-telemetry-ingress-journal.md)
- [Developer Architecture Guide](../developer-architecture-guide.md)
- [Telemetry Ingress Evaluation Harness](../telemetry-ingress-evaluation-harness.md)
- [Operational Event Timeline Design](../operational-event-timeline-design.md)
- [Decide Where New Data Belongs](../how-to/decide-where-data-belongs.md)
