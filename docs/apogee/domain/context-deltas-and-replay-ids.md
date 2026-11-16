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

**The design (revised per the director, 11-15: ordered ids, no hashing).** A SHA-256 content id is
~87 bytes and uniformly random, so each insert lands on a random B-tree page (page splits, cache
misses, full-page images in WAL after each checkpoint), and the long key repeats in the primary key
and every index and foreign key that references it. Today's `Ids.new` (~45 bytes) is a monotonic
sequence that appends at the right edge. So the new deterministic ids are **ordered and built from
their inputs:**

```
<kind>_<stream key>_<offset>_<index>        e.g.  mar_k3v9q2m8x1zt_00000a3f1c80_0002
```

- `kind`: 3 letters (`mar` managed action request, `aep` alarm episode, `aev` episode event).
- `stream key`: 12 base32 characters naming (partition identity, journal stream). It is derived
  **once per stream** (when the partition first sees it) and cached; no per-record hash.
- `offset`: the input frame's journal byte offset, 12 hex digits zero-padded (up to 256 TB per
  stream).
- `index`: the output's index within that input, 4 hex digits.

That is **34 bytes**, shorter than today's ~45. Within a stream the ids increase with the offset, so
each active stream appends at its own right edge: a handful of hot leaf pages, not random ones. A new
stream (one per contact) starts at one new place in the index, once.

- **Timer-driven effects** (no input frame): the stream key names (partition identity, `timer`), and
  the offset is the timer's fire time in microseconds, zero-padded. Still ordered, still replay-safe.
- **Text, not a composite key.** A composite (stream key bigint, offset bigint, index smallint) would
  be 18 bytes, but these ids are referenced as strings (episode events → episodes, transitions,
  the API); keeping the text column keeps every reference and reader unchanged.
- **Managed action request:** `INSERT ... ON CONFLICT (action_request_id) DO NOTHING`. Still 1
  statement; a replay inserts nothing.
- **Episode and episode event:** both ids come from the input. The episode is inserted (or the open
  one updated) as today, then the event with `ON CONFLICT (event_id) DO NOTHING RETURNING`: no row
  back means a replay, so the episode change is skipped. That replaces the `seen?` read, so a
  transition goes from about 6 statements to about 5.
- **Sources that never replay** (acknowledgements, ground-limit reconcile) keep `Ids.new`.
- **Transitions and evaluations** keep their content ids for now (see the volumes below). They are
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
flapping parameter drives transitions per sample, give them the same ordered id then.

**The expected cost:** per record, the same or one statement fewer; no per-record hash; ids 34 bytes
instead of ~45; inserts append per stream.

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
