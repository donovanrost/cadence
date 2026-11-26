# Recovery from the archive: what it needs (DECISIONS #94/#95, with #92 phase 1)

domain, 2026-11-15. A read-only exploration of the user's direction: a runtime partition recovers
from its **snapshot + the ingress archive**, and the ingress journal becomes a near-empty
burst/backpressure buffer.

Notation: `L/` = `apps/cadence/lib/cadence/`. All findings are from the code on `ui-apogee-spa`.

## Verdict

**Feasible, and mostly a re-keying of what exists.** Everything needed for the cursor already
exists, but nothing indexes it yet:
- journal positions are per-stream byte offsets plus a sequence;
- the archived evidence carries `journal_stream_id` and offsets in its metadata;
- downstream packet and frame ids are already derived from (stream, offset).

Four things must change first:
1. **The snapshot stores a per-stream position vector,** where the position is the first byte not
   yet consumed into a complete frame.
2. **The archive is indexed by (stream, offset).**
3. **The journal trims behind the archive cursor alone.**
4. **Every downstream effect is idempotent under replay.** This is identity v2:
   - nothing may derive from `evidence_id`;
   - semantic actions need deterministic ids.

Two prerequisites the rulings assume don't hold today:
- **The journal is still off by default.** The default-on change, b6d7bc9a6, isn't on the team
  branch.
- **The current-value store is ETS by default, not Postgres.** So "rebuild `latest` from
  Cadence's Postgres at boot" works only with the Postgres store (`telemetry_latest_values`) on.

## (a) Positions: what the snapshot records

**A journal stream** is one per (mission, realized contact, path, provider binding).
- Its id is a random incarnation (`L/ingress_journal/file_system.ex:1552-1576`).
- Positions are absolute byte offsets from 0, plus a record `sequence` (`file_system.ex:745-750`;
  `entry.ex`).
- Positions are **not** per source endpoint or partition.

**The archive** has a row per journal *entry*: `ingress_archive_evidence_entries`, keyed by
`evidence_id = sha(stream, start, end)`.
- `journal_stream_id`, `journal_start_offset` and `journal_end_offset` are in the jsonb metadata
  (`L/ingress_journal/evidence.ex:75-92`).
- There are no columns and no index for them.

**What the snapshot needs:**
- `positions: %{stream_id => offset}`, the first byte not yet consumed into a complete frame.
- It must not use the processing batch's `end_offset`. Today the processing cursor acks
  `batch.last.end_offset` (`L/runtime/ingress_journal_consumer.ex:310`) while a partial TM frame
  sits in the partition's in-memory `tm_frame_remainder`, which is never persisted
  (`L/runtime/partition_owner.ex:322`). After a restart that frame is lost **today**, journal or
  not.
- **The alternative** is to snapshot the decode continuity itself (remainder + TM
  pipeline/continuity state). The position-at-frame-start is simpler and keeps the snapshot
  semantic-only.

**Recovery of a partition:**
1. Load its snapshot.
2. For each stream in the vector, read the archive records with `start_offset >= position`, in
   offset order.
3. Read every record of streams that started after the snapshot (new contacts). The archive
   finds them by (source endpoint, receipt time ≥ snapshot time).
4. Read the journal's tail that isn't archived yet (the archive cursor < journal end).

## (b) Ordering: is a processed frame always in the journal or the archive?

The pipeline: socket → journal append (fsync in `:sync`, before the next `recv`;
`L/provider_adapters/tcp_socket.ex:1092-1153`). Then **two independent consumers**:

- **Processing:** decode → semantic (a synchronous Postgres commit today) → projector (QuestDB,
  alarms) → processing ack (in memory, durable at the 250 ms checkpoint).
- **Archive:** segment file + index rows → archive ack.

The two cursors are unordered with respect to each other. A segment is deleted only behind
**both** durable cursors (`file_system.ex:924-931, 1016-1022`), and a stream directory only when
both are at the tail, the contact is settled, and 72 h have passed
(`L/contacts/journal_reclaim.ex`).

- **With the journal on:** no frame is ever in *neither* place. The only gap is the in-memory
  partial frame above, fixed by the frame-start position.
- **Under the user's direction:** trim behind the **archive cursor alone**. An unprocessed but
  archived byte is recoverable from the archive, so processing no longer holds the journal. The
  journal then holds only what isn't archived yet: near-empty in steady state, as the user wants.
- **New risk: effects are now at-least-once over up to 60 s.** Recovery re-runs everything after
  the snapshot position, and the projector has already persisted those batches' effects. Each
  effect must be idempotent:
  - Samples are idempotent: packet ids are `journal_packet_id(stream, frame offset, sha)`, and
    frame ids are `frame_record_id(stream, offset, len)` (`L/protocol/tm_frame_ingress.ex:189-195,
    286-298`).
  - **Anything keyed by `evidence_id` is not idempotent.** Processing evidence merges up to 8
    entries; archive evidence is one per entry. The same bytes therefore get different
    `evidence_id`s live and on replay. `Update.metadata.evidence_id` is one such key. Audit every
    id derived from `evidence_id` and re-derive it from (stream, offset): this is identity v2.
  - **Semantic outputs need deterministic ids:**
    - alarm transitions, episodes, `semantic_latest_alarm_states`;
    - above all **action requests** (a monitoring-triggered command).

    Their ids must be content ids over (partition identity, the input's stream/offset, the
    output's index), so a replay over a 60 s window doesn't raise an alarm or a command twice.

## (c) Several streams per partition; mission-root partitions

**Several streams can feed one partition.** A partition is keyed by source endpoint, and
concurrent paths or contacts with the same endpoint share it (`L/runtime/path_coordinator.ex:336-353`).
- The position **vector** handles completeness fine.
- **Order doesn't replay exactly.** Live order is mailbox arrival; replay merges by
  (receipt_time, stream, offset). Results can differ where order matters (latest value,
  persistence counters).
- **It matters less than it sounds.** TM decode continuity already resets on every stream switch
  (`tm_frame_ingress.ex:77-126`), and the DownlinkCombiner picks winners only for observation
  rows, not telemetry. Accept "deterministic given the merged order" and record the merge rule.

**Mission-root partitions** (cross-craft derived parameters, #92) don't exist yet; nothing
produces `:mission` affinity. Their inputs are other partitions' **outputs**, not frames.
- Recovery for them is snapshot + upstream samples after a position per upstream partition (an
  output sequence), read from the sample store, not the archive.
- That belongs in phase 1's identity design: each partition's outputs carry a monotonic
  per-partition sequence.

## (d) Journal-off deployments

**Built (#692).** A partition recovers from its last semantic snapshot (`semantic_runtime_snapshots`,
one row per partition and basis) and the journal replays from the snapshot's per-stream offsets;
`semantic_runtime_commits`, the per-batch commit path and `CommitRetirement` are gone. The journal's
durable processing cursor follows the snapshots (`IngressJournalConsumer.SnapshotGate`), a recovered
partition tells the consumers it gated to replay (`SemanticSnapshotNotifier`), and it skips the
frames its snapshot already includes (`SemanticSnapshots.skip_replayed?/2`), so a replay applies
nothing twice. Journal off: nothing replays, and a crash loses the memory since the last snapshot
(pinned by `monitoring_replay_ids_e2e_test.exs`).

**The ETS current-value store is seeded from the snapshot (#831, DECISIONS #96).** A starting owner
puts its recovered snapshot's `latest` values into the store (`PartitionOwner.CurrentValueSeed`,
`Storage.seed_current_values/3`) before it takes a frame: each with its OWN generation and receipt
time, so the staleness rules still say stale; under the same source identity as ingest, so a live
value replaces it; never over a newer value already there; no observation written, no fact
published. Only what the snapshot holds can be seeded: the parameters the mission model's semantic
plan evaluates (monitoring and algorithms), not every telemetry point; a snapshot written before
updates carried their point is skipped until its next snapshot. ETS only (the Postgres store is
not a cache).

**A superseded owner is fenced at its next snapshot, not its next batch** (accepted, #692 review):
the previous owner keeps processing until its next snapshot write (one interval, 60 s) fails on the
new epoch and it stops. Its snapshot cannot overwrite the new owner's; its effects are insert-or-get
under the same replay-safe ids, so nothing duplicates.

**The archive isn't written at all on the TCP path.**
- The FileSystem archive's `persist_raw_evidence_multi` is a no-op (`L/ingress_archive/filesystem.ex:40-45`).
- The projector runs with `archive_raw_evidence?: false` (`L/runtime/persistence.ex:109-115`).
- Evidence ids are random (`L/ingress/raw_evidence.ex:51`).

Settlement already reports lost data: "with the journal off, nothing survives a stop"
(`L/contacts/contact_settlement.ex:174, 325`).

**Proposal:** journal-off is a declared degraded mode: recovery = snapshot only, and the gap is
reported as lost, as now. Making the off-path archive with deterministic ids would rebuild a
second capture path; ADR-018 put capture first so we don't do that.

Note too that only TCP + downlink + TM uses the journal (`path_coordinator.ex:636-640`). Other
adapters and protocols need the same capture-first path before archive recovery covers them.

## (e) Boot cost

**Snapshot at end of pass and at shutdown means an idle partition's snapshot is complete:** zero
replay. Only partitions **in a pass at the crash** replay, up to 60 s plus the unarchived tail
each. That is dozens at boot, not 1,000.

**Per replaying partition:** one index query by (stream, offset), plus a full read and decompress
of each touched segment. Journal-path archive segments are up to 128 entries or 8 MB
(`config.exs:91-98`); 60 s at dev rates is one or two segments.

**Stagger:** recover a partition on its first input, or in waves of N concurrent. The segment
read is the cost, and N=8 bounds memory to about 64 MB of decompressed segments.

## (f) The archive redesign and retention

- **Index:** add `stream_id`, `start_offset`, `end_offset` columns to the archive index (or the
  part-4-style `archive_segments` + `archive_record_keys` applied to the **ingress** archive), with
  a unique index on (stream_id, start_offset). Replay's existing scope queries (receipt
  time/endpoint) stay.
- **Retention:** prune whole segments by settled contact, never past any partition's snapshot
  position for that stream. End-of-pass snapshots make that "contact settled + margin"; the
  journal reclaim already uses settled + 72 h.
  - The ingress archive has **no retention code yet** (none found; "part 5" exists only as a
    reference in DECISIONS #83 and the BACKLOG).
  - Recovery puts a new floor under it: a segment whose stream still has a partition with an
    older snapshot position must stay.

## Interaction with #92 phase 1 (per-partition identity)

- **The snapshot belongs to the partition identity, not the revision.** It contains the position
  vector, algorithm memory, monitoring state and timers (excluding `latest`, if the Postgres
  current-value store is on).
- **Today a runtime-basis change starts an empty lineage** (`L/semantic_runtime/store.ex:395-401`).
  With plan ids independent of the revision id, state can carry across a revision when the
  parameter and policy identities it is keyed by (qualified names) survive. That decides whether
  a model rollout loses alarm state.
- **Output ids:** each partition's outputs get a monotonic sequence, for idempotency and for
  mission-root partitions' positions.

## `latest`: in the snapshot, or the Postgres current-value store? (director's item 2)

**Measured on dev** (read-only, a 1% sample of `semantic_runtime_commits`; 393,649 rows,
15 GB):
- the full semantic state term averages **23.8 KB** (max 24.6 KB) per spacecraft;
- the busiest partitions commit about **300 times an hour in a pass** (one commit per processed
  batch).

`latest` holds about 146 points per spacecraft on this catalog and is most of that term. Monitoring
state (83 policies) and algorithm memory are a few KB.

| | (a) `latest` in the 60 s snapshot | (b) Postgres current-value store on by default |
|---|---|---|
| Writes per spacecraft-hour **in a pass** | ≤ 60 snapshot rows + 1 at end of pass | ~300 batches × up to ~146 upserted points ≈ **40k row upserts** |
| Bytes per spacecraft-hour in a pass | ≈ 60 × ~24 KB ≈ **1.4 MB** (vs ≈ 60 × ~4 KB = 0.25 MB without `latest`) | ≈ 40k × ~300 B of tuple + WAL ≈ **10–15 MB** |
| Out of a pass | none (the end-of-pass snapshot is exact) | none |
| Boot cost per partition | none extra (it's in the snapshot row) | one indexed query, ~146 rows |
| Correct after a crash mid-pass? | **Yes**: recovery replays from the snapshot position, which re-applies every update since, so `latest` comes out exact | Yes, but adds nothing: the replay would rebuild the same values |

**Decided (director, 2026-11-15): (a).** At dev's ~0.4 contact-hours per spacecraft-day that is about 0.55 MB per spacecraft-day, against about 99 MB today. **Recommendation was (a).** Keep `latest` in the snapshot. It costs about 1 MB an hour per spacecraft
in a pass, against 10–15 MB and 40k upserts for (b), and it needs no second store to stay in step.
The replay from the snapshot position makes it exact.

Bonus: at partition start, seed the ETS current-value store (which the live UI reads, and which a
restart empties) from the snapshot's `latest`, so the console shows values right after a restart.
That holds whichever option is chosen.

The Postgres store stays what its moduledoc says it is: for tests and rebuild flows.

## Prerequisites and open questions

1. **Journal on by default:** b6d7bc9a6 isn't on the team branch.
2. **`latest` stays in the snapshot** (see the comparison above); the Postgres current-value store
   stays off.
3. **Identity v2 audit:** every id derived from `evidence_id` re-keyed to (stream, offset), plus
   deterministic ids for semantic outputs and action requests.
4. **The capture-first path for non-TCP/non-TM adapters,** or an explicit "snapshot only" there.
5. **For the user:**
   - Is a 60 s at-least-once replay acceptable for **action requests** (commands triggered by
     monitoring), given deterministic ids that suppress duplicates?
   - Or must actions be held until their input's snapshot position is durable?
