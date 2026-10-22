# Fleet model memory and rolling restart rehearsal — 2026-10-22 UTC

The model-copy amplification is removed from runtime specifications. A fleet now
stores source-to-model references plus one entry per distinct executable model.
This remains compact across coordinator calls, replies, and partition handoff;
it does not depend on restoring heap sharing after a large message has arrived.
Source model validation and runtime identity calculation also run once per
distinct model. The existing per-source runtime basis digest is preserved.

The change accepts the former source-to-full-model input at admission and compacts
legacy specifications before coordinator transfer. Partition selection retains
only the selected source/model and its applicable bindings. There is no database
migration or semantic identity change associated with this representation change.
Identical revision IDs alone are not used to deduplicate executable plans.

Erlang documents the underlying [loss of sharing when terms cross process
boundaries](https://www.erlang.org/doc/system/commoncaveats.html#accidental-copying-and-loss-of-sharing).
The regression test sends a 1,000-source specification through a real process and
back, checking its size on both sides. Additional checks cover heterogeneous
models, broken references, executable-plan validation, partition pruning, and
compatibility with the previous runtime identity calculation.

## Environment and source

- OrbStack, one physical node, 8 GiB VM; unchanged 4 GiB app-container limits.
- Three replicas, 500 configured spacecraft, 1,000 sources, one distinct model,
  5,000 bindings, 27 commands per spacecraft.
- Ten live feeds at `LAB_RATE_HZ=0.2`; this is not a 500-simultaneous-contact test.
- Database `cadence_chaos_20261022_050426`, restored from the activated pre-traffic
  fixture. Previous experiment databases and all volumes were retained.
- Server image `cadence-chaos:301ad377-1792645878`, image ID
  `sha256:796b1a4346bd80dde0f6b5af189d954a63602a6e358f3c35d8aef6a307d3874c`.
- Traffic image `cadence-chaos-simulator:301ad377-1792645878`, image ID
  `sha256:e914844e9d0f224c8ff908baf24f6d7e5521199f2062c8f14d4c5a884505bf88`.
- The image was built from the working tree based on `301ad377`. Source hashes and
  build/test logs are under `var/chaos/checks/model-copy-*`. Diagnostics are
  evaluated from the checked-out lab scripts; they return small summaries.

All compilation and test workloads finished before the startup and traffic
measurements. A stalled first npm install was canceled; the successful build used
`npm ci --no-audit --no-fund --foreground-scripts`. No dependency versions changed.

## Simultaneous cold startup

Artifact: `var/chaos/runs/20261022T051642Z-startup`.

All three replicas were scaled from zero together. Ten source partitions on each
replica were recovered concurrently, without the previous sequential workaround.
Kubernetes rollout readiness took 15.90 seconds; complete partition recovery took
18.47 seconds. There were zero container restarts and zero cgroup OOM kills.

| Pod suffix | Startup cgroup peak | BEAM memory after recovery |
| --- | ---: | ---: |
| `4mvrb` | 749,432,832 B (714.71 MiB) | 459,229,970 B |
| `9d88k` | 800,718,848 B (763.62 MiB) | 465,515,594 B |
| `ppvv8` | 750,297,088 B (715.54 MiB) | 459,746,450 B |

The previous clean-fixture startup peaks were 2,399,612,928–2,457,710,592 bytes,
measured with sequential startup after simultaneous recovery had caused a global
VM OOM. The new worst peak is approximately 67% below the former lowest peak.
This addresses a startup allocation spike; steady BEAM memory is still substantial.
These startup peaks were captured before the separate model-sizing diagnostic.

`var/chaos/checks/model-copy-model-memory.txt` compares both representations of the
same admitted model without allocating a flattened legacy copy:

| Representation | Shared heap size | Copy size (`flat_size × word size`) |
| --- | ---: | ---: |
| Former source-to-full-model map | 948,296 B | 867,069,760 B (826.90 MiB) |
| Indexed source/model table | 948,424 B | 952,872 B (0.91 MiB) |

The copy is approximately **910 times smaller**. The full specification still has
a 62,359,784-byte copy size; 58,048,288 bytes belong to the binding set. Model
indexing therefore removes the dominant amplification without making the entire
fleet specification cheap to copy.

## Traffic baseline

Artifact: `var/chaos/runs/20261022T051812Z-baseline`.

The 60-second run passed all 23 samples, starting and finishing with three Ready
replicas. There were zero HTTP/freshness failures, source-reported drops, semantic
sequence regressions, or artifact-collection errors. All 20 sampled raw/protocol
archive objects remained unchanged and readable on every replica. Throughput was
26.0 archived frames/s at the configured ten-feed workload.

## Rolling restart

Artifact: `var/chaos/runs/20261022T051933Z-rollout`.

The 180-second same-image rolling restart began with all three replicas healthy
and all ten feeds fresh. All replacement pods became Ready with zero restarts and
zero cgroup OOM kills. Their cgroup peaks were 702,844,928–739,708,928 bytes
(670.29–705.44 MiB).

**Memory stability and sampled archive durability passed; continuity failed.**
Of 70 samples, 50 violated the ten-second freshness limit. HTTP readiness never
failed; the worst frame age was 135.66 seconds. All ten feeds were stale at the
last sample (105.29–135.66 seconds). There were no source-reported drops or semantic
sequence regressions, and all 20 sampled archive objects remained unchanged and
readable on every replica. Artifact collection had no errors.

The captured source socket table contains ten `CLOSE_WAIT` connections with
roughly 304–391 KB queued each. A later receiver snapshot found one established
connection, showing that reconnection can eventually occur; it did not restore
continuity within the measured window. These observations reproduce the passive
TCP close-detection problem from the preceding rehearsal. Successful client-side
socket writes and zero reported drops do not establish receiver acceptance.

For the three pods retired by this run, all 30 journal streams (ten containing
data) had caught-up archive and processing checkpoints at the final snapshot.
This is a successful graceful-drain observation, not evidence of replacement-pod
takeover after an abrupt kill; earlier fault datasets retain that separate gap.

This test isolates process replacement on the fixed image. It does not exercise
a mixed-version upgrade, prove lossless delivery, or certify continuous delivery.
The one-node archive volume also does not establish storage availability after
node loss. Source reconnection and retained-journal/partition ownership need
separate work, with the failed evidence retained for comparison.

## Validation

`mix precommit` passed: 4,146 tests passed, one excluded, plus formatting,
compilation with warnings as errors, strict Credo, extension, workspace, and
architecture checks. The targeted memory/activation run passed 17 tests. The
Python lab harness passed nine tests, including startup CLI dispatch and refusal
to start while an existing app or generator deployment is still active.
