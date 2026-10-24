# TM framing and ordered journal retries

## Failure reproduced from the preserved feed 2 journal

The `20261023T042127Z-rollout` run stalled feed 2 with
`{:tm, {:unsupported_tm_sdu_kind, :vca_sdu}}`. Its owner retained 1,100 bytes of a
partial transfer frame; its executor reported 11,273 failures and one successful
processing item. This was not evidence of VCA traffic from the simulator.

The retained journal for pod UID `6a776a74-1aa5-4e30-aefd-99e0aeeadddc`, stream
`stream-55f62b384ba55785db5e10d7c365cc2a85d8524eae7717a5dd66ae0d2c06182c`, contains:

| Record | Start offset | Payload bytes | Meaning |
| --- | ---: | ---: | --- |
| 0 | 0 | 14,495 | 13 complete 1,115-byte frames |
| 1 | 14,495 | 14,480 | 12 complete frames and 1,100 bytes |
| 2 | 28,975 | 15 | Remaining bytes of record 1's last frame |
| 3 | 28,990 | 14,495 | 13 complete frames |
| 4 | 43,485 | 14,495 | 13 complete frames |
| 5 | 57,980 | 14,495 | 13 complete frames |

All 52 captured records have valid checksums. Decoding them in order produces
500 packets and finishes with an empty frame remainder.
The failure reproduces by decoding ranges `[0]`, `[0,1]`, `[0,1,2,3]`,
`[0,1,2,3,4]`, then `[5]`: the last call returns the same VCA error with the same
1,100-byte remainder. These ranges correspond to the growing retries queued
while recovery was running. The first replacement's logs show five-second
`GenServer.call` timeouts during recovery, which completed after 18.281 seconds.

A timed-out call did not cancel the owner's queued request. The journal consumer
retried from its unacknowledged cursor, incorporating additional records each
time. Those overlapping bytes then entered the same stateful TM decoder.

Local evidence is retained under `var/chaos/checks/framing-feed2/`, with
`framing-records.log`, `framing-reproduce-all.log`, and the previous fencing run's
logs. The previous database `cadence_chaos_20261023_033733` remains intact.

## Changes

- Ordered ingress waits for a definitive owner response. The mission coordinator
  still handles other partitions asynchronously, bounds pending requests, and
  reports owner death to waiting callers.
- A failed journal batch retains its original entry range and evidence identity.
  New socket records cannot enlarge a retry.
- A partition retains its most recent successful journal result. An exact retry
  returns that result without advancing frame reassembly, semantic state, or
  managed application state again. This is one result per partition, not a
  history cache.
- A failed processing-cursor acknowledgement retries acknowledgement only.
- Failures back off from 250 ms to 30 seconds. Polling, stale completions, and
  quiescence requests cannot bypass the delay. Success resets it. Failed bytes
  remain in journal custody; neither consumer cursor is advanced to skip them.
- Consumer snapshots expose phase, consecutive failures, and retry delay. Retry
  logs include the byte range and bounded error detail. The counter
  `cadence.telemetry.ingress.journal.processing.retry` has a bounded `phase`
  dimension.

The result cache is local and covers the latest exact journal request. Durable
framing recovery after a process restart, arbitrary historical overlap, and
replacement-pod journal handoff remain separate contracts. This change does not
claim exactly-once processing across those boundaries or skip malformed input.

## Rehearsal setup

The new, independently seeded dataset is `cadence_chaos_20261023_233753`.
It has 500 configured spacecraft, 1,000 source endpoints, 500 application
bindings, 5,000 governed binding rules, and ten live TCP feeds at 0.2 Hz. Contacts expire at `2026-10-24T07:52:26Z`. The previous
failed dataset and its PVC contents were preserved.

Server image: `cadence-chaos:f586938c-1792798718`, image ID
`sha256:f8384a01f2637119dd5ced14695c9a6cc0580457b5ede2d92ab29ccb5131c757`.
The unchanged simulator was retagged as
`cadence-chaos-simulator:f586938c-1792798718`; its image ID remains
`sha256:11c1298ab3db379b4a43a17d1b3fae10fac89980de3fd4374d02b31fdbb49866`.
Production source fingerprints are in `framing-source-hashes.json`.

The first image build failed because the Tailwind wrapper's downloader rejected
a GitHub response header exceeding 10 KiB. The lab Dockerfile now downloads the
same configured Tailwind 4.1.12 executable with its existing curl installation.
The subsequent server build passed. Both runtime images are retained; only
unused build cache was pruned. Completed pod objects from the previous disk
incident were archived to `framing-retired-pods/` before removal so they would
not block the harness's wait-for-deletion step.


## Validation

`mix precommit` passed: 4,169 tests passed and one was excluded, including
compilation with warnings as errors, strict Credo, architecture checks, and
plane checks. The nine lab harness tests also passed. New regressions cover
recovery exceeding the former five-second timeout, partial-frame exact retries,
stable batch identity as new data arrives, capped backoff, stale completions,
quiescence during retry, and acknowledgement failure without re-decoding.

Startup run `20261023T235442Z-startup` passed with three replicas: Kubernetes
readiness in 16.725 seconds and all 30 partition owners ready in 19.292 seconds.
There were no restarts or OOM kills. Per-pod cgroup peaks were 716.8, 731.8, and
720.5 MiB.

The five-minute healthy baseline `20261023T235538Z-baseline` passed:
108 samples, zero HTTP/freshness failures, 699 semantic commits without sequence
regressions, and 20 sampled archive objects unchanged and readable on all three
replicas. Throughput was 25.76 archived frames/s; HTTP p95 was 596.49 ms.
All 30 executors and journal consumers reported zero failures, and the protocol
anomaly table was empty.

The rolling restart `20261024T000148Z-rollout` began with three healthy replicas
and 782 valid semantic commits. It **failed the overall freshness requirement**:

| Check | Result |
| --- | --- |
| Freshness samples | 13 failures out of 52; maximum age 34.790 seconds |
| Final feed state | All ten fresh, including feed 2 |
| HTTP checks | Zero failures; p95 809.08 ms |
| Semantic sequence audit | 1,223 commits, zero regressions |
| Archive sample | 19 objects unchanged and readable on every replica |
| Source-reported drops | Zero |
| Replacement pods | Three Ready; zero restarts or OOM kills |
| Replacement cgroup peaks | 682.7–802.5 MiB |
| Successful owner replay | 6.076–23.414 seconds across ten owners |
| Executor and consumer failures | Zero on all 30 of each across replacement pods |
| Protocol anomalies | Zero |
| Artifact capture errors | Zero |

Continuous logs from all six retiring/replacement pods contain no
`unsupported_tm_sdu_kind`, telemetry ingress processing failures, or journal
retry warnings. The OTel retry query succeeded with no series emitted; the
explicit zero counts come from the executor/consumer snapshots. The former
five-second timeout was exceeded repeatedly during live recovery without
resubmitting or corrupting the byte stream.

The three retired pods' 30 journal streams retain 130,455 bytes beyond processing
checkpoints and 28,990 bytes beyond archive checkpoints, with no unscanned bytes.
These checkpoints are custody evidence, not proof that every byte past them was
never processed. The tails remain preserved; replacement-pod journal handoff is
still required. This run validates the framing/retry fix, not uninterrupted or
lossless production delivery. Recovery checkpoints and recovery-aware traffic
admission remain necessary to meet the ten-second freshness budget.

The post-rollout baseline `20261024T000615Z-baseline` passed all 21 samples with
three healthy replicas, zero HTTP/freshness failures, 1,517 commits without
regressions, and 31 intact sampled archives. HTTP p95 was 411.6 ms and archived
throughput was 25.65 frames/s.

After stopping synthetic traffic, all 30 active journal consumers had no
in-flight work; their journals had zero pending bytes for both processing and
archive custody. All executors and consumers still reported zero failures.
The final PostgreSQL audit covered **1,598 commits** with zero unfenced writes,
broken predecessors, regressed epochs, or incorrect heads. Read-only full
semantic replay passed for **all ten partitions**, including feed 2. With traffic
stopped, those sequential verification replays took 2.209–7.009 seconds each;
these are distinct from the contended owner recovery timings during rollout.

Cadence remains at three Ready replicas. Synthetic traffic is paused to retain
the audited state and limit storage growth. Databases, archives, journals, and
all run artifacts remain available. The commit hooks also run the affected
workspace checks; their output is retained in `framing-commit.log`.
