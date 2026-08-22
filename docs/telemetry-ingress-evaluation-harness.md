---
title: Telemetry Ingress Evaluation Harness
tags: [design, telemetry, ingress, benchmarking, observability, reliability, testing]
status: draft
created: 2026-07-30
updated: 2026-07-30
---

# Telemetry Ingress Evaluation Harness

> Status: **draft / proposed.** This document defines the measurement and test
> infrastructure needed to evaluate telemetry-ingress batching and the
> capture-first journal proposed by
> [ADR-018](decisions/018-capture-first-telemetry-ingress-journal.md). It does not
> claim that the complete harness or metric set exists today, and it does not
> accept the journal design by itself.

## 1. Purpose

Cadence needs repeatable evidence that distinguishes four different questions:

1. How many bytes can a source place on the wire?
2. How many bytes can Cadence receive and, when applicable, durably capture?
3. How quickly can Cadence frame, interpret, dispatch, and persist those bytes?
4. Did every stage preserve the expected bytes, ordering, provenance, and
   outputs across normal operation and failure recovery?

The current profiler, simulator, drain sink, and OpenTelemetry stack provide a
useful foundation. They are not yet sufficient to prove byte custody, durable
capture, exact backlog, deterministic replay, or storage behavior under the
burst and recovery scenarios in ADR-018.

This document defines:

- a deployment-neutral workload and result contract;
- the byte and cursor invariants every run must evaluate;
- the application, BEAM, storage, and platform measurements required;
- low-overhead observability rules for a high-rate data path;
- deterministic traffic and correctness oracles;
- fault-injection boundaries and expected evidence;
- adapters for server, Docker Compose, and Kubernetes execution; and
- the sequence in which measurement readiness, batching, and journaling should
  be evaluated.

## 2. Decision Boundary

This harness supports the decision in ADR-018; it does not replace it.

ADR-018 remains authoritative for:

- the proposed journal and consumer model;
- durability and fencing requirements;
- required failure behavior;
- deployment portability;
- the motivating burst envelope; and
- acceptance or rejection of the architecture.

This document is authoritative only for how evidence should be produced and
reported. Passing a subset of its scenarios is not enough to accept ADR-018.
The full ADR acceptance criteria still apply.

## 3. Existing Foundation

Cadence already has several useful measurement surfaces:

- [`Cadence.Telemetry.Profiler`](../apps/cadence/lib/cadence/telemetry/profiler.ex)
  maintains hot-path counters for raw bytes, ingress results, stage timings,
  database work, and archive activity.
- [`mix cadence.profile`](../apps/cadence/lib/mix/tasks/cadence.profile.ex)
  samples a running Cadence node and reports ingress, packet, sample, database,
  and archive rates.
- [`Cadence.Observability.Metrics.Catalog`](../apps/cadence/lib/cadence/observability/metrics/catalog.ex)
  exports bounded OTLP metrics for ingress results, processing duration,
  backpressure, executor and projector queue depth, persistence, BEAM memory,
  and exporter health.
- [`Cadence.Observability.Metrics.RuntimeSampler`](../apps/cadence/lib/cadence/observability/metrics/runtime_sampler.ex)
  periodically samples BEAM and runtime state.
- [`CadenceSimulator.SimulatorMetrics`](../apps/cadence_simulator/lib/cadence_simulator/simulator_metrics.ex)
  counts generated and transmitted bytes and supports sampled stage timings.
- [`CadenceSimulator.DrainSink`](../apps/cadence_simulator/lib/cadence_simulator/drain_sink.ex)
  counts bytes and chunks received by a receiver with no Cadence processing.
- The [local observability stack](how-to/local-observability-stack.md) routes
  OTLP metrics, logs, and traces into GreptimeDB, Loki, Tempo, and Grafana.

These surfaces now answer whether the source and current semantic path are
saturated, including socket-boundary bytes, executor byte/age backlog, semantic
outputs, and BEAM pressure. Important limitations remain:

- a socket receive counter proves bytes accepted by Cadence's operating system,
  not bytes the spacecraft or upstream provider attempted to send;
- the executable full-flow profile uses non-retaining counting archive adapters
  and therefore does not qualify durable custody, recovery, or replay;
- the local collector receives application OTLP but does not collect host,
  filesystem, block-device, container, or Kubernetes metrics;
- the first full-flow profile uses fixed 62,500-byte TM frames containing one
  packet each and does not represent every mission's framing distribution;
- durable ingress-latency history still needs a metrics-history reader; the
  dashboard retains its operational-event reader only for pre-ADR-019 rows; and
- run orchestration still needs a wrapper that extracts the bounded JSON result
  line before deleting the tmpfs-backed Compose project.

The first harness milestone is to close these measurement gaps on the current
path. A journal prototype should not be responsible for inventing its own
baseline after it exists.

## 4. Principles

### 4.1 Measure Byte Custody Directly

Rates and queue depths are not proof of lossless capture. Every run must track
absolute byte progress from a deterministic source range through each custody
boundary.

### 4.2 Separate Capture From Processing

Capture rate, processing rate, archive rate, and catch-up rate are different
signals. The harness must not label delayed semantic products as lost when the
bytes are durably captured, or label bytes as safe merely because the processor
is keeping up.

### 4.3 Keep Measurement Overhead Bounded

Exact high-rate counters should use counters or atomics on the hot path and be
sampled periodically into OTLP. Full per-frame traces, logs, or reporter
messages can become the workload being measured and are not the default for
qualification runs.

### 4.4 Use One Evidence Contract Across Deployments

The traffic corpus, scenario, byte invariants, metric meanings, and result
schema remain the same on a server, in Docker Compose, and in Kubernetes.
Platform adapters may differ only in orchestration, lifecycle actions, and
resource collection.

### 4.5 Make Every Result Reproducible

Every reported number must be tied to source revision, configuration, traffic
corpus, random seed, deployment topology, hardware, storage profile,
observability mode, and run phase.

### 4.6 Keep Correctness And Performance Both Mandatory

A fast run with unexplained byte gaps fails. A correct run that cannot meet the
target envelope also fails performance qualification. Neither result substitutes
for the other.

## 5. Evaluation Topology

The logical topology is:

```text
                         +----------------------+
scenario + corpus -----> | workload controller  |
                         +----------+-----------+
                                    |
                           phase and fault control
                                    |
                                    v
+---------------+       +-----------+----------+       +----------------+
| traffic driver | ----> | Cadence ingress path | ----> | output oracle  |
+-------+-------+       +-----------+----------+       +--------+-------+
        |                           |                           |
 source counters       app/BEAM/storage metrics        output identities
        |                           |                           |
        +---------------------------+---------------------------+
                                    |
                                    v
                         +----------------------+
                         | result artifact      |
                         +----------------------+
```

The workload controller is a test role, not a required production service. It
coordinates phases and collects evidence without owning any Cadence runtime
state.

For qualification runs, the traffic driver should not share the constrained
CPU, memory, or storage resources assigned to Cadence. A colocated driver is
acceptable for smoke tests only, and the result must say that it was colocated.

## 6. Canonical Run Model

Each evaluation is one immutable run with one globally unique `run_id`. A run
contains one or more named phases:

1. `prepare` verifies configuration, storage capacity, and source reachability;
2. `warmup` establishes connections, caches, and steady runtime state;
3. `measure` applies the declared traffic schedule and records qualification
   statistics;
4. `fault` applies an optional declared failure while measurement continues;
5. `recover` observes restart, replay, or catch-up behavior;
6. `drain` stops new traffic and allows bounded consumers to catch up; and
7. `verify` freezes cursors and evaluates byte and output invariants.

Not every scenario needs every phase, but phases must never be inferred only
from wall-clock timestamps. The controller records explicit phase transitions
into the result stream.

Durations measured within one process use monotonic time. Cross-host wall time
is useful for correlation but is not the primary source for append, commit, or
processing latency. Hosts must still use a documented clock-synchronization
method when source-to-receiver wall-clock latency is reported.

### 6.1 Run Manifest

Before traffic begins, the controller writes a manifest equivalent to:

```yaml
schema_version: 1
run_id: 2026-07-30T18-42-00Z-batching-256k-01
scenario: batching_steady_state
variant: batching_only
source_revision: <git-sha>
deployment:
  kind: server # server | compose | kubernetes
  topology: driver_remote_cadence_single_node
  cadence_instances: 1
  containers: # laptop_tmpfs only; every overlay service is listed
    source:
      memory_limit_bytes: <hard-limit>
    sink:
      memory_limit_bytes: <hard-limit>
storage:
  profile: server_local_nvme
  filesystem: <reported-filesystem>
  mount_options: <reported-options>
  max_bytes: <hard-limit>
  tmpfs_mounts: [] # laptop_tmpfs only: [{path: ..., max_bytes: ...}]
  component_tmpfs_paths: {} # optional role -> paths subset for multi-container profiles
traffic:
  corpus_id: tm-realistic-v1
  corpus_sha256: <sha256>
  seed: 381746
  minimum_rate_ratio: 0.99
  block_size_bytes: 262144
  phases:
    - name: warmup
      duration_seconds: 30
      target_bps: 500000000
    - name: measure
      duration_seconds: 120
      target_bps: 750000000
observability:
  mode: metrics_sampled_traces
  metric_sample_interval_ms: 1000
  trace_sampling_policy: <declared-policy>
processing:
  target_cap_bps: null
safety:
  max_source_bytes: <hard-limit>
  max_wall_clock_seconds: <hard-limit>
  max_artifact_bytes: <hard-limit>
  docker_memory_budget_bytes: <hard-limit> # laptop_tmpfs only
  docker_overhead_bytes: <reserved-budget> # laptop_tmpfs only
  process_headroom_bytes: <reserved-per-process> # laptop_tmpfs only
```

The exact serialization may evolve, but the semantic fields are required. The
manifest records intended settings; the result artifact separately records
observed rates and effective runtime configuration.

The source-byte, wall-clock, and artifact limits are mandatory for every run.
For `laptop_tmpfs`, the Docker memory budget, Docker overhead reserve,
per-process headroom, and memory limit of every Compose service are mandatory as
well. The controller computes maximum source bytes and validates storage plus
memory budgets before starting a workload. It rejects a run that can exceed any
declared limit. Runtime timeouts remain a secondary guard; they do not replace
the byte or memory budgets.

When a multi-container profile declares `component_tmpfs_paths`, each runnable
role validates only the bounded mounts it owns while the profile preflight
validates the complete storage declaration. This prevents a traffic source from
being assigned the memory budget for a Cadence-only ingress journal.

The first executable laptop profile lives in
[`dev/ingress-benchmark/compose.laptop-tmpfs.yaml`](../dev/ingress-benchmark/compose.laptop-tmpfs.yaml)
and uses
[`laptop-tmpfs-manifest.yaml`](../dev/ingress-benchmark/laptop-tmpfs-manifest.yaml).
Render and inspect the merged configuration before building anything:

```bash
docker compose \
  -f docker-compose.yml \
  -f dev/ingress-benchmark/compose.laptop-tmpfs.yaml \
  config
```

The preflight role reads the manifest and `/proc/self/mountinfo`, prints a JSON
report, and performs no benchmark writes or network traffic:

```bash
docker compose \
  -f docker-compose.yml \
  -f dev/ingress-benchmark/compose.laptop-tmpfs.yaml \
  --profile ingress-preflight \
  run --rm ingress_preflight
```

The `ingress-source-capacity` profile contains a paced deterministic TCP source
and a byte-validating sink. It is intentionally a small, non-qualifying smoke
scenario. Do not run it until the preflight report passes and the effective
Compose configuration contains no host `./var` mounts for enabled services.

### 6.2 Live Grafana Monitoring

Grafana provisions **Cadence / Ingress Load Test** from
[`cadence-ingress-load-test.json`](../dev/grafana/provisioning/dashboards/json/cadence-ingress-load-test.json).
It compares receive and processed byte rates with an editable target, then
shows receive distributions, byte backlog and age, backpressure, processing and
persistence latency, semantic output, BEAM pressure, and metric-export health.

When running on a laptop, include the same Compose overlay while starting the
observability services. It replaces GreptimeDB, Tempo, Loki, and Grafana data
directories with size-capped tmpfs mounts, so the test cannot write telemetry
history into host `./var` paths. Dashboard annotations should mark explicit
phase transitions from the run manifest.

The source-capacity smoke sends only to the validating sink and therefore does
not populate Cadence ingress metrics. The dashboard becomes an acceptance
artifact when the source targets a real Cadence ingress endpoint with OTLP
metrics enabled.

The executable semantic-path profile lives in
[`compose.full-flow-tmpfs.yaml`](../dev/ingress-benchmark/compose.full-flow-tmpfs.yaml)
with the exact workload in
[`full-flow-500mbps-manifest.yaml`](../dev/ingress-benchmark/full-flow-500mbps-manifest.yaml).
It starts an isolated source, Cadence, PostgreSQL, metrics-only collector,
GreptimeDB, and Grafana. Every mutable data directory is a size-capped tmpfs;
the only published port is Grafana on `3300`; all bind mounts are read-only.
Its container limits total 6.5 GiB inside an 8,394,457,088-byte Docker budget,
leaving a 768 MiB Docker overhead reserve.

This profile exercises the production TCP provider, fixed-message framer, TM
decoder, ingress executor, persistence projector, profiler, and operational
event store. It replaces the two payload archives with counting ACK adapters
that retain no bytes. A passing result is therefore a semantic-path throughput
baseline, not evidence for ADR-018's durability decision.

The same full-flow profile now enables the ADR-018 validation candidate and
mounts `/benchmark/journal` as a size-capped tmpfs. TCP reads are captured as
checksummed journal entries before framing; the processing consumer may emit
many frames from one entry. Result invariants therefore distinguish wire-frame
counts from journal-entry counts, require both journal cursors to reach the
planned byte total, and report peak retained bytes, consumer lag, and journal
utilization. The tmpfs profile qualifies throughput and boundedness only. It
does not qualify process-, host-, or node-loss durability.

### 6.2.1 First 500 Mb/s Semantic-Path Baseline

On 2026-07-30, the laptop tmpfs profile completed a 150-second measure phase at
500,000,000 bits per second:

| Signal | Observed result |
| --- | ---: |
| Source bytes accepted by TCP | 9,375,000,000 |
| Source blocks / TM frames | 150,000 |
| Source measure duration | 150.000313 s |
| Cadence active receive duration | 149.729 s |
| Cadence observed receive rate | 500,904,968 bit/s |
| Cadence TCP reads | 72,146 |
| Average TCP read size | 129,944.8 bytes |
| Peak sampled executor backlog | 17 frames / 1,062,500 bytes |
| Peak sampled persistence backlog | 17 frames |
| Executor failures | 0 |
| Persistence failures | 0 |
| TM frames / packets produced | 150,000 / 150,000 |
| Protocol anomalies | 0 |
| Queue drain after receive completion | 1 ms |
| Final BEAM memory | 80,283,047 bytes |

Every byte, framing, processing, persistence, counting-archive, packet, and
anomaly invariant passed. No sampled heartbeat observed paused reads. The
PostgreSQL container reached about 1.16 GiB of its 1.5 GiB memory limit, and its
1.25 GiB tmpfs reached 81% utilization before teardown. The final database was
443 MiB, of which the 150,001-row `operational_events` relation occupied 427
MiB. The profiler reported 150,000 inserts and 444,292 database queries, making
operational metric-event write amplification an explicit follow-up measurement
target.

The run also exposed an observability contract defect: Cadence exported
counters and histograms with delta temporality while Grafana applied Prometheus
`rate()` and histogram-rate queries that require cumulative series. The metric
reporter now retains bounded series and exports cumulative sums and histograms;
regression tests lock that contract. The queue-depth and BEAM series from the
run were present and matched the runner, but its throughput chart must not be
used as the authoritative rate for this pre-fix run.

A confirmatory 500 Mb/s run after that fix again processed all 9.375 GB and
150,000 frames with every invariant passing. Cadence observed 501,152,651
bit/s. Across thirteen interior 60-second dashboard samples, receive throughput
ranged from 499,965,542 to 500,799,990 bit/s with a 500,073,388 bit/s average;
processed throughput averaged 500,085,441 bit/s. This agreement between
absolute provider bytes and the dashboard closes the metric-temporality finding.

### 6.2.2 First 1 Gb/s Saturation Probe

The 1 Gb/s profile doubles the logical traffic to 18.75 GB and 300,000 frames
over the same 150-second target. It uses the same Docker memory budget but
reallocates limits to a 1.25 GiB Cadence container, 3 GiB PostgreSQL container,
and 2.5 GiB PostgreSQL tmpfs. The complete profile is
[`full-flow-1gbps-manifest.yaml`](../dev/ingress-benchmark/full-flow-1gbps-manifest.yaml).
Use its checked-in Compose environment file so those limits and the manifest
cannot drift apart:

```bash
docker compose \
  --env-file dev/ingress-benchmark/full-flow-1gbps.env \
  -f dev/ingress-benchmark/compose.full-flow-tmpfs.yaml \
  --profile preflight run --rm preflight
```

Only start the remaining services after this preflight passes.

The first attempt revealed that the source regenerated 62,488 bytes of
SHA-derived packet data for every frame. It transferred all bytes in 183.9
seconds, limiting the attempted workload before Cadence could be isolated. The
corpus generator now reuses the immutable packet-data body and changes only the
TM and packet counters; a 1.875 GB local generation-and-hash check measured
15.2 Gb/s. The attempt also revealed that byte completeness alone could produce
a false passing result after the target duration. Both the source and Cadence
runner now require at least `traffic.minimum_rate_ratio`, set to `0.99` in the
checked-in profiles.

The authoritative optimized-source run produced this result:

| Signal | Observed result |
| --- | ---: |
| Source / Cadence bytes | 18,750,000,000 / 18,750,000,000 |
| Source blocks / TM frames / packets | 300,000 / 300,000 / 300,000 |
| Source transfer duration | 180.437455 s |
| Cadence active receive duration | 180.714 s |
| Cadence observed receive rate | 830,040,838 bit/s |
| Minimum acceptable receive rate | 990,000,000 bit/s |
| Peak sampled executor backlog | 17 frames / 1,062,500 bytes |
| Peak sampled persistence backlog | 17 frames |
| Executor / persistence failures | 0 / 0 |
| Protocol anomalies | 0 |
| Queue drain after receive completion | 3 ms |

This run **failed performance qualification** because
`receive_target_rate_met` was false. Every byte-custody and semantic correctness
invariant passed. During the sustained section, the optimized source used about
7% CPU while Cadence used about one full CPU core and both bounded queues stayed
near 16-17 frames, identifying the current semantic path rather than source
generation as the limiting boundary on this machine. PostgreSQL reached about
1.97 GiB memory; its tmpfs reached 73%. The final 836 MiB database contained a
300,001-row, 820 MiB `operational_events` relation. The result remains a
non-durable, co-located laptop baseline rather than a deployment-independent
capacity claim.

### 6.2.3 Capture-First 500 Mb/s And 1 Gb/s Runs

On 2026-07-31, the page-cache journal candidate completed the 500 Mb/s profile
and then ran the 1 Gb/s saturation probe in the bounded laptop Compose profile.

The 500 Mb/s run passed every result invariant:

| Signal | Observed result |
| --- | ---: |
| Source / Cadence bytes | 9,375,000,000 / 9,375,000,000 |
| Source / Cadence receive rate | 500,001,463 / 497,614,767 bit/s |
| TM frames / packets | 150,000 / 150,000 |
| Journal entries | 102,634 |
| Peak retained journal bytes | 801,856,539 |
| Peak processing/archive lag | 749,312,500 bytes |
| Peak journal utilization | 84.97% |
| Journal-full events | 0 |
| Post-receive drain | 5.077 s |
| Executor / projector failures | 0 / 0 |

Both consumers acknowledged the complete absolute byte range and finished at
zero lag. This qualifies the candidate for the checked-in 500 Mb/s laptop
scenario, but the 85% peak shows that the 900 MiB logical journal has limited
headroom for additional burst mismatch even at that rate.

The same passing run exposed a downstream architecture failure. The profiler
recorded 307,902 Ecto Repo commands for 102,634 journal entries:

| Classified operation | Count |
| --- | ---: |
| `INSERT` | 102,634 |
| `SELECT` / `UPDATE` / `DELETE` | 0 |
| other | 205,268 |

The `other` operations were the transaction boundaries around each effective
projector batch, giving one `BEGIN`, one `operational_events` upsert, and one
`COMMIT` per journal entry. The inserted event was a per-result
`ingress.processing_latency_ms` observation. Because the benchmark used
counting archive acknowledgements, a no-op telemetry-history writer, and ETS
current values, this isolated the operational-event write amplification rather
than an archive or telemetry-history cost.

This result accepts the storage-class and sink-boundary correction in
[ADR-019](decisions/019-telemetry-data-plane-persistence-and-projection-topology.md).
The passing throughput result remains valid for the measured candidate, but its
database behavior is not an acceptable production persistence architecture.
The next comparison must produce zero per-entry operational-event inserts for
the no-anomaly corpus and report intentional per-sink batch sizes.

The 1 Gb/s run failed before the 150-second traffic phase completed. The
journal repeatedly approached its admission limit, socket reads paused, and
the source hit its five-second send timeout:

| Signal | Observed result |
| --- | ---: |
| Planned source bytes | 18,750,000,000 |
| Source transport-accepted bytes | 8,557,000,000 |
| Cadence received bytes | 8,556,959,932 |
| Source effective accepted rate | 851,764,242 bit/s |
| Minimum acceptable rate | 990,000,000 bit/s |
| Peak sampled journal utilization | 99.995% |
| Journal-full count | 1 |
| Source failure | `{:send_failed, :timeout}` |
| Container OOM events | 0 |

Cadence drained every admitted journal byte to zero consumer lag with no
executor or projector failure, but it could not receive the planned range and
exited at the wall-clock fuse. The result demonstrates the journal's intended
behavior: it absorbs a bounded mismatch and then converts sustained overload
into transport backpressure. It does not increase the throughput of the
semantic processing and persistence path behind it.

The run also exposed three harness issues. Component-specific tmpfs ownership
was required so the source did not budget Cadence's 1 GiB journal. Grafana's
service default, two `_ratio` metric names, and the SRE overview's unscoped
label query were corrected and verified through Grafana with live range-query
responses. Finally, the Cadence runner raises at its receive fuse instead of
emitting a structured failed result. A follow-up should preserve the partial
byte ledger, peak journal state, and failed invariants in the result artifact;
the dashboard should also distinguish journal/socket admission pauses from
projector queue backpressure.

### 6.2.4 ADR-019 Hot-Path Correction Comparison

On 2026-07-31, the same bounded tmpfs profiles were repeated after the first
ADR-019 migration slice removed per-result ingress-latency operational events
and skipped empty Postgres transactions. The profiler observed zero Repo
commands for both no-anomaly, no-telemetry-history workloads.

| Signal | 500 Mb/s result | 1 Gb/s result |
| --- | ---: | ---: |
| Source / Cadence bytes | 9,375,000,000 / 9,375,000,000 | 18,750,000,000 / 18,750,000,000 |
| Source accepted rate | 499,999,260 bit/s | 999,994,393 bit/s |
| Cadence receive rate | 501,082,338 bit/s | 1,003,868,239 bit/s |
| TM frames / packets | 150,000 / 150,000 | 300,000 / 300,000 |
| Journal entries | 106,575 | 127,163 |
| Repo commands | 0 | 0 |
| Peak projector depth | 1 | 1 |
| Peak retained journal bytes | 500,299,415 | 943,194,971 |
| Peak processing lag | 447,863,128 bytes | 905,437,500 bytes |
| Peak journal utilization | 53.01% | 99.94% |
| Journal-full events | 0 | 45 |
| Post-receive drain | 2 ms | 1 ms |
| Executor / projector failures | 0 / 0 | 0 / 0 |

Every byte-custody and semantic correctness invariant passed in both runs. The
500 Mb/s comparison reduced the prior 307,902 Repo commands to zero, peak
journal utilization from 84.97% to 53.01%, and post-receive drain from 5.077
seconds to 2 milliseconds. This confirms that the operational-event write was
the measured downstream persistence bottleneck rather than required telemetry
history or archive work.

The corrected path also crossed the 1 Gb/s acceptance threshold on the same
laptop profile where the prior run stopped after 8.557 GB at about 852 Mb/s.
That result is still marginal rather than a general 1 Gb/s capacity claim: the
900 MiB journal reached 99.94% utilization and reported 45 journal-full
admission events before recovering. It has effectively no additional burst or
scheduling headroom at this rate. The next optimization should measure and
separate journal processing, raw-archive export, and protocol-archive sink lag
rather than reintroducing per-entry database work.

### 6.2.5 Independent Raw Archive Consumer And Bounded Dwell

The next ADR-019 slice moved raw archival out of semantic persistence and onto
an independent journal consumer. Archive batches carry deterministic journal
ranges, the consumer advances only its archive cursor after an explicit
completion receipt, and failures retain the same batch for ordered retry. A
25 ms maximum dwell intentionally coalesces shallow queues while entry-count
and byte thresholds cap each batch.

The first 500 Mb/s run without dwell passed, but persisted 105,858 journal
entries in 71,856 archive batches, only 1.47 entries per batch. That was a
coordination success and a batching failure. Repeating the checked-in 150-second
profiles after adding bounded dwell produced:

| Signal | 500 Mb/s result | 1 Gb/s result |
| --- | ---: | ---: |
| Source / Cadence bytes | 9,375,000,000 / 9,375,000,000 | 18,750,000,000 / 18,750,000,000 |
| Source accepted rate | 499,999,783 bit/s | 999,998,040 bit/s |
| Cadence receive rate | 499,108,260 bit/s | 1,004,251,331 bit/s |
| TM frames / packets | 150,000 / 150,000 | 300,000 / 300,000 |
| Journal entries | 112,997 | 114,379 |
| Raw-archive batches | 5,140 | 4,221 |
| Average entries per archive batch | 21.98 | 27.10 |
| Repo commands | 0 | 0 |
| Peak processing lag | 812,500 bytes | 916,649,616 bytes |
| Peak archive lag | 2,125,000 bytes | 607,943,256 bytes |
| Peak retained journal bytes | 73,789,456 | 943,204,274 |
| Peak journal utilization | 7.82% | 99.95% |
| Journal-full events | 0 | 98 |
| Archive failures | 0 | 0 |
| Post-receive drain | 6 ms | 1 ms |

All byte-custody, framing, semantic-processing, cursor, archive, and anomaly
invariants passed. At 500 Mb/s, bounded dwell reduced archive operations by
92.8% relative to the initial independent-consumer run while both consumer
lags remained below 2.2 MB. This qualifies the topology and intentional batch
formation for the laptop profile.

At 1 Gb/s, a transient stalled both consumers and brought the 900 MiB journal
to 99.95% utilization. The transport entered its bounded read-pause behavior,
then both cursors recovered and drained immediately after receive completion.
The result proves correct recovery and backpressure, but it remains marginal:
the profile has effectively no scheduling or burst headroom at 1 Gb/s.

Both load runs used ephemeral counting archives, reported
`durable_storage_qualified: false`, and kept every writable container path on a
size-capped tmpfs. Filesystem and Postgres archive adapters have focused
durability and idempotency tests, but their sustained storage throughput is not
qualified by these runs.

Grafana was verified through its provisioned API after the run. GreptimeDB
contained the raw-archive acknowledgement, attempt, batch-size, duration, and
queue series, and the live dashboard returned the corrected exported
`cadence_telemetry_ingress_archive_batch_size_bucket` query. This check caught
and corrected an earlier `_evidence_bucket` query that could never return data.

### 6.2.6 Bounded Capture Records And Receive-Boundary Decoupling

The next slice tested the hypothesis exposed by the marginal 1 Gb/s run: the
kernel's TCP receive size had become the journal record and semantic work size.
When a transient delay allowed the 1 MiB socket buffer to accumulate, later
`recv(0)` calls returned much larger binaries and expanded the amount of
framing, persistence, and cursor work completed before the next journal item.

The candidate now admits one received binary as a batch but writes it as
logical records no larger than 256 KiB. Admission accounts for every subrecord
before the first write, and `sync` durability performs one `fdatasync` after
the complete batch. Semantic processing consumes one logical record at a time;
the framer still emits every complete frame found in that block. Stable
absolute offsets and capture-batch identity preserve replay provenance.

The checked-in 150-second profiles produced:

| Signal | 500 Mb/s result | 1 Gb/s result |
| --- | ---: | ---: |
| Source / Cadence bytes | 9,375,000,000 / 9,375,000,000 | 18,750,000,000 / 18,750,000,000 |
| Cadence receive rate | 499,178,020 bit/s | 997,705,278 bit/s |
| TM frames / packets | 150,000 / 150,000 | 300,000 / 300,000 |
| TCP reads | 111,625 | 129,442 |
| Journal entries | 111,637 | 134,538 |
| Largest capture record | 262,144 bytes | 262,144 bytes |
| Largest semantic work item | 262,144 bytes | 262,144 bytes |
| Peak processing lag | 812,500 bytes | 2,312,500 bytes |
| Peak archive lag | 2,187,500 bytes | 5,562,500 bytes |
| Peak retained journal bytes | 72,381,385 | 74,472,215 |
| Peak journal utilization | 7.67% | 7.89% |
| Journal-full events | 0 | 0 |
| Repo commands | 0 | 0 |
| Post-receive drain | 1 ms | 1 ms |

Every byte-custody, framing, semantic-processing, cursor, archive, boundedness,
and anomaly invariant passed. At 1 Gb/s, peak processing lag fell roughly
396-fold from 916,649,616 bytes, and the 98 prior journal-full events fell to
zero. The result is also direct evidence that a transport batch can exceed the
logical record bound: 129,442 TCP reads became 134,538 journal records.

Grafana's provisioned dashboard API exposed the new "TCP receive and
capture-record size" panel, and its GreptimeDB datasource returned live series
for `cadence_telemetry_ingress_journal_record_size_bytes_bucket`. Immediately
after the run, the two-minute p99s were about 846,371 bytes for TCP receive
size and 258,855 bytes for capture-record size. Thus `TCP_NODELAY` and kernel
coalescing remain transport concerns without controlling the semantic
processing quantum.

As with the earlier runs, both profiles used ephemeral counting archives and
reported `durable_storage_qualified: false`. They qualify the bounded-record
topology and steady-state laptop profile, not persistent-volume throughput or
burst headroom beyond 1 Gb/s.

### 6.2.7 Async Cursor Checkpoint And Bounded Semantic Batching

The next 1.375 Gb/s probe first separated cursor durability from ordered
journal service. In the original candidate, cursor-file `fsync` ran inside the
journal GenServer; measured checkpoint work consumed 5.342 of 5.421 seconds of
maintenance time and produced a source timeout after 36 seconds. Cursor writes
now run in one monitored worker. The GenServer still serializes successful
durable-cursor publication and prefix reclamation, but it continues to admit
bytes and answer consumer reads while filesystem durability is pending.

With that stall removed, an unbatched run accepted all 25.78125 GB but took
157.073 seconds, or 1.313 Gb/s, below the 99% rate gate. Its 149,091 capture
records produced 149,091 semantic work items and 1,302 journal-full retries.
Per-item evidence reads, executor delivery, persistence completion, and cursor
acknowledgement remained proportional to capture-record count.

The candidate now preserves 256 KiB capture records as durability units while
combining at most eight compatible records and 2 MiB into a semantic work item.
The aggregate carries the complete byte range and the ordered set of physical
capture-batch identifiers. The TM framer emits all complete frames in that
bounded block, and cursor acknowledgement still occurs only after semantic
completion.

The identical 150-second rerun produced:

| Signal | Observed result |
| --- | ---: |
| Source / Cadence bytes | 25,781,250,000 / 25,781,250,000 |
| Source accepted rate | 1,374,994,766 bit/s |
| Cadence receive rate | 1,373,315,400 bit/s |
| TM frames / packets | 412,500 / 412,500 |
| Journal capture records | 157,053 |
| Semantic work items | 29,149 |
| Average records per semantic item | 5.39 |
| Maximum semantic batch | 8 records / 2,097,152 bytes |
| Journal-full retries | 147 |
| Final drain | 1 ms |
| Executor / projector / archive failures | 0 / 0 / 0 |
| Throughput and correctness gate | passed |

The source completed in 150.000571 seconds, effectively exact target rate.
Semantic batching reduced work-item coordination by 80.4% and preserved every
byte-custody, framing, cursor, archive, boundedness, and anomaly invariant.

The run still does not establish burst headroom. A late transient slowed socket
receive, semantic processing, raw archive, reductions, and garbage collection
together; the 900 MiB journal briefly reached 99.99% utilization before the
system recovered and exceeded target rate long enough to remain on schedule.
BEAM memory peaked near 129 MB during the interval, which excludes a BEAM heap
growth explanation but not cgroup or tmpfs page-cache pressure. The next probe
should add container memory-current, memory-limit, memory-event, and tmpfs
working-set series before selecting another runtime optimization.

### 6.3 Resource Attributes And Metric Dimensions

Run-level identity belongs in OpenTelemetry resource attributes and the run
manifest. It does not belong as an unbounded attribute on every metric
instrument.

Recommended run-scoped resource attributes include:

- `service.name` and `service.instance.id`;
- `deployment.environment.name`;
- `cadence.benchmark.run.id`;
- `cadence.benchmark.variant`;
- `cadence.source.revision`;
- `cadence.storage.profile`; and
- `cadence.deployment.kind`.

Metric dimensions remain bounded. Appropriate dimensions include direction,
protocol family, outcome, consumer role, queue role, and a finite state or
reason class. Mission, contact, provider, path, evidence, segment, and trace
identifiers belong in logs, traces, manifests, or result records rather than
high-cardinality metric series.

## 7. Deterministic Traffic Corpus

The harness needs a pregenerated, immutable corpus so source generation does not
become part of the receiver benchmark unless generation is the subject of the
test.

Each corpus declares:

- corpus identifier and content hash;
- total byte length;
- protocol family and managed framing configuration;
- frame sizes and distribution;
- packet multiplicity per frame;
- packet reassembly cases;
- catalog/runtime definition revision;
- expected frame, packet, anomaly, dispatch, work-item, and sample counts;
- expected absolute byte ranges for frames and packets;
- expected incomplete tail, if any; and
- whether the corpus may be repeated within one stream epoch.

The baseline corpus must be representative of the intended mission workload.
A single repeated empty frame may be useful for raw capture stress, but it is
not evidence of full semantic Cadence throughput.

The correctness corpus must deliberately include:

- multiple frames in one source block;
- frames split across source blocks;
- frames split at each candidate journal segment boundary;
- packet reassembly across frames;
- idle or fill data where supported;
- malformed data with a declared resynchronization outcome;
- an incomplete final tail; and
- at least two simultaneous path streams with independent identities.

### 7.1 Traffic Driver Contract

The driver must support:

- pregenerated file or memory-mapped corpus replay;
- declared block sizes independent of protocol frame size;
- rate pacing in bits per second, not only generation steps per second;
- ramp, steady-state, burst, pause, resume, and stop phases;
- deterministic reconnect at a declared source offset;
- optional repetition under explicitly distinct stream epochs;
- actual bytes accepted by the local transport API;
- send-operation duration and blocked-send time;
- connection and reconnect outcomes; and
- a final source-side range and checksum report.

The source report is evidence of attempted or locally accepted transmission. It
does not prove remote receipt or durable capture.

Before a Cadence qualification run, the same driver and traffic schedule must
be tested against the counted drain sink. If the driver cannot sustain the
target wire rate with headroom, the Cadence result is source-limited and cannot
qualify the receiver.

## 8. Byte Ledger And Invariants

Each stream is identified by a stable path-local stream identity and a stream
epoch. Within an epoch, offsets are unsigned absolute byte positions beginning
at zero.

The canonical ledger is:

```text
source attempted range
        >= transport accepted range
        >= Cadence socket-received range
        >= durable-capture range
        >= processing committed range
        >= archive committed range
```

The ordering describes possible progress, not permission to silently discard
the difference. Any final difference must be explained by a declared in-flight
state, source gap, failure policy, or incomplete tail.

Required per-stream observations are:

- `source_end_offset`: final byte offset offered by the source;
- `received_end_offset`: final contiguous byte offset read by Cadence;
- `durable_end_offset`: final contiguous offset past a successful durability
  boundary, when a journal is present;
- `processing_offset`: highest contiguous consumer offset committed after
  required semantic effects;
- `archive_offset`: highest contiguous archive consumer offset committed; and
- explicit gap or quarantined ranges with reason and evidence.

For the current non-journal baseline, `durable_end_offset` is absent rather than
inferred from downstream archive success.

Every run evaluates at least these invariants:

1. Offsets are monotonic within a stream epoch.
2. No consumer offset exceeds the available received or durable offset.
3. Every byte below `durable_end_offset` is readable after the failure model
   claimed by the selected durability profile.
4. Consumer lag equals available end offset minus consumer offset.
5. Every non-empty gap has a recorded cause and declared policy outcome.
6. Frame and packet provenance ranges are within the source epoch and reproduce
   on replay.
7. Expected output identities are neither missing nor duplicated after replay,
   except where an explicitly tested at-least-once boundary exposes a duplicate
   that downstream idempotency must absorb.
8. Cursor recovery never skips an uncommitted range.

The result artifact contains the evaluated values and a pass/fail record for
each invariant. A dashboard screenshot is not a substitute for this record.

## 9. Application Metric Contract

Metric names below are the proposed semantic contract. Final implementation
names should follow the conventions already used by
`Cadence.Observability.Metrics.Catalog`, but changes to spelling must not change
the meanings.

### 9.1 Receive Boundary

| Metric | Type | Unit | Meaning |
| --- | --- | --- | --- |
| `cadence.telemetry.ingress.received` | counter | `By` | Bytes returned by the Cadence transport receive operation |
| `cadence.telemetry.ingress.receive.operation.duration` | histogram | `s` | Time spent in each receive operation |
| `cadence.telemetry.ingress.receive.size` | histogram | `By` | Bytes returned per receive operation |
| `cadence.telemetry.ingress.stream.started` | counter | `{stream}` | New stream epochs started by bounded reason class |
| `cadence.telemetry.ingress.stream.ended` | counter | `{stream}` | Stream epochs ended by bounded reason class |
| `cadence.telemetry.ingress.source_gap` | counter | `{gap}` | Explicit source gaps or discarded ranges by reason class |

Receive counters must be recorded before conversion into `RawEvidence` or
executor items. They establish the baseline for work Cadence actually accepted
from the transport.

### 9.2 Current Processing Path

The existing evidence, frame, packet, sample, anomaly, processing-duration,
backpressure, queue-depth, persistence, and database metrics remain required.
The baseline adds:

| Metric | Type | Unit | Meaning |
| --- | --- | --- | --- |
| `cadence.telemetry.ingress.processed` | counter | `By` | Raw bytes successfully handed through semantic processing |
| `cadence.telemetry.ingress.queue.size` | gauge | `By` | Raw bytes represented by the executor queue |
| `cadence.telemetry.ingress.queue.oldest.age` | gauge | `s` | Age of the oldest executor item |
| `cadence.telemetry.ingress.batch.size` | histogram | `By` | Raw bytes represented by each processing batch |
| `cadence.telemetry.ingress.batch.item.count` | histogram | `{item}` | Evidence or frame items represented by each batch |

Resolve, framing/runtime, sample extraction, dispatch, current-value recording,
and persistence need distributions or sampled distributions in addition to
cumulative averages. Averages alone cannot show queueing or storage tail
latency.

### 9.3 Journal Capture

The current validation candidate exports:

| Metric | Type | Unit | Meaning |
| --- | --- | --- | --- |
| `cadence.telemetry.ingress.journal.appended` | counter | `By` | Bytes admitted through the configured page-cache or `fdatasync` boundary |
| `cadence.telemetry.ingress.journal.append.duration` | histogram | `s` | End-to-end append duration through that boundary |
| `cadence.telemetry.ingress.journal.record.size` | histogram | `By` | Payload bytes in each bounded logical capture record |
| `cadence.telemetry.ingress.journal.capacity.exhaustion` | counter | `{event}` | Admissions rejected because the bounded journal is full |
| `cadence.telemetry.ingress.journal.reclaimed` | counter | `By` | Segment bytes reclaimed after every required durable cursor advanced |
| `cadence.telemetry.ingress.journal.retained` | gauge | `By` | Bytes occupied by active journal segments |
| `cadence.telemetry.ingress.journal.capacity` | gauge | `By` | Configured aggregate journal capacity |
| `cadence.telemetry.ingress.journal.utilization` | gauge | `1` | Largest retained-to-capacity ratio among active journals |

The `durability` dimension is bounded to `sync` or `page_cache`. In `sync` mode,
a successful stream append writes all bounded subrecords and then includes one
`fdatasync`; in `page_cache` mode it is explicitly volatile. The append metric
therefore describes the admitted transport batch, while record-size describes
the logical records it published. Before acceptance, add separate
append-versus-durable-commit counters if commit becomes asynchronous, plus
filesystem-free, reclaimable-byte, and open/sealed-segment measurements.

### 9.4 Journal Consumers And Recovery

| Metric | Type | Unit | Meaning |
| --- | --- | --- | --- |
| `cadence.telemetry.ingress.journal.lag` | gauge | `By` | Sum of journal-tail minus cursor offset by bounded consumer role |
| `cadence.telemetry.journal.consumer.lag.time` | gauge | `s` | Maximum age of the oldest unconsumed byte range by consumer role |
| `cadence.telemetry.journal.consumer.processed` | counter | `By` | Bytes consumed by processor or archiver |
| `cadence.telemetry.journal.consumer.batch.size` | histogram | `By` | Bytes read in a consumer batch |
| `cadence.telemetry.journal.consumer.catch_up.estimate` | gauge | `s` | Estimated time to consume current lag at observed rate |
| `cadence.telemetry.journal.cursor.commit.duration` | histogram | `s` | Durable cursor commit duration |
| `cadence.telemetry.journal.recovery` | counter | `{event}` | Recovery outcomes by bounded type |
| `cadence.telemetry.journal.checksum.failure` | counter | `{failure}` | Checksum failures by segment state |
| `cadence.telemetry.journal.torn_tail` | counter | `{event}` | Torn or truncated active-tail detections and outcomes |
| `cadence.telemetry.journal.reclamation` | counter | `{segment}` | Segment reclamation outcomes |

Consumer role is a finite value such as `processor` or `archiver`. Segment ID,
cursor generation, and byte range belong in correlated logs or result records,
not metric attributes.

Exact offsets are per-stream state and do not aggregate meaningfully across
independent journals. They must be available in bounded runtime snapshots and
the byte-ledger result record. The OTLP gauges expose aggregate lag and maximum
lag age for alerting without turning path or stream identity into an unbounded
metric dimension.

## 10. BEAM And Process Measurements

The existing aggregate BEAM memory and run-queue measurements remain useful.
Qualification runs additionally require:

- scheduler utilization over each phase;
- total and interval reductions;
- garbage-collection count, reclaimed words, and observable pause duration;
- total, process, binary, ETS, and system memory;
- process count and port count;
- executor, projector, journal writer, consumer, and archive mailbox length;
- heap and total-memory growth for those path-local workers;
- runnable process and port queues; and
- observable process restarts or supervisor churn.

Per-process measurements should be sampled periodically by known worker role.
They must not add process identifiers as durable metric dimensions. The result
artifact may retain the transient PID and registry identity for forensic use.

The primary memory gate is bounded growth while backlog grows on disk. A run
fails if BEAM heap, binary memory, or mailbox depth grows approximately with
the entire unprocessed byte backlog rather than the configured in-memory
window.

## 11. Host, Storage, And Platform Measurements

Application metrics cannot explain storage saturation alone. Every qualified
run records:

- host or node CPU utilization, load, and steal time where available;
- process or container CPU and throttling;
- resident memory, swap activity, and memory pressure;
- network bytes, packets, errors, drops, retransmissions, and socket pressure;
- filesystem capacity, inode use, and read-only transitions;
- block-device read/write throughput and operation rate;
- block-device latency, queue depth, utilization, and throttling;
- Postgres and time-series-store CPU, I/O, pool, and query pressure; and
- the observability collector and backends' resource use when colocated.

The journal mount or volume must be identifiable without relying only on a
device name that changes across deployments. The run manifest records the
logical storage profile and the platform adapter resolves it to the observed
mount, volume, device, or storage class.

Storage qualification includes simultaneous:

- journal append and durable commit;
- processor reads;
- archive reads or export;
- cursor commits;
- segment reclamation; and
- observability writes when the stack shares the same storage system.

Sequential write throughput against an otherwise idle filesystem is diagnostic
data, not qualification evidence.

## 12. Observability Modes And Measurement Tax

Every performance scenario is run under declared observability modes:

| Mode | Metrics | Traces | Logs | Purpose |
| --- | --- | --- | --- | --- |
| `minimal` | exact local counters only | off | failures only | Establish the lowest-overhead reference |
| `metrics` | periodic OTLP metrics | off | failures only | Measure production metric cost |
| `sampled_traces` | periodic OTLP metrics | explicitly sampled | failures and declared phase events | Diagnose representative latency |
| `diagnostic` | expanded sampling | expanded but bounded | expanded but bounded | Short, non-qualification investigation |

Full per-evidence tracing is not a qualification default. The current ingress
path creates producer, consumer, stage, and persistence spans. At high evidence
rates, those spans and their persistence links may materially change allocation,
mailbox, network, and backend behavior.

The harness reports the throughput, CPU, memory, and latency difference between
`minimal`, `metrics`, and `sampled_traces`. It also verifies:

- metric reporter queue occupancy;
- metric, log, and trace export failures;
- dropped metric data points or log records;
- collector and backend saturation; and
- whether sampling configuration actually took effect.

A performance number is invalid if the observability pipeline silently dropped
the measurements used to compute it.

## 13. Harness Components

The implementation should keep the following roles separate even if a local
smoke runner hosts several of them in one executable.

### 13.1 Scenario Controller

The controller:

- validates the manifest and selected adapter;
- records the effective configuration;
- starts and transitions run phases;
- directs rate changes and declared faults;
- observes readiness without treating liveness as readiness;
- records phase markers;
- waits for bounded drain and recovery conditions;
- gathers component reports; and
- evaluates final invariants.

### 13.2 Traffic Driver

The driver owns corpus replay, pacing, reconnect behavior, and source-side
counters. It never queries Cadence internals to decide that a byte was received.

### 13.3 Output Oracle

The oracle consumes result records or an exported verification stream and
checks expected identities, counts, byte provenance, gaps, duplicates, and
ordering. It must be able to compare the first processing pass with replay.

The dumb drain sink remains a source-capacity tool and is not used as the
semantic output oracle.

### 13.4 Measurement Collector

The collector gathers:

- periodic application snapshots;
- OTLP metric time series;
- bounded trace and log references;
- BEAM/process samples;
- platform resource samples; and
- component start, stop, and failure events.

It retains raw samples in the artifact so summary calculations can be audited.

### 13.5 Fault Adapter

The fault adapter performs only declared scenario actions. It records request,
acknowledgment, observed effect, and recovery timestamps separately. A requested
pod deletion is not considered injected until the old pod actually terminates,
for example.

### 13.6 Artifact Writer

The artifact writer produces an immutable bundle. It must finish even when the
run fails, while clearly marking missing or incomplete evidence.

## 14. Scenario Suite

### 14.1 Source Capacity

Run each source driver, corpus, block size, and traffic schedule against the
counted sink. Demonstrate target wire rate with documented headroom and without
source queue growth or send errors.

### 14.2 Current Fixed-Message Baseline

Measure the current production-shaped ingress path at a rate staircase that
crosses its sustainable limit. Record received and processed bytes, evidence
rate, executor and projector queues, archive behavior, stage latency, database
cost, BEAM saturation, and host resources.

### 14.3 Batching-Only Matrix

Run the same corpus and rate schedule using candidate read-block sizes of at
least:

- 64 KiB;
- 256 KiB;
- 1 MiB; and
- 4 MiB.

Measure allocations and executor messages per byte, frames per batch,
processing and persistence batch sizes, tail latency, throughput, and resource
cost. The comparison must isolate batching from journaling.

### 14.4 Capture And Catch-Up

For the motivating ADR scenario:

1. warm up at a sustainable rate;
2. deliver 1 Gb/s for ten minutes;
3. cap semantic processing at 500 Mb/s during the burst;
4. prove continuous durable capture and bounded BEAM memory;
5. release the processing cap;
6. measure catch-up rate and estimated versus actual catch-up time; and
7. verify final offsets, checksums, frame continuity, provenance, and outputs.

The processor cap must be a deterministic harness control on semantic work. It
must not indirectly slow socket receipt or journal append, and the result must
record observed rather than merely configured processing rate.

### 14.5 Storage Contention

Repeat capture and catch-up while journal write, processing read, archive
export, cursor commit, reclamation, database activity, and observability traffic
operate concurrently. Include latency and throughput throttling profiles.

### 14.6 Recovery And Idempotency

Exercise each ADR-018 failure boundary with deterministic fault timing. Verify
the declared recovered, retried, quarantined, or source-gap result and compare
outputs before and after replay.

### 14.7 Multiple Paths

Run at least two independent path journals simultaneously. Prove that offsets,
epochs, backpressure, consumer lag, recovery, and reclamation remain isolated.

### 14.8 Observability Overhead

Repeat a stable workload under each observability mode. Establish whether the
production-intended configuration changes sustainable throughput, tail latency,
or memory enough to affect the architectural decision.

## 15. Fault-Injection Contract

Every fault scenario specifies:

- injection boundary;
- trigger phase and source offset;
- preconditions;
- action;
- expected observable effect;
- expected byte/cursor state after recovery;
- allowed duplicate window;
- timeout; and
- required logs, metrics, and invariant results.

The minimum fault matrix is:

| Fault | Required outcome evidence |
| --- | --- |
| Writer crash before durable commit | Uncommitted tail is absent or recovered under the declared commit contract; cursor does not skip it |
| Writer crash after durable commit | Committed bytes recover and remain readable without a source gap |
| Process or node restart with open segment | Open segment is recovered, truncated, or quarantined exactly as specified |
| Torn active tail | Valid prefix is retained and the damaged suffix is reported explicitly |
| Sealed-segment checksum failure | Corruption is detected and quarantined or fails closed; it is never silently decoded |
| Processing crash before effects | Range is retried without advancing the cursor |
| Processing crash after effects but before cursor commit | At-least-once replay occurs and downstream identities remain idempotent |
| Archive outage | Capture policy remains explicit, archiver lag grows visibly, and recovery drains without silent loss |
| Cursor checkpoint loss or rollback | Replay begins from a safe earlier offset and does not skip work |
| Low space and disk full | Threshold and full policy activate before undefined filesystem failure |
| Read-only filesystem transition | Writer fails closed or applies the declared source policy with a visible event |
| Reclaimer crash | Referenced segments remain safe and reclamation resumes idempotently |
| Provider disconnect and reconnect | A new declared stream epoch begins without joining unrelated byte ranges |
| Container or pod replacement | Selected volume profile delivers exactly its documented recovery guarantee |
| Stale or second writer | Fencing prevents concurrent mutation and reports the rejected generation |

Fault success is not merely process survival. Each row must end with a byte and
cursor invariant result.

## 16. Deployment Adapters

### 16.1 Server Process

The server adapter supports:

- starting Cadence with explicit run resource attributes;
- resolving the provisioned journal directory and backing filesystem;
- process kill and restart;
- service restart;
- machine reboot when the durability profile claims reboot survival;
- host and process resource collection; and
- cleanup that refuses to delete a directory outside the declared run root.

### 16.2 Docker Compose

The Compose adapter supports:

- an explicit persistent journal volume or bind mount;
- container start, stop, kill, replacement, and Compose recreation;
- retention of the declared volume across replacement;
- container CPU, memory, network, and throttling measurements;
- host filesystem and block-device measurements for the volume; and
- verification that temporary container storage is not mistaken for the
  selected persistent profile.

### 16.3 Kubernetes

The Kubernetes adapter supports:

- an explicit PersistentVolumeClaim and recorded storage class/access mode;
- pod deletion, graceful termination, and forced termination;
- replacement against the same claim;
- node drain and volume detach/reattach when the storage profile claims it;
- readiness that stays false until journal recovery and fencing complete;
- stale-writer rejection;
- kubelet/container CPU, memory, network, and filesystem measurements;
- PVC capacity and available CSI or storage-provider latency/throttling metrics;
- pod scheduling, eviction, volume-attachment, and node-pressure events; and
- clear distinction between pod ephemeral-storage pressure and journal-volume
  pressure.

The Kubernetes adapter is not the canonical implementation of the harness. It
is one orchestration and resource-collection adapter behind the same scenario
and evidence contracts used by server and Compose runs.

### 16.4 Local Laptop Container Profile

Development on a personal laptop uses a dedicated, non-qualifying
`laptop_tmpfs` profile. Cadence, the traffic driver, the output oracle, and the
supporting observability services run in containers. Every high-volume writable
path uses an explicitly size-capped `tmpfs` mount rather than a host bind mount,
named volume, or container writable layer.

The protected paths include, when enabled:

- the ingress journal;
- filesystem ingress and protocol archives;
- generated-corpus scratch space;
- benchmark-mutated Postgres, QuestDB, or other history-store data;
- GreptimeDB, Loki, Tempo, and Grafana data;
- raw metric, trace, log, and result-sample staging; and
- any temporary decompression or replay workspace.

The repository's ordinary development Compose stack currently persists several
of these services under host `./var` directories. That configuration is not the
laptop benchmark profile. The profile must override those writable mounts with
size-capped `tmpfs` mounts before a workload starts.

Container logs can still consume host disk through the Docker logging driver
even when application paths use `tmpfs`. Laptop runs therefore use failure-only
application logging where practical and a bounded or disabled container log
sink. Only the small manifest, summary, invariant report, and explicitly
selected diagnostic excerpts may be copied to the host, and their combined
size must remain below `max_artifact_bytes`.

The controller preflight must verify:

- every declared high-volume path resolves to `tmpfs` inside its container;
- each mount has an explicit byte limit;
- each container has a compatible memory limit;
- the sum of mount limits, process headroom, and Docker overhead fits within the
  declared Docker Desktop memory budget;
- the traffic schedule fits within `max_source_bytes` and
  `max_wall_clock_seconds`;
- projected peak backlog plus format and observability amplification fits below
  the journal and service limits; and
- no fallback path points into the repository, a host `./var` directory, a
  named volume, or an unbounded container writable layer.

`tmpfs` protects the laptop disk but transfers pressure to memory. The harness
must treat memory pressure, swap activity, container OOM termination, and
Docker Desktop VM pressure as explicit abort conditions rather than allowing
the host to become unresponsive.

The ADR's motivating ten-minute scenario receives about 75 GB at 1 Gb/s and
builds about 37.5 GB of backlog while processing is capped at 500 Mb/s, before
format and observability overhead. It is not a laptop scenario. The
`laptop_tmpfs` profile runs scaled tests that preserve rate ratios, block and
segment boundary cases, cursor behavior, and fault ordering within a safe byte
budget.

This profile may prove instrumentation, harness orchestration, segment format,
checksums, cursor logic, replay behavior, and deterministic fault outcomes. It
cannot qualify disk throughput, durable-commit latency, reboot survival,
container-replacement persistence, or the full ADR burst target. Those require
explicitly provisioned qualification infrastructure.

## 17. Result Artifact

Every run produces a bundle equivalent to:

```text
run-manifest.yaml
effective-config.json
phase-events.jsonl
source-report.json
cadence-byte-ledger.json
output-oracle.json
metric-samples.jsonl
resource-samples.jsonl
fault-events.jsonl
trace-references.json
summary.json
```

`summary.json` contains:

- run status: `passed`, `failed`, or `incomplete`;
- observed source, receive, durable-capture, processing, and archive rates;
- p50, p95, p99, and maximum latency where supported;
- maximum and final lag by consumer;
- observed and predicted catch-up time;
- CPU, memory, scheduler, mailbox, storage, network, and database headroom;
- source, received, durable, processing, and archive offsets;
- expected and observed frame, packet, anomaly, and sample counts;
- every invariant and its evidence reference;
- every fault and its observed outcome;
- observability exporter drops or failures;
- comparison-baseline identifier; and
- reasons the run cannot be used for qualification.

Raw samples remain available so summary calculations can be reproduced. The
bundle may link to retained Grafana, GreptimeDB, Loki, or Tempo data, but those
external systems are not the only copy of the qualification result.

## 18. Analysis And Qualification Rules

Performance comparisons use the same corpus, schedule, runtime configuration,
semantic work, deployment resources, storage profile, and observability mode
unless the varied field is the subject of the experiment.

Each qualification point requires:

- a declared warmup period excluded from the primary result;
- a measurement period long enough to expose queues and periodic flushes;
- at least three usable repetitions unless the scenario is a destructive
  lifecycle test whose repetition policy is separately justified;
- reporting of every repetition rather than only the best result;
- median and range or another declared variability summary;
- zero unexplained byte gaps;
- no source limitation at the target rate;
- no metric or artifact loss that invalidates the conclusion; and
- explicit classification of saturation rather than an arbitrary timeout.

Rate thresholds alone are insufficient. A passing result must also satisfy the
scenario's latency, backlog, correctness, recovery, and resource-headroom gates.

Results qualify only the tested deployment and storage profile. A server NVMe
result does not qualify a Compose bind mount or Kubernetes storage class.

## 19. Implementation Sequence

### Phase 0: Measurement Readiness

Instrument the current path before changing its architecture:

- socket-boundary bytes and receive distributions;
- processed bytes;
- queue bytes and oldest age;
- stage latency distributions;
- missing BEAM/process samples;
- platform resource collection;
- benchmark run resource attributes and artifact schema; and
- the `laptop_tmpfs` safety preflight and hard run budgets.

Exit gate: the current path can produce a complete byte-ledger baseline except
for the intentionally absent durable journal offset.

### Phase 1: Deterministic Driver And Oracle

Build the pregenerated corpus driver, counted and validating sink, scenario
controller, output oracle, and artifact writer.

Exit gate: source-capacity, current-path smoke, and deliberate-corruption runs
produce deterministic pass and fail artifacts.

### Phase 2: Current Baseline And Batching

Run the fixed-message baseline and batching-only matrix. Identify the sustainable
rate and the reason for every plateau before journaling changes the path.

Exit gate: Cadence knows how much improvement comes from larger byte batches and
which bottleneck remains.

### Phase 3: Journal Prototype

Add journal capture, cursor, recovery, reclamation, and fencing metrics. Run
scaled capture/catch-up, correctness, and fault scenarios locally. Run the full
rate, storage-contention, and durability scenarios only on explicitly
provisioned qualification infrastructure.

Exit gate: the prototype meets or fails the ADR target with auditable byte and
resource evidence.

### Phase 4: Deployment Qualification

Run the same conformance corpus and required lifecycle scenarios through server,
Compose, and Kubernetes adapters. Qualify performance separately for each
supported storage profile.

Exit gate: ADR-018 has the portability evidence required for an acceptance
decision, or the unsupported profiles and failed criteria are explicit.

## 20. Harness Readiness Criteria

The evaluation harness is ready to produce architectural evidence when:

1. A deterministic source corpus and expected-output oracle exist.
2. Source, receive, processing, and optional durable/archive offsets are reported
   without inference across missing boundaries.
3. Exact counters remain stable under the target event rate.
4. Tail latency and resource samples cover the declared phases.
5. Metric and artifact loss is detectable.
6. The same scenario manifest runs through server, Compose, and Kubernetes
   adapters without changing semantic assertions.
7. Faults produce deterministic byte/cursor outcomes.
8. A failed invariant causes the run to fail even when throughput is high.
9. Result bundles can be compared without querying a still-running Cadence node.
10. Observability overhead is measured and declared.

## 21. Non-Goals

This document does not:

- select a journal implementation;
- define a production benchmark API exposed to customers;
- require Kubernetes for local development or server deployments;
- turn run IDs or domain identifiers into unbounded metric labels;
- make the observability backend part of the telemetry custody chain;
- treat source-side `send` success as proof of Cadence receipt;
- treat page-cache append as durable commit without the selected profile's
  durability boundary;
- qualify disk durability or the full burst target from the `laptop_tmpfs`
  profile; or
- accept ADR-018 based on an idle-disk write benchmark.

## 22. Related Documents

- [ADR-018: Capture-First Telemetry Ingress Journal](decisions/018-capture-first-telemetry-ingress-journal.md)
- [ADR-019: Telemetry Data-Plane Persistence and Projection Topology](decisions/019-telemetry-data-plane-persistence-and-projection-topology.md)
- [Profile Cadence Telemetry Ingress](how-to/profile-cadence-telemetry-ingress.md)
- [Benchmark Simulator Throughput Against a Dumb Sink](how-to/benchmark-simulator-throughput.md)
- [Archive Backlog and Backpressure](how-to/archive-backlog-and-backpressure.md)
- [Local Observability Stack](how-to/local-observability-stack.md)
- [BEAM-Native Improvement Inventory](how-to/beam-native-improvement-inventory.md)
