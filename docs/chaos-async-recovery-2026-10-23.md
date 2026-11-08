# Partition recovery isolation and rolling deployment rehearsal — 2026-10-23 UTC

## Change

Mission-owned partitions now acknowledge their supervisor's startup handshake
before initializing and replaying semantic history. Initialization runs in the
partition's `handle_continue/2`, so timers, managed capability state, and replay
remain in the owning process. Direct/offline callers retain synchronous startup
unless they explicitly select deferred initialization.

The mission coordinator sends monitored asynchronous requests for ingress,
binding queries, snapshots, and generation reconciliation. A recovering owner
can delay its own requests without blocking the coordinator or another cold
partition's startup. Replies retain the owner's ordering. Owner death returns a
`partition_unavailable` error to pending callers. There are at most 32 outstanding
requests per partition; additional requests receive `partition_busy`. This is a
per-partition request-count bound, not a global recovery-memory budget.

Generation application remains a barrier: the new generation is acknowledged
only after all existing owners reconcile. While application is pending, new
partition work receives `generation_applying`. Duplicate application checks wait
on the small generation identity rather than copying the fleet specification
again. A reconciliation failure stops the coordinator, whose existing
one-for-all supervisor retires partially reconciled owners. This preserves the
previous failure behavior without blocking the coordinator during replay.

Expected initialization errors stop a transient child without an automatic
restart loop; a subsequent caller can retry. Unexpected owner crashes still
restart under supervision. This change does not introduce distributed ownership
fencing, replay checkpoints, or handoff of retired pod journals.

Recovery start/completion logs include mission, partition, generation, duration,
and outcome. OTEL metrics `cadence.runtime.partition.recovery.started` and
`cadence.runtime.partition.recovery.duration` expose attempts and initialization
latency, with bounded outcome labels and histogram boundaries through 600 seconds.
Partition identifiers stay in logs rather than metric labels.

## Regression coverage

The coordinator tests hold a partition at its recovery telemetry boundary while
checking warm ingress, another cold partition, binding/snapshot requests, and
coordinator identity queries. They also exercise bounded admission, owner death
and retry, delayed/coalesced generation acknowledgements, and failure of a
partially reconciled generation. Existing ingress, reassembly, and generation
identity tests remain in the focused suite.

A reporter regression test exercises real recovery telemetry spans and decodes
the exported OTLP payload, verifying that attempts are counted and successful,
failed, and exceptional completions export duration points with only the bounded
outcome label. This caught and corrected an initial attempt-counter measurement
error before the measured cluster runs.

## Environment

The rehearsal uses OrbStack's single physical node, three Cadence replicas with
unchanged 4 GiB memory limits, the Reflect Orbital fixture with 500 configured
spacecraft, and ten live feeds at 0.2 Hz. The separate database
`cadence_chaos_20261023_022453` was restored from the activated pre-traffic fixture.
The previous failed database `cadence_chaos_20261023_012610` and all earlier run
artifacts remain intact. A fresh fixture is experiment setup, not recovery of a
failed deployment.

Fresh contacts end at 10:33:07 UTC. The server image is
`cadence-chaos:f9d7ff93-1792723085`, ID
`sha256:47e83806fa808d00a1f977912f00d23d1a47520aa67d45edffcacf8e41b61c72`.
It contains this working-tree change based on `f9d7ff93`. The simulator image is
`cadence-chaos-simulator:f9d7ff93-1792723085`, with the unchanged image ID
`sha256:f6df7edefd24dd605cd3f8ad4964ca5d7520cb3ef7949213b12b2d5a10a24ba5`.
Source hashes and image IDs are recorded in
`var/chaos/checks/async-recovery-source-hashes-final.json`.

The ten-second freshness threshold and three-replica admission requirement remain
unchanged. The deployment experiment is a same-image rolling restart. It does not
test a mixed-version application upgrade, multi-node loss, 500 concurrent live
contacts, or command/uplink delivery.

## Environment interruption

Startup attempt `var/chaos/runs/20261023T024956Z-startup` was aborted and retained
as failed before any application container started. All three pods reported
`ErrImagePull`: the newly built local server image had disappeared. Node image-GC
events recorded 448,409,402 bytes removed, matching the unused server image, while
Docker reported 11.9 GB of build cache. The host had 17 GiB available. The node
still reported Ready with its DiskPressure condition false.

The image was restored from build cache with the identical SHA-256 above and a
stopped container reference retained it. Pruning unused build cache reclaimed
7.531 GB. Databases, volumes, and experiment evidence were preserved. This is lab
environment repair before measurement, not an application recovery success.

## Validation and simultaneous startup

Final `mix precommit` passed: 4,157 tests passing and one excluded, including
2,676 core, 144 simulator, and 959 web tests. Compilation with warnings as errors,
strict Credo, workspace/extension/architecture checks, and plane tests passed.
The focused coordinator suite passed ten tests; the metrics suites passed eleven;
all nine Python lab harness tests passed. Builds and tests finished before the
measured runs.

Startup artifact: `var/chaos/runs/20261023T025311Z-startup`.
All three replicas started together from zero. Kubernetes readiness took 20.73 s,
and all ten source partitions on every replica recovered by 25.45 s. There were
zero container restarts and zero cgroup OOM kills.

| Pod suffix | Cgroup peak | BEAM memory after recovery |
| --- | ---: | ---: |
| `4kcp7` | 749,268,992 B | 475,694,866 B |
| `4xvwk` | 756,375,552 B | 469,005,242 B |
| `qbkbj` | 757,235,712 B | 461,956,442 B |

The live metrics backend returned both the recovery attempt counter and duration
histogram after startup. Its response is retained in
`var/chaos/checks/async-recovery-metrics-startup.json`.

## Baseline

The 60-second baseline, `var/chaos/runs/20261023T025422Z-baseline`, passed all
22 samples with three Ready replicas before and after. There were zero HTTP or
freshness failures, source drops, semantic sequence regressions across 238
commits, or artifact errors. All 20 sampled archive objects remained unchanged
and readable on every replica. Throughput was 26.77 archived frames/s; HTTP p95
was 418.48 ms.

Traffic continued into an extended baseline so the rolling test would begin with
history comparable to the prior failed rollout's 728 commits. The database,
images, replicas, workload, and acceptance thresholds were unchanged.

The 180-second extension, `var/chaos/runs/20261023T025658Z-baseline`, also passed:
66 samples, three Ready replicas, zero HTTP/freshness failures, source drops,
semantic regressions across 820 commits, or artifact errors. All 20 sampled archive
objects remained intact on every replica. Throughput was 25.65 archived frames/s;
HTTP p95 was 619.80 ms. This healthy run directly preceded the rolling restart.

## Rolling restart: coordinator isolation works; continuity still fails

Artifact: `var/chaos/runs/20261023T030119Z-rollout`.
The independent admission check found three Ready replicas, ten fresh feeds, and
zero regressions across 905 semantic commits. The 180-second window produced
49 samples: zero HTTP failures, but 25 freshness violations and a maximum age of
66.856311 s. Feeds 1, 3, and 9 remained stale at the end; the other seven were
fresh. HTTP p95 was 977 ms. The resilience verdict is **failed**.

Read-only probes during the rollout directly verified the isolation change:

- At the third probe, `vz9vp` answered a coordinator identity request in 1.866 ms
  with an empty mailbox while five owners were in `SemanticRuntime.Store` replay.
  `zlpgw` answered in 0.614 ms while another owner replayed.
- At the second probe, `zlpgw` answered in 1.985 ms while feeds 4 and 10 were
  simultaneously recovering. Their recovery logs bracket the probe and report
  21.486 s and 21.447 s durations. Successful recoveries across the replacement
  pods took 17.116–24.603 s.
- The first probe also caught a separate one-second timeout on `vz9vp` before it
  had any partition owners. Its stack was `gen_server.loop_wakeup`, with one
  queued message and an idle partition supervisor. This is a startup/wakeup
  latency observation, not evidence that replay still held the coordinator.

Probe artifacts are in `var/chaos/checks/async-recovery-during-rollout-{1,2,3}/`.
These are sampled diagnostics, not a coordinator latency SLA. The measured
rollout includes those small read-only probes. `otel-recovery.json` captures the
new metric series over the rollout and post-window diagnosis.

All three replacements became Ready with zero container restarts and zero OOM
kills. Cgroup peaks were 755,331,072–806,510,592 B (720–769 MiB). Fourteen TCP
reconnects completed in 251–351 ms; the final socket capture had ten established
connections and no `CLOSE_WAIT` connections. There were zero reported source
drops. All 19 sampled archive objects remained unchanged and readable on every
replica. Artifact collection reported no errors.

The semantic audit found four regressions across 1,339 commits:

| Feed | Commit | Previous sequence | Stored sequence |
| --- | ---: | ---: | ---: |
| 1 | 1180 | 16,560 | 144 |
| 3 | 1120 | 15,552 | 144 |
| 3 | 1179 | 864 | 144 |
| 9 | 1186 | 16,560 | 133 |

Post-window partition snapshot requests returned
`partition_unavailable -> partition_initialization_failed -> semantic_runtime_replay_diverged`
for each of these three feeds. The exact divergent commit IDs are retained in
`var/chaos/checks/async-recovery-failure-reasons.log`. Retrying the same invalid
history repeatedly consumed recovery work, but no longer stopped other
partitions from making progress. This is fail-closed recovery, not repaired
semantic history.

Six journal streams from the three retired pods retained 86,970 bytes beyond
their processing checkpoints. One of those streams also retained 14,495 bytes
beyond its archive checkpoint. The raw segments remain on the shared PVC; no
replacement-pod claim/replay is implemented. The sampled archive hash check
therefore must not be interpreted as complete custody of every admitted byte.
The detailed memory, reconnect, socket, and journal summary is
`var/chaos/checks/async-recovery-rollout-analysis.json`.

## Remaining work and final state

The coordinator no longer serializes mission traffic behind partition replay.
The next correctness blocker is durable ownership fencing and conditional commits
against the expected predecessor, including routing back to an already-warm
owner with stale state. Retired journals need logical-stream claim and replay.
After those correctness boundaries, verified checkpoints and bounded timer
queries are needed to bring history-dependent recovery below the freshness
budget. Repeated deterministic recovery failures also need explicit backoff or
quarantine instead of immediately repeating unchanged work.

These findings do not certify safe continuous delivery. No repair or deletion was
applied to the failed database. After capture and diagnosis, Cadence and synthetic
traffic were scaled to zero to stop repeated failed recovery; Postgres, QuestDB,
the simulator service, shared volumes, and all run evidence remain available.
The stopped Docker container `cadence-chaos-recovery-image` retains the validated
local server image against image GC.
