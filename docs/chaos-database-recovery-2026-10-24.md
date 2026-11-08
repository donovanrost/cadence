# Database pressure and archive-writer recovery

## Findings

The failed rolling rehearsal is retained in
`var/chaos/runs/20261025T035347Z-rollout/`. Database requests timed out and
connections were refused without a PostgreSQL container restart or OOM kill.
The protocol archive writer crashed because its organization lookup and index
transaction can raise database exceptions, bypassing its existing error-return
and retry path.

Inspection through each live replica's Repo pool found substantial retained
PostgreSQL query-plan memory. On `cadence-75d68c8dd6-74tfm`, all ten sampled
backends retained about 19 MiB each in plan-related memory contexts. The largest
named statement was a 1,000-row protocol archive insert: 28,000 parameters and
187,387 SQL characters. The other two replicas' pools retained about 11.4 MiB
and 33.2 MiB of plan memory in total. These are backend memory-context
measurements, not container RSS measurements.

Ecto names bulk insert statements by table. The issue is the size of the plan
retained on each connection, not an unbounded number of distinct batch-size
statements. This explains one source of persistent database memory pressure;
it does not establish the sole cause of the earlier timeouts, readiness-probe
failures, or host swapping.

Evidence:

- `var/chaos/checks/dbfix-prepared-caches.txt`
- `var/chaos/checks/dbfix-top-prepared.txt`
- `var/chaos/checks/dbfix-prepared-cadence-75d68c8dd6-jsnwc.json`
- `var/chaos/checks/dbfix-prepared-cadence-75d68c8dd6-wfm7s.json`

## Changes

Protocol archive indexes, ingress archive indexes, observation identity batches,
and transition-evidence batches use uncached bulk statements. Ordinary query
caching remains unchanged. Batch size limits, transactional writes, identity
conflict checks, ownership fencing, and durability requirements are preserved.

The protocol archive writer converts database connection/query exceptions into
explicit flush failures. It retains the buffer, rejects further enqueues for
that mission while blocked, and retries with exponential delay capped at five
seconds. Unacknowledged work remains in the journal. A failed batch retains its
segment identifier, so retries reuse its immutable file instead of creating
orphan files. Stale timer messages cannot bypass retry scheduling. Resetting
metrics does not clear backpressure or alter retry state.

## Validation

The 35 focused tests passed. They cover database exceptions, unchanged writer
PID, timer-driven recovery, bounded buffering under repeated caller retries,
metric-reset independence, file reuse, record retrieval, and absence of large
retained bulk statements. Existing archive idempotency, conflict, and observation
revision tests also passed. Evidence:
`var/chaos/checks/dbfix-final-focused.log`.

The full `mix precommit` run passed: 2,720 Cadence tests, 960 web tests
(one excluded), 144 simulator tests, 336 foundation tests, and 42 plane tests,
plus formatting, compilation, lint, catalog and architecture checks. Evidence:
`var/chaos/checks/dbfix-precommit.log`. The ten Python lab tests also passed.

The first commit hook exposed an existing coordinator-test race: a DOWN reply
can arrive before Registry removes the terminated owner. The test now waits
for that cleanup before asserting successful retry. All 13 coordinator tests
and 21 consecutive runs of the affected case passed. Runtime source and the
validated image were unchanged by this test synchronization fix. Evidence:
`dbfix-coordinator-test.log` and `dbfix-coordinator-repeat.log` under the same
checks directory. The final commit uses the normal hook's `full` profile to
rerun `mix precommit` with this test change included.

The candidate image is `cadence-chaos:e35feebf-dbfix-final-1792903728`. To avoid
recreating the large frontend/dependency build cache on the constrained disk,
the five changed backend modules were compiled inside the previous Linux release
image and copied into its release. The parent is
`sha256:fcb1a13e550affd7dab9ace382dc4a58b12dea5dded9cd6b0491475f72fbbbb2`.
No dependencies, release module inventory, frontend assets, or configuration
changed. The reproducible build recipe and exact source hashes are retained in
`var/chaos/checks/dbfix-image-context/` and
`var/chaos/checks/dbfix-image-sources.json`; build output is in
`var/chaos/checks/dbfix-final-build.log`.

Before a new baseline could start, OrbStack entered disk pressure and evicted
the lab application and dependencies. The remaining Docker build cache was
reclaimed (1.247 GB). Node and pod snapshots are in
`var/chaos/checks/dbfix-disk-pressure-{node,pods}.json`.

The user authorized wiping the accumulated container and volume data. The old
Cadence lab namespace and its four volumes were removed, along with the Docker
Compose telemetry stores. The Kubernetes volumes alone held about 62 GiB:
41 GiB PostgreSQL, 11 GiB archives and 9.9 GiB QuestDB. The local-path cleanup
pods were themselves evicted, so the already-released volumes were cleared
through Docker after all lab pods had stopped. Source, run reports and the
candidate images were retained; local non-container PostgreSQL was untouched.
Fresh infrastructure uses the same resource limits and load profile: three
Cadence replicas (four during surge), PostgreSQL limited to 1 GiB, 500 configured
spacecraft, ten live contacts at `LAB_RATE_HZ=0.2`, and a ten-second freshness
threshold. The fresh database is `cadence_chaos`. The candidate image digest is
`sha256:ea5ca300c94d4ad7d5764cdfeeb45d76664b271ce847bef621f53a8824e1daa4`.

### Startup and infrastructure recovery

`var/chaos/runs/20261025T050717Z-startup/` passed: three replicas ready in
15.8 seconds, all ten source partitions recovered on every replica in 17.3
seconds, no restarts or OOM kills, and container memory peaks of 493–539 MiB.
The first fresh baseline also passed (`20261025T050921Z-baseline`): 20 samples,
maximum feed age 5.28 seconds, 20 immutable archive objects checked, 294 commits
audited without regressions, and no source drops.

After that baseline, with traffic paused, Docker and the Kubernetes API stopped
responding. An orderly OrbStack restart restored service, but the VM was then
observed 64 minutes behind the host. This would invalidate the harness's recent
receipt-time bounds. A temporary sleep inhibitor and a second orderly restart
restored clock alignment (measured drift 0.54 seconds). Cadence initially
restarted while PostgreSQL was unavailable during infrastructure recovery;
the workloads subsequently became ready. These infrastructure restarts are
separate from the rolling experiment. Evidence is in
`var/chaos/checks/dbfix-orb-clock-drift.json` and `dbfix-orb-recovery-*`.

### Repeated baseline and rolling deployment

Validation was repeated after recovery with a full continuous healthy minute
before each experiment and an additional health check immediately before the
rolling restart. Traffic was paused for the full-history audits outside the
timed windows.

| Measurement | Baseline | Rolling replacement |
| --- | --- | --- |
| Run | `20261025T073218Z-baseline` | `20261025T073451Z-rollout` |
| Timed window / samples | 60 seconds / 24 | 180 seconds / 70 |
| HTTP / freshness failures | 0 / 0 | 0 / 0 |
| Maximum feed age | 5.01 seconds | 5.16 seconds |
| Archive objects, unchanged and accessible on every replica | 26 | 27 |
| Semantic commits audited / sequence regressions | 567 / 0 | 1,082 / 0 |
| Source drops / artifact errors | 0 / 0 | 0 / 0 |

Both runs passed. All three old pods drained successfully in 10.054–10.078
seconds, including the ten-second readiness delay. Their 30 retained journal
streams had **zero bytes beyond either the processing or archive checkpoint**
and zero unscanned bytes. The three replacement pods had no restarts.
No database timeout or archive-writer error appeared in the collected rolling
logs. PostgreSQL had no OOM kills; its peak total cgroup memory during the
rolling rehearsal was 685.2 MiB (anonymous memory peaked at 362.6 MiB; file
cache peaked separately at 398.3 MiB).

BEAM inspection checked out all ten Repo connections on each replica after
both runs. None of the 30 connections retained a named bulk insert statement;
the largest retained prepared statement had 30 parameters. After rolling,
plan-related memory totaled 31.1–31.9 MiB per ten-connection pool. Every archive
writer reported successful flushes and zero flush failures. The baseline and rolling traffic intervals
inserted 273 and 515 semantic commits respectively, with no routine monitoring
evaluation rows. Alarm transitions and evidence remain covered by the focused
transaction and retry tests. This verifies the
cache behavior change; the fresh dataset and infrastructure reset prevent
attributing all latency improvement solely to that change.

Evidence: `var/chaos/checks/dbfix-{baseline,rollout}-*`,
`dbfix-inspect-{baseline,rollout}.json`, and the two run directories above,
including OTel snapshots, archive hashes, journal checkpoints and state audits.

### Sudden termination exposure

`var/chaos/runs/20261025T073936Z-pod-kill/` targeted the active receiver
`cadence-674576547c-lzskb` with Chaos Mesh `pod-kill` and `gracePeriod: 0`,
after another healthy three-replica preflight. It passed all 71 samples over
180 seconds: no HTTP/freshness failures, maximum feed age 5.09 seconds,
46 archive objects unchanged, 1,607 commits audited without regressions,
zero source drops and no artifact errors.

The killed pod's ten retained streams had zero bytes beyond either durable
consumer checkpoint and zero unscanned bytes. There was therefore no exposed
processing suffix requiring a commit-coverage scan in this sample
(`exposure-coverage.json`). This does not measure bytes in TCP buffers, sender
queues or partial protocol reassembly, and does not bound worst-case crash
exposure. Automatic handoff remains deferred. The lab was left at three Ready
replicas with synthetic traffic paused after validation.

### Protocol-continuity follow-up

A final database inspection found protocol-counter warnings at generator
restarts and receiver replacement, despite continuous archived frame counters.
During rolling replacement, feed 7's warning expected counter 95 and observed
43, while archived frames actually advanced from 42 to 43. The sudden-kill run
also recorded stale counter comparisons on feeds 4, 8 and 10. This identifies
protocol continuity-state recovery as follow-up work; it is distinct from the
semantic-state sequence audit and from the database/archive-writer fixes.

A separate audit checked 4,810 archived frames during the rolling window and
4,940 during the sudden-kill window, spanning all ten spacecraft. Neither had
a within-batch or between-batch modulo-256 sequence discontinuity or duplicate
counter within a batch. Evidence is in each run's
`archive-frame-continuity.json` and `archive-frame-batches.json`, with anomaly
details in `var/chaos/checks/dbfix-protocol-anomalies.json`. This counter audit
cannot rule out a whole 256-frame-cycle gap or establish exactly-once delivery.

This is a fresh, single-node lab validation with ten live spacecraft. It does
not certify 500 simultaneous contacts or multi-day retention behavior. The
accumulated data was reset, not given a new retention policy. Automatic journal
handoff and a lossless sudden-termination guarantee remain deferred.
