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

**The design:**
- **Id:** `Canonical.content_id(kind, {partition identity, stream_id, offset, output index})`, a
  SHA-256 over a small term, as transitions and evaluations already use.
- **Managed action request:** `INSERT ... ON CONFLICT (action_request_id) DO NOTHING` (the primary
  key is the unique index). Same statement count (1); a replay inserts nothing.
- **Episode event:** a deterministic `event_id`, inserted `ON CONFLICT DO NOTHING`. That replaces
  the `seen?` read, so an alarm transition drops from about 6 statements to about 5.
- **Episode:** an episode is stateful (one active per subject), so it keeps `lock_active`. Its id
  becomes deterministic from the opening transition, so a replayed open re-derives the same row:
  `ON CONFLICT (episode_id) DO NOTHING` instead of a second episode.
- **Transitions and evaluations:** already content ids. Replay-stable **only if** `update_id`
  (the sample id) is. That belongs to the identity-v2 audit (recovery-from-archive.md (b)): nothing
  may derive from `evidence_id`.

**The expected cost:** per sample, the same or one statement fewer per transition; one hash per
effect (already paid for transitions). No extra reads.

## Before/after measurement (the gate for both)

Both changes are measured the same way, on :4011, on the **busiest partition during a pass**
(qa's slot; the handlers are attached and detached through `var/qa-scripts/rpc.sh`).

| Metric | How | Window |
|---|---|---|
| **Per-sample decode-to-commit time** | `[:cadence, :runtime, :ingress_persistence_projector, :persist_result]` `duration_us` plus the batch's queue wait, divided by the batch's sample count; p50/p95/p99 | 10 min in a pass |
| **Statements per commit** | count `[:cadence, :repo, :query]` events from the projector's process between batch start and `persist_result`; mean and max | the same 10 min |
| Context-match cost (#98) | `:timer.tc` of `MonitoringEvaluator.evaluate` over the partition's plan and a recorded batch, before vs after, with 007's delta present | a bench, 10k samples |

- **Before:** taken on the current team branch, ahead of either change.
- **After:** taken with the change, at the same pass slot and partition.
- **Pass:** p95 per sample and mean statements per commit are within run-to-run noise (two
  "before" runs set the noise band). Anything above the band is a regression and goes to the
  director before landing.

| | p50 / p95 / p99 per sample (µs) | statements per commit (mean / max) |
|---|---|---|
| Before, run 1 | pending (qa slot) | pending |
| Before, run 2 | pending | pending |
| After #98 | pending | pending |
| After #99 | pending | pending |
