# Semantic ownership fencing and rolling deployment rehearsal — 2026-10-23 UTC

## Change and guarantees

Semantic partitions now have a PostgreSQL head keyed by organization scope,
mission, and partition. Claiming the head increments a durable ownership epoch.
The returned writer token also identifies the runtime basis and generation and
records the exact commit position used to reconstruct local state. Claims reject
older generations and conflicting bases within the same generation.

Claims use a short row-lock transaction. Replay occurs afterwards, through a
bounded log prefix ending at the captured head; it does not hold the ownership
lock. A claim can supersede another claim while that owner is recovering. The
superseded owner cannot commit with its old epoch. There is no wall-clock lease
or dependency on Erlang node connectivity.

Each semantic update or timer commit locks the head and checks both ownership and
the expected predecessor. A database trigger independently checks the epoch,
basis, and predecessor and advances the head atomically with the inserted commit.
An insert failure rolls back the head change. This closes the old unfenced insert
path as well as the normal application API.

On contention, a telemetry or timer evaluator claims a new epoch, verifies and
replays the missing suffix from its known state, and recomputes the input. There
are at most two recovery retries per evaluation. A retry of an already committed
input returns its original result with the **current durable state and head**,
never its historical state. Timer scope iteration carries the updated writer
position between scopes. Deterministic replay divergence still fails closed.

This is an optimistic transfer protocol: writers can supersede one another, but
only a holder of the current epoch and predecessor can append. It does not route
ingress to an exclusive long-lived owner or provide fairness under sustained
contention. It fences semantic state commits; it does not make every managed
capability side effect or downstream projection part of the same transaction.

## Migration and rollout boundary

The migration leaves historical commits intact and permits their fencing columns
to remain null. Every new insert must supply a valid epoch and predecessor.
An existing log's latest position initializes its head when first claimed, and
full deterministic replay still verifies its contents. This does not repair any
previously divergent history.

The old binary does not supply fencing fields. Applying the migration therefore
makes that binary's semantic writes fail closed. **The first adoption requires a
controlled cutover from the unfenced version.** The rehearsal starts on the new
schema and tests replacement of replicas that all use the new protocol. It is
not evidence that a mixed unfenced/fenced deployment is interruption-free.

## Observability and regression coverage

`cadence.runtime.partition.ownership` exports acquisitions, fenced attempts, and
stale-predecessor rejections using bounded outcome labels. Logs include mission,
partition, generation, epoch, and predecessor. The lab captures this metric in
`otel-ownership.json` alongside memory, freshness, logs, and traces.

Database-backed tests cover superseded epochs even with an unchanged head,
outdated predecessors, generation and basis conflicts, token scope isolation,
legacy inserts rejected by the database, telemetry and timer recovery, duplicate
inputs and timers without state rollback, and deterministic replay across cursor
batches. Two independent database connections race to append from the same
predecessor; exactly one successor is accepted. An OTLP reporter test checks
ownership counts and excludes partition/epoch metric labels.

## Environment

The independent database is `cadence_chaos_20261023_033733`, restored from the
activated pre-traffic fixture with 500 spacecraft. The failed database
`cadence_chaos_20261023_022453` and all earlier evidence are preserved. The lab uses
three replicas on OrbStack's single physical node, unchanged 4 GiB application
memory limits, ten live feeds at 0.2 Hz, and the unchanged ten-second freshness
threshold. Startup and measured runs begin only after the build and host checks
finish.

The server image is `cadence-chaos:8d41528c-1792726974`, ID
`sha256:dffca9ad9adc0e0925f0a9c970d0541486cad0830da4fe9e768137d7e1488f76`.
The simulator image is `cadence-chaos-simulator:8d41528c-1792726974`, with the
unchanged ID `sha256:f6df7edefd24dd605cd3f8ad4964ca5d7520cb3ef7949213b12b2d5a10a24ba5`.
The images contain the working-tree change based on `8d41528c`. Production source
hashes and image identities are retained in
`var/chaos/checks/fencing-source-hashes.json` and `fencing-images.json`.
A stopped Docker container retains the server image against image GC. Fresh
contacts expire at `2026-10-23T11:51:38.883178Z`.

## Validation and startup

Final `mix precommit` passed **4,165 tests, one excluded**: 2,684 core, 959 web,
144 simulator, 336 package, and 42 plane tests. Compilation with warnings as
errors, strict Credo, workspace, extension, and architecture checks passed.
All nine Python harness tests passed. The final log is
`var/chaos/checks/fencing-precommit-final.log`.

Startup artifact: `var/chaos/runs/20261023T035617Z-startup`.
Three replicas started simultaneously from zero; Kubernetes readiness took
**15.922 seconds** and all ten partitions on each replica were ready after
**17.986 seconds**. There were **zero restarts and zero OOM kills**.

| Pod suffix | Cgroup peak | BEAM memory after warmup |
| --- | ---: | ---: |
| `j6h42` | 779,534,336 B | 473,360,740 B |
| `ks4zg` | 776,265,728 B | 464,664,364 B |
| `w7nr2` | 763,973,632 B | 459,965,900 B |

The live OTEL backend returned the new ownership counter after traffic began:
35 acquisitions and five fenced attempts across the three pods. The warmed owners
that had lost their epoch reclaimed ownership and recovered before appending.
The response is retained in `var/chaos/checks/fencing-metrics-startup.json`.

## Initial baseline and storage interruption

The 60-second baseline `var/chaos/runs/20261023T035727Z-baseline` passed all 19
samples with three Ready replicas, zero HTTP/freshness failures, zero source
drops, and zero semantic sequence regressions across 257 commits. All 20 sampled
archive objects remained unchanged and readable on every replica. Observed
throughput was 24.70 archived frames/s; HTTP p95 was 901.04 ms. A subsequent SQL
snapshot audited 348 commits, with zero unfenced rows, broken predecessor links,
regressed epochs, or incorrect durable heads.

The extended baseline `var/chaos/runs/20261023T035959Z-baseline` **failed** after
Kubernetes reported `DiskPressure` at 04:02:22 UTC. It retained 55 samples,
including 12 continuity failures and 11 HTTP failures. No rollout was injected.
Kubelet evicted Cadence, traffic, PostgreSQL, QuestDB, simulator, and Chaos Mesh
pods. `MemoryPressure` remained false. This is not a successful application
continuity result, and the failure was not discarded.

The node's configured hard disk threshold was 5%, with 10% minimum reclaim and a
five-minute pressure transition period. The minimum reclaim is added to the
threshold, as described in the [Kubernetes eviction documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/#minimum-eviction-reclaim).
Read-only VM inspection found 55.6 GiB in lab PVCs: PostgreSQL 30.2 GiB, QuestDB
23.7 GiB, archives 1.7 GiB. Docker container logs totaled about 180 MiB. No database,
PVC, archive object, or run evidence was deleted.

Unused build cache was reclaimed in three passes: 6.049 GB, 962.4 MB, and 705.9 MB
(the last pass followed the simulator rebuild). Free node storage rose to roughly
14–15 GB. Traffic was scaled to zero during recovery. The retained Cadence image
kept its exact digest. Image GC had removed the simulator image, so it was rebuilt
from unchanged source and given a new tag:
`cadence-chaos-simulator:8d41528c-restored-1792728717`, ID
`sha256:11c1298ab3db379b4a43a17d1b3fae10fac89980de3fd4374d02b31fdbb49866`.
Subsequent runs use this rebuilt simulator; the original startup and baseline used
the earlier digest. The data history remains in the same database.

Incident evidence is retained in the failed run's `environment-incident.json`,
`node-events.json`, and OTEL captures, plus `var/chaos/checks/fencing-incident-*`,
`fencing-vm-retained-usage.log`, and the cache-prune logs. The lab needs a node
storage preflight and an explicit retention policy for long rehearsals; host free
space alone did not describe the guest's eviction headroom.

After disk pressure cleared, all 30 partition recoveries on the three replacement
replicas verified the same preserved history. The post-incident audit found **649
commits and zero semantic regressions**, zero unfenced rows, zero broken
predecessors, zero regressed epochs, and zero incorrect heads. The failed run's
19 sampled archive objects were unchanged and readable on every replacement.
Its final verdict remains failed; artifact collection also recorded that traffic
sockets could not be captured during eviction.

The original pods' retained journal streams contained **144,950 B beyond their
processing checkpoints**, with zero bytes beyond archive checkpoints and zero
unscanned bytes. This independently demonstrates the remaining journal-handoff
problem: preserving a valid semantic prefix does not process retired streams'
remaining inputs. Evidence is in `fencing-disk-incident-journal-analysis.json`.

## Recovered healthy baseline

`var/chaos/runs/20261023T041618Z-baseline` passed its three-minute window: **68
samples**, three Ready replicas before and after, zero HTTP/freshness failures,
zero source drops, and zero regressions across **1,124 semantic commits**. All
**30 archive objects** were unchanged and readable on every replica; artifact
errors were empty. Throughput was **25.56 archived frames/s**, with HTTP p95
**651.62 ms**. Disk and memory pressure were false.

A subsequent conditional-write audit at 1,175 commits found zero unfenced rows,
broken predecessor links, regressed epochs, or incorrect heads. The rollout began
from this healthy baseline on the same database and unchanged workload, retaining
more history than the previous unfenced rollout's initial 905 commits.

## Rolling deployment result

`var/chaos/runs/20261023T042127Z-rollout` started with three healthy replicas and
**1,317 commits without regressions**. The same-image rolling restart completed
with three Ready replacements and **zero replacement restarts or OOM kills**.

The freshness verdict was **failed**: **32 of 53 samples** exceeded ten seconds;
maximum age was **63.346 seconds**. HTTP failures were zero, HTTP p95 was
823.08 ms, and observed throughput was 23.52 archived frames/s. Nine feeds were
fresh at the final sample; feed 2 remained stale. All 28 sampled archive objects
were unchanged and readable on all replicas. Source-reported drops and artifact
errors were zero. The traffic socket capture had ten established connections and
no `CLOSE_WAIT` sockets; this run does not contain reconnect-duration log lines.

| Replacement pod suffix | Cgroup peak | BEAM memory after window |
| --- | ---: | ---: |
| `8pjkw` | 818,700,288 B | 408,787,292 B |
| `nh5wm` | 917,422,080 B | 536,305,452 B |
| `pq56q` | 739,926,016 B | 389,537,748 B |

The semantic audit found **zero regressions across 1,707 commits**, compared with
four regressions in the earlier unfenced rolling run. This is a correctness
result, not a claim of improved rollout latency: the retained history and the
recovered baseline differ from that earlier run.

The live logs captured the exact stale-owner condition. On `sf2vd`, feed 3 tried
its old epoch 8 and predecessor 641 at 04:22:46.498 UTC. It was fenced, then
acquired epoch 10 at durable predecessor 1460 before replaying the missing suffix.
Other warmed owners were similarly rejected. The SQL audit during the rollout
found 1,502 commits with no unfenced rows, broken predecessors, regressed epochs,
or incorrect heads. Ownership counters were exported in `otel-ownership.json`.
The retained `fencing-rollout-progress.log` includes old-pod events that would
otherwise disappear when those pods were removed.

Successful individual initialization/replay durations were **10.819–34.917 s**,
already above the freshness budget. Existing warm owners also needed suffix
replay after ownership transfer. Initialization remains off the mission
coordinator's synchronous path, but operational readiness still precedes replay
completion and full replay cost grows with retained history.

Feed 2 also entered a distinct protocol failure loop. At 04:27:02 UTC, its
executor reported **11,273 failures** and
`{:tm, {:unsupported_tm_sdu_kind, :vca_sdu}}`. The partition had a **1,100-byte
frame remainder** and a valid recovered semantic sequence of 24,624. Its recovery
had completed successfully in 18.281 s; no semantic replay divergence was found.
This points to a framing/reconnect-boundary or failed-record handling problem,
whose precise cause is not established by this run. The error was retried rapidly
without making progress. The executor snapshot and the journal identity/cursors
are retained in `fencing-feed2-diagnostic.log` and `fencing-feed2-journal.json`.

The three retired rollout pods retained **333,385 B beyond processing** and
**72,475 B beyond archive checkpoints**, with zero unscanned bytes. The journal
files remain on the PVC; replacement pods do not claim them. These figures exclude
the earlier disk-eviction pods. See `fencing-rollout-journal-analysis.json`.

## Final correctness verification and remaining work

After artifact capture, synthetic traffic was stopped. A read-only full
deterministic replay succeeded for **all ten partitions**, including feed 2.
The final SQL audit covered **2,037 commits**: zero unfenced inserts, broken
predecessor links, regressed epochs, or incorrect heads. The logs are
`var/chaos/checks/fencing-full-replay.log` and `fencing-audit-final.json`.
The fencing change is validated; the overall rolling-delivery requirement is not.

Cadence and traffic were then scaled to zero to stop the failed-record retry
loop. PostgreSQL, QuestDB, simulator service, all databases, archives, journals,
images needed for this run, and evidence remain available. No failed history was
reset to obtain the subsequent baseline.

Next priorities are:

1. Diagnose TM stream framing at reconnection and stop deterministic failures
   from spinning indefinitely on one journal record. Preserve the offending bytes
   and distinguish incomplete input, invalid input, and retryable failures.
2. Claim retired journals by logical stream and recover their unprocessed suffix
   independently of pod UID; validate append, archive, processing, and acknowledgement
   boundaries under termination.
3. Add verified semantic replay checkpoints and recovery-aware admission so a
   replacement is operationally ready within the freshness budget.
4. Audit projection acknowledgements and managed capability side effects that
   remain outside the fenced semantic transaction, including per-commit timer
   acknowledgement and partially committed multi-scope timers.
5. Add guest-storage preflight and a deliberate retention policy for the lab,
   preserving evidence and verified recovery points before discarding history.

These tests cover ten live feeds with 500 configured spacecraft on one physical
node. They do not certify lossless/exactly-once delivery, mixed-version schema
compatibility, multi-node storage availability, 500 concurrent live contacts, or
uplink/command continuity.
