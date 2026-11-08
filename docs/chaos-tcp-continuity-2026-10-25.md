# TM receive continuity across reconnects — 2026-10-25

TCP receiver processes and partition owners have different lifetimes. A contact's journal can also survive several TCP connections. The partition previously kept frame counters and partial frame/packet buffers from whichever connection last reached that replica. When traffic returned after another replica had processed intervening frames, the receiver compared against stale counters. The prior rollout's SCID 7 warning compared expected 95 with observed 43 even though the archive showed frame 42 immediately before frame 43.

Each TCP connection now gets a transport_session_id in captured ingress metadata. Journal replay preserves it, and batching cannot combine entries across connections. TM ingress establishes a new counter baseline and clears partial frame and packet buffers when the session, journal, or source changes. Ordinary reads and retries retain state; real gaps within one connection still produce protocol anomalies. A reconnect does not establish whether anything was lost while this receiver was disconnected.

Informational reset logs include session/journal identifiers and discarded-byte counts. No counter table, journal handoff service, or StatefulSet dependency was introduced.

## Validation

OrbStack, three Cadence replicas, Reflect Orbital with 500 configured spacecraft and ten live feeds at LAB_RATE_HZ=0.2. Contacts were renewed before testing. The runner required a continuous healthy minute before each experiment and rechecked health before injection. VM/host clock drift was 0.60 seconds. Load and resource limits were unchanged.

| Experiment | Samples | Archived frames | Connection changes checked | Maximum freshness age | Protocol anomalies |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline | 24 | 1560 | 0 | 5.06 s | 0 |
| rollout | 69 | 4680 | 13 | 5.56 s | 0 |
| pod-kill | 56 | 4563 | 4 | 9.73 s | 0 |

All three runs passed: zero HTTP/freshness failures, archive-counter gaps, source drops, semantic sequence regressions, missing/changed archive objects, or missing session IDs. The fault runs observed archived connection changes. The archive check compares counters across connections independently of the decoder reset, so suppressing stale local comparisons cannot by itself make this check pass.

All three rolling replacements drained in 10.05–10.07 seconds, including the ten-second readiness delay. The 30 retired journal streams had zero bytes behind processing/archive checkpoints and zero unscanned bytes.

ChaosMesh pod-kill used zero grace on an active receiver. Its 10 retired journal streams had 14,495 bytes behind the processing checkpoint, zero behind the archive checkpoint, and zero unscanned bytes. A forensic range audit matched the complete pending range to semantic commit 2684 (144 updates, spacecraft 10), leaving zero bytes without a matching semantic commit.

This deletion still delivered SIGTERM: the BEAM entered its fallback shutdown drain. Seven QuestDB projection retries failed with `:terminating` because `RestClient.write/2` calls `Application.ensure_all_started(:req)` while the application controller is shutting down. Raw frames and semantic commits were durable, but the final history projection was not acknowledged. This remains a separate shutdown/projection follow-up; archive continuity is not proof of complete QuestDB history.

### Direct SIGKILL: strict resilience verdict failed

The added `process-kill` experiment kills the exact Cadence Docker container with SIGKILL, verifies exit code 137 with no OOM, then retires its pod to exercise replacement-pod recovery. It checks the OrbStack context and lab labels before killing anything. This avoids treating a short SIGTERM shutdown as an abrupt crash.

Starting from another healthy minute with three replicas, this run checked 69 samples, 4,615 archived frames, and five reconnects. There were zero protocol anomalies or HTTP failures, but one sample reached 10.32 seconds of freshness age on spacecraft 2, 4, 5, 6, and 8. Each of those feeds had a genuine 13-frame archive gap (expected 234, observed 247): 65 frames total.

The retired pod retained exactly 72,475 bytes behind both its processing and archive checkpoints, with zero unscanned bytes. The checksum/range audit found these bytes in the old journal and no matching semantic commits. Each missing 13-frame batch is 14,495 bytes, accounting for the complete exposure. Existing archive objects remained readable and unchanged; there were no source buffer drops or semantic state regressions.

The strict verdict remains **failed**. The counter fix is validated, while abrupt replacement still strands bounded pending journal work because automatic handoff is deferred. This is not a claim of lossless sudden termination, and no threshold was relaxed or failed run discarded.

Regression tests cover stale counters on a returning receiver, partial frame/packet discard, preserved framing across ordinary reads, modulo wrap, real gaps, stable journal replay metadata, batching boundaries, and a real TCP receiver death/reconnect. An existing backoff test was also corrected to use the executor's receive timestamp instead of racing the test process's scheduling delay.

Validation commands: focused Cadence tests; python3 -m unittest discover -s dev/chaos -p 'test_*.py'; mix precommit (required by the full commit hook).

## Evidence and limits

- baseline: `var/chaos/runs/20261025T203905Z-baseline`
- rollout: `var/chaos/runs/20261025T204138Z-rollout`
- pod-kill: `var/chaos/runs/20261025T204633Z-pod-kill`
- direct SIGKILL: `var/chaos/runs/20261025T205432Z-process-kill` (failed strict resilience verdict)

Tested image: `cadence-chaos:b536f39e-continuity-final-1792960578` (`sha256:f66ada7d91e89a6146b7370142477b8cd030c86024141523028c0083e953dcb8`). Built with the normal lab Dockerfile, then recompiled the two changed ingress modules against that Linux release after the final refinement. The image context, build logs, and source hashes are retained under `var/chaos/checks/continuity-*`.

This measures ten live spacecraft on one physical node. Modulo-256 archive counters cannot rule out loss of an entire counter cycle or prove exactly-once delivery. Archived counter continuity is not a zero-loss guarantee. Automatic replacement-pod journal handoff remains deferred.
