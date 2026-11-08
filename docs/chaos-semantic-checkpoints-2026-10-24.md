# Durable semantic checkpoints and rolling deployment

## Recovery contract

Each successful fenced semantic commit now publishes a checkpoint in the same
PostgreSQL transaction. The checkpoint references the commit's existing compressed
state; it does not duplicate the state blob. Its SHA-256 covers the checkpoint
format/engine version, organization scope, mission, partition, runtime basis,
commit sequence, commit ID, and encoded state. There is one checkpoint per scope
and runtime basis. The commit log remains intact.

Ownership acquisition captures the checkpoint reference while holding the head
lock. State loading and replay happen after that lock is released. This prevents
a concurrently advancing checkpoint from moving the recovery boundary. Recovery
validates scope, version, sequence and checksum, then verifies every result and
state in the suffix through the captured head. Missing, incompatible, or invalid
checkpoints fall back to full verified replay. A divergent suffix or history fails
recovery; it is never skipped or published as a new checkpoint.

Fenced warm owners use this same recovery path before recomputing an input or
timer. A standby that has not processed traffic recently therefore restores the
durable head instead of replaying every commit since its stale local state.
Foreign-scope writer tokens are rejected before acquiring a new epoch.

A successful fallback publishes only if its original writer still owns the same
head. Losing that race leaves publication to the new owner. Normal commits retain
the existing epoch and exact-predecessor checks, including the database insert
fence. A failed commit transaction cannot advance the checkpoint. Duplicate inputs
retain the current state and head.

`Store.recover/3` remains a **read-only full-history audit**. It ignores checkpoints
and verifies all persisted results and states. Checkpoints are trusted execution
snapshots with integrity checks; they do not continuously re-audit the historical
prefix. Engine/state changes that invalidate snapshots must increment
`Checkpoint.@version`; deterministic replay still has to succeed under the new
engine before recovery can continue.

## Timer recovery and adoption

The additive migration creates the checkpoint table and nullable input/timer
metadata. Partial indexes are built concurrently. Older binaries can continue
appending rows without the new metadata, and those rows remain replayable.

The first writer recovery verifies existing history once and backfills timer
metadata within that replay transaction. Subsequent cursor queries return only
the latest commit per timer key. Pending projection queries exclude ordinary
updates, and projection acknowledgements target their timer key and time. A
legacy NULL-metadata suffix remains visible during mixed-version operation.
Unacknowledged timer results remain durable across checkpoint recovery.

Checkpoint recovery emits bounded `outcome` metrics and logs its checkpoint/head
positions, replayed commit count, and elapsed milliseconds. The existing partition
recovery span continues to measure the complete initialization path. The chaos
harness captures the checkpoint counter alongside ownership and journal retries.

## Validation

The rehearsal retains `cadence_chaos_20261023_233753`, starting with the 1,598
commits independently audited after the previous framing test. No history is
deleted or reset to make checkpoint recovery pass. The workload remains 500
configured spacecraft, ten live feeds at 0.2 Hz, three replicas, and a ten-second
freshness threshold.

First server image: `cadence-chaos:4712c5bf-checkpoints-1792802873`, image ID
`sha256:44bbba8e781acd412cf7ca2a97a786a8122410a0c159059a854b4abcdfa6b85a`.
The simulator is unchanged: `cadence-chaos-simulator:f586938c-1792798718`.
`checkpoint-source-hashes.json` records the image's source fingerprints, which
were compared with the final code and tests before deployment.

The first `mix precommit` passed 4,176 tests, with one excluded. The final store suite has 18
tests, including restart hits, suffix verification/backfill, corruption and
version fallback, full-prefix auditing, scope isolation, transaction rollback,
stale writers (including warm checkpoint hits and missing-checkpoint fallback),
pending timer projections, and an append racing with recovery
after ownership acquisition. The nine Python harness tests passed.

### Startup on retained history

The additive migration completed in 0.2 seconds while the old three replicas
were running and synthetic traffic was paused. All three were then replaced
together for the initial adoption test. No fixture restore or contact renewal
was needed; the original ten contacts remained valid.

| Measurement | Legacy bootstrap | Checkpoint restart |
| --- | ---: | ---: |
| Run | `20261024T005536Z-startup` | `20261024T005729Z-startup` |
| Kubernetes Ready | 16.03 s | 17.01 s |
| All 30 partition owners ready | 69.00 s | 19.21 s |
| Checkpoint outcome | 30 missing | 30 hits |
| Commits replayed across all replicas | 4,794 | 0 |
| Semantic recovery duration | 2,727–11,837 ms | 2–23 ms |
| Per-pod cgroup memory peaks | 759–852 MiB | 717–747 MiB |
| Restarts / OOM kills | 0 / 0 | 0 / 0 |

All 1,598 commits remain present. Bootstrap produced ten checkpoints, all matching
their durable heads, with zero legacy metadata rows remaining. The checkpoint
table including indexes occupies 32 KiB. First adoption is deliberately still a
full verified replay on each replica that starts without a checkpoint.

### Live baseline and rolling restart

The first baseline (`20261024T005852Z-baseline`) failed 3 of 84 freshness samples,
reaching 13.66 seconds before any fault was injected. HTTP requests all succeeded;
2,344 commits had zero sequence regressions, 41 sampled archive objects were
intact on all replicas, source-reported drops were zero, and artifact collection
had no errors. Runtime snapshots showed no executor/consumer failures or queued
work; the feeds recovered without intervention. Kubernetes reported no memory,
disk, or PID pressure and no pod restarts. The cause of that transient pause was
not established. The rollout gate refused injection, and the run is retained.

The second baseline (`20261024T010537Z-baseline`) failed 2 of 75 samples, reaching
18.84 seconds. It retained three Ready replicas, zero HTTP failures, zero
regressions across 3,121 commits, 40 intact sampled archive objects, zero source
drops, and no artifact errors. Host snapshots showed about 10 GiB of swap in use
and active swap-ins, but do not establish causality for these pauses.

After pausing traffic, all ten partitions passed full replay and matched their
checkpoint states exactly. The independent fencing audit covered 3,224 commits
with no unfenced writes, broken predecessors, regressed epochs, or incorrect
heads. The third baseline (`20261024T011518Z-baseline`) had 46 healthy samples
with a maximum age of 6.08 seconds before an operator interruption at
`2026-10-24T01:18:06Z`: node free storage approached 6%, close to its 5% hard
eviction threshold. Its later stale samples follow the deliberate traffic stop;
the run is not a passing baseline.

### Storage maintenance outside measured tests

No unused Docker build cache remained. Retained PVCs occupied 60.6 GiB, including
32.5 GiB of PostgreSQL data and 26.3 GiB of QuestDB data. Synthetic traffic was
paused before maintenance. Historical QuestDB observation partitions can be
[converted reversibly to Parquet while remaining queryable](https://questdb.com/docs/concepts/parquet/).

The oldest partition, `2026-10-21`, retained all 577,008 rows while shrinking from
1,674,186,752 to 174,284,501 bytes. Its complete ordered CSV export remained
1,080,033,406 bytes with SHA-256
`c088ea628098effe590ae974df48c856412924856ad1a467deff1e74a2fd8eb7` before and after.
The initial unbounded sorted verification query exceeded QuestDB's 1 GiB memory
limit and caused one QuestDB OOM restart, outside the measured workload. The
subsequent verification used bounded time slices and passed without changing
memory limits. Cadence pods did not restart. Database-native conversion preserved
the data; no database, historical row, archive, or journal was removed.

The `2026-10-22` partition retained all 7,522,560 rows and shrank from
21,827,575,808 to 2,402,874,980 bytes. Bounded exports before and after both
contained 14,082,215,854 bytes with SHA-256
`517afbabfee6f05fd7420135edd4ca07ee62f22197faf50d5d50c6d075f221bc`.
The two conversions reclaimed about 19.5 GiB. Free node storage recovered to
25.7 GiB (30.5%). The latest partition, PostgreSQL histories, archives, journals,
and the workload configuration were retained. Verification artifacts are
`checkpoint-compact-2026-10-21.json` and `checkpoint-compact-2026-10-22.json`
under `var/chaos/checks/`.

### Fresh validation after maintenance

The host then slept during traffic warm-up. `pmset` recorded sleep/dark-wake
cycles from approximately 01:53 to 02:51 UTC, ending with a lid/user wake. The
hour-old feed timestamps after waking are an environmental interruption, not a
replay measurement. No rolling fault was injected. Traffic was paused and the
three Cadence replicas restarted after PostgreSQL recovered. A temporary
`caffeinate -is` assertion was used for the remaining tests; system sleep settings
and application resource limits were unchanged.

The recovery startup (`20261024T025909Z-startup`) passed with three Ready replicas
in 20.62 seconds and all 30 partition owners initialized in 22.59 seconds. No
Cadence restart or OOM occurred.

The subsequent five-minute baseline (`20261024T030031Z-baseline`) failed 10 of 56
freshness samples, with maximum age 23.03 seconds. HTTP requests all succeeded;
4,678 commits had zero sequence regressions, 59 sampled archive objects remained
intact on every replica, source drops were zero, and artifact collection had no
errors. Per-pod memory peaks were 811–863 MiB, with no restarts or OOM events.
The rollout gate again refused injection. The user requested continuing on this
machine as-is; other workloads were not closed or suspended.

After retaining these failed extended baselines, a separate 60-second pre-roll
window was selected to assess immediate health. This shorter window cannot
establish sustained stability or erase the longer failures. The workload and
ten-second threshold were unchanged.

That short baseline (`20261024T030948Z-baseline`) passed all 17 samples, maximum
age 7.36 seconds, with three Ready replicas, zero HTTP failures, zero sequence
regressions across 5,161 commits, 59 intact sampled archives, zero drops, and no
artifact errors. The next rollout attempt stopped in its preflight history audit:
the growing retained log exceeded the audit's 120-second transaction timeout.
No rolling fault was injected. The final harness permits ten minutes for this
streaming full-history audit, outside the measured continuity window, with a
matching outer command timeout. It still checks every retained commit.

Code review also found that warm owners still used their older local state for
suffix replay after losing ownership. The final build routes both initial
recovery and fenced retry through the captured durable checkpoint. The first
build's startup and baseline results above are retained separately; final-build
validation follows below.

### Final build

Image: `cadence-chaos:4712c5bf-checkpoints-warm-1792811896`, ID
`sha256:481383a69cf5caec23f4e58a739fa3bb3813bc52076255ac4cccb6f5e6390ddd`.
Its source fingerprints are retained in `checkpoint-warm-source-hashes.json`.
The simulator, database, contacts, replica count, and memory limits are unchanged.

The 18 store tests and nine Python harness tests passed. A full check run
overlapping the image build passed 2,695 of 2,696 core tests, but failed an existing
40-ms `refute_receive` assertion in the journal-consumer retry-backoff test. The
workspace stopped there. Its log is retained as `checkpoint-warm-precommit.log`;
the retry test and full checks were rerun after the build completed.
The isolated retry suite passed all five tests. The subsequent full
`mix precommit` passed **4,177 tests, one excluded**, recorded in
`checkpoint-final-precommit.log`; no test or production retry timing was relaxed.

The final image's startup (`20261024T034003Z-startup`) passed. Three replicas were
Ready in 16.62 seconds, all 30 owners were initialized in 19.58 seconds, and all
30 recoveries hit checkpoints with zero replayed commits in 3–27 ms. Memory peaks
were 718–735 MiB, with zero restarts and OOM kills. Startup logs also captured nine
successful warm-owner checkpoint hits as traffic resumed, each replaying zero
commits. The retained database still includes all earlier history.

The first final-build baseline (`20261024T034123Z-baseline`) failed all seven
samples, reaching 44.53 seconds. It retained three Ready replicas, zero HTTP
failures, zero sequence regressions across 5,816 commits, 74 intact sampled
archives, zero source drops, and no artifact errors. Memory peaks were
759–890 MiB, with no restarts or OOMs. Connections were distributed 2/2/6.
Runtime snapshots had zero executor/consumer failures; the feeds subsequently
recovered. No rolling fault was injected.

The six-feed replica logged 15-second database transaction/checkout timeouts in
`ObservationIdentityStates.record_existing_state/2`, `upsert_state/2`, and
`record_envelopes/2`, followed by `cadence.telemetry.ingress.persistence_failed`.
This identifies observation persistence as a remaining bottleneck. It does not
establish whether CPU scheduling, storage latency, or query volume caused the
timeouts. All 39 captured checkpoint recoveries hit with zero replayed commits;
the nine warm hits took at most 221 ms. Evidence is retained in
`checkpoint-final-baseline-logs/` and `checkpoint-final-baseline-runtime.log`.

The host-only harness also now samples preflight health **after** the history
audit, so a minutes-old healthy sample cannot admit a rollout. The nine harness
tests passed after this ordering change; it does not change the deployed image
or freshness threshold. One final baseline retry was made after the feeds
recovered, retaining the same workload and connection distribution.

That retry (`20261024T035231Z-baseline`) verified 6,179 commits with zero
regressions, but its fresh preflight sample was already unhealthy (maximum age
228.18 seconds). Artifact collection then failed before the timed window.
PostgreSQL logged a backend killed by signal 9 at `03:53:05.942Z` and restarted
its other server processes. It completed crash recovery and accepted connections
at `03:53:44.603Z`. The killed backend was inserting an ingress archive evidence
entry; that identifies the victim, not necessarily the allocation responsible.

PostgreSQL's cgroup first recorded a 1,073,741,824-byte peak against the same 1 GiB
limit, five cumulative OOM events and two cumulative OOM kills. A later snapshot
recorded seven events and three kills. Its Kubernetes
container restart count remained zero because the postmaster survived. At least
two backend OOMs are directly evidenced during recovery: the second occurred at
`03:57:25.382Z`, with connections accepted again at `03:58:00.551Z`. The
cumulative count does not establish when the remaining kill occurred. Evidence is retained in
`checkpoint-final-blocked-postgres.log`, `checkpoint-final-postgres-memory.txt`,
and `checkpoint-final-blocked-pods.json`. Resource sampling after recovery showed
about 1.62 GiB available node memory and 20.58 GiB free storage.

No rolling fault was injected on either build: gates failed on baseline health
or preflight auditing. **Rolling validation remains blocked**, despite successful
checkpoint unit tests and startup measurements. Further fault attempts were
stopped and traffic paused. Two post-outage runtime snapshots had empty ingress
registries, so the three Cadence replicas were restarted before the final
read-only integrity audit. Databases, archived objects, and all pod journals
remain retained; no resource or freshness limit was raised.

The post-outage restart (`20261024T040030Z-startup`) again initialized three
replicas and all 30 owners without a Cadence restart or OOM. Readiness took
53.69 seconds and all-owner initialization 70.76 seconds in the recovering lab;
these timings are retained alongside the earlier fast startup, not excluded.
All 30 post-outage recoveries were checkpoint hits, replaying zero commits in
22–296 ms; the logs are in `checkpoint-post-outage-startup-logs/`.

The final read-only replay reconstructed all ten partitions from their complete
histories and exactly matched each checkpoint state. It covered 6,341 committed
rows (the largest allocated commit sequence was 6,408; sequence IDs are not a
row count). Full audit replay took 47.32–107.93 seconds per partition. The separate
fencing audit found zero unfenced writes, broken predecessors, regressed epochs,
or incorrect heads. All ten checkpoints matched their heads, with zero legacy
metadata rows remaining. The checkpoint table and indexes occupied 120 KiB.
Evidence: `checkpoint-final-full-replay.log`, `checkpoint-final-fence-audit.json`,
and `checkpoint-final-audit.json` under `var/chaos/checks/`.

Tempo inspection found five `cadence.telemetry.ingress.persist_batch` traces
lasting 125–126 seconds around the PostgreSQL failure. Trace
`6fe58696896ea93bb04cd5e9a65bd825` began at `03:51:06.342Z`, lasted 125.391 seconds,
and ended with `persistence_failed`; its separately reported queue wait was
34.945 seconds. Trace `88394e5ac3c184f7da0d796728e536ce` lasted 126.004 seconds
after 22.354 seconds of queue wait. Both ended just after PostgreSQL began crash
recovery. Neither retrieved trace included child spans, so the division between
database waits and execution remains unmeasured. Earlier six-minute traces
overlapped host sleep/wake. These observations do not establish swap as the sole
cause. Raw trace responses are retained as `checkpoint-trace-<trace-id>.json`.

The lab was paused after the integrity audit. A subsequent memory investigation
briefly started one replica without traffic, then stopped it again; all durable
data remains retained. See the memory follow-up in the
[opportunity report](runtime-improvement-opportunities-2026-10-22.md).

## Subsequent validation after runtime memory normalization

The later runtime-representation change established a healthy three-replica
baseline on the same retained database and passed the sampled rolling-restart
checks. All 30 startup recoveries hit the existing checkpoints, replayed zero
historical commits and completed checkpoint restoration within 32 ms. The final
fencing audit covered 7,413 commits with ten correct heads/checkpoints and no
regressions. See [the memory implementation and rehearsal results](runtime-improvement-opportunities-2026-10-22.md#runtime-representation-implementation-2026-10-24-utc)
for measurements, exact run directories, and the remaining processing-cursor and
journal-handoff limitations. This follow-up supersedes the earlier blocked
validation status without changing the observations recorded above.
