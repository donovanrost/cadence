# Per-craft deltas and replay-safe ids: designs and their performance gates (DECISIONS #98, #99)

domain, 2026-11-15. The user accepted both recommendations **on the condition that neither costs
performance**. Each design below states where its cost lands, then the measurement that proves it.
**A measurable regression in either is a blocker that goes back to the director.**

Notation: `L/` = `apps/cadence/lib/cadence/`.

## #98: per-craft value deltas as context-scoped rules

**The ruling:** a per-craft threshold (BATT_TEMP limits for 007) is a monitoring rule scoped to that
craft in the shared lineage, not a per-craft layer or revision.

**Today:** `MonitoringEvaluator.select_rules/2` walks the plan's `contexts` **per sample** and
evaluates each context's criteria against `latest` (`L/semantic_runtime/monitoring_evaluator.ex:114`).
Adding craft-identity contexts there would add a criteria check per context per sample.

**The design:** craft identity never reaches the evaluator.
- A context whose criteria match only **spacecraft identity** is a *static* context.
- When a partition's monitoring plan is **built for its craft** (plan decode at partition start or at
  an activation change), the static contexts are resolved once:
  - a static context that matches this craft replaces the default rules of its policy;
  - one that doesn't match is dropped.
- The result is a plain per-craft plan: `policy_id => rules`, the same shape the evaluator reads now.
- Dynamic contexts (criteria over telemetry values) still evaluate per sample, exactly as today.

**The cost:**
- Per sample: **none added.** A craft with a delta and a craft without one evaluate the same number
  of contexts as today's plan.
- Per partition start: one pass over the plan's contexts (O(contexts)), microseconds.
- Memory: one resolved plan per partition, which already holds one plan.

**The compiler's side:** a static context can only match identity (spacecraft id or SCID; no
telemetry term). One that mixes identity and telemetry is lowered as identity-resolved, then
dynamic over the rest, so nothing searches rules per sample for the identity part.

## #99: replay-safe ids for monitoring effects

**The ruling:** a replay of up to 60 s after a crash may re-run monitoring. Each effect gets a
deterministic id over (partition identity, the input's stream and offset, the output's index), and
is written insert-or-get: **one statement, `ON CONFLICT` on a unique index, no extra read.**

**Today**, per alarm transition (`L/semantic_observations.ex:182-219`, `L/alarms/episodes.ex`):

| Effect | Id today | Statements today |
|---|---|---|
| Monitoring evaluation | content id (`Canonical.content_id`) | batched `insert_all ... ON CONFLICT DO NOTHING` |
| Alarm transition | content id over the evaluation | 1 insert, `ON CONFLICT DO NOTHING` |
| Latest alarm state | keyed by subject | 1 upsert |
| Episode | **random** (`Ids.new("alarm_episode")`) | `seen?` (1 `EXISTS` read), `lock_active` (1 `SELECT ... FOR UPDATE`), 1 insert or update |
| Episode event | **random** (`Ids.new("alarm_event")`) | 1 insert |
| Managed action request | **random** (`Ids.new("managed_action_request")`, `L/runtime/partition_owner/runtime_records.ex:112`) | 1 plain insert, no conflict handling |

So an alarm transition costs about **6 statements** today, and a replayed action request inserts a
**second request**.

**The design (revised twice on 11-15 with the director: no hashing, then time first).**

*Why not a content id:* a SHA-256 content id is ~87 bytes and uniformly random. Each insert lands on
a random B-tree page, causing page splits, cache misses and full-page images in WAL after each
checkpoint, and the long key repeats in every index and foreign key.

*Why not stream first:* the bench showed it (below). With N streams interleaved, only one appends at
the index's right edge; the other N-1 split interior pages 50/50 and leave them half full.

*The id, time first:*

```
<kind>_<receipt µs, 10><stream key, 6><offset, 8><index, 2>      e.g.  aep_65ahf2ggn6000k3v0000a3f100
```

All four fields are fixed-width base32hex (`0-9a-v`). The columns use C collation, so the id sorts
like the numbers. That is **30 bytes** (as built: 31, a 3-digit index; see "As built"): today's ids are 39 (action requests), 30 (episodes) and 28
(events).
- `kind`: `mar` (managed action request), `aep` (alarm episode), `aev` (episode event).
- `receipt µs`: the input frame's receipt time, in µs since 2020-01-01 (2^50 µs is about 35 years).
  It comes from the journal entry and is carried unchanged through the archive, so a replay derives
  the same id. Ids from all streams increase together with time, so inserts append at the right
  edge, as `Ids.new` does today.
- `stream key`: an **ordinal allocated per (partition identity, journal stream)**, not a hash (see
  the collision analysis below). It is allocated with a get-or-create in a small
  `partition_stream_keys` table, durably, before the first effect that uses it commits. That is one
  statement per new stream per partition, about once per contact. 32^6 is about 1.07 billion
  ordinals.
- `offset`: the frame's journal byte offset (32^8 bytes = 1 TiB per stream; a stream is one
  contact's path).
- `index`: the output's index within that input (up to 1,024).
- **Timer-driven effects** (no input frame): the receipt time is the timer's fire time, and the
  stream key is the partition's `timer` ordinal.

*Writing it:*
- **Managed action request:** `INSERT ... ON CONFLICT (action_request_id) DO NOTHING RETURNING`,
  one statement.
- **Episode and episode event:** the episode is inserted (or the open one updated) as today. Then the
  event is written with `ON CONFLICT (event_id) DO NOTHING RETURNING`. No row back means a replay,
  so the episode change is skipped. That replaces the `seen?` read, so a transition goes from about
  6 statements to about 5.
- **Sources that never replay** (acknowledgements, ground-limit reconcile) keep `Ids.new`.

**No silent drops (the director's condition 1).** `RETURNING` gives back no row only on a conflict,
which only happens on replay. Then, and only then, the writer reads the existing row and checks two
things:
- **The source:** the existing id's stream ordinal resolves to the same (partition, journal stream).
  It also checks that offset, index and receipt time match.
- **The effect:** the stored effect matches the new one (action kind and document, or the episode
  event's kind and payload).

Equal means a replay, so it carries on. Anything different is a **hard error and an alert**
(`MM_REPLAY_ID_CONFLICT`): either two different effects share an id, or the replay was not
deterministic. Both are bugs, and neither is swallowed. The normal path pays nothing; a replay pays
one read per already-written effect.

**The collision analysis.** Two different effects share an id only if they agree on kind, receipt µs,
stream key, offset and index.
- **Within one (partition, stream):** (offset, index) is unique by construction. No collision is
  possible.
- **Across streams, with an allocated ordinal:** the keys differ by construction. **No collision is
  possible.** The conflict check above is then a tripwire for bugs, not for chance.
- **Why not a hashed 6-character key (30 bits):** a key collision between two concurrently active
  streams has probability 2^-30 per pair.
  - Take 1,000 craft with about 100 streams active at once, 10-minute contacts, over 10 years. That
    is about 5,000 concurrent pairs × 525,600 windows ≈ 2.6 × 10^9 pair-windows, so about 2.4
    pairs share a key.
  - Such a pair then collides when the same offset is received in the same µs on both streams. For
    identical framing started together, that is up to ~0.1 per pair.
  - So **up to ~0.2 expected collisions over the fleet's life.** Small, but it rests on luck, so
    the key is allocated rather than hashed.
- **The partition is in the key** because one input frame can produce effects in two partitions
  (a craft and the mission root), at the same offset and index.

**Replay stability (the director's condition 2).** Ids are stable only if the receipt time is exactly
the journal entry's, carried unchanged through the archive and identity v2, including **per-frame
receipt times**, along with the offsets and the stream ordinal. A required test (with the identity-v2
work): run a pass and record every effect id; crash the partition; recover from snapshot + archive;
assert the replayed effects' ids are **byte-identical**, and that no new rows appear. Timer
effects: the same assertion across a restart, with fire times.

**As built (domain, 11-17, branch `domain/replay-ids`; lead's three rulings).**

- **The input is the frame, not the evidence batch.** A raw evidence's start offset changes when a
  replay batches the journal differently, so effects are keyed on the frame that completed the
  packet: (journal stream, the frame's absolute offset). Frame ingress already computes that offset
  for `journal_packet_id` (#71); it is now carried as `PacketRecord.journal_frame` →
  `Sample.journal_frame` → the semantic update's metadata (`effect_source`). The receipt time in
  the id is that of the journal record holding the frame's **last** byte (its first byte can sit
  in an earlier evidence, whose records a different batch doesn't have).
- **Not stored, not archived.** `journal_frame` is a struct field, not provenance: the archive
  entry, `journal_packet_id` and the stored observation (provenance, row, identity) are unchanged,
  so a pre-#99 archived range replays with no conflict and B's residual stays null for packet rows.
- **A derived update is keyed on its trigger**, never on the frame of the input whose metadata it
  copies (that can be older, its ids already taken). A timer-triggered algorithm uses the stream
  `timer:<algorithm>` and its fire time.
- **The index is per input, and stable whatever recovery restored.** Action requests are numbered
  per (stream, offset) in deterministic order after the input is processed, across all of a
  frame's packets and every capability that answers them (two capabilities on one frame get 0 and
  1, not 0 and 0). Alarm effects are numbered over the frame's monitoring EVALUATIONS (every
  monitored update x policy, emitted whatever the state), and a transition takes its evaluation's
  index. Not over the transitions: which of them a replay re-derives depends on the monitoring
  state recovery restored. A partition that starts empty is seeded with only the NON-normal latest
  states, so a replay can re-derive a subset, and numbering transitions would hand one subject
  another's stored id and wedge the partition on MM_REPLAY_ID_CONFLICT (api-ops' review; the
  two-subject end-to-end test reproduces it on transition numbering and passes on evaluation
  numbering).
- **The index is 3 base32hex digits (32,768 per input per kind)**, so ids are **31 bytes**. A
  frame's evaluations are bounded by its bits: a 1,115-byte TM frame of 8-bit fields is ~1,100
  updates, x 3 policies ~3,300; a 2,048-byte AOS frame ~6,100. Past 32,768 an effect keeps an
  `Ids.new` id (no replay dedupe), logged as `MM_REPLAY_ID_INDEX_OVERFLOW` and counted as the
  telemetry event `[:cadence, :replay_id, :index_overflow]`.
- **Timers and initialization have their own allocated streams**, so they never share an ordinal
  by chance: a managed timer `timer:<capability>:<timer key>` at its fire time; a managed
  application's **initialization** `init:<activation>:<capability>` with offset = the binding set
  version and a fixed receipt time. A restart re-runs init and gets the existing request back
  (insert-or-get); it never re-issues it. Only a new activation or a new binding set version gives
  a new id.
- **Writing:** action requests in one `insert_all ... ON CONFLICT DO NOTHING RETURNING` per batch
  (one statement, fewer than today's one per request). Episodes and events: the episode (on open)
  and the event are insert-or-get; a stored id means a replay and the episode change is skipped
  (`seen?` isn't read for keyed observations). Inputs without a journal position, ground limits
  and acknowledgements keep `Ids.new`.
- **The tripwire compares what derives from the input:** an episode's or event's subject and
  observation time (not its source ref: a transition's id derives from its sample id, which
  includes the evidence id, and that changes when a replay batches the journal differently; not
  the event kind or payload either: an honest replay can decide a different kind because the
  episode moved on, and the payload holds acknowledgement state); an action request's kind, timer
  key and delay (not its metadata, which is the capability's and could carry batch-dependent ids).
  Today's managed request kinds are schedule and cancel timer. A kind that sets no timer would be
  compared on its kind alone: safe (no false trips) but weak, so a new request kind brings its own
  input projection (api-ops' review note). A mismatch is `MM_REPLAY_ID_CONFLICT`, an error that rolls the batch back.
- **The end-to-end test** (`monitoring_replay_ids_e2e_test.exs`): a live mission runtime with a
  catalog limit; a frame raises it, a later frame clears it. Then the crash window (the
  partition's semantic rows and the monitoring seed's latest alarm state dropped, the owner
  killed) and the journal replays the raise, as the same evidence and re-cut mid-frame:
  monitoring re-derives the raise and, with no open episode, would open a second one (what an
  `Ids.new` id did); the stored episode id stops it. It found the source-ref tripwire problem
  above. Two more: the two-subject wedge (an empty start, seeded, replays a frame where only one of
  two subjects re-derives), and a managed application's request re-emitted after a restart and a
  re-cut replay (one row, the same id).
- **Known, not #99:** the transition and evaluation rows keep content ids over the sample id, so a
  replay that batches differently writes them again (new evidence id, new sample id). They are
  low-volume (written only on a transition) and covered by the identity-v2 audit below.

*Transitions and evaluations* keep their content ids for now (see the volumes below). They are
replay-stable only if `update_id` (the sample id) is: that is on the identity-v2 audit
(recovery-from-archive.md (b)).

**Volumes of the existing content-id tables** (dev, `pg_stat_user_tables`, since the stats reset
2026-11-14 21:22Z; a catalog read):

| Table | Inserts | Size (heap / indexes) |
|---|---|---|
| `semantic_monitoring_evaluations` | 0 | 0 / 32 kB |
| `semantic_alarm_transitions` | 0 | 0 / 32 kB |
| parameter updates | no table: they live in `semantic_runtime_commits`' state term, which #94 retires | (23,142 rows; 403 MB / 362 MB) |
| `alarm_episodes`, `alarm_episode_events`, `managed_action_requests` (the #99 tables) | 0 each | 0 / 32 kB each |

Evaluations are persisted **only on a transition** (`SemanticObservations.add_result/2`), so both
content-id tables scale with alarm transitions, not with samples. **Neither is high-volume; no
follow-up is needed now.** Watch item: if #92 step 2 moves the Limits policies onto this path and a
flapping parameter drives transitions per sample, give them the same time-first id then.

**The expected cost:** per record, the same or one statement fewer; no per-record hash; ids 30 bytes
(today 28 to 39); inserts append at the right edge; one get-or-create statement per new stream per
partition.

## Before/after measurement (the gate for both)

**A finding first:** on dev, the #99 paths write nothing (0 rows in all three tables since 11-14
21:22Z). A live before/after of the busy path can't show their storage cost, so #99's storage gate
is a **synthetic bench**; the live runs guard the busy path as a whole.

**Live** (`var/qa-scripts/measure-98-99.exs`, qa's slot, 11-17 01:01-01:19Z cluster, the busiest
projector in a pass; handlers attached and always detached):

| Metric | How |
|---|---|
| Per-sample time | the projector's `persist_result` (`duration_us` + `queue_wait_ms`) ÷ batch size; p50/p95/p99. **This is enqueue-to-commit:** no event spans decode→commit today (decode and evaluation run in the partition owner before the enqueue). Every #99 statement runs in this span; #98's change runs before it, so #98 also gets the bench below. |
| Statements per commit | `[:cadence, :repo, :query]` events from the projector process per persisted batch; mean/max |
| WAL bytes per commit | `pg_current_wal_lsn()` delta over the window ÷ persisted batches. `pg_stat_statements` isn't installed, so this is cluster-wide WAL (the simulator and other partitions too); the same in both runs |
| Index growth | `pg_indexes_size` of the three #99 tables, start vs end of the window, per hour; ÷ the pass's craft count gives per craft-hour |

**Synthetic** (test partition 12, its own database; no slot needed):
- insert 100k rows into each #99 table with today's ids, hashed ids and ordered ids, at the pass's
  stream fan-out (a few streams interleaved);
- measure the WAL bytes per insert (`pg_current_wal_lsn()` delta) and each index's size after;
- each run spans at least one natural checkpoint (5 min). No manual `CHECKPOINT`: the server is
  shared with :4011.

**Synthetic results (11-16 04:15-04:29Z, test partition 12).** These are copies of the three tables
with their real indexes and the episode→event FK. Each run inserts 100k rows per table, as 1,000
commits of 100 rows from 4 interleaved streams (25 frames × 4 outputs), paced over about 6 minutes.
The WAL is attributed per relation with `pg_waldump`.
- Run 1 compared today, hashed and stream-first ids and spanned 2 natural checkpoints.
- Run 2 compared today and time-first ids and spanned 1.

PK size, MB:

| Ids | Requests | Episodes | Events |
|---|---|---|---|
| today (`Ids.new`: 39 / 30 / 28 bytes) | 5.8 | 4.9 | 4.9 |
| hashed (`content_id`, 87 bytes) | 14 | 13 | 13 |
| stream-first (29 bytes), run 1 | 7.8 | 7.8 | 7.8 |
| **time-first (30 bytes), run 2** | **4.9** | **4.9** | **4.9** |

Index WAL, MB, with full-page writes in brackets:

| Ids | Requests | Episodes | Events |
|---|---|---|---|
| today, run 1 | 37.4 (74) | 27.4 (12) | 19.7 (9) |
| hashed, run 1 | 58.8 (1,729) | 47.6 (1,566) | 61.4 (3,228) |
| stream-first, run 1 | 39.3 (91) | 30.3 (29) | 25.9 (42) |
| today, run 2 | 37.2 (40) | 27.4 (7) | 19.6 (6) |
| **time-first, run 2** | **36.3 (40)** | **27.4 (7)** | **19.6 (6)** |

- **Stream-first is worse than today:** with N streams, N-1 insertion points split interior pages
  50/50.
- **Time-first matches today, and beats it for action requests:** its PK is 16% smaller (30 vs 39
  bytes), with 2.5% less index WAL.
- For episodes and events, time-first is identical to today to the byte. The 2 bytes events gain
  vanish in alignment padding.
- It meets the director's bar: the PK is at or below today's size and the index WAL is within the
  noise.
- The bench has a single writer, which flatters today's and time-first ids equally. With concurrent
  partitions, both insert a little left of the edge.

**#98 bench:** `:timer.tc` of `MonitoringEvaluator.evaluate` over the partition's plan and a
recorded batch, 10k samples, before vs after, with 007's delta present.

**Pass rule:** two live "before" runs set the noise band. p95, statements per commit and WAL per
commit must stay inside it; the synthetic WAL per insert and index bytes per row must be at or below
today's ids. Anything worse goes to the director before landing.

| | p50 / p95 / p99 per sample (µs) | statements per commit (mean / max) | WAL bytes per commit | #99 index growth per craft-hour |
|---|---|---|---|---|
| Before, run 1 | pending (11-17 slot) | pending | pending | pending |
| Before, run 2 | pending | pending | pending | pending |
| After #98 | pending | pending | pending | pending |
| After #99 | pending | pending | pending | pending |
