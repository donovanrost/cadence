# Durable archive rehearsal — 2026-10-22 UTC

The [model-copy follow-up](chaos-model-memory-2026-10-22.md) records the subsequent
fix and simultaneous three-replica startup/rolling-restart measurements. The
results below describe the earlier image and remain historical evidence.

**Archive durability and journal identity are improved; continuous-operation
delivery remains blocked.** This rehearsal established a healthy three-replica
baseline before injecting faults. Unlike the [first rehearsal](chaos-lab-results-2026-10-21.md),
the measurements below do not begin with stalled telemetry or use diagnostic mode.

## Changes exercised

- Raw and protocol archives share the persistent `cadence-archives` volume.
  Immutable publication syncs the file and directory, and concurrent publishers
  cannot replace an existing object with different content.
- Archive indexes store content hashes. A duplicate ID with different content,
  including different captured frame bytes, returns an error instead of accepting
  the earlier row. Unverifiable legacy duplicates fail closed.
- Processing completion waits for archive flush. A filesystem write failure
  cannot acknowledge processing while protocol records remain only in memory.
- New journal incarnations persist a random identity before accepting bytes.
  Restarts recover their original identity and offsets; fresh storage generates
  different evidence/frame IDs. Existing version-1 metadata retains its identity.
  Missing metadata beside existing segments fails closed.
- Each pod uses its own journal directory on the retained volume. Replacement
  preserves old journal bytes, but automatic processing handoff is **not yet
  implemented**. The new identity prevents collisions; it does not fence owners.
- Faults target established ingress sockets, rather than archive-file location.
  Checks include raw/protocol object checksums on every Ready replica and a
  read-only scan for semantic state-sequence regressions.

## Environment and baseline

Server image: `cadence-chaos:301ad377-1792641042`, image ID
`sha256:d39066425f9ccaf406183bc63b138e8c6fe3b218a9cc9b756f5a711891fac4cb`.
This is a working-tree build, not a committed revision. Image metadata and source
fingerprints are in `var/chaos/checks/durability-images.json` and
`durability-source-sha256.json`.
The later journal/memory diagnostics are evaluated from the checked-out lab
scripts through release RPC; application sources still match the tested image.

The workload remains 500 activated spacecraft, 5,000 telemetry bindings, 1,000
source runtime bases, and 27 commands per spacecraft. Ten feeds transmit at
`LAB_RATE_HZ=0.2`: about 20 packets/s and 26 archived transfer frames/s. This does
not establish capacity for 500 simultaneous contacts. OrbStack has one physical
node and an 8 GiB VM; application containers have a 4 GiB memory limit.

One pod was OOM-killed during simultaneous initial fleet recovery, before traffic
started. The kernel records `global_oom` / `CONSTRAINT_NONE` at 04:01:25 UTC,
with victim PID 957498 in the matching pod cgroup. Two starting BEAMs each had
about 2.1 GiB resident memory. This was exhaustion of the shared 8 GiB VM, not
that pod reaching its 4 GiB container limit. The node recorded `SystemOOM`.
After retrying warm-up, all three replicas settled at approximately
425–457 MB of BEAM memory and accepted traffic. Subsequent dataset setup starts
and warms replicas sequentially. The bootstrap OOM remains relevant to capacity
and recovery planning; it is not hidden in a passing fault measurement.
Kernel evidence is saved in `var/chaos/checks/durability-kernel.log`, and the
startup metrics in `durability-bootstrap-memory.json`. Earlier kernel history
also contains a container-cgroup OOM, so the global diagnosis applies specifically
to this rehearsal's confirmed kill. New memory diagnostics record cgroup peaks,
OOM counters, BEAM categories, and largest-process metadata around recovery.
They avoid copying the full runtime specification. The exact allocation driving
the startup peak still needs profiling; increasing pod limits cannot fix the
confirmed VM-wide exhaustion.

The next clean, pre-traffic dataset reproduced startup cgroup peaks of
2,399,612,928–2,457,710,592 bytes per pod without OOM when started sequentially.
Subsequent partition warm-up sampled roughly 306–431 MB BEAM memory. Because the
fixture has no telemetry commits, a large historical replay backlog cannot
explain that startup peak. Fleet configuration materialization/transfer is the
profiling target: `SpacecraftModelBindings` builds 1,000 source entries,
`MissionCoordinator.apply_spec` sends the complete specification, and
`share_source_models` restores shared models after the message copy. A read-only
measurement of the activated `source_runtime_bases` map found **948,296 bytes
with sharing, versus 867,069,760 bytes (827 MiB) without sharing**, using
`:erts_debug.size/1` and `flat_size/1`. The calculation did not send the full map
between processes or allocate the flattened copy. This demonstrates substantial
copy amplification in that concrete path; it does not attribute the entire
2.3 GiB startup peak. Evidence: `durability-model-memory.txt`.

The original failed database `cadence_chaos` and its compressed dump remain
untouched. The first new dataset is `cadence_chaos_20261022_033702`.
`var/chaos/bootstrap/durable-seeded.sql.gz` preserves its activated pre-traffic
fixture. A failed history is retained as a separate database before another
independent experiment is prepared. Dataset replacement is never counted as
automatic recovery or uninterrupted operation.
QuestDB history and the shared archive/journal volume remain retained across
datasets. Freshness and sequence checks use the selected PostgreSQL database;
archive checks use its indexed object keys. This is not a reset of every backend.

## Measured results

All freshness limits below are ten seconds. All runs collected OTEL metrics,
logs, and traces, plus pod events and application/source logs.
These are bounded queries (1,000 log entries and 100 traces), not exhaustive
tracing. One replacement logged an exporter initialization error, then successful
initialization five seconds later; the opening startup interval may lack spans.

| Exercise | Observed result | Verdict |
| --- | --- | --- |
| Three replicas, 120-second baseline | 46 samples; no HTTP/freshness failures; no drops; no semantic regressions; 26.28 frames/s | Passed the sampled baseline; this initial collector checked protocol archives only |
| Three replicas, corrected 60-second baseline | 24 samples; no HTTP/freshness failures; 20 raw/protocol objects unchanged and readable on all three replicas; no drops or semantic regressions; 26.13 frames/s | Passed |
| Network delay, 200 ms ± 50 ms for 30 seconds | 33 samples; no HTTP failures, 11 freshness failures; worst frame age 32.59 s; recovered; no drops/regressions; all 20 objects retained unchanged | Durability passed; continuity failed |
| Database partition for 30 seconds | 45 samples; no HTTP failures, 21 freshness failures; worst frame age 58.95 s; 100 source-reported dropped outputs; seven semantic sequence regressions; all 16 sampled objects retained unchanged on all replicas | Durability passed; continuity and state consistency failed |
| Separate 60-second baseline before pod failure | 24 samples; no HTTP/freshness failures, drops, or semantic regressions; all 20 objects unchanged on all three replicas; 25.94 frames/s | Passed |
| Pod failure for 30 seconds | 47 samples; one HTTP failure, three continuity failures; 40 source-reported dropped outputs; four semantic sequence regressions; all 20 objects retained unchanged on all replicas | Durability passed; continuity and state consistency failed |
| Separate 60-second baseline before pod kill | Three Ready replicas; all feeds fresh; no HTTP/freshness failures, drops, or semantic regressions; all 20 objects retained unchanged | Passed |
| Pod kill | 46 samples; no HTTP failures, 37 continuity failures; 30 source-reported dropped outputs; two semantic sequence regressions; three feeds still stale after two minutes; all 20 objects retained unchanged | Durability passed; continuity, recovery, and state consistency failed |
| Separate 60-second baseline before rolling restart | 24 samples; no HTTP/freshness failures, drops, or semantic regressions; all 20 objects retained unchanged; 26.56 frames/s | Passed |
| Same-image rolling restart, 180 seconds | 68 samples; no HTTP failures, 48 continuity failures; all ten feeds stale at completion; no recorded drops or semantic regressions; all 20 objects retained unchanged; replacement pods had zero restarts | Durability passed; continuity and source reconnection failed |

Evidence directories under `var/chaos/runs/`:

- `20261022T040358Z-baseline`
- `20261022T040641Z-baseline`
- `20261022T040807Z-network-delay`
- `20261022T041024Z-database-partition`
- `20261022T041600Z-baseline`
- `20261022T041710Z-pod-failure`
- `20261022T042735Z-baseline`
- `20261022T042845Z-pod-kill`
- `20261022T043230Z-baseline`
- `20261022T043341Z-rollout`

The first baseline's raw-archive selector incorrectly used a nullable contact
field. The corrected collector selects journal stream identities; the second
baseline verifies ten raw and ten protocol objects. Multiple sources can share
one protocol segment, so subsequent sample counts need not equal twenty.

The network-delay artifact records one successful injection and recovery on the
receiver with seven established feeds. Its logs include a five-second mission
coordinator call timeout. Freshness recovered after the fault ended.

The database partition produced durable evidence of stale runtime state: source
001 appended semantic sequence **144 after 12,816**, and source 002 appended
**144 after 13,392**. The sequence audit detects these regressions without changing
runtime state. It is a consistency check, not a full deterministic replay proof.
The failed dataset is preserved; a later healthy dataset does not repair it.

Pod failure ran against the separately restored database
`cadence_chaos_20261022_041411`. Sources 005–008 appended sequence 144 after 3,168.
The selected container restarted twice as Chaos Mesh substituted and restored its
image; its last termination was `Error`, exit 2, not an OOM. Journal snapshots
added after this experiment distinguish durable cursor backlog from missing
archive objects; later runs capture them before and after injection.

Pod kill used the separate database `cadence_chaos_20261022_042620`. The deleted
receiver had six established feeds. Its source-003 journal retained **14,495
bytes beyond both durable consumer checkpoints**, with no incomplete record tail.
The journal's pod UID no longer existed; no replacement advanced its checkpoints.
Checkpoint lag alone does not prove those bytes were never processed, but the
retained backlog is direct evidence for the missing takeover path. Sources
003, 008, and 009 ended at 105–106 seconds of frame age. Sources 004 and 005
appended semantic sequence 144 after 2,736. Archive survival is therefore not
being counted as successful recovery.

Rolling restart used `cadence_chaos_20261022_043116` and the same image. All ten
feeds ended at 97–133 seconds of age although all replacement pods were Ready.
After measurement, all ten source sockets were in `CLOSE_WAIT`, with roughly
435–536 KB queued per socket; none of the replacements had an established ingress
connection. Source counters continued increasing without reporting dropped
outputs. `SendBuffer` uses passive TCP sockets and counts successful socket sends;
those counters do not prove receiver acceptance. The evidence therefore identifies
a source close-detection/reconnection failure, and cannot attribute this run's
entire stall to Cadence recovery or readiness. The captured socket tables and
`receivers-after.json` preserve that distinction. No semantic regressions were
recorded in this run, but four retired journals each retained 14,495 bytes beyond
their processing checkpoints (raw-archive cursors had caught up).

Source reconnection and retained-journal takeover need separate fixes and a new
rolling-delivery rehearsal. This run exercised process replacement, not a
mixed-version upgrade, and does not certify continuous delivery.

## Final lab state

The lab is left running three Ready replicas with zero restarts and ten live
feeds, using the separate database `cadence_chaos_20261022_043901`. The final
60-second baseline, `20261022T045030Z-baseline`, passed: 24 samples, zero HTTP or
freshness failures, zero reported drops, zero semantic regressions, and 20 sampled
raw/protocol objects unchanged and accessible on all three replicas. No chaos
faults remain active. The earlier failed databases and artifacts are preserved;
this clean dataset is not being represented as recovery of their histories.

## Remaining delivery requirements

Archive survival alone does not establish safe rolling delivery. Runtime
partitions need exclusive ownership, fenced commits, and recovery before a new
receiver accepts a source. Retained pending journals need explicit takeover and
replay. Readiness and shutdown must account for those operations, and the source
needs a measured reconnect/replay contract. Local ETS projections and node-local
registries also require a coherent multi-replica design.

The lab explicitly warms all ten partitions on every replica before traffic.
Code inspection explains why a warm standby can later write stale state:
`MissionCoordinator.start_partition_owner` reuses an existing local owner, while
`SemanticRuntime.Store.commit_input` checks duplicate input identity without
checking an ownership epoch or the predecessor state. A partition cached before
another replica advances can therefore append a new input from its older state.
The observed sequence resets are consistent with this path. Fault-free startup
does not establish safe ownership transfer.

This is a local pod/process rehearsal, not node/zone failure testing. The shared
PVC is local to OrbStack's node. Sampling freshness and object checksums does not
prove zero packet loss, exactly-once command effects, or full archive replay.

## Validation

`mix precommit` passed, including 2,669 core tests, 959 web tests (one excluded),
138 simulator tests, package tests, strict Credo, and architecture checks.
It passed again after the diagnostic additions; the final log is
`var/chaos/checks/durability-precommit-final.log`. All seven Python harness tests
and `git diff --check` also passed.
Focused regressions cover journal restart/fresh-storage identity, legacy metadata,
missing identity metadata, immutable publication races, content collisions, and
archive failure before processing acknowledgement. Both Linux release images and
the production frontend publication check passed. Logs are under
`var/chaos/checks/durability-*`.

See the [runbook](how-to/run-chaos-lab.md) for commands and measurement limits.
