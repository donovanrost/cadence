defmodule Cadence.Reads.MissionTimeline do
  @moduledoc """
  Canonical mission timeline read boundary.

  It combines the durable mission-events projection with operational events
  that have not yet earned an eager projection. Persisted projection rows win
  on identity collisions so richer family-specific entries remain canonical.
  """

  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Reads.MissionEvents

  @spec list_for_mission(binary(), binary(), keyword()) :: [Entry.t()]
  def list_for_mission(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    source_limit = max(limit * 4, 1_000)

    projected_entries =
      MissionEvents.list_for_mission(organization_id, mission_id,
        limit: source_limit,
        order: :desc
      )

    operational_entries =
      organization_id
      |> OperationalEvents.list_events(mission_id, limit: source_limit, order: :desc)
      |> Enum.flat_map(&MissionEventProjection.project_operational_event/1)

    operational_entries
    |> then(&(&1 ++ projected_entries))
    |> Map.new(&{&1.mission_event_id, &1})
    |> Map.values()
    |> Enum.filter(&matches?(&1, opts))
    |> Enum.sort_by(
      fn entry ->
        {DateTime.to_unix(entry.occurred_at, :microsecond), entry.mission_event_id}
      end,
      :desc
    )
    |> Enum.take(limit)
  end

  @spec fetch_for_mission(binary(), binary(), binary()) ::
          {:ok, Entry.t()} | {:error, :mission_event_not_found}
  def fetch_for_mission(organization_id, mission_id, mission_event_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(mission_event_id) do
    case MissionEvents.fetch_for_mission(organization_id, mission_id, mission_event_id) do
      {:ok, %Entry{} = entry} ->
        {:ok, entry}

      {:error, :mission_event_not_found} ->
        fetch_operational_event(organization_id, mission_id, mission_event_id)
    end
  end

  defp fetch_operational_event(organization_id, mission_id, "mission_event:" <> event_id) do
    case OperationalEvents.fetch_event(organization_id, mission_id, event_id) do
      {:ok, event} ->
        event
        |> MissionEventProjection.project_operational_event()
        |> Enum.find(&(&1.mission_event_id == "mission_event:#{event_id}"))
        |> case do
          %Entry{} = entry -> {:ok, entry}
          nil -> {:error, :mission_event_not_found}
        end

      {:error, :not_found} ->
        {:error, :mission_event_not_found}
    end
  end

  defp fetch_operational_event(_organization_id, _mission_id, _mission_event_id),
    do: {:error, :mission_event_not_found}

  defp matches?(entry, opts) do
    atom_matches?(entry.category, Keyword.get(opts, :category)) and
      atom_matches?(entry.kind, Keyword.get(opts, :kind)) and
      atom_matches?(entry.severity, Keyword.get(opts, :severity)) and
      value_matches?(entry.spacecraft_id, Keyword.get(opts, :spacecraft_id)) and
      after_or_at?(entry.occurred_at, Keyword.get(opts, :from_occurred_at)) and
      before?(entry.occurred_at, Keyword.get(opts, :to_occurred_at))
  end

  defp atom_matches?(_value, nil), do: true

  defp atom_matches?(value, expected) do
    Atom.to_string(value) in Enum.map(List.wrap(expected), &to_string/1)
  end

  defp value_matches?(_value, nil), do: true
  defp value_matches?(value, expected), do: value == expected

  defp after_or_at?(_occurred_at, nil), do: true

  defp after_or_at?(occurred_at, %DateTime{} = from),
    do: DateTime.compare(occurred_at, from) in [:gt, :eq]

  defp before?(_occurred_at, nil), do: true
  defp before?(occurred_at, %DateTime{} = to), do: DateTime.compare(occurred_at, to) == :lt
end
