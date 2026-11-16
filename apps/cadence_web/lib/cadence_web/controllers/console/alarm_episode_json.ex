defmodule CadenceWeb.Console.AlarmEpisodeJSON do
  @moduledoc "Wire shape of console alarm episodes. Contract: docs/apogee/api/alarms-console.md."

  alias CadenceWeb.Console.WireValue

  @threshold_keys ~w(red_low yellow_low yellow_high red_high)

  @spec list(map(), [binary()]) :: map()
  def list(%{episodes: episodes, summary: summary}, permissions) do
    %{summary: summary, permissions: permissions, episodes: Enum.map(episodes, &episode/1)}
  end

  @doc "One episode; `events` is included when the read loaded them (show and commands)."
  @spec episode(map()) :: map()
  def episode(episode) do
    base = %{
      id: episode.id,
      source: to_string(episode.source),
      status: to_string(episode.status),
      cleared_unacknowledged: episode.cleared_unacknowledged,
      severity: to_string(episode.severity),
      peak_severity: to_string(episode.peak_severity),
      source_state: episode.source_state,
      spacecraft_id: episode.spacecraft_id,
      spacecraft: Map.get(episode, :spacecraft),
      point: point(episode.point),
      thresholds: thresholds(Map.get(episode, :thresholds)),
      context: WireValue.encode(episode.context || %{}),
      opened_at: episode.opened_at,
      cleared_at: episode.cleared_at,
      first_value: WireValue.encode(episode.first_value),
      last_value: WireValue.encode(episode.last_value),
      last_observed_at: episode.last_observed_at,
      last_evaluated_at: episode.last_evaluated_at,
      acknowledged_at: episode.acknowledged_at,
      acknowledged_by: episode.acknowledged_by,
      assignee: episode.assignee,
      assigned_at: episode.assigned_at,
      # U68 R5 (parity A7a/c): the definition that opened it and its triggering sample.
      limit_definition_id: Map.get(episode, :limit_definition_id),
      limit_definition_version: Map.get(episode, :limit_definition_version),
      limit_set_name: Map.get(episode, :limit_set_name),
      trigger: Map.get(episode, :trigger)
    }

    case Map.fetch(episode, :events) do
      {:ok, events} -> Map.put(base, :events, Enum.map(events, &event/1))
      :error -> base
    end
  end

  defp point(point) do
    %{id: point.id, name: point[:name], unit: point[:unit]}
  end

  defp thresholds(nil), do: nil

  defp thresholds(thresholds),
    do: Map.new(@threshold_keys, &{&1, WireValue.encode(Map.get(thresholds, &1))})

  defp event(event) do
    %{
      id: event.id,
      kind: to_string(event.kind),
      actor: event.actor,
      at: event.at,
      payload: WireValue.encode(event.payload || %{}),
      sample: Map.get(event, :sample)
    }
  end
end
