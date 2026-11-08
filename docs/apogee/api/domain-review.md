# api review of the change-set facade (change-sets.md §12)

Overall the facade works for the web layer. These are the things I need so the HTTP and channel
layer stays thin:

1. **Explicit mission.** User scopes have `mission_id: nil`, and console routes derive the org
   from the mission. Please make every call `fun(scope, mission_id, ...)` (for example
   `current(scope, mission_id)` and `stage(scope, mission_id, attrs, ops)`), and check
   `operate_mission` / `manage_mission` inside, as you planned.
2. **Optimistic concurrency on mutations.** Give the open set a monotonically increasing
   `version` (it bumps on every stage, withdraw or rebase). `submit`, `review` and `discard` take
   `expected_version` and return `{:error, :change_set_changed}` on mismatch. This covers both a
   double click and "someone staged after I looked". I'll map it to `409`.
3. **Tagged errors I can map:** `:change_set_not_found`, `:change_set_changed`, `:frozen_in_review`,
   `:path_already_staged` (with the other author), `{:conflicts, [..]}`, `:forbidden`, and
   `{:invalid_op, index, reason}`. Anything with details should be a map I can pass through as
   `error.details`.
4. **Permissions per mission.** Expose `permissions(scope, mission_id) :: [binary]` that returns
   the `config.*` strings. They depend on the mission's org, so I'll put them on
   `GET /missions/:id` (`permissions`), not on the global session.
5. **Change notifications.** Publish
   `ScopedReadUpdates.publish(:configuration_changed, org, mission)` after stage, withdraw,
   discard, submit, review and rollback. The mission channel will relay it as invalidate resource
   `changes`.
6. **Apply progress.** For ux's live step list, broadcast `{:change_set_progress, set_id, step}`
   on a PubSub topic you own (for example `"change-sets:" <> set_id`), with
   `step = %{key, label, state: :pending | :running | :done | :failed, at}`. I'll expose it as a
   `change_set:<id>` channel. A `current/2` call that includes the last known steps lets a
   reconnecting client catch up.
7. **Readiness.** Agreed: back `/readiness` with `Cadence.Reads.Readiness.mission(scope, mission_id)`.
   Return plain maps close to setup-shapes.md R (areas[6], findings grouped by cause with
   `fix: %{kind, id}`, severities `blocker | caution | stale | not_set_up | optional`). I'll do
   the JSON encoding. It must work on unstaged ops in the sandbox, as you said.
8. Small: return times as `DateTime`, actors as `%{kind, id, name}`, and revision numbers as
   integers. I'll render `rN` labels in JSON.
