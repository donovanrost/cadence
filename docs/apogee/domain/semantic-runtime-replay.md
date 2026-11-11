# Semantic runtime replay: don't change the Result shape

A runtime partition recovers by replaying its committed inputs. `SemanticRuntime.Store` stores
each commit's result as `term_to_binary` (`result_term`). On recovery, `verify_replay`
(`semantic_runtime/store.ex`) recomputes it and requires `expected_result == actual_result`.
Otherwise it fails with `semantic_runtime_replay_diverged` and the partition doesn't recover.

**So any change to what a commit's Result contains breaks recovery of every pre-deploy commit**
on the first restart after the deploy. That includes:

- a new field on `Result`, `MonitoringResult` or another struct inside it;
- a new key or value in their `metadata`;
- a different value for the same input, e.g. a reordered list or a changed default.

Found while designing flight events (api-ops, 2026-11-11): recording the matched monitoring rule
on `MonitoringResult` would have failed every partition. The rule is now derived at the alarm hook
from the transition's own plan (`MonitoringEvaluator.matched_rule/3`, flight-events.md), and the
Result is unchanged.

If a change to the Result is unavoidable, do one of these:

- **Versioned decode.** Teach `verify_replay` to compare an old-shape stored result with the new
  shape (or upgrade it on decode), with a test that replays a commit written before the change.
- **Keep it outside the Result.** Derive it where it's needed, from the same inputs and plan, as
  flight events do.

The same goes for anything hashed into an identity. For example, a monitoring evaluation's
`evaluation_id` hashes its evaluation document, so a new field there gives already-seen evidence
new ids and duplicate rows.
