defmodule Cadence.Reads.ActionQueue.AlarmItems do
  @moduledoc """
  Alarm and flight-event items of the action queue, from active alarm episodes (both sources,
  DECISIONS #17).

  A **flight event** (docs/apogee/domain/flight-events.md) is a `catalog_monitoring` episode that
  a state rule opened (`MODE = SAFE`): the episode context's `rule_kind` is `enumerated`,
  `boolean` or `string`. Episodes opened before the rule kind was recorded fall back to the value:
  a non-numeric `last_value` is a state. Every other episode is an alarm.

  Per kind, each spacecraft contributes its worst active episode (critical first, then
  unacknowledged, then most recently opened). Alarms are grouped by identical cause `{source,
  severity, point, source_state}`; flight events by `{severity, point name, value}`, by name
  because fleets on different catalog revisions (#65) have different ids for the same point.
  Critical items are P1, caution items P2. `acknowledged` counts the members whose episode has
  been acknowledged; `ActionQueue` sorts fully acknowledged items after the others in the same
  priority.
  """

  alias Cadence.Reads.ActionQueue.Item

  @severity_rank %{critical: 2, caution: 1}
  @state_rules ~w(enumerated boolean string)

  @spec items([map()], %{binary() => map()}) :: [map()]
  def items(episodes, by_id) do
    {flight, alarms} =
      episodes
      |> Enum.filter(&queued?(&1, by_id))
      |> Enum.split_with(&flight_event?/1)

    grouped(
      alarms,
      &{&1.source, &1.severity, &1.point.id, &1.source_state},
      &alarm(&1, &2, by_id)
    ) ++
      grouped(flight, &{&1.severity, point_name(&1), &1.last_value}, &flight(&1, &2, by_id))
  end

  @doc "Whether an episode is a flight event rather than an alarm (see the moduledoc)."
  @spec flight_event?(map()) :: boolean()
  def flight_event?(%{source: :catalog_monitoring} = episode) do
    case (Map.get(episode, :context) || %{})["rule_kind"] do
      nil -> state_value?(episode.last_value)
      kind -> kind in @state_rules
    end
  end

  def flight_event?(_episode), do: false

  defp state_value?(value), do: not is_nil(value) and not is_number(value)

  defp grouped(episodes, key, build) do
    episodes
    |> Enum.group_by(& &1.spacecraft_id)
    |> Enum.map(fn {_id, own} -> Enum.max_by(own, &rank/1) end)
    |> Enum.group_by(key)
    |> Enum.map(fn {key, worst} -> build.(key, worst) end)
  end

  defp alarm({source, severity, point_id, condition}, worst, by_id) do
    worst
    |> common(severity, by_id)
    |> Map.merge(%{
      id: "alarm:#{source}:#{severity}:#{point_id}:#{condition}",
      kind: :alarm,
      source: source,
      point: point(point_id, hd(worst)),
      condition: condition
    })
    |> Item.new()
  end

  defp flight({severity, name, value}, worst, by_id) do
    first = hd(worst)
    value_json = Jason.encode!(value)
    item = common(worst, severity, by_id)

    item
    |> Map.merge(%{
      id: "flight_event:#{severity}:#{name}:#{value_json}",
      kind: :flight_event,
      source: :catalog_monitoring,
      point: point(first.point.id, first),
      condition: first.source_state,
      event: %{value_json: value_json, entered_at: item.since}
    })
    |> Item.new()
  end

  defp common(worst, severity, by_id) do
    %{
      priority: if(severity == :critical, do: 1, else: 2),
      state: severity,
      since: worst |> Enum.map(& &1.opened_at) |> Item.min_datetime(),
      count: length(worst),
      acknowledged: Enum.count(worst, &(&1.status == :acknowledged)),
      spacecraft:
        worst
        |> Enum.sort_by(& &1.opened_at, &Item.earlier?/2)
        |> Enum.map(&member(&1, Map.fetch!(by_id, &1.spacecraft_id)))
    }
  end

  defp point(point_id, episode),
    do: %{
      id: point_id,
      name: Map.get(episode.point, :name),
      subsystem: nil,
      unit: Map.get(episode.point, :unit)
    }

  defp point_name(episode), do: Map.get(episode.point, :name) || episode.point.id

  defp queued?(episode, by_id) do
    episode.status in [:new, :acknowledged] and Map.has_key?(@severity_rank, episode.severity) and
      Map.has_key?(by_id, episode.spacecraft_id)
  end

  defp rank(episode) do
    {Map.fetch!(@severity_rank, episode.severity), if(episode.status == :new, do: 1, else: 0),
     episode.opened_at && DateTime.to_unix(episode.opened_at, :microsecond)}
  end

  # For a flight event, `first_crossed_at` is when the spacecraft entered the state: the episode
  # opens at the triggering sample's generation time (spacecraft time), not when it was processed.
  defp member(episode, craft) do
    craft
    |> Item.member()
    |> Map.merge(%{
      value: episode.last_value,
      first_crossed_at: episode.opened_at,
      episode_id: episode.id,
      status: episode.status,
      acknowledged_by: Map.get(episode, :acknowledged_by),
      assignee: episode.assignee
    })
  end
end
