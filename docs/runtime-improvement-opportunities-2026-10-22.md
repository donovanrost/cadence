# Runtime improvement opportunities — 2026-10-22 UTC

Follow-up to the [model-copy fix and three-replica rehearsal](chaos-model-memory-2026-10-22.md).
The completed memory/durability/lab checkpoint is commit `6e117a41` on
`codex/fleet-model-memory`.

This is an investigation and proposed work order, not a claim that these remaining
issues have been fixed. Measurements use the same 500-spacecraft fixture and ten
live feeds. The generator was manually restarted after the failed rolling run;
that action is recovery between experiments, not successful continuous delivery.
The subsequent `20261022T053823Z-baseline` passed all 23 samples with three Ready
replicas, no freshness/errors/drops/regressions, and 30 intact archive objects.

## TCP follow-up — 2026-10-23

The [simulator reconnect fix and new rehearsal](chaos-tcp-reconnect-2026-10-23.md)
validate close detection and timed reconnect: eleven reconnects took 253–334 ms,
with no source drops or remaining `CLOSE_WAIT` sockets. Full application continuity
still failed: 28/47 freshness samples violated the limit and one semantic sequence
regressed. A receiving mission coordinator blocked on partition initialization
while its child replayed semantic history. Prioritize recovery/admission and
ownership fencing next; the table below retains the original measurements.

## Recovery isolation follow-up — 2026-10-23

The [asynchronous recovery change and rehearsal](chaos-async-recovery-2026-10-23.md)
remove replay from the coordinator's blocking path. A live coordinator answered
in 1.866 ms with five partition owners replaying concurrently. Startup and both
healthy three-replica baselines passed; the extended baseline audited 820 commits
without regressions. Memory remained below the earlier OOM range.

The subsequent rolling restart still failed: 25/49 freshness violations, maximum
age 66.86 s, and four durable sequence regressions across three feeds. Those feeds
then returned `semantic_runtime_replay_diverged`; other partitions kept processing.
Successful individual recoveries took 17.1–24.6 seconds, exceeding the freshness
budget even with a responsive coordinator. Six retired streams retained 86,970 B
past processing checkpoints, including 14,495 B past an archive checkpoint.

The current correctness priority is **ownership epochs, conditional predecessor
checks, and logical-stream journal handoff**. Existing warm owners must not accept
work based on stale local state. Then add verified replay checkpoints and bounded
timer queries, plus backoff/quarantine for deterministic recovery failures. A
separate sampled one-second coordinator timeout before owners existed showed
`gen_server.loop_wakeup`; profile that startup/hibernation cost alongside the
remaining full-specification copies.

All evidence and the failed database were retained. Cadence and synthetic traffic
were scaled to zero after diagnosis to stop repeated replay of divergent history.

## Ownership fencing follow-up — 2026-10-23

The [ownership fencing change and rehearsal](chaos-ownership-fencing-2026-10-23.md)
add durable epochs and conditional predecessor checks, with a PostgreSQL insert
fence. Stale writers recover before recomputing, and duplicate inputs retain the
current durable state. All ten partitions passed full deterministic replay; the
final audit covered 2,037 commits with no unfenced writes, broken predecessors,
regressed epochs, or incorrect heads.

The healthy three-replica baseline passed 68 samples and audited 1,124 commits.
The subsequent rolling restart retained a valid semantic history (zero
regressions across 1,707 commits), but failed 32/53 freshness samples, reaching
63.35 seconds. Individual recoveries took 10.82–34.92 seconds. Feed 2 then retried
`{:tm, {:unsupported_tm_sdu_kind, :vca_sdu}}` over 11,000 times with a 1,100-byte
frame remainder. Its semantic state replayed successfully. Investigate framing
at reconnection and failed-record handling before interpreting this as another
semantic ownership failure.

Logical-stream journal handoff remains a correctness priority: the retired
rollout pods retained 333,385 B beyond processing and 72,475 B beyond archive
checkpoints. Verified replay checkpoints and recovery-aware admission remain
necessary for the freshness budget. Projection acknowledgements and managed
capability side effects still need a separate transactional audit.

The rehearsal also exposed a lab capacity issue: retained PVCs occupied 55.6 GiB,
and disk pressure evicted the entire lab during an earlier extended baseline.
Unused build cache was reclaimed; no database, archive, journal, or failed run
was deleted. Recovery and the subsequent passing baseline used the same database.
Add guest-storage preflight and a retention policy that preserves verified
recovery points and evidence. Cadence and traffic were stopped after validation
to halt the protocol retry loop; supporting services and retained data remain.

## TM framing and retry follow-up — 2026-10-24

The [framing/retry fix and rehearsal](chaos-tm-framing-2026-10-23.md) reproduce
feed 2's VCA error from its retained journal. All 52 records are valid and decode
into 500 packets in order. Five-second ingress timeouts left owner work queued;
growing retries then fed overlapping byte ranges into a decoder retaining a
1,100-byte partial frame. Ingress now waits for a definitive response, retries
retain their original batch, exact journal retries reuse the last result, and
acknowledgement retries do not re-decode. Failures use capped backoff.

Startup and both healthy three-replica baselines passed. The rolling restart
reported zero framing errors, zero executor/consumer failures, and zero protocol
anomalies; all ten feeds recovered. Overall continuity still failed 13/52 samples
with a maximum age of 34.79 seconds. Successful owner recoveries took
6.08–23.41 seconds. The 1,223-commit rollout audit found no sequence regressions.

Prioritize verified replay checkpoints and recovery-aware traffic admission for
the freshness budget. Journal handoff remains a separate correctness blocker:
retired rollout pods retained 130,455 bytes beyond processing checkpoints and
28,990 bytes beyond archive checkpoints. No retained data was discarded.

## Durable checkpoint follow-up — 2026-10-24

The [checkpoint change and rehearsal](chaos-semantic-checkpoints-2026-10-24.md)
publish an integrity-checked checkpoint atomically with every fenced commit.
Initial recovery and warm-owner reacquisition restore that checkpoint and verify
only the suffix through the captured head. Full-history replay remains available
as an independent, read-only audit. Indexed timer metadata removes normal
telemetry inputs from timer recovery queries; cursors select the latest commit
per timer key. Missing or incompatible checkpoints require verified bootstrap.

On the same retained 1,598-commit history, initial checkpoint recovery took
2–23 ms rather than 2.73–11.84 seconds, and all 30 owners became ready in
19.21 rather than 69.00 seconds. The report retains failed extended baselines,
the host sleep interruption, and subsequent final-build validation separately.
These results do not certify continuous delivery. Logical-stream journal
handoff, recovery-aware admission, and transactional projection/side-effect
auditing remain priorities. Pending timer results can still grow with an
unacknowledged backlog; test that case separately from ordinary telemetry.

A final-build baseline also exposed 15-second database timeouts in
`ObservationIdentityStates.record_existing_state/2`, `upsert_state/2`, and
`record_envelopes/2` on a replica receiving six of ten streams. Checkpoint hits
replayed zero commits, but observation persistence failed and feed age reached
44.53 seconds. Profile transaction duration, pool waits, and per-observation
query volume before changing timeouts. Consider batched identity-state updates
while preserving canonical-selection, duplicate-counting, and retry semantics.
Include uneven contact distribution in the next capacity test.

The last preflight then encountered a PostgreSQL backend OOM at its 1 GiB cgroup
limit. PostgreSQL performed crash recovery while the Kubernetes container
restart count remained zero. Include database cgroup OOM counters and backend
crash logs in lab health gates, and budget connection/query concurrency alongside
memory. Rolling validation for the checkpoint change remains blocked by these
persistence failures; no fault was injected into the unhealthy final baseline.

The rehearsal also demonstrates the need for capacity preflight and storage
retention design. Reversible compression of two inactive QuestDB partitions
reclaimed about 19.5 GiB with identical complete CSV hashes before and after.
No historical rows, databases, archives, or journals were discarded.

## BEAM memory investigation — October 23, 2026, evening MDT

The checkpoint image was examined through its release RPC shell on one replica
with synthetic traffic stopped. The retained fixture still contains 500
spacecraft. A snapshot before explicitly warming ten source partitions measured
297.4 MiB of BEAM allocations and 540.4 MiB charged to the container. Immediately
after warm-up, those values were 447.3 and 748.2 MiB. These are distinct accounting
surfaces: container memory also includes allocator reservations, native memory,
code mappings and file-backed pages; it is not all live Elixir data. The post-warm
container statistics reported 660.6 MiB anonymous and 86.6 MiB file memory.

| Post-warm allocation | MiB |
| --- | ---: |
| Process heaps and process memory | 246.4 |
| Binary allocations | 83.8 |
| Loaded code | 72.3 |
| ETS | 5.8 |
| Other BEAM allocations | 39.0 |

The largest process groups were the mission coordinator (64.3 MiB), ten partition
owners (63.7 MiB combined), and their DynamicSupervisor (47.2 MiB). Diagnostic GC
of processes over 1 MiB reduced total BEAM memory to 405.5 MiB, but the partition
owners still occupied 63.6 MiB and the supervisor 56.7 MiB. Container memory did
not immediately fall. Forced GC is a diagnostic, not a proposed production fix;
timed background reconciliation also continued during these snapshots.

State was copied from one selected process at a time into a short-lived diagnostic
worker, which emitted only sizes and exited. This later inspection is excluded
from the baseline snapshots above. It confirmed:

- The fleet specification's flat copy size remains 62,359,784 B. Its binding set
  accounts for 58,048,288 B. Configurations repeated across 5,000 rules and 5,000
  instances account for 49,968,000 B, despite only ten distinct configurations
  totaling 49,968 B. Index immutable configurations by content/identity in the
  admitted runtime representation while preserving governed hashes.
- A one-source specification copies 4,342,232 B, including 2,490,728 B of fleet
  metadata. The sampled owner's semantic state was only 274,664 B. Narrowing
  metadata to the partition's needs should precede scaling active partitions.
- The supervisor retains 44,593,232 B of child specifications for ten children,
  approximately 4.46 MB each. Start children with compact immutable references
  and resolve the required specification during initialization, preserving
  restart correctness and generation identity.
- The 30-second reconciler rebuilds the binding set and runtime specification
  before the unchanged-generation check. A live sample found a single 60,290,264 B
  binary referenced by that reconciler. This is allocation churn to investigate,
  not proof of a permanent leak. Check durable identity and runtime liveness
  before materialization. The existing status projection also retrieves the
  entire specification to select six small fields.

A separate settled reconciler inspection found only 1,232 B of retained state;
targeted GC reduced its process allocation from 17,556,008 B to 4,064 B. This
supports avoiding repeated materialization and its leftover allocations, rather
than treating that process's entire heap as required persistent runtime state.

Binary ownership was deduplicated by binary address within each process. Raw
reference-size sums are invalid because many references point to the same
backing binary; even the deduplicated per-process totals overlap across processes.
ETS was small and `persistent_term` used about 1.05 MiB in this sample. The earlier
source-model indexing fix remains effective; the remaining costs are primarily
binding configuration, partition metadata, retained child arguments, and periodic
materialization. In this lab all three replicas load the mission and are explicitly
warmed for ten partitions each; adding replicas does not divide these fixed costs.

Evidence is retained under `var/chaos/checks/memory-pivot-*`, including pre/post-warm
snapshots, allocator statistics, binary ownership, targeted GC, and field sizes.
The diagnostic replica was stopped afterward. No production source, memory limit,
or traffic configuration was changed during this investigation.

## Original work order and measurements

| Priority | Opportunity | Evidence | Next change and acceptance check |
| --- | --- | --- | --- |
| P0 | Detect source disconnection and account for delivery honestly | The rolling restart produced 50 freshness failures in 70 samples; all ten captured source sockets were in `CLOSE_WAIT`. `SendBuffer` uses passive TCP, handles no socket-close message, reconnects after a send error, and counts a successful socket write as sent. | Add explicit close/error detection and bounded reconnect/backpressure. Define generated, queued, written, and receiver-admitted counters separately. Repeat rolling replacement and pod kill; verify reconnect time and compare receiver records with independently numbered inputs. Do not silently drop the failed buffer on reconnect. |
| P0 | Fence partition writers and make retired journals recoverable | Owners are registered locally. An already-running local owner is reused. `Store.commit_input` deduplicates the input ID but does not require an ownership epoch or expected prior state. Earlier DB partition and pod-kill runs durably recorded semantic sequence regressions; killed-pod journals retained unclaimed bytes. | Introduce durable ownership epochs and a conditional commit against the expected durable predecessor. Losing an epoch must stop writes. Claim/replay retained ingress by logical stream independently of pod UID. Test two writers, database isolation, kill during append/ack, and lease transfer. A stale owner must be rejected; replay must resume from the durable prefix. |
| P1 — small first step | Return an activation-status summary instead of the whole specification | The existing status projection copies **62,359,784 B** to select six fields whose combined copy size is **360 B**. Each coordinator currently occupies about 67.4 MB of process memory. | Add a small runtime observation API and use it in `ActivationStatus`. Keep a full-plan API for callers that truly need plans. A real message-copy regression should prove that repeated status reads do not transfer executable plans or bindings. |
| P1 | Normalize runtime binding configurations and narrow partition metadata | 5,000 rules plus 5,000 instances contain **49,968,000 B** of configuration copies, but just **ten distinct configurations totaling 49,968 B**. A one-source partition specification is **4,342,232 B**, of which **2,490,728 B** is fleet metadata. | Use unique configuration entries plus references in the admitted runtime representation. Preserve the governed binding hash and exact per-source selection. Define the metadata contract needed by capability initialization, then project only relevant metadata. Check mixed models, explicit capabilities, selector ordering, hashes, and copies across supervisor/owner boundaries. |
| P1 | Bound timer recovery and introduce verified replay checkpoints | The main replay cursor streams 100 rows, but `timer_cursors`, `pending_timer_results`, and `mark_timer_projected` use `Repo.all`. They retrieve ordinary telemetry inputs too. The observed 629 commits already occupy 46.7 MB on disk, with 10.7 MB of input terms, 17.2 MB of result terms, and 14.7 MB of state terms. | Add queryable input kind/timer identity and narrow indexed timer queries, then stream bounded results. Add validated checkpoints tied to runtime basis and commit watermark, with tail replay. Compare deterministic results before/after and test recovery after hours/days of history at increasing input rates. |
| P1 | Skip unchanged-generation materialization before loading the full model | Every replica has a 30-second safety poll. Three diagnostic reconciliations of the unchanged generation each issued **11 SQL queries** and consumed **22.4–23.2 million BEAM reductions** before returning the same applied observation. | Check durable activation identity and runtime liveness first. Cache immutable admitted data by activation and execution basis; invalidate on activation change, runtime loss, failed apply, or execution-contract change. Measure query count, CPU, allocation, and recovery correctness before adopting the cache. |

The quickest isolated memory improvement is the status-summary API. The larger
memory win is the runtime binding/configuration index. For safe continuous
delivery, source reconnection and fenced ownership/recovery take precedence over
raising traffic volume.

## Additional findings and limits

The normalized source-model table removes the previous 827 MiB message expansion,
but does not make memory independent of the number of distinct models. This lab
has one model shared by 500 spacecraft; heterogeneous fleets need separate capacity
measurements.

Ten live partition owners were distributed 3/4/3 across the replacement replicas.
Their measured process heaps totaled roughly 20.0/34.1/24.5 MB. The corresponding
partition supervisors occupied 21.1/25.3/21.1 MB. Startup arguments include the
partition specification, so shrinking that specification helps both owners and
the processes supervising them. These are snapshots, not a proven per-contact
memory slope. Source plans also occur both at the partition root and in its
single-entry source index, about 0.87 MB each; that is another bounded duplication
to assess after the larger metadata copy.

The storage observation covered 05:18:00–05:26:58 UTC and includes the rolling
outage, so it is not a sustained throughput forecast. All 629 rows had a null
`projected_at`; that field tracks timer projection, and null does **not** establish
that telemetry was lost. The issue is that timer queries scan/decode unrelated
telemetry rows before discarding them. Recovery currently verifies every historic
commit by re-executing it, making startup work grow with history even when its
main query is streamed.

The three unchanged-generation reconciliations took 2,012, 983, and 655 ms on
one replica. The commit hook was running on the host at the time, so these are
diagnostic timings, not isolated latency/capacity benchmarks. The query counts
and unchanged generation/applied timestamp directly demonstrate repeated work.
The temporary telemetry handler was detached after the measurement.

The OTEL reporter was checked rather than assumed to be a leak: it had 102–104
series per replica, zero failed exports, and zero dropped data points at the
snapshot. Its configured series/queue limits remain valuable safeguards.

HTTP readiness currently tests database access and the drain flag. It is not a
statement about mission ownership, completed replay, or contact freshness. Keep
those operational states visible, and gate ingress admission on the prerequisites
for durable capture and safe ownership. The latest rolling run had healthy HTTP
readiness throughout a prolonged telemetry gap.

No Erlang peers were connected in the three replicas. Local registries and
node-local observation caches are not a distributed ownership mechanism. The
shared archive PVC is on a single OrbStack node; node loss and multi-node storage
availability have not been tested.

`SourceRuntimeBases` currently admits at most 1,000 sources. The fixture's two
sources per spacecraft put 500 spacecraft exactly at that bound. Increasing the
bound alone does not demonstrate support for a larger constellation.

## Next capacity experiment

After correcting the continuity/ownership issues, vary configured fleet size and
active contact count independently. Start with 10, 50, and 100 active contacts,
then reach 500 only with a measured memory budget. Compare one and three replicas
at equal aggregate input rates, then increase rate to find saturation. Record
startup peak, steady working set, per-process heaps, mailbox/backlog growth,
replay duration, SQL work, accepted/processed/archived record counts, and contact
freshness. Include a surge replica during rollout. Repeat with multiple distinct
models and long retained histories; fresh startup alone cannot reveal replay cost.

## Evidence and code paths

Read-only measurement scripts and results are retained under `var/chaos/checks/`:
`opportunity-snapshot.exs`, `opportunity-memory.json`,
`opportunity-partition-size.exs`, `opportunity-partition-size.txt`,
`opportunity-semantic-storage.json`, `opportunity-metrics-reporter.json`,
`opportunity-reconcile.exs`, and `opportunity-reconcile.txt`.
They return sizes, counts, and process metadata, not full runtime states.

Relevant implementation paths:

- `apps/cadence/lib/cadence/projections/activation_status.ex`: `applied_basis/1`.
- `apps/cadence/lib/cadence/runtime/mission_coordinator.ex`: `active_spec/1`,
  `start_partition_owner/5`, `start_new_partition_owner/5`.
- `apps/cadence/lib/cadence/runtime/mission_runtime_spec.ex`: `partition_input/2`.
- `apps/cadence/lib/cadence/runtime/partition_owner/partition_builder.ex`: `build/6`.
- `apps/cadence/lib/cadence/control/mission_runtime_reconciler.ex`: `reconcile_state/1`.
- `apps/cadence/lib/cadence/semantic_runtime/store.ex`: commit and recovery queries.
- `apps/cadence_simulator/lib/cadence_simulator/send_buffer.ex`: `do_flush/2`,
  `do_send/2`, `do_connect_output/2`.
- `apps/cadence_web/lib/cadence_web/controllers/health_controller.ex`: `ready/2`.
