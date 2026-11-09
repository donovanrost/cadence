# Domain facade: alarm episodes

Owner: **domain**. Status: **shipped** (commit `b2ba4d8c`). Consumers: **api / api-ops**, fe-ops.
Design: `docs/apogee/domain/alarm-lifecycle.md` (DECISIONS #6, #17).

## Reads: `Cadence.Reads.AlarmEpisodes`

```elixir
list(scope, mission_id, filters \\ %{}) :: {:ok, %{episodes: [episode], summary: summary}} | {:error, term}
get(scope, mission_id, episode_id)     :: {:ok, episode + %{events: [event]}} | {:error, :episode_not_found | ...}

filters: %{state: "active" (default) | "cleared" | "all", severity: "critical" | "caution",
           spacecraft_id, source: "catalog_monitoring" | "ground_limit", assignee_id, limit: 1..200 (50)}
```

Active episodes come in action-queue order: critical before caution, New before acknowledged,
then newest opened first. Cleared episodes come newest cleared first.

```elixir
episode = %{id, source: :catalog_monitoring | :ground_limit,
  status: :new | :acknowledged | :cleared, cleared_unacknowledged: boolean,
  severity: :critical | :caution, peak_severity, source_state,   # raw state, e.g. "distress", "red_high"
  spacecraft: %{id, name, scid} | nil, spacecraft_id,
  point: %{id, name, unit},                                       # unit from catalog declarations, or nil
  thresholds: %{"red_low", "yellow_low", "yellow_high", "red_high"} | nil,   # ground limits only
  context: map,   # ground: limit_definition_id/version, limit_set_name; catalog: policy_id, mission_model_revision_id
  opened_at, cleared_at, first_value, last_value, last_observed_at,
  last_evaluated_at,   # ground limits: when the evaluation job last ran -> "evaluated 3m ago"
  acknowledged_at, acknowledged_by: actor | nil, assignee: %{id, name} | nil, assigned_at}

event = %{id, kind: :raised | :escalated | :deescalated | :acknowledged | :assigned | :unassigned
                    | :note | :handed_off | :cleared,
          actor: actor | nil, at, payload: map}
# escalated payload: %{"from", "to", "acknowledgement_cleared" => boolean, ...}; cleared: %{"cause", "unacknowledged"}

summary = %{active: n, critical: %{new: n, acknowledged: n}, caution: %{new: n, acknowledged: n}}
```

## Commands: `Cadence.Control.Alarms`

```elixir
acknowledge(scope, mission_id, episode_id, note \\ nil)                  # idempotent
assign(scope, mission_id, episode_id, user_id | nil, note \\ nil)        # doesn't acknowledge; nil unassigns
hand_off(scope, mission_id, episode_id, %{to: user_id | nil, note: String.t()})   # note required
add_note(scope, mission_id, episode_id, note)                            # also on cleared episodes
permissions(scope, mission_id) :: {:ok, ["alarm.acknowledge", "alarm.assign"] | []}
# each command returns {:ok, episode (without spacecraft/thresholds enrichment)}
```

Errors: `:episode_not_found`, `:episode_cleared` (ack/assign/hand-off on a cleared episode),
`:note_required`, `:assignee_not_member`, `:forbidden` (not a human member who can operate the
mission), `:mission_not_found`.

## Live

After commit, every episode change publishes `ScopedReadUpdates` `:alarms_changed` (org, mission),
on `read-updates:alarms_changed:<org>:<mission>`. That covers sources (catalog transitions,
ground evaluations and rebuilds) and commands.

## Notes for the console

- Catalog-monitoring episodes are live (runtime partitions). Ground-limit episodes are only as
  fresh as their evaluation job, so always show `last_evaluated_at` for them.
- `Reads.AlarmList` (ground limits only, latest-state view) still works. Moving the console's
  `/alarms` and the action queue to episodes is api's call.
