# OrbStack resilience lab

This lab builds Linux OTP releases, deploys three Cadence replicas into the
`cadence-chaos` namespace, and exercises active synthetic contacts during pod
failures and rolling replacements. Every Kubernetes command pins the `orbstack`
context. It has its own PostgreSQL, QuestDB, provider simulator, and credentials.
It never uses the development database or a real ground provider.

The [durability rehearsal](../chaos-lab-results-2026-10-22.md) verifies retained
archive objects and restart-safe journal identities, while exposing remaining
runtime handoff failures. The [first rehearsal](../chaos-lab-results-2026-10-21.md) exposed
scale-out interruptions, archive loss, and replay failures. This is a diagnostic
environment; it is not a production-ready deployment recipe.

The Reflect Orbital tenant contains **500 synthetic spacecraft**, their complete
command/telemetry configurations, ten ground sites, and two provider routes per
spacecraft. The traffic profile keeps **ten simultaneous contacts** open for eight
hours. At the default `LAB_RATE_HZ=1.0`, it emits ten packet families per spacecraft
per second: 100 packets/second, not 500 simultaneously transmitting spacecraft.
The first-run command below uses `0.2` (20 packets/second), matching the initial
rehearsal. Increase `LAB_RATE_HZ` to exercise throughput independently of fleet size.
Generator updates use `Recreate` to prevent overlapping senders for one source.
Set the rate before a run and keep the generator deployment unchanged throughout
application rollouts and fault injection.

## Prerequisites and first run

Run from the repository root. Install OrbStack, Python 3, kubectl, and Helm.
OrbStack's built-in Kubernetes is single-node; its Docker images are directly
available to pods. No registry credentials are needed. The initial build downloads
the pinned Elixir/OTP and Node images and compiles both releases and frontend
assets. No application secrets are supplied to the build.

```sh
# Keep the existing observability stack running. Starting Kubernetes for the first
# time can restart OrbStack's engine; restart these Compose services afterward.
orb start k8s
docker compose up -d greptimedb tempo loki otel_collector grafana questdb

python3 dev/chaos/lab.py build
python3 dev/chaos/lab.py mesh
python3 dev/chaos/lab.py up --replicas 1
python3 dev/chaos/lab.py seed
python3 dev/chaos/lab.py warm
python3 dev/chaos/lab.py scale 2
python3 dev/chaos/lab.py warm
python3 dev/chaos/lab.py scale 3
python3 dev/chaos/lab.py warm
LAB_RATE_HZ=0.2 python3 dev/chaos/lab.py traffic
python3 dev/chaos/lab.py status
```

`up` applies infrastructure, runs a one-shot migration Job, then deploys the
application (three replicas by default; the laptop bootstrap above starts with one).
`seed` is rerunnable: it migrates the lab QuestDB, seeds the existing
fixture, activates the exact 500 saved revisions, creates continuous synthetic
contacts, and starts the persisted mission on each replica. This explicitly
selects direct activation for the **lab Earendil mission only**. The fixture's
production escape hatch requires both `CADENCE_CHAOS_LAB=true` and
`POD_NAMESPACE=cadence-chaos`; neither is set in normal releases.
The lab Dockerfile also appends a guarded runtime configuration that enables
local provider credentials for the synthetic simulator and sets logging to info.
This configuration is not part of the normal production release.
If a killed activation executor committed its generation but did not finish its
execution receipt, the seed resumes that same approved execution before verifying it.

Open <http://cadence.cadence-chaos.svc.cluster.local:4001/sign-in>.
The generated administrator credentials are in `var/chaos/credentials.json`
(mode 0600, ignored by Git). Image tags are saved in `var/chaos/images.json`.
Secrets are reused across invocations. Do not delete them while retaining the
database volume.

If direct OrbStack DNS access is disabled, use a port-forward for interactive UI
access. **Do not use a port-forward to evaluate HTTP failover**: it pins a single
pod and is not the Kubernetes Service load balancer.

```sh
kubectl --context orbstack -n cadence-chaos port-forward service/cadence 14001:4001
# Open http://localhost:14001/sign-in; this exact origin is allowed by the lab image.
```

On a laptop, finish image builds before activating the full fleet or benchmarking.
Each replica currently recovers the entire mission, so fleet recovery duplicates
memory and CPU work. Start with `scale 1` before `seed` if memory is constrained,
then scale to three after activation. Keep a surge replica's recovery footprint
available during rollouts. A build running alongside three recoveries exhausted
the initial lab's 3 GiB container limit during activation.
The default per-container limit is now 4 GiB; override it with `LAB_APP_MEMORY`
before `up`. Limits are ceilings, not reserved capacity: the single OrbStack VM
must still have enough memory for replicas, the surge pod, databases, and OTEL.

The [model-copy follow-up](../chaos-model-memory-2026-10-22.md) records successful
simultaneous startup after removing fleet-model copy amplification. The staged
bootstrap above remains available for smaller development hosts.

## Simultaneous startup measurement

After seeding a deployment, measure all replicas starting together:

```sh
kubectl --context orbstack -n cadence-chaos scale deployment/cadence deployment/traffic --replicas=0
kubectl --context orbstack -n cadence-chaos wait --for=delete pod -l app=cadence --timeout=120s
kubectl --context orbstack -n cadence-chaos wait --for=delete pod -l app=traffic --timeout=120s
python3 dev/chaos/lab.py startup --replicas 3
LAB_RATE_HZ=0.2 python3 dev/chaos/lab.py traffic
python3 dev/chaos/lab.py run baseline --seconds 60
python3 dev/chaos/lab.py run rollout --seconds 180
```

`startup` requires the app and generator to be stopped. It starts all requested
replicas together, warms ten source partitions on each concurrently, and records
Kubernetes readiness time separately from complete partition recovery time. Its
artifact directory contains per-pod cgroup peaks (including early startup), BEAM
memory categories, OOM counters, and restart counts. A successful startup requires
all requested pods and partitions to recover without restarts or OOM kills. This
is a startup/memory verdict; the separate traffic runs determine continuity.
Use a seeded, pre-traffic dataset to isolate configuration startup from historical
replay, and retain the failed database when preparing an independent dataset.

`source_model_snapshot.exs` reports only sizes and model counts, without returning
the model through RPC. It compares the indexed representation with the former
source-to-full-model map and reports the full specification and binding-set sizes.
Do not use `:sys.get_state` to inspect fleet state: inspection itself copies it.

## Experiments and evidence

`warm` recovers the ten source partitions on each Ready replica before traffic.
Allow all ten feeds to become fresh before running an experiment. The runner
refuses to inject a fault without that baseline. Each experiment samples HTTP
readiness and the persisted transfer-frame index for each of the ten SCIDs.
It requires at least three Ready replicas initially; use
`--minimum-ready-replicas 1` only for an explicitly single-replica comparison.

If the deployment cannot establish a healthy baseline, `--diagnostic` permits an
explicitly diagnostic injection to troubleshoot the lab and application. Such a
run always fails the continuity verdict, even if it subsequently recovers. Its
results cannot separate pre-existing disruption from the injected fault. Baseline
captures can also record an unhealthy deployment without injecting anything.
If no replica has an established ingress connection, diagnostic mode can target a Ready
replica to test Chaos Mesh plumbing; `action.json` marks that fallback explicitly.
It does not demonstrate failover of an active stream.

```sh
python3 dev/chaos/lab.py run baseline --seconds 120
python3 dev/chaos/lab.py run pod-kill --seconds 180
python3 dev/chaos/lab.py run pod-failure --seconds 180
python3 dev/chaos/lab.py run network-delay --seconds 180
python3 dev/chaos/lab.py run database-partition --seconds 180
python3 dev/chaos/lab.py run rollout --seconds 240
```

The fault starts after 15 seconds. Network and pod-failure injections last 30
seconds. The pod-kill experiment deletes one application pod. Selectors require
both the lab namespace and application labels; PostgreSQL and the simulator are
excluded from pod kills. The runner narrows the selector to the replica with
the most established TCP connections on ports 42100–42109. Shared archive access
alone does not identify an active receiver. Database partition cuts that application's database
connection, leaving the other replicas available. Chaos Mesh namespace filtering
is enabled, and only this lab is annotated for injection. Experiment objects are
removed in cleanup so failed runs do not leave faults active.

Results are written to `var/chaos/runs/<UTC timestamp>-<experiment>/`:

- `samples.jsonl`: timestamps, HTTP status/latency, per-SCID frame counts and age.
- `summary.json`: measured continuity verdict and explicit limitations.
  Archive losses distinguish files already missing at the start from files newly
  missing after the action.
- `action.json`: fault/restart timing.
- `archive-before.json`, `archive-after.json`: sampled indexed archive objects and
  the pods that actually hold their files before and after the experiment.
- `archive-hashes-before.json`, `archive-hashes-after.json`: SHA-256 of both raw
  and protocol archive objects on every Ready replica. Changed bytes or missing
  access from any replica fail the resilience verdict.
- `receivers-before.json`, `receivers-after.json`: established ingress connection
  count per pod; `traffic-sockets.txt` captures source TCP state and queued bytes.
- `journals-before.json`, `journals-after.json`: retained journal namespaces,
  existing pod UIDs, complete-record tails, durable consumer checkpoints, and
  bytes beyond each checkpoint. Includes retired pods from earlier datasets;
  correlate the target UID before attributing backlog to a fault. Live snapshots
  are not atomic and checkpoints may lag completed processing.
- `semantic-sequence-audit.json`: read-only scan of ordered semantic commits for
  state-sequence regressions within a partition and runtime basis. Regressions
  fail the verdict; this check does not replace full deterministic replay.
- `pods.json`, `events.txt`, `experiments.json`, `cadence.log`, `traffic.log`.
- `node-events.json`: node events, including `SystemOOM`; `memory-before-<pod>.txt`
  preserves each initial container's memory measurements before replacement.
- `otel-memory.json`, `otel-freshness.json`, `otel-logs.json`, `otel-traces.json`:
  bounded queries against the existing OTEL backends for the experiment window.
- `runtime-<pod>.txt`: each replica's node identity, connected peers, local mission
  coordinator registration, memory, and per-spacecraft current-value counts.
  `LAB_MEMORY` includes BEAM categories, the ten largest processes (metadata only),
  cgroup current/peak memory, and OOM counters. `warm` prints
  `LAB_RECOVERY_MEMORY` with peak and final sampled breakdowns; its cgroup peak
  also covers startup before the sampler attached.

A healthy web response alone cannot pass: every expected feed must remain below
the freshness threshold (default ten seconds), and sampled archive files must
still exist after recovery. Missing historical files fail the overall resilience
verdict even if current telemetry remains fresh. A failure exits nonzero. This is a
test that also fails on simulator-reported dropped packets. It remains a
sampled continuity test, **not a proof of zero packet loss, duplicate-free command
delivery, or production readiness**. Source counters, sequence-aware reconciliation,
full archive decode/readability after replacement, command receipts, and WebSocket session
continuity are further acceptance gates. The summary deliberately never certifies
production delivery.

The original rehearsal reused journal record IDs after pod replacement. New
journals now have persisted incarnation IDs, but runtime ownership and replay
failures can still prevent recovery. After preserving a failed run, reset only
the synthetic contacts to attempt an independent baseline for the next experiment:

```sh
python3 dev/chaos/lab.py renew-contacts
```

This pauses the generator, cancels the fixture's current rehearsal contacts, stops
their runtimes on each replica, creates new contact identities, then resumes the
same generator configuration. Historical data and evidence are preserved. This is
manual recovery between experiments and must never be counted as uninterrupted
operation or automatic failover.
Contact shutdown or semantic replay can themselves fail after a fault. In that
case, preserve the error and database; the command leaves the generator paused.
Do not erase recovery state to turn a failed continuity run into a passing one.

For a separate rehearsal when an old database has divergent replay history, stop
the app and generator, then create a new database without deleting the failed one:

```sh
kubectl --context orbstack -n cadence-chaos scale deployment/cadence deployment/traffic --replicas=0
python3 dev/chaos/lab.py new-dataset
python3 dev/chaos/lab.py up --replicas 1
python3 dev/chaos/lab.py seed
python3 dev/chaos/lab.py warm
python3 dev/chaos/lab.py scale 2
python3 dev/chaos/lab.py warm
python3 dev/chaos/lab.py scale 3
python3 dev/chaos/lab.py warm
LAB_RATE_HZ=0.2 python3 dev/chaos/lab.py traffic
```

`var/chaos/dataset.json` records the new and preserved database names. Prior run
artifacts and the old database remain available. This is a new baseline, never
recovery evidence for the previous run. QuestDB historical data also remains.

## Scaling and delivery

```sh
python3 dev/chaos/lab.py scale 1
python3 dev/chaos/lab.py run baseline --seconds 120 --minimum-ready-replicas 1
python3 dev/chaos/lab.py scale 3
python3 dev/chaos/lab.py run baseline --seconds 120

# New source revision: build creates a unique timestamped tag.
python3 dev/chaos/lab.py build
python3 dev/chaos/lab.py deploy cadence-chaos:<new-tag>
```

Keep traffic running through builds and deployments. Run a long baseline capture
in another terminal while deploying to include the migration and rollout window.
`deploy` runs migrations before changing the Deployment image and stops on a
migration failure. It never automatically rolls back database changes. Use
expand/contract migrations: add compatible schema, deploy compatible readers and
writers, backfill, and remove old schema only after old replicas are gone and the
rollback window closes. The `run rollout` experiment performs a same-image rolling
restart; that exercises replacement/recovery but does not establish compatibility
between two different versions.

Application rollouts use `maxUnavailable: 0`, `maxSurge: 1`, a ten-second minimum
ready time, a 90-second termination grace period, and a preStop readiness marker
followed by ten seconds for endpoint propagation. `/health/live` checks HTTP
liveness; `/health/ready` also checks database access and the drain marker. These
probes intentionally do not claim runtime ownership or completed mission recovery.
The PodDisruptionBudget protects two replicas during voluntary evictions; it does
not prevent deliberate kills, involuntary failures, or application-level data loss.

## Observability

The lab emits OTLP to the existing collector via `host.docker.internal:4318`.
Set `LAB_OTEL_ENDPOINT` before `up` to select another collector. Resources include
`service.name=cadence-chaos`, `deployment.environment.name=chaos-lab`, pod name,
namespace, and unique `service.instance.id` for each pod. The simulator's counters
are retained in `traffic.log`.
The evidence collector reads GreptimeDB on port 4000, Loki on 3100, and Tempo on
3200. Override `LAB_METRICS_URL`, `LAB_LOGS_URL`, or `LAB_TRACES_URL` if those
backends use different addresses. Failed artifact queries prevent a passing run.

Open the existing [SRE dashboard](http://localhost:3000/d/cadence-sre-overview?var-service=cadence-chaos&var-mission=mission-earendil-demo).
Compare telemetry freshness and missed intervals, ingress/persistence queues,
backpressure, database latency, BEAM memory, and errors around the timestamps in
`action.json`. In Grafana Logs, filter `service_name="cadence-chaos"` and compare
pod identities; in traces, filter `service.name="cadence-chaos"`.

## Known architecture boundaries under test

- `Cadence.Control.MissionRecovery` recovers every active mission on each node.
  Its registries and dynamic supervisors are node-local. There is no demonstrated
  cross-pod placement lease or fenced handoff. Replicas can recover the same mission.
- Erlang nodes have unique names, but this lab does not invent distributed mission
  ownership or automatic discovery. Local ETS projections and PubSub do not become
  a coherent distributed runtime merely by increasing the replica count.
- Raw and protocol archives use the shared `cadence-archives` PVC. Publication
  syncs files and directory entries, prevents object replacement, and checks
  content hashes before accepting duplicate record IDs. Processing completion
  waits for protocol archive flush; the independent raw consumer waits for its
  durable receipt. This volume survives pod deletion. OrbStack's `ReadWriteOnce`
  permits multiple pods on its one node; a multi-node deployment needs suitable
  shared storage or an object-store backend. See the [Kubernetes access-mode
  contract](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes).
- Journals use separate `/data/journal/<pod UID>` directories on that PVC, so
  replicas never concurrently append to the same file. Container restarts recover
  their original journal. Replacement pods retain the old bytes but do not yet
  resume the old pod's pending processing; that requires explicit ownership and
  handoff. This is still a delivery blocker, not an automatic recovery guarantee.
- New journals persist a random stream incarnation before accepting bytes. A
  process restart reuses that identity and its offsets; new storage gets new IDs.
  Version-1 metadata keeps its historical identity. Missing metadata alongside
  existing segments fails closed. New hash columns are nullable for schema
  compatibility, but a duplicate legacy row without a hash fails closed rather
  than asserting unverified content equality. Lost historical archive files
  cannot be reconstructed by this change. A production upgrade needs a verified
  backfill/migration policy for legacy rows before replaying them; these fresh-data,
  same-image fault runs do not establish mixed-version compatibility.
- A Service cannot move an established TCP connection to another pod. Source
  reconnect, replay, sequence accounting, and bounded recovery must be measured.
- The synthetic fixture provides downlink only. Exactly-once command effects and
  ambiguous uplink acknowledgement recovery need a separate command scenario.
- OrbStack runs these pods on one physical node. It exercises replica/process and
  network faults, not node, storage-zone, or control-plane availability. A later
  multi-node environment is required for those conclusions.

## Stop and verify

```sh
python3 dev/chaos/lab.py stop  # remove faults, scale lab workloads to zero, keep data
python3 -m unittest discover -s dev/chaos -p 'test_*.py'
mix precommit
```

The lab never deletes its namespace or persistent volumes automatically. For a
fresh dataset, explicitly delete only `cadence-chaos`, then remove its local
credentials file before running `up` again. Chaos Mesh is in its own namespace
and can remain installed for future experiments.

References: [OrbStack Kubernetes](https://docs.orbstack.dev/kubernetes/),
[Chaos Mesh Helm installation](https://chaos-mesh.org/docs/production-installation-using-helm/),
[Kubernetes Deployment rollouts](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/),
[pod termination](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/).
