defmodule Cadence.Reads.ActionQueue.AlarmItems do
  @moduledoc """
  Alarm items of the action queue, from active alarm episodes (both sources,
  DECISIONS #17).

  Each spacecraft contributes its worst active episode (critical first, then
  unacknowledged, then most recently opened). Those are grouped by identical
  cause `{source, severity, point, source_state}`. Critical items are P1,
  caution items P2. `acknowledged` counts the members whose episode has been
  acknowledged; `ActionQueue` sorts fully acknowledged items after the others
  in the same priority.
  """

  alias Cadence.Reads.ActionQueue.Item

  @severity_rank %{critical: 2, caution: 1}

  @spec items([map()], %{binary() => map()}) :: [map()]
  def items(episodes, by_id) do
    episodes
    |> Enum.filter(&queued?(&1, by_id))
    |> Enum.group_by(& &1.spacecraft_id)
    |> Enum.map(fn {_id, own} -> Enum.max_by(own, &rank/1) end)
    |> Enum.group_by(&{&1.source, &1.severity, &1.point.id, &1.source_state})
    |> Enum.map(fn {key, worst} -> item(key, worst, by_id) end)
  end

  defp item({source, severity, point_id, condition}, worst, by_id) do
    members =
      worst
      |> Enum.sort_by(& &1.opened_at, &Item.earlier?/2)
      |> Enum.map(&member(&1, Map.fetch!(by_id, &1.spacecraft_id)))

    first = hd(worst)

    Item.new(%{
      id: "alarm:#{source}:#{severity}:#{point_id}:#{condition}",
      priority: if(severity == :critical, do: 1, else: 2),
      kind: :alarm,
      state: severity,
      source: source,
      since: worst |> Enum.map(& &1.opened_at) |> Item.min_datetime(),
      count: length(members),
      acknowledged: Enum.count(worst, &(&1.status == :acknowledged)),
      spacecraft: members,
      point: %{
        id: point_id,
        name: Map.get(first.point, :name),
        subsystem: nil,
        unit: Map.get(first.point, :unit)
      },
      condition: condition
    })
  end

  defp queued?(episode, by_id) do
    episode.status in [:new, :acknowledged] and Map.has_key?(@severity_rank, episode.severity) and
      Map.has_key?(by_id, episode.spacecraft_id)
  end

  defp rank(episode) do
    {Map.fetch!(@severity_rank, episode.severity), if(episode.status == :new, do: 1, else: 0),
     episode.opened_at && DateTime.to_unix(episode.opened_at, :microsecond)}
  end

  defp member(episode, craft) do
    craft
    |> Item.member()
    |> Map.merge(%{
      value: episode.last_value,
      first_crossed_at: episode.opened_at,
      episode_id: episode.id,
      status: episode.status,
      assignee: episode.assignee
    })
  end
end
