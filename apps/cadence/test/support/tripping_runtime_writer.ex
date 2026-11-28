defmodule Cadence.Test.TrippingRuntimeWriter do
  @moduledoc """
  A partition owner's `runtime_writer:` for the #99 trip tests (supervision, not storage). A write
  the mission isn't configured to trip succeeds without storing anything; a tripped write runs the
  real tripwire, `ReplayId.check_replay/4` (it logs MM_REPLAY_ID_CONFLICT at error
  level and returns `{:error, {:replay_id_conflict, kind, id}}`), as a conflicting stored effect
  would.

  `configure(mission_id, trip: kinds, notify: pid)`: `kinds` is a list of
  `:initialized` / `:timer_handled` (runtime records whose capability record has that event kind)
  and `:semantic_timer` (semantic timer results). Each trip sends `{:tripped, kind, mission_id}`.
  """

  alias Cadence.Platform.ReplayId

  def configure(mission_id, opts), do: :persistent_term.put(key(mission_id), Map.new(opts))
  def reset(mission_id), do: :persistent_term.erase(key(mission_id))

  def persist_managed_runtime_records(capability_records, action_requests, timer_events) do
    mission_id = mission_id(capability_records ++ action_requests ++ timer_events)
    kinds = Enum.map(capability_records, & &1.event_kind)

    case Enum.find(kinds, &trip?(mission_id, &1)) do
      nil -> :ok
      kind -> conflict(mission_id, kind, :managed_action_request)
    end
  end

  def persist_semantic_timer_result(_policy, runtime_spec, _result, _samples, _opts) do
    if trip?(runtime_spec.mission_id, :semantic_timer),
      do: conflict(runtime_spec.mission_id, :semantic_timer, :alarm_episode),
      else: :ok
  end

  defp trip?(nil, _kind), do: false

  defp trip?(mission_id, kind),
    do: kind in Map.get(:persistent_term.get(key(mission_id), %{}), :trip, [])

  defp conflict(mission_id, kind, replay_kind) do
    case Map.get(:persistent_term.get(key(mission_id), %{}), :notify) do
      pid when is_pid(pid) ->
        send(pid, {:tripped, kind, mission_id})

      _none ->
        :ok
    end

    ReplayId.check_replay(replay_kind, "trip-test-#{kind}", %{effect: "stored"}, %{effect: "new"})
  end

  defp mission_id([record | _rest]), do: Map.get(record, :mission_id)
  defp mission_id([]), do: nil

  defp key(mission_id), do: {__MODULE__, mission_id}
end
