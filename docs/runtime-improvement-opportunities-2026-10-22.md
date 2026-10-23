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

## Recommended work order

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
