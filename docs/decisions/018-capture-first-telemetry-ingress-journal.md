---
title: "ADR-018: Capture-First Telemetry Ingress Journal"
aliases:
  [telemetry ingress journal, durable ingress spool, capture first, batched framing]
tags: [adr, architecture, telemetry, ingress, journal, archive, backpressure, runtime]
status: proposed
created: 2026-07-29
updated: 2026-07-31
---

# ADR-018: Capture-First Telemetry Ingress Journal

## Status

Proposed; experimental implementation in progress

This ADR is deliberately validation-gated. It records the strongest current
design hypothesis and the evidence required before Cadence adopts it. It does
not authorize an unconditional production migration by itself.

On 2026-07-31, implementation of the validation candidate was authorized so
the design can be exercised through the real runtime rather than only through
a standalone prototype. The candidate is controlled by
`ingress_journal[:enabled?]` / `CADENCE_INGRESS_JOURNAL_ENABLED` and currently
supports TCP TM downlink paths. This implementation milestone does not satisfy
the acceptance criteria below by itself.

The implemented candidate now includes:

- path-local checksummed filesystem records with `:sync` and explicit
  `:page_cache` durability profiles;
- torn-tail recovery, bounded admission, independently checkpointed processing
  and archive cursors, and segment reclamation behind their durable minimum;
- one immutable TCP-read entry feeding the existing multi-frame TM decoder;
- stable journal evidence, frame, and packet identities plus absolute frame
  offsets;
- an independent raw-archive consumer with deterministic range identities,
  explicit completion receipts, bounded batch dwell, ordered retry, and its own
  archive cursor;
- persistence-completion acknowledgements and executor-local persistence
  credits, eliminating synchronous projector snapshots from the processing
  loop; and
- runtime metrics, load-test result fields, and Grafana panels for journal
  admission rate/latency, retention, utilization, per-consumer lag, raw-archive
  throughput, batch shape, and retry state.

The 2026-07-31 load runs also disproved the candidate's downstream generic
persistence shape. The passing 500 Mb/s run executed 307,902 Ecto Repo commands
for 102,634 journal entries: one `BEGIN`, one per-entry ingress-latency
operational-event upsert, and one `COMMIT` per effective projector batch. That
work performed no `SELECT`s and did not make the following archive and history
writes transactionally atomic. [ADR-019](019-telemetry-data-plane-persistence-and-projection-topology.md)
therefore accepts a replacement target based on explicit, batch-native sinks,
sparse operational events, and metrics storage for numerical observations. The
current generic persistence projector is migration code, not the target
architecture.

Still required before acceptance are poisoned-input quarantine, stream epochs
and writer fencing, low-free-space policy, the complete fault corpus, the
remaining batch-native derived sinks, and server/Compose/Kubernetes persistent
volume qualification. Process-crash replay and raw-archive effect/checkpoint
retry now have focused proof, but do not yet constitute the complete recovery
matrix or durable-volume qualification.

The proposal extends:

- [ADR-005](005-runtime-partitioning-and-workload-isolation.md), which assigns
  ordered semantic work and protocol state to runtime partitions;
- [ADR-006](006-contact-link-and-transport-runtime-model.md), which keeps raw
  evidence path-specific and semantic processing in endpoint partitions;
- [ADR-012](012-provider-adapter-and-ground-station-simulator-model.md), which
  makes provider adapters responsible for external I/O while Cadence owns
  framing, replay, and semantic processing;
- [ADR-015](015-management-control-data-plane-architecture.md), which treats
  live ingress, protocol execution, and backpressure as data-plane concerns; and
- [ADR-019](019-telemetry-data-plane-persistence-and-projection-topology.md),
  which defines the downstream processing, sink, acknowledgement, and storage
  class boundaries.

## Context

Cadence needs an explicit failure model for telemetry sources that can deliver
bytes faster than the semantic pipeline can process them.

Consider a system that can sustainably frame, dispatch, decommutate, and persist
500 Mb/s while an active downlink delivers 1 Gb/s. If the source cannot be
slowed, the backlog grows at 500 Mb/s, or 62.5 MB/s. A buffer can absorb a finite
burst, but it cannot repair a permanent capacity mismatch:

- 16 GiB absorbs about 4.6 minutes of that difference;
- 64 GiB absorbs about 18.3 minutes; and
- a ten-minute burst requires about 37.5 GB before safety headroom.

The architectural question is whether Cadence should first capture inbound
bytes into a bounded, recoverable journal and let framing and archival consume
from that journal, rather than requiring live interpretation to keep pace with
capture.

### Baseline Runtime Shape Before The Candidate

The current TCP path:

1. receives passive TCP data;
2. concatenates it with an in-memory receive remainder;
3. splits the stream into configured fixed-size messages;
4. creates one `Cadence.Ingress.RawEvidence` value per message;
5. enqueues those values into a path-local
   `Cadence.Runtime.ProviderIngressExecutor`;
6. performs ordered runtime decoding and semantic work; and
7. sends successful processing results to an asynchronous
   `Cadence.Runtime.IngressPersistenceProjector`.

The TCP receiver pauses reads when the executor queue reaches a high watermark
and resumes below a low watermark. This is the correct behavior for a source
that honors TCP backpressure. It does not guarantee lossless capture when an
upstream ground system has a finite buffer, discards when Cadence stops reading,
or uses a transport that cannot be backpressured.

The persistence projector batches successful processing results. Raw ingress
archive writes occur from that downstream persistence path. Therefore, the raw
archive cannot currently recover bytes that were lost before executor enqueue,
were resident only in volatile queues during a crash, or failed before a
successful processing result was produced.

The default filesystem ingress archive is also not an upstream write-ahead log.
It buffers `RawEvidence` values in memory, later serializes them into compressed
segment objects, and records query indexes in Postgres.

### Existing Batched Decode Capability

The current TM framing kernel already accepts an arbitrary binary plus a saved
remainder. It can decode all complete frames in that binary and return lists of:

- transfer-frame records;
- packet records; and
- protocol anomalies.

The endpoint partition can dispatch a list of resulting packets in order. The
current TCP boundary does not exploit this fully because it creates a separate
executor item for every configured fixed-size frame before the decoder runs.

This means there are two related but separate hypotheses:

1. larger byte batches may improve sustained processing throughput by reducing
   per-frame allocation, tracing, message, and queue overhead; and
2. a durable journal may preserve raw input and absorb bounded bursts even when
   processing remains slower than capture.

The journal must not be credited with throughput gains that actually come from
batching, and batching must not be mistaken for durable burst protection.

## Proposed Decision

Cadence proposes to introduce a **capture-first telemetry ingress journal**
between provider I/O and protocol interpretation, subject to the proof and
acceptance gates in this ADR.

The intended data flow is:

```text
provider adapter
  -> append captured bytes to a path-local ingress journal
       -> processing cursor -> byte blocks -> framer -> frames/packets -> runtime
       -> archive cursor    -> sealed segments -> long-term raw archive/index

segment reclaimer
  -> deletes a local segment only after all required durable cursors pass it
```

### 1. Capture Precedes Protocol Interpretation

For supported streaming providers, the first Cadence-owned operation after
receiving bytes will be an append to the ingress journal.

The capture boundary will preserve, at minimum:

- organization and mission ownership;
- realized contact, path, and provider binding identity;
- source endpoint and spacecraft identity already resolved by the control
  handoff;
- a provider-session or stream epoch;
- absolute byte start and end offsets within that epoch;
- receipt-time evidence;
- transport record boundaries when the provider supplies them; and
- enough metadata to select the correct protocol framing configuration.

SCID, VCID, APID, and other protocol fields remain decoded evidence. They do not
replace the path, provider, source-endpoint, or spacecraft ownership of the
captured stream.

### 2. The Journal Is A Bounded Append Log

The journal is not an unbounded BEAM mailbox, a list of `RawEvidence` structs,
or a general job queue.

It will use immutable, checksummed segments with a small versioned header and a
recoverable manifest. Segment publication will be atomic: consumers may only
advance into bytes that the writer has made visible under the selected
durability class.

The candidate keeps transport, custody, and processing boundaries distinct:

- a TCP `recv` result is only an opportunistic transport batch and may vary
  from a few bytes to the configured socket buffer;
- a **logical capture record** is capped independently, currently at 256 KiB;
- one admitted transport batch may write several capture records under one
  capacity decision and one synchronous durability boundary;
- **journal segment size** remains tens or hundreds of MiB;
- the semantic consumer combines at most eight compatible adjacent capture
  records and at most 2 MiB into one work item, independently of TCP receive
  and segment boundaries;
- archive consumers retain their own larger batch thresholds; and
- emitted frame or packet lists contain the complete records found in the
  bounded semantic block, subject to downstream scheduling limits.

Every capture record retains absolute start and end offsets plus a stable
capture-batch identity. A semantic batch retains the ordered set of capture
batch identifiers and the complete absolute byte range. A large transport
receive therefore cannot become one unbounded framer or persistence item,
while exact byte order and recovery identity remain reproducible.

No value such as 64 KiB will become an architectural constant without benchmark
evidence.

Queue and capacity limits will be expressed primarily in bytes and time lag,
not only item counts.

### 3. The Journal Uses A Deployment-Neutral Durable-Volume Contract

Cadence must support the same journal semantics when it runs:

- directly on a server;
- in Docker Compose; or
- in Kubernetes.

The journal format, cursor rules, recovery algorithm, and reclamation contract
will not depend on which of those deployment environments starts the Cadence
process. The initial implementation hypothesis is a mounted filesystem that
supports efficient sequential I/O, durable synchronization, atomic segment
publication, exclusive writer ownership, capacity inspection, and recovery
after process or container restart.

The deployment environment supplies the volume and declares its durability
profile. It does not redefine what a committed journal offset means.

| Deployment | Suitable journal backing | Not durable journal backing | Recovery boundary |
| --- | --- | --- | --- |
| Server | Dedicated disk, dedicated filesystem, or explicitly provisioned persistent directory | tmpfs used without an accepted volatile-only policy | Process and service restart; machine or disk loss depends on the selected storage |
| Docker Compose | Explicit bind mount or named volume with documented host storage | Container writable layer or an untracked anonymous/temporary volume | Container recreation; host loss depends on the volume implementation |
| Kubernetes | PersistentVolumeClaim with a measured storage class, or a local PersistentVolume when node affinity is an accepted constraint | Container writable layer, `emptyDir`, or memory-backed `emptyDir` | Pod restart; node, zone, and cluster recovery depend on the storage class and topology |

A Docker named volume is normally host-local, not replicated storage. A
Kubernetes `PersistentVolumeClaim` is a lifecycle and attachment abstraction,
not a durability guarantee by itself. Local PersistentVolumes, network block
volumes, replicated filesystems, and managed storage classes have different
failure domains and performance characteristics.

Cadence will describe journal durability using storage capabilities rather than
deployment labels. The capability profile must state whether committed data is
expected to survive:

- a Cadence process crash;
- a container or pod replacement;
- a host or Kubernetes node loss;
- an availability-zone loss; and
- loss of the backing volume itself.

The fastest initial server profile may use a dedicated local NVMe volume. Docker
Compose may map the same filesystem contract onto a host bind mount or named
volume. Kubernetes may map it onto a PersistentVolumeClaim. Every supported
profile must be benchmarked with its actual filesystem, mount options, storage
class, and synchronization semantics; performance measured on local NVMe cannot
be attributed to an arbitrary Kubernetes volume.

The ordinary filesystem page cache may provide memory-speed buffering while the
journal retains a durable-storage contract.

A RAM disk is not the default design because it:

- is lost with a node or power failure;
- competes directly with the BEAM for memory;
- can turn burst pressure into node-wide memory pressure; and
- does not by itself provide stronger semantics than a bounded in-memory queue.

The precise acknowledgment policy remains an explicit durability choice. A
writer may group commits by byte count or a short time interval, but it must
document whether acknowledgment means:

- copied into the Cadence process;
- accepted by the operating-system page cache; or
- made durable with an `fdatasync`/equivalent boundary.

Cadence must not describe page-cache acceptance as power-loss durability.

### 4. Consumers Use Durable, Monotonic Cursors

Each journal consumer owns a monotonically increasing committed offset per
stream epoch.

The first expected consumers are:

- **processing**, which frames, dispatches, decommutates, and completes the
  downstream effects required by its processing contract; and
- **archive export**, which makes a sealed segment discoverable in the
  canonical long-term raw archive.

The processing cursor advances only after the required downstream work is safe
to retry or durably complete. Decoding a frame is not sufficient acknowledgment
if a crash would lose all of its required outputs.

ADR-019 defines how those outputs declare required, replayable asynchronous, or
best-effort completion and forbids one generic persistence acknowledgement from
standing in for all three. Raw archive export and semantic processing retain
independent cursors even when an implementation temporarily co-locates their
workers.

The archive cursor advances only after the destination object and its discovery
metadata are both complete. If the local journal itself becomes the canonical
raw archive, Cadence may eliminate the separate archive-export cursor, but only
after defining retention, replay, and node-loss behavior for that design.

Cursor persistence must not introduce a synchronous Postgres write for every
read block. The implementation may use journal-local checkpoints, batched
durable cursor updates, or another measured mechanism, provided recovery remains
correct.

### 5. Reclamation Is Segment-Based And Fail-Safe

The reclaimer may delete only sealed segments whose end offset is less than or
equal to every cursor required by the configured retention policy.

Reclamation must be:

- segment-based rather than byte-by-byte;
- idempotent across restarts;
- blocked by an unhealthy required consumer;
- observable; and
- unable to delete the active writer segment.

A poisoned input must not pin the journal forever without explanation. The
processing contract needs bounded retry, durable anomaly evidence, and an
operator-visible quarantine or skip decision. The raw bytes must remain in the
canonical archive even when semantic processing cannot continue normally.

### 6. Processing Is At-Least-Once And Idempotent

Consumer recovery is at-least-once. Cadence will not claim exactly-once
processing across the journal, runtime state, Postgres, filesystem archive, and
telemetry history backends.

Records derived from journaled input need deterministic identities based on
stable provenance such as:

```text
stream epoch + absolute byte range + decoded record index or content identity
```

Downstream unique constraints, idempotent writes, and cursor ordering must make
reprocessing safe after a consumer crashes between applying effects and
committing its cursor.

### 7. Framing Consumes Byte Blocks And Emits Record Batches

The processing consumer will read up to a configured byte-block size and pass
the bytes plus its prior framing remainder to the protocol decoder.

The decoder may emit zero, one, or many complete frames. Downstream runtime work
will preserve the order of frames and packets required by the owning endpoint
partition.

Frame provenance must use absolute stream offsets. A frame that begins in one
read block or segment and ends in another must still point to its complete
captured byte range. Offsets relative only to the most recent decoder input are
not sufficient.

Streaming and record-oriented transports have different capture contracts:

- TCP-like streams preserve ordered byte offsets but not socket-read
  boundaries; and
- UDP datagrams, provider-native messages, and delivered objects must retain
  their original record boundaries and loss/gap evidence.

The journal must not flatten meaningful datagram or object boundaries into an
indistinguishable byte stream.

### 8. Ownership Remains Path-Local And Semantics Remain Partition-Owned

The active journal writer is path- and provider-session-local, consistent with
ADR-006 and ADR-012. Simultaneous downlink paths retain independent capture
truth and must not be combined in the journal.

The journal does not move telemetry meaning into the provider adapter. Provider
adapters still own external I/O, while endpoint partitions continue to own
framing continuity, selector resolution, packet meaning, managed applications,
derived telemetry, and limits.

If a stream is handed from a path-local journal to an endpoint partition, that
handoff must preserve ordered exclusive ownership of the processing cursor.

### 9. Deployment Lifecycle Does Not Change Journal Semantics

Every deployment profile must preserve one active writer per path, provider
session, and stream epoch. Process placement, container recreation, or pod
rescheduling must not permit two writers to append conflicting bytes to the
same journal epoch.

Ownership needs an explicit fencing mechanism. On an orderly handoff, the old
owner stops capture, synchronizes and seals its active segment, checkpoints
required state, and releases ownership before the new owner recovers. After an
abrupt failure, the replacement owner must recover the durable tail and acquire
a newer fencing generation before it appends. A new provider connection may
start a new stream epoch, but it must not conceal an unexplained gap in the
previous epoch.

Deployment integration must apply these lifecycle rules:

- Cadence is not ready to accept ingress until the volume is available, journal
  recovery has completed, exclusive ownership is held, and free capacity is
  above the configured start threshold.
- Backlog, provider backpressure, and a temporarily slow consumer are health
  signals; they must not automatically fail a liveness probe and create a
  restart loop.
- Graceful shutdown pauses or closes ingress, synchronizes the active segment,
  and checkpoints cursors within the available termination grace period.
- Abrupt termination remains a tested recovery case. Correctness must not depend
  on Docker or Kubernetes always delivering a graceful shutdown.

Deployment-specific requirements are:

- **Server:** the service manager starts Cadence only after the configured
  journal mount is available and does not silently fall back to a root
  filesystem directory.
- **Docker Compose:** the Compose definition uses an explicit named volume or
  bind mount, preserves it across container replacement, and provisions stable
  ownership and permissions.
- **Kubernetes:** the workload and volume topology enforce single-writer
  attachment, preserve the claim across pod replacement, define reclaim policy
  intentionally, provide adequate termination grace, and account for pod
  disruption, node drain, volume detach/reattach time, and storage throttling.

Kubernetes does not require a distinct journal implementation. A StatefulSet
may be appropriate when stable identity and per-replica claims are useful, but
this ADR does not require one before the runtime ownership and failover model is
proven. The invariant is stable recoverable storage plus fenced single-writer
ownership, not a particular Kubernetes workload kind.

### 10. Full-Journal Behavior Is Explicit

The journal is finite. Capacity exhaustion is an operational state, not an
exception to hide.

Cadence will expose high and low watermarks based on:

- bytes used and free;
- oldest unprocessed and unarchived age;
- capture rate;
- processing and archive rates; and
- estimated time to exhaustion.

When a reliable stream can be slowed, Cadence pauses reads and reports
backpressure before exhausting the journal. When a source cannot be slowed,
Cadence records a visible gap or loss condition and raises an operational alarm.
It must not silently overwrite unacknowledged segments.

The final policy may allow an operator to prioritize raw capture, live semantic
processing, or availability for a specific mission. Such policy must be
explicit, scoped, and auditable rather than inferred by the reclaimer.

### 11. Observability Is Part Of The Contract

The journal must report at least:

- captured bytes and current capture bitrate;
- append and durable-commit latency;
- open and sealed segment counts;
- bytes used, free, and reclaimable;
- per-consumer committed offset, lag bytes, and lag time;
- consumer processing rate and estimated catch-up time;
- checksum, torn-tail, and recovery events;
- backpressure entry and release;
- full-journal and source-gap events; and
- segment reclamation success and failure.

Metrics must also identify the configured durability profile and backing-volume
topology without exposing credentials or provider secrets. Kubernetes
ephemeral-storage pressure, PVC attachment problems, filesystem read-only
transitions, and storage throttling must be distinguishable from semantic
processing lag.

Existing provider, executor, projector, and archive metrics remain useful during
comparison. Journal metrics must distinguish capture health from processing
health so operators can see that bytes are safe even when live products are
late.

During the ADR-019 migration, generic projector metrics must be decomposed into
per-sink batch size, dwell time, write duration, retry state, lag, and oldest
uncommitted age. Per-entry metric-event writes are not an observability
mechanism.

## Validation Program

Cadence will not accept this ADR until the journal proves materially better than
the simpler alternatives under representative workloads.

The deployment-neutral workload, byte-ledger, metric, fault-injection,
environment-adapter, and result-artifact contracts are defined in the
[Telemetry Ingress Evaluation Harness](../telemetry-ingress-evaluation-harness.md).
That follow-on document defines how evidence is produced; the acceptance gates
in this ADR remain authoritative.

### 1. Establish The Current Baseline

Use the existing ingress profiler and standalone simulator sink benchmark to
measure, for the same traffic shape:

- provider/simulator maximum wire rate;
- current fixed-message Cadence throughput;
- executor and projector queue depth and age;
- archive queue depth, flush latency, and segment size;
- scheduler utilization, reductions, heap growth, garbage collection, and
  binary memory; and
- CPU, disk, and database utilization.

The benchmark corpus must include realistic frame sizes, packet multiplicity,
decom definitions, and managed-application work. A dumb byte sink is necessary
for source capacity but is not evidence of full Cadence throughput.

### 2. Isolate The Batching Hypothesis

Before adding a journal, compare the current fixed-message path with a path that
feeds larger byte chunks into the existing stateful TM decoder.

At minimum, test configurable read-block sizes such as:

- 64 KiB;
- 256 KiB;
- 1 MiB; and
- 4 MiB.

Measure whether the improvement comes from fewer executor messages, fewer
`RawEvidence` allocations, less tracing overhead, fewer persistence items, or a
different bottleneck. This experiment determines how much of the throughput
problem can be solved without a journal.

### 3. Prove Capture And Catch-Up

The initial stress target for the motivating scenario is:

- capture 1 Gb/s for ten minutes;
- intentionally cap semantic processing at 500 Mb/s during the burst;
- preserve a contiguous journal offset range with no unexplained holes;
- keep BEAM memory bounded while the journal grows on disk;
- resume at or above the measured sustainable processing rate; and
- catch up without restarting or corrupting framing continuity.

The target may change when a real mission burst envelope is known, but every
accepted target must state input rate, processing rate, duration, required
capacity, and safety margin.

The storage benchmark must include simultaneous journal append, processing
read, archive export, cursor commit, and segment reclamation. Sequential write
throughput measured in isolation is insufficient.

### 4. Prove Failure Recovery

Inject failures at the following boundaries:

- writer crash before and after a durable commit;
- process and node restart with an open segment;
- torn or truncated active-segment tail;
- checksum failure in a sealed segment;
- processing crash before effects, after effects, and before cursor commit;
- archive destination outage and recovery;
- cursor checkpoint loss or stale checkpoint replay;
- disk-full and low-free-space transitions;
- reclaimer crash during deletion; and
- provider disconnect and reconnect into a new stream epoch.

Each test must produce a defined result: recovered bytes, safely retried work,
quarantined corruption, or an explicit source gap. Silent loss is a failure.

### 5. Prove Protocol And Provenance Correctness

The correctness suite must cover:

- multiple frames in one read block;
- one frame split across read blocks;
- one frame split across journal segments;
- packet reassembly across multiple frames;
- an incomplete final tail;
- malformed bytes and resynchronization policy;
- frame and packet absolute byte provenance;
- deterministic identities on replay;
- duplicate processing after a cursor-recovery rollback;
- separate simultaneous path journals; and
- preservation of datagram or provider-message boundaries where applicable.

### 6. Compare Operational Cost

The prototype must be compared with:

- current TCP backpressure and in-memory queues;
- batching without a journal;
- a larger bounded in-memory queue;
- the existing filesystem ingress archive moved earlier in the path;
- direct object-store capture; and
- an external durable log such as Kafka or Pulsar.

The comparison must include implementation complexity, operational dependencies,
recovery behavior, storage amplification, node affinity, observability,
deployment portability, and the failure domain introduced by each supported
volume profile.

### 7. Prove Deployment Portability

The same journal conformance corpus must pass when Cadence runs:

- as a server process against a provisioned filesystem directory;
- in Docker Compose against an explicit persistent volume; and
- in Kubernetes against at least one documented PersistentVolumeClaim storage
  class.

The conformance corpus must prove identical segment decoding, checksums,
absolute offsets, cursor recovery, and derived record identities across all
three environments.

Lifecycle tests must include:

- server process kill and restart, plus machine reboot where the target profile
  claims reboot durability;
- Docker container kill, replacement, and Compose recreation without deleting
  the declared volume;
- Kubernetes pod deletion and replacement on the same claim;
- Kubernetes graceful termination and forced termination;
- volume detach and reattach or node drain where the storage profile claims
  rescheduling durability;
- rejection of a second active writer or stale fencing generation; and
- storage latency, throughput throttling, read-only remount, and capacity
  pressure.

Performance qualification is per storage profile. Passing on a bare-server NVMe
volume does not qualify a Docker host volume or Kubernetes storage class, and
passing the correctness corpus does not by itself prove the 1 Gb/s stress
target.

## Acceptance Criteria

This ADR may move from Proposed to Accepted only when all of the following are
true:

1. A measured mission or platform requirement defines the burst envelope the
   journal must absorb.
2. Batching-only results are known and separated from journal results.
3. The prototype sustains the target capture rate with documented CPU, memory,
   disk, and database headroom.
4. BEAM heap and mailbox growth remain bounded while backlog accumulates.
5. Offset accounting proves no silent byte loss in the passing stress and fault
   scenarios.
6. Frames crossing blocks and segments retain correct absolute provenance.
7. Processing restart is idempotent under at-least-once delivery.
8. Archive outage, disk pressure, and journal exhaustion have explicit tested
   behavior.
9. The implementation has a capacity model and operational alert thresholds.
10. The same journal format and recovery contract pass on a server, in Docker
    Compose, and in Kubernetes.
11. Deployment configuration and documentation distinguish ephemeral storage,
    host-persistent storage, reattachable storage, and replicated storage without
    overstating their failure guarantees.
12. Kubernetes pod replacement and stale-writer fencing pass against at least
    one supported PersistentVolumeClaim profile.
13. In a no-anomaly full-flow corpus, data-plane Postgres work scales with
    segment/checkpoint batches and sparse facts rather than journal entries,
    frames, packets, or telemetry samples, as required by ADR-019.
14. The benefit justifies the added durable-state ownership and recovery
    complexity compared with batching and backpressure alone.

Failure to meet these criteria means Cadence will either retain the current
backpressure model, adopt batching without a journal, or evaluate another
durable-log implementation. The ADR is not accepted merely because a prototype
can write 1 Gb/s to an otherwise idle disk.

## Alternatives Considered

### Keep The Current Backpressure Chain

This remains the simplest correct design for reliable sources that can slow down
without losing data. It does not provide Cadence-owned burst retention when the
external source cannot honor backpressure.

### Batch Before The Existing Executor Without A Journal

This may raise the sustainable processing rate substantially and should be
tested first. It does not preserve volatile in-flight bytes across a crash or
absorb a burst beyond bounded memory and upstream buffering.

### Use A Larger In-Memory Queue Or RAM Disk

This is simpler than durable recovery but keeps the failure domain in node
memory and can endanger the BEAM under pressure. It is acceptable only if the
requirement is explicitly process-local smoothing rather than recoverable
capture.

### Move The Existing Ingress Archive Earlier

Reusing the archive abstraction is attractive, but its current contract accepts
interpreted `RawEvidence`, buffers in memory, writes compressed segment objects,
and maintains per-evidence discovery metadata. It would require a different
upstream capture contract, cursor semantics, and crash model. The implementation
may share storage code, but the journal and archive responsibilities should not
be conflated by name alone.

### Write Directly To Object Storage

Object storage is a strong long-term raw archive but normally has higher and more
variable commit latency than a local sequential log. Multipart or batched upload
also leaves an interval that still needs local buffering and recovery semantics.

### Adopt Kafka, Pulsar, Or Another External Durable Log

An external log already provides segments, cursors, replication, and retention.
It also adds a major operational dependency and may duplicate Cadence's
path-local ownership and archive model. It should be reconsidered if local-disk
failover, multi-node consumer ownership, or replicated capture becomes a proven
requirement that a small journal cannot satisfy safely.

### Build Different Journals For Each Deployment Environment

Separate server, Docker Compose, and Kubernetes journal implementations could
optimize for each platform, but they would create multiple segment formats,
recovery paths, and correctness surfaces. Cadence will instead begin with one
filesystem-oriented journal contract and qualify multiple backing-volume
profiles. A distinct storage implementation is justified only when a required
environment cannot satisfy that contract and the alternative passes the same
conformance suite.

## Consequences If Accepted

### Positive

- Raw telemetry can be made safe before expensive interpretation.
- Bounded bursts no longer require the semantic pipeline to match instantaneous
  capture rate.
- Processing and archive consumers can recover independently.
- Corrupt or unsupported input remains available for forensic analysis.
- Larger framing batches can reduce per-frame runtime overhead.
- Capture health and product latency become separately observable.
- The journal has one portable recovery model across supported deployment
  environments.

### Negative

- Cadence gains a new durable local-state owner and recovery protocol.
- Backing-volume topology creates explicit host, node, zone, and failover
  concerns.
- Cursor and downstream idempotency semantics become first-class contracts.
- Storage is temporarily amplified while journal and archive copies overlap.
- Operators must size, monitor, and alarm on finite journal capacity.
- Live products may be delayed even while raw capture remains healthy.
- Each supported Docker volume and Kubernetes storage profile requires both
  correctness and performance qualification.

### Constraints Introduced

- Journal segments are immutable after sealing.
- No segment is reclaimed before its required durable cursors pass it.
- Provider/path capture identity is preserved independently for every downlink
  contribution.
- Protocol records carry stable absolute provenance into captured bytes.
- Consumer effects tolerate at-least-once replay.
- Journal-full behavior is explicit and never silently overwrites required data.
- A RAM disk cannot be described as durable capture.
- Container writable layers, `emptyDir`, and other ephemeral volumes cannot be
  described as recoverable capture.
- Every deployment preserves fenced single-writer ownership.
- Segment format, cursor semantics, and recovery behavior remain portable across
  server, Docker Compose, and Kubernetes operation.

## Current Evaluation Sequence

1. Completed: capture reproducible current-path and dumb-sink baselines.
2. Completed: identify the synchronous projector snapshot and per-frame
   persistence amplification as the measured current-path ceiling.
3. Implemented in the candidate: batch TCP reads through the existing TM
   framing kernel and preserve absolute byte provenance.
4. Implemented in the candidate: path-local journal segments, recovery,
   cursor checkpoints, bounded admission, reclamation, admitted-byte and append
   latency metrics, and live Grafana capture panels.
5. Completed: run the updated tmpfs-isolated 500 Mb/s and 1 Gb/s full-flow
   profiles; the journal preserved and drained admitted bytes, while the runs
   exposed semantic-path saturation and per-entry Postgres write amplification.
6. Completed in the candidate: separate raw-archive custody from semantic
   processing, remove no-op database amplification, and qualify explicit
   archive batching and receipts under both load profiles.
7. Completed in the candidate: normalize arbitrary TCP receives into bounded
   256 KiB capture records, admit each receive as a subrecord batch, and repeat
   both profiles. The 1 Gb/s run captured all 18.75 GB with 2.31 MB peak
   processing lag, 7.89% peak journal utilization, and no full events.
8. Run the journal conformance corpus on a server, in Docker Compose, and in
   Kubernetes against a documented PersistentVolumeClaim profile.
9. Run capture/catch-up, replay, and fault-injection proofs with the rollout
   control enabled only in the test deployment.
10. Qualify performance separately for each supported backing-volume profile.
11. Compare results against batching-only and current backpressure behavior.
12. Revisit this ADR with evidence and either accept, revise, or reject it
    before enabling the journal by default.

## Open Questions

1. What real mission burst rate and duration should define the first supported
   capture envelope?
2. Which durability acknowledgment class is required for flight operations?
3. Should the journal volume become the first tier of the canonical raw archive,
   or remain a transient spool exported into the existing archive?
4. How should journal ownership and fencing fail over when a runtime partition
   moves to another process, container, pod, or node?
5. Must the first version replicate capture synchronously, or is the selected
   host/PersistentVolume durability plus provider recovery sufficient?
6. Which downstream effects must complete before the processing cursor advances?
7. How should operator-authorized quarantine and skip decisions be represented?
8. What encryption-at-rest and secure-erasure requirements apply to local raw
   telemetry segments?
9. Should one stream epoch align with a provider connection, a realized contact,
   or an explicit provider delivery session?
10. At what measured scale does an external replicated log become simpler than
    maintaining a Cadence-owned journal?
11. Which durability profiles are product-supported by Cadence, and which are
    customer-qualified deployment choices?
12. Which Kubernetes storage classes and access modes can satisfy both the
    fencing semantics and target capture throughput?
13. Does Kubernetes failover eventually require journal-aware placement or a
    dedicated capture service independent of the main Cadence workload?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-005: Runtime Partitioning and Workload Isolation](005-runtime-partitioning-and-workload-isolation.md)
- [ADR-006: Contact, Link, and Transport Runtime Model](006-contact-link-and-transport-runtime-model.md)
- [ADR-012: Provider Adapter and Ground Station Simulator Model](012-provider-adapter-and-ground-station-simulator-model.md)
- [ADR-015: Management Plane, Control Plane, and Data Plane Architecture](015-management-control-data-plane-architecture.md)
- [ADR-019: Telemetry Data-Plane Persistence and Projection Topology](019-telemetry-data-plane-persistence-and-projection-topology.md)
- [Developer Architecture Guide](../developer-architecture-guide.md)
- [Telemetry Ingress Evaluation Harness](../telemetry-ingress-evaluation-harness.md)
- [Profile Cadence Telemetry Ingress](../how-to/profile-cadence-telemetry-ingress.md)
- [Archive Backlog and Backpressure](../how-to/archive-backlog-and-backpressure.md)
- [Benchmark Simulator Throughput Against a Dumb Sink](../how-to/benchmark-simulator-throughput.md)
