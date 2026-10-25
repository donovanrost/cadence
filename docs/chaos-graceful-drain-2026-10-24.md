# Graceful draining and sudden-termination exposure

## Scope

Planned shutdown now withdraws readiness, closes new lifecycle admissions,
stops local control workers, and quiesces contacts while runtime, database, and
archive resources remain available. TCP receivers finish an in-flight journal
append after their socket closes. Both processing and archival must reach each
journal's captured tail; sealing syncs data and persists the final consumer
positions before stopping mission runtimes.

One process-wide coordinator shares the result between concurrent release RPC
and OTP shutdown requests. Its deadline, callback failures, and restart behavior
are explicit and fail closed. The Kubernetes hook allows 65 seconds, including
a ten-second readiness propagation delay, inside the existing 90-second grace
period. Logs and a lifecycle telemetry event record outcome and duration.

Automatic journal handoff remains deferred. Replacement pod UIDs start separate
journals; retained old tails remain available for investigation. No StatefulSet,
new durable queue, cross-pod journal lease, or zero-byte crash-loss guarantee is
introduced.

## Rehearsal environment

- Image: `cadence-chaos:e35feebf-drain2-1792893383`, digest
  `sha256:78b2cea3589061349575ab9e1ae647f0111d13a836a10f6fe623faab11919dbe`.
- Existing database: `cadence_chaos_20261023_233753`; all history retained.
- Reflect Orbital: 500 configured spacecraft; ten live contacts at `LAB_RATE_HZ=0.2`.
- Three replicas, a fourth surge replica during rollout, and a ten-second
  per-feed freshness threshold. Existing resource limits unchanged.
- One OrbStack node on the same laptop. The local build and test workloads
  finished before the timed baseline.

## Validation evidence

The final image's simultaneous startup passed: Kubernetes readiness in 17.0
seconds, all ten partitions recovered on every replica in 18.0 seconds, no
restarts or OOM kills. Container memory peaks were 547–559 MiB.
Evidence: `var/chaos/runs/20261025T020122Z-startup/`.

The first 60-second baseline passed all checks: 14 samples, no HTTP or freshness
failures, maximum feed age 5.71 seconds, 172 archive objects accessible with
unchanged hashes on every replica, zero source drops, and no regressions in
10,384 semantic commits.
Evidence: `var/chaos/runs/20261025T020302Z-baseline/`.

The immediately following rollout attempt was refused before injection because
freshness had deteriorated after its full-history audit. A subsequent diagnostic
sample found feed ages up to 44.31 seconds; another sample about a minute later
found all feeds below 4.8 seconds. PostgreSQL logged canceled writes and lost
client connections during the stall. Its OOM counters did not increase. This is
not attributed conclusively to swapping, and it is not counted as a rollout
failure because no rollout occurred.

The retry preserved its audit (11,133 commits, zero regressions) and required a
full minute of three Ready replicas and all ten feeds below ten seconds after
the audit. It could not establish that healthy minute: queries timed out and
feed ages reached 38–86 seconds. It was interrupted before injecting a fault.
Its samples and audit are retained in
`var/chaos/checks/drain-settled-rollout-*`.

PostgreSQL subsequently suffered repeated backend OOM kills inside its unchanged
1 GiB cgroup limit, beginning at 02:16:07 UTC. Synthetic traffic was paused, but
database recovery/retry cycles continued. A 02:21–02:22 UTC capture recorded
anonymous memory rising from about 91 MB to 739 MB before another OOM kill;
memory was spread across multiple backends, including idle connections. This
does not identify the allocating SQL or prove a single cause. Evidence is in
`var/chaos/checks/drain-pg-memory-cycle.txt` and `drain-pg-recovery.log`.

The stalled statements included observation identity rows, monitoring
evaluations, and archive indexes. A sample of the latest 100 semantic commits
averaged 45,340 bytes of input, 73,122 bytes of result, and 23,364 bytes of full
runtime state, each already encoded with term compression. The small checkpoint
table references those commits rather than storing another state copy. Retained
table sizes include earlier lab runs and are not attributable solely to this
rehearsal.

No rollout or pod-kill fault was injected in these attempts. Work shifted to
removing routine monitoring evaluation writes before retrying validation.

## Sparse monitoring evaluation follow-up

Routine normal and unchanged-alarm evaluations no longer write separate
`semantic_monitoring_evaluations` rows. Transitions retain their supporting
evaluation in the same transaction as the transition and latest-state update.
Existing history, acknowledgements, idempotency, and late-arrival ordering are
preserved. Monitoring execution and the full semantic recovery result remain
unchanged.

Local verification passed: 29 focused tests, ten Python lab tests, and the full
`mix precommit` command (exit zero). The latter includes 2,719 Cadence tests,
960 web tests with one excluded browser test, 144 simulator tests, and the
catalog, protocol, architecture, and plane checks. Logs are retained in
`var/chaos/checks/monitoring-focused.log` and
`var/chaos/checks/monitoring-precommit.log`. The changed application source and
test files still match the hashes captured when the deployed image was built.

The image is `cadence-chaos:e35feebf-monitoring-1792898662`, digest
`sha256:fcb1a13e550affd7dab9ace382dc4a58b12dea5dded9cd6b0491475f72fbbbb2`.
Its first simultaneous startup reached readiness in 16.2 seconds and recovered
all ten partitions on every replica in 17.8 seconds, without restarts or OOMs.
Peak container memory was 493–562 MiB.
Evidence: `var/chaos/runs/20261025T033016Z-startup/`.

The first preflight could not produce a healthy minute: the lab's freshness
query scanned all retained archive history and timed out. The sampler now uses
the existing mission/kind/receipt-time index with a recent time bound, held
fixed throughout each experiment so counts do not age out of throughput deltas.
It still requires all ten fresh feeds, and the semantic sequence audit still
checks all retained commits. Database sample duration is now recorded separately.

During that attempt, Kubernetes also declared node disk pressure and evicted
the dependencies and application pods. This invalidates the run independently
of the sampling problem. No rollout fault was injected. Disposable Docker build
cache cleanup reclaimed 11.15 GB; all lab images and persisted data were retained.
Terminal pod metadata and available logs were saved before removing terminal
pod objects. Evidence is in `var/chaos/checks/monitoring-fullscan-baseline-*`,
`monitoring-node-events.txt`, and `monitoring-terminal-pods/`.

After recovery, a second startup passed with the same image and database
(`var/chaos/runs/20261025T034217Z-startup/`). An additional preflight found the
same full-history scan in the latest-frame archive selection query; that query
now also selects recent frames using the existing index. The failed preparation
is retained in `var/chaos/checks/monitoring-archive-scan-baseline-*`.

### Completed baseline

`var/chaos/runs/20261025T034902Z-baseline/` passed all checks:

- 23 samples over the 60-second window, zero HTTP/freshness failures, maximum
  feed age 4.89 seconds, with the unchanged ten-second threshold.
- 204 sampled archive objects retained with unchanged hashes on every replica.
- 12,247 semantic commits audited, zero state-sequence regressions.
- Zero source drops and no artifact capture errors.

Across the surrounding 193-second traffic interval, PostgreSQL inserted 51,515
observation identity rows and 370 semantic commits, with zero monitoring
evaluation or alarm-transition rows. A bounded BEAM inspection of ten recent
commits found 830 evaluations and zero transitions, confirming monitoring still
executed. WAL grew by 317,355,644 bytes during that interval. The baseline does
not isolate the effect of the evaluation change from the sampling corrections
and infrastructure recovery. PostgreSQL reached its cgroup limit with cache
included, but recorded no OOM kills.

### Failed rolling deployment

`var/chaos/runs/20261025T035347Z-rollout/` started after another full healthy
minute and passed a fresh three-replica health gate immediately before injection.
It failed continuity: 22 of 32 samples failed freshness, with a maximum measured
age of 64.27 seconds and a final database-query timeout. HTTP samples remained
200. There were no PostgreSQL OOM kills or container restarts. Host measurements
showed approximately 45 MiB/s of swap reads and 66 MiB/s of swap writes during
the stall; this is evidence of resource contention, not an attribution of every
failure to swapping.

Two old pods drained successfully in 14.78 and 12.16 seconds, including the
ten-second settling delay. The third drain failed while waiting for quiescence;
its process was shut down and the container ultimately exited 137. The rollout
eventually reached three Ready replacement replicas. Synthetic traffic was
manually paused after the timed window while the rollout recovered. Two OTel
artifact queries timed out (`otel-memory.json` and `otel-ownership.json`).

The failed pod logged database connection refusals and request timeouts before
the drain failed. Its archive writer then crashed on a database queue timeout
at 04:00:32 UTC, followed by the quiescence caller's shutdown at 04:00:33 UTC.
Kubernetes also recorded repeated one-second PostgreSQL readiness-probe
timeouts. The database container's survival therefore does not establish
continuous database availability to Cadence. At this stage the failures remained unresolved;
the evidence does not isolate the initial cause or establish that extending
the drain deadline would resolve it. Relevant logs and structured events are
in `var/chaos/checks/monitoring-live-logs/` and
`var/chaos/checks/monitoring-rollout-final-events.json`.

All 207 sampled archive objects remained accessible with unchanged hashes, and
12,832 semantic commits showed no sequence regressions. Source logs reported
zero dropped outputs. These successes do not override the failed continuity and
drain verdicts.

The retired pods' 30 journals contained 3,580,265 bytes beyond their durable
processing checkpoints, zero bytes beyond archival checkpoints, and zero
unscanned bytes. A checksum-verified range audit matched seven semantic commits
covering part of that suffix; 3,014,960 bytes had no matching commit in the audit.
These are pending-processing measurements, not an unrecoverable raw-data-loss
claim. Automatic journal handoff remains deferred. The failure already includes
a forced termination under load; a separate healthy-baseline pod-kill experiment
has not been run.

This attempt did not satisfy the rolling-deployment acceptance gate, so the
commit was deferred while the database and archive-writer failures were investigated.

## Database-recovery follow-up

The subsequent [database recovery report](chaos-database-recovery-2026-10-24.md)
records the fixes, the user-authorized reset of accumulated lab data, and the
successful fresh three-replica startup, baseline and rolling rehearsal. All
three old pods drained in about 10.1 seconds including the ten-second settle
delay; their 30 journal streams had zero processing or archive checkpoint lag.
A subsequent zero-grace pod kill also passed continuity and archive checks;
its ten retired streams had zero measured checkpoint lag in that sample.
The failed retained-history run above remains evidence of the earlier problem,
not a passing result or a multi-day retention certification.

## Interpretation

The runner now records pod UIDs before injection and totals exposure only for
pods retired during that experiment. A planned rollout must leave zero complete
journal bytes beyond either durable consumer cursor and no unscanned record
bytes, in addition to passing continuity, archive-integrity, and semantic-state
checks.

The sudden-termination experiment explicitly uses zero grace time. Durable
checkpoint lag is an exposure measurement, not itself proof of missing semantic
work: completed commits can precede checkpoint persistence. Exposed ranges must
be compared with semantic evidence identities before reporting uncommitted
bytes. Socket buffers, sender queues, partial protocol reassembly, and node-loss
durability are outside this journal-tail measurement. Uplink/command delivery
and a quantitative acceptable crash-loss budget remain separate work.
