# OrbStack resilience rehearsal — 2026-10-21 UTC

**Cadence did not meet the continuous-operation delivery gate.** The lab can now
build releases, seed the 500-spacecraft Reflect Orbital tenant, run multiple
replicas, inject scoped Chaos Mesh faults, and collect application and OTEL
evidence. Healthy HTTP probes did not imply healthy mission operations.

Use the [runbook](how-to/run-chaos-lab.md) to reproduce the environment. Raw local
evidence is under `var/chaos/`; it is ignored by Git and must be copied separately
if these findings need to be shared. Times and run directory names are UTC.
The isolated PostgreSQL state after the faults is preserved in
`var/chaos/bootstrap/postgres-after-chaos.sql.gz` for replay investigation.

## Workload and environment

- OrbStack Kubernetes v1.34.8+orb1, Docker runtime, one physical node. The VM had
  8 GiB of memory on a 16 GiB laptop. This is a replica/process rehearsal, not a
  node or availability-zone test.
- Chaos Mesh 2.8.5; only `cadence-chaos` is enabled for injection. PostgreSQL,
  QuestDB, provider simulator, and credentials are isolated from development.
- Server image `cadence-chaos:301ad377-1792561894`, built from the working tree
  based on commit `301ad377`; the tag is not a claim that the changes were committed.
- All **500 spacecraft activated**, with 5,000 telemetry capability bindings,
  1,000 source runtime bases, and 27 commands per spacecraft verified by the seed.
- **Ten** synthetic contacts transmit continuously, with `LAB_RATE_HZ=0.2` and
  ten packet families per source: approximately **20 packets/second** and
  **26 archived transfer frames/second**. The other spacecraft are configured but
  not transmitting. The scripts default to 1.0 Hz; these measurements do not
  establish capacity for 500 simultaneous contacts.
- Application journals and archives use pod-local `emptyDir`; PostgreSQL and
  QuestDB retain their volumes. This deliberately exposes existing filesystem
  assumptions. It is not a proposed production persistence design.

## Measured results

| Exercise | Observation | Conclusion |
| --- | --- | --- |
| One replica, fresh contacts, 60-second baseline | 24 samples; zero HTTP or freshness failures; 26.49 indexed frames/s; HTTP p95 731.7 ms; all three sampled archive objects remained present | Passed this narrow baseline |
| Scale from one to three while contacts were active | All replicas became Ready, while telemetry exceeded the 10-second freshness threshold; some feeds remained hundreds of seconds behind | Scale-out interrupted operations |
| Chaos Mesh pod kill, three replicas | Injection confirmed; replacement became Ready; zero HTTP failures, 26/26 freshness failures, 20 simulator-reported dropped outputs, three of seven sampled archive files lost | Failed resilience; started unhealthy, so telemetry disruption cannot all be attributed to the kill |
| Network delay, 200 ms ± 50 ms for 30 seconds | Injection and recovery confirmed; zero HTTP failures in 34 samples; telemetry already stalled | Diagnostic plumbing check only; no passing operations verdict |
| Pod failure for 30 seconds | Injection and recovery confirmed; zero HTTP failures in 32 samples; telemetry already stalled | Diagnostic plumbing check only; no passing operations verdict |
| PostgreSQL network partition for 30 seconds | Bidirectional injection and recovery confirmed; one HTTP timeout in 33 samples; telemetry already stalled | Diagnostic failure; no passing operations verdict |
| Same-image rolling restart, three replicas | Replacement completed; zero HTTP failures in 28 samples across 120 seconds; no new indexed frames | HTTP remained reachable; continuous operations did not recover |

The one-replica baseline is `runs/20261021T055828Z-baseline`. The injected kill is
`runs/20261021T060838Z-pod-kill`. Its `experiments.json` records a successful
injection against the archive-holding receiver `cadence-bfbb54d5f-8442s`.
`archive-before.json` and `archive-after.json` identify the lost objects.

The delay and pod-failure runs are `runs/20261021T061457Z-network-delay` and
`runs/20261021T061637Z-pod-failure`. They targeted a Ready replica after the failed
recovery, with `target_holds_archive=false`. They demonstrate that Chaos Mesh can
apply and remove these faults on OrbStack; they do not demonstrate active stream
failover. Archive objects missing before a diagnostic run are not attributed to
that run's fault.
The database-partition run is `runs/20261021T061815Z-database-partition`; its HTTP
request timed out after 3.14 seconds at 06:18:35Z, shortly after injection.
The rolling restart is `runs/20261021T061956Z-rollout`. It also began unhealthy
and is diagnostic-only. No experiment in this rehearsal established safe delivery
between two different application versions.

An earlier attempted injection, `runs/20261021T060526Z-pod-kill`, selected no pod
because the namespace opt-in was mistakenly a label instead of an annotation.
The harness failed that run, the configuration was corrected, and the injection
was rerun. It is not evidence of resilience. Setup attempts without completed
summaries are also excluded from measured results.

## Delivery blockers exposed

### Durable bytes and stream identity must survive replacement

The archive index survives a pod deletion, but its files do not. More subtly,
ingress journal stream IDs derive from contact/path/provider identity, while a
new empty journal restarts byte positions at zero. Frame record IDs reuse those
stream positions. Conflict-ignore archive inserts then retain the earlier index
row even when newly received bytes differ or live in a new object.

`bootstrap/journal-id-collision.txt` captures one exact collision: frame ID
`frame_14e27755d2685e826a538b33c3a166e003b00cf21464af8cc1569dfc44e94fa2`
was received into a new pod's file at **05:56:32.926762Z**, while its database row
still reported **05:37:14.477451Z** and referenced the deleted pod's object.
Relevant implementation points are `IngressJournal.FileSystem.stream_id/1`,
`IngressJournal.Identity`, `Protocol.TMFrameIngress`, and
`Protocol.RecordArchive.Filesystem` conflict handling.

Production needs durable archive access plus recoverable stream positions and
an explicit identity/epoch policy. An epoch alone would avoid collisions but
would not recover lost bytes, prevent duplicates, or fence an old writer.

### Replica count does not establish exclusive runtime ownership

Every replica recovers the active mission into node-local supervisors, registries,
and projections. Runtime snapshots show no connected Erlang peers. There is no
demonstrated cluster-wide lease or fenced handoff in this deployment. A Kubernetes
Service distributes new TCP connections; it cannot transfer an established stream
or reconcile process-local state.

During scale-out, the original mission coordinator blocked waiting for a partition
to start. The partition was running semantic-state recovery in
`Cadence.SemanticRuntime.scoped_latest/2`; other ingress calls timed out at five
seconds. See `bootstrap/blocked-partition.txt`, the coordinator snapshots, and
`bootstrap/scale-three-errors.log`. These are observations of blocking recovery,
not proof of a permanent deadlock. The laptop's resource contention also limits
performance attribution.

After the kill, resetting contacts at three replicas blocked for over three
minutes in synchronous contact shutdown. The generator was paused, old contacts
were canceled, and the application was restarted. Creating new contacts then
failed partition recovery with `semantic_runtime_replay_diverged`. The database
was preserved for investigation. That attempted recovery is an operational
interruption and is excluded from continuity verdicts; see
`bootstrap/renew-three-interrupted.txt` and `bootstrap/semantic-replay-diverged.log`.

### Readiness and shutdown need an operations contract

The new `/health/live` probe checks HTTP liveness. `/health/ready` checks database
access and a preStop drain marker. They deliberately do not claim completed
mission recovery, archive accessibility, or ownership. Their green status during
stale telemetry is direct evidence that more is needed before using readiness as
a delivery gate.

The Deployment uses zero unavailable replicas, one surge replica, a minimum ready
time, and a termination grace period. These preserve HTTP capacity but cannot
provide a fenced stream handoff or make pod-local files durable. Database changes
also require expand/contract compatibility; a same-image restart does not prove
old/new version compatibility or rollback safety.

### Concurrent bootstrap and activation need recovery coverage

Cold concurrent startup hit a default data-source primary-key race on two
replicas (`bootstrap/replica-startup.log`). During an earlier image build plus
three fleet recoveries, activation was OOM-killed with the original 3 GiB container
limit. The generation was committed but its execution receipt was
still in progress. The seed now resumes that same approved execution and verifies
its completion. Evidence is in `bootstrap/pods-after-activation.json` and
`bootstrap/seed-resource-pressure.log`.

The lab now defaults to a 4 GiB per-container ceiling and bootstraps the fixture
on one replica before scale-out. This does not eliminate aggregate VM contention
or prove a production memory requirement.
A final cold restoration at three replicas also OOM-killed one pod with the 4 GiB
limit configured; it became Ready after an automatic restart. See
`var/chaos/final-pods.json` and `bootstrap/final-startup-retry.log`. Raising the
per-container ceiling did not eliminate recovery memory pressure on this VM.

## OTEL evidence

Metrics, logs, and traces reached the existing GreptimeDB, Loki, and Tempo stack
with `service.name=cadence-chaos` and per-pod identity. The first kill/recovery
window showed new replicas reaching approximately **1.9 GiB of BEAM memory**,
telemetry freshness reaching **418.8 seconds**, and scheduler run queue reaching
**23**. Saved queries are in `var/chaos/observability/`; later experiment folders
include their own `otel-*.json` snapshots. These are observed peaks in the queried
window, not capacity limits or a diagnosis by themselves.

The [SRE dashboard](http://localhost:3000/d/cadence-sre-overview?var-service=cadence-chaos&var-mission=mission-earendil-demo)
can correlate pod identity, recovery memory, freshness, database latency, and
errors with each run's action timestamp. Direct SQL freshness sampling remains
part of the gate so a responsive HTTP endpoint or a quiet queue cannot conceal
stalled persistence.

## Next acceptance gates

1. Establish durable journal/archive storage, restart-safe stream identity, and
   sequence reconciliation across crash/replay boundaries.
2. Define the owner of each contact/ingress partition, acquire a lease with a
   fencing token, and prove that replacement cannot create two active writers.
3. Make recovery bounded and isolated so one recovering partition cannot block
   unrelated feeds. Define readiness and drain acknowledgements around ownership
   and accepted work, with sufficient surge resources.
4. Repeat healthy three-replica fault and rollout runs, then test an actual
   old-to-new image pair with compatible migrations. Measure frame gaps,
   duplicates, archive readability, reconnect time, and WebSocket continuity.
5. Add uplink scenarios covering acknowledged, unacknowledged, and ambiguous
   command effects, then increase simultaneous contacts and use multiple nodes.

This rehearsal tests synthetic downlink only. It does not certify lossless
delivery, exactly-once command effects, production continuous delivery, or
multi-node resilience.

## Code validation and retained environment

- `mix precommit` passed, including 2,663 core tests, 138 simulator tests, and
  959 web tests, plus the workspace/architecture checks and plane-specific tests.
- `corepack pnpm check` and `corepack pnpm test` passed. The ordinary frontend
  suite's producer-only exclusions remain intentional; native producer fixtures
  also execute through the backend suite.
- The production browser run passed eight of nine journeys after updating stale
  typed-header assertions. The remaining command-workspace journey passed its
  targeted rerun after correcting the relocated refresh-button selector. The
  publication build and browser contract checks passed. These browser checks use
  native test fixtures, not the 500-spacecraft Kubernetes dataset.
- All six Python runner tests passed. They cover missing/stale feeds, failed
  injection evidence, diagnostic verdicts, namespace opt-in, and rollout isolation.

Completed check logs are retained in `var/chaos/checks`. Pre-existing validation
failures encountered during image preparation also required correcting the
QuestDB smoke's ILP write callback, the producer heading harness, a timing-sensitive
test, and the reviewed frontend output digest. The expired dependency review was
renewed after confirming its zero-violation baseline and existing startup callers.

The application is left at three replicas with synthetic traffic paused. The
databases, simulator, Chaos Mesh, and existing OTEL stack are retained; fault
objects are removed. The failed dataset is deliberately preserved. Kubernetes
Ready status does not mean its telemetry recovery failures have been repaired.
