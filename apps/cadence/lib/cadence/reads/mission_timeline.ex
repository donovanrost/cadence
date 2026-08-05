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
  alias Cadence.SourceEndpoints

  @spec list_for_mission(binary(), binary(), keyword()) :: [Entry.t()]
  def list_for_mission(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    source_limit = max(limit * 4, 1_000)

    projected_entries =
      MissionEvents.list_for_mission(
        organization_id,
        mission_id,
        projected_read_opts(opts, source_limit)
      )

    operational_entries =
      organization_id
      |> OperationalEvents.list_events(mission_id, operational_read_opts(opts, source_limit))
      |> Enum.flat_map(&MissionEventProjection.project_operational_event/1)

    endpoint_spacecraft = endpoint_spacecraft(organization_id, mission_id, opts)

    operational_entries
    |> then(&(&1 ++ projected_entries))
    |> Map.new(&{&1.mission_event_id, &1})
    |> Map.values()
    |> Enum.map(&enrich_spacecraft(&1, endpoint_spacecraft))
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

  defp projected_read_opts(opts, source_limit) do
    opts
    |> Keyword.take([
      :category,
      :kind,
      :severity,
      :spacecraft_id,
      :from_occurred_at,
      :to_occurred_at
    ])
    |> Keyword.put(:limit, source_limit)
    |> Keyword.put(:order, :desc)
  end

  defp operational_read_opts(opts, source_limit) do
    opts
    |> Keyword.take([:kind, :severity, :from_occurred_at, :to_occurred_at])
    |> maybe_put(:category, operational_categories(Keyword.get(opts, :category)))
    |> Keyword.put(:limit, source_limit)
    |> Keyword.put(:order, :desc)
  end

  defp operational_categories(nil), do: nil

  defp operational_categories(categories) do
    categories = List.wrap(categories)

    if Enum.any?(categories, &(to_string(&1) == "runtime")) do
      nil
    else
      categories
      |> Enum.flat_map(&operational_category/1)
      |> Enum.uniq()
    end
  end

  defp operational_category(category) do
    case to_string(category) do
      "operations" -> [:contact, :commanding, :dashboard]
      "health" -> [:limits, :data_source, :source_credential]
      "transport" -> [:comms]
      _unknown -> []
    end
  end

  defp endpoint_spacecraft(organization_id, mission_id, opts) do
    if is_binary(Keyword.get(opts, :spacecraft_id)) do
      organization_id
      |> SourceEndpoints.list_source_endpoints(mission_id)
      |> Map.new(&{&1.source_endpoint_id, &1.spacecraft_id})
    else
      %{}
    end
  end

  defp enrich_spacecraft(%Entry{spacecraft_id: nil} = entry, endpoint_spacecraft) do
    spacecraft_ids =
      entry
      |> source_endpoint_refs()
      |> Enum.map(&Map.get(endpoint_spacecraft, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case spacecraft_ids do
      [spacecraft_id] -> %{entry | spacecraft_id: spacecraft_id}
      _none_or_ambiguous -> entry
    end
  end

  defp enrich_spacecraft(%Entry{} = entry, _endpoint_spacecraft), do: entry

  defp source_endpoint_refs(%Entry{metadata: metadata}) when is_map(metadata) do
    scope = Map.get(metadata, "scope") || Map.get(metadata, :scope) || %{}
    payload = Map.get(metadata, "payload") || Map.get(metadata, :payload) || %{}

    (Map.get(scope, :source_endpoint_refs) ||
       Map.get(scope, "source_endpoint_refs") ||
       Map.get(payload, :source_endpoint_refs) ||
       Map.get(payload, "source_endpoint_refs") || [])
    |> List.wrap()
  end

  defp source_endpoint_refs(%Entry{}), do: []

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

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
