# Simulator TCP reconnect and rolling deployment rehearsal — 2026-10-23 UTC

The simulator now observes peer TCP closure without waiting for another generated
packet or a failed send. Its internally owned sockets use `active: :once`, rearm
after peer data, and handle close/error notifications only for the current socket.
Caller-owned attached sockets retain their original ownership contract.

Reconnects run on a single reference-tagged timer, including after initial
connection refusal. Attempts refresh the runtime endpoint, use a one-second
connect timeout, and retry at 250 ms intervals. Writes also have a one-second
timeout and close the socket on timeout. Successful reconnects flush retained
packets in order. Logs report the endpoint, attempt count, outage duration, and
retained packet count; stats expose connection attempts, connections, disconnects,
last error, and whether a retry is pending.

Packets that have not been sent are retained while disconnected, up to a default
1 MiB byte limit. Overflow rejects the incoming batch with a logged/counted drop
and a coordinator status update. An actual failed send is ambiguous, so its batch
is counted as dropped rather than replayed. Successful send counters still mean
socket acceptance, not receiver persistence. These semantics follow the
[Erlang TCP send contract](https://www.erlang.org/doc/apps/kernel/gen_tcp.html#send/2)
and [active socket behavior](https://www.erlang.org/doc/apps/kernel/inet.html#setopts/2).
There is no claim of durable source buffering or exactly-once delivery.

## Environment and preparation

- OrbStack, one physical node, three Cadence replicas, unchanged 4 GiB app limits.
- Reflect Orbital fixture: 500 configured spacecraft; ten live feeds at 0.2 Hz.
- Database `cadence_chaos_20261023_012610`, restored from the activated pre-traffic
  fixture. All earlier databases, volumes, and experiment evidence were preserved.
- Fresh contacts end at 09:27:10 UTC on October 23.
- Server image `cadence-chaos:79811230-1792718685`, ID
  `sha256:d996e8c85cb0ce86c7414bc254017116124e3ba89714a7a733cfbb3d6b7af8ed`.
- Simulator image `cadence-chaos-simulator:79811230-1792718685`, ID
  `sha256:f6df7edefd24dd605cd3f8ad4964ca5d7520cb3ef7949213b12b2d5a10a24ba5`.
- Images contain the working-tree change based on `79811230`; file hashes and image
  IDs are recorded in `var/chaos/checks/tcp-source-images.json`.

An attempt to renew expired contacts in the prior database was stopped before
measurement. With 48,627 semantic commits retained, the renewal RPC waited in
`MissionCoordinator.start_new_partition_owner/5`, whose supervisor was waiting in
`proc_lib.sync_start/2`. This identifies the wait location, not its ultimate cause.
That database remains available as `cadence_chaos_20261022_050426`; no history was
removed to change an experiment verdict. Preparing a fresh fixture is operator
setup, not evidence of automatic recovery.

## Validation

The focused suite covers real TCP FIN/half-close without new writes, RST with
endpoint refresh, peer data followed by FIN, repeated initial connection failure,
sustained disconnect with ordered recovery, bounded overflow, stale notifications,
and caller-owned socket handling. All ten tests passed. The nine Python lab
harness tests also passed. `mix precommit` passed with 4,152 tests passing and one
excluded, including all 144 simulator tests. Compilation with warnings as errors,
strict Credo, workspace/extension/architecture checks, and plane tests passed.
Build and test processes finished before the measured startup and traffic runs.

## Simultaneous three-replica startup

Artifact: `var/chaos/runs/20261023T013433Z-startup`.

All three replicas started from zero together. Kubernetes readiness took 16.44 s;
all ten source partitions on every pod were recovered by 17.98 s. There were zero
container restarts and zero cgroup OOM kills.

| Pod suffix | Cgroup peak | BEAM memory after recovery |
| --- | ---: | ---: |
| `2hw2r` | 769,114,112 B | 461,068,634 B |
| `776kp` | 762,404,864 B | 450,732,058 B |
| `bgfbc` | 784,056,320 B | 464,638,482 B |

## Baseline attempts

The first baseline, `var/chaos/runs/20261023T013537Z-baseline`, failed before any
rollout: 3 of 18 samples exceeded ten seconds, with maximum age 17.70 s. HTTP
responses remained 200, but p95 latency was 2,255.55 ms. All twenty sampled archive
objects were intact on all replicas; there were no source drops, TCP disconnects,
semantic sequence regressions, or artifact errors.

At 01:36:46 UTC a readiness request exceeded its one-second database checkout
limit. A subsequent host snapshot showed load average 26.59, 15 GiB physical memory
used, and 7.3 GiB in the compressor. These observations suggest resource contention;
they do not establish a root cause. This failed baseline is retained and was not
used to authorize fault injection. The repeat uses the same database, pods, traffic,
code, and ten-second threshold.

The repeat, `var/chaos/runs/20261023T013822Z-baseline`, passed all 21 samples with
three Ready replicas before and after. There were no HTTP/freshness failures,
source drops, semantic sequence regressions (607 commits audited), or artifact
errors. All 18 sampled archive objects remained unchanged and readable on every
replica. Throughput was 25.93 archived frames/s; HTTP p95 was 647.06 ms. The rolling
restart was launched from this healthy state, with its own independent admission
check of freshness and semantic history.

## Rolling restart: reconnect passes; application continuity fails

Artifact: `var/chaos/runs/20261023T014116Z-rollout`.

The 180-second same-image restart began with three Ready replicas, all ten feeds
fresh, and zero semantic regressions across 728 existing commits. There were 47
samples. All eleven TCP reconnect events completed in 253–334 ms; one feed moved
twice. The final source socket capture contains ten `ESTABLISHED` connections and
no `CLOSE_WAIT` connections. Receiver sockets were distributed 6/3/1 across the
replacement pods. No simulator output was reported dropped.

All three replacement pods became Ready with zero container restarts and zero
cgroup OOM kills. Their cgroup peaks were 814,448,640–876,445,696 bytes (777–836 MiB).
All sixteen sampled raw/protocol archive objects remained unchanged and readable
on every replica. Artifact collection reported no errors. This does not mean all
journal tails were archived: seven streams belonging to the retired pod UIDs each
retained 14,495 bytes beyond both archive and processing checkpoints (101,465 bytes
in total). Their files remain on the shared volume, but replacement pods do not
claim retired journals. Drain completion and journal handoff remain necessary.

**The rollout did not pass application continuity.** There were 28 freshness
violations, a maximum age of 118.91 seconds, and seven stale feeds in the final
sample (SCIDs 2, 3, 4, 6, 8, 9, 10). HTTP readiness remained 200 throughout.
Throughput was 18.09 archived frames/s during the disruption. The final semantic
audit found one regression: spacecraft 004's sequence went from 13,824 to 144 at
commit 989. Its audit inspected 1,146 commits. A zero-drop sender counter does not
negate these receiver-side failures.

The receiving pod `cadence-84896d84c9-7w55z` repeatedly logged five-second
`process_telemetry_ingress` timeouts. After the sampling window, its mission
coordinator was waiting inside `start_new_partition_owner/5`, with 28 queued
messages; the partition supervisor was synchronously awaiting child initialization.
A child stack was executing `SemanticRuntime.Store.replay_row/3` through
`SemanticRuntime.evaluate_monitoring/5`. This demonstrates that synchronous history
replay blocks mission-level ingress while a partition is starting. It does not
establish how much each replay phase contributes to the delay. The process was no
longer present in a later diagnostic, so the snapshot alone is not evidence of a
permanent deadlock. Stack evidence is in
`var/chaos/checks/tcp-rollout-recovery-stacks.txt`.

These results validate the simulator close/reconnect fix and expose the next
Cadence blockers: admission/readiness while replay is incomplete, isolating
partition recovery from the mission coordinator, and fencing semantic ownership
so a stale writer cannot commit an earlier state. Retired journal tail takeover
also remains unresolved. The existing server code,
readiness policy, and ownership protocol were not changed in this commit.

This is a single-node, ten-live-feed, same-image restart rehearsal. It is not a
mixed-version schema upgrade, 500 simultaneous contacts, node-loss test, or proof
of lossless/exactly-once continuous delivery. The full rolling test remains failed.
