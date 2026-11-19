defmodule Cadence.Reads.AlarmEpisodes.Triggers do
  @moduledoc """
  U68 R5 (fe-ops, parity A7a/c): the definition that produced a ground-limit episode and the
  sample that opened it, so "Inspect producing vN" and "Open exact sample" have their targets.

    * `limit_definition_id`, `limit_definition_version`, `limit_set_name`: from the episode's
      context, written at opening (the definition that OPENED it); `nil` for catalog monitoring.
    * `trigger: %{sample_id, sample_type, point_id, at, receipt_time}`: a ground episode's opening
      limit event (`opened_by_ref`), `at` its sample's generation time, else receipt;
      `receipt_time` the sample's receipt time (§11c(D) D1: the one-sample read matches on it). A
      catalog-monitoring transition records no sample: `sample_id: nil`, `at: opened_at`,
      `receipt_time: nil`.
    * each show event with a source record gains `sample: %{id, at, receipt_time}` the same way.

  Limit events are read schemaless by table, one query per page.
  """

  import Ecto.Query

  alias Cadence.Repo

  @spec put(binary(), binary(), [map()]) :: [map()]
  def put(org, mission, episodes) do
    events = limit_events(org, mission, refs(episodes))

    Enum.map(episodes, fn episode ->
      episode
      |> Map.merge(producer(episode))
      |> Map.put(:trigger, trigger(episode, Map.get(events, episode[:opened_by_ref])))
      |> put_event_samples(events)
    end)
  end

  defp refs(episodes) do
    episodes
    |> Enum.filter(&(&1.source == :ground_limit))
    |> Enum.flat_map(fn episode ->
      [episode[:opened_by_ref] | Enum.map(Map.get(episode, :events, []), & &1[:source_ref])]
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp producer(%{source: :ground_limit, context: %{} = context}),
    do: %{
      limit_definition_id: text(context["limit_definition_id"]),
      limit_definition_version: integer(context["limit_definition_version"]),
      limit_set_name: text(context["limit_set_name"])
    }

  defp producer(_episode),
    do: %{limit_definition_id: nil, limit_definition_version: nil, limit_set_name: nil}

  defp trigger(episode, %{} = event),
    do: %{
      sample_id: event.sample_id,
      sample_type: event.sample_type,
      point_id: episode.point.id,
      at: event.at,
      receipt_time: event.received
    }

  defp trigger(episode, nil),
    do: %{
      sample_id: nil,
      sample_type: nil,
      point_id: episode.point.id,
      at: episode.opened_at,
      receipt_time: nil
    }

  defp put_event_samples(%{events: events} = episode, limit_events) when is_list(events),
    do: %{episode | events: Enum.map(events, &event_sample(&1, limit_events))}

  defp put_event_samples(episode, _limit_events), do: episode

  defp event_sample(%{source_ref: ref} = event, limit_events) when is_binary(ref) do
    sample =
      case Map.get(limit_events, ref) do
        %{sample_id: id, at: at, received: received} -> %{id: id, at: at, receipt_time: received}
        nil -> %{id: nil, at: event.at, receipt_time: nil}
      end

    Map.put(event, :sample, sample)
  end

  defp event_sample(event, _limit_events), do: Map.put(event, :sample, nil)

  defp limit_events(_org, _mission, []), do: %{}

  defp limit_events(org, mission, ids) do
    from(e in "telemetry_limit_events",
      where: e.organization_id == ^org and e.mission_id == ^mission and e.limit_event_id in ^ids,
      select: %{
        id: e.limit_event_id,
        sample_id: e.sample_id,
        sample_type: e.source_sample_type,
        generated: type(e.generation_time, :utc_datetime_usec),
        received: type(e.receipt_time, :utc_datetime_usec)
      }
    )
    |> Repo.all()
    |> Map.new(fn event ->
      {event.id,
       %{
         sample_id: event.sample_id,
         sample_type: event.sample_type,
         at: event.generated || event.received,
         received: event.received
       }}
    end)
  end

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp integer(value) when is_integer(value), do: value
  defp integer(_value), do: nil
end
