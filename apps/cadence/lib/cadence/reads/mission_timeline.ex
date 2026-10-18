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
    page_for_mission(organization_id, mission_id, opts).entries
  end

  @doc "Reads a bounded portion of canonical history with a stable exclusive continuation."
  def page_for_mission(organization_id, mission_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    source_limit = max(limit * 4, 1_000)

    projected =
      MissionEvents.list_for_mission(
        organization_id,
        mission_id,
        projected_read_opts(opts, source_limit + 1)
      )

    operational =
      OperationalEvents.list_events(
        organization_id,
        mission_id,
        operational_read_opts(opts, source_limit + 1)
      )

    {projected, projected_frontier} = portion(projected, source_limit, &cursor/1)

    {operational, operational_frontier} =
      portion(operational, source_limit, &operational_cursor/1)

    frontier =
      [projected_frontier, operational_frontier]
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&cursor_key/1, fn -> nil end)

    operational_entries =
      Enum.flat_map(operational, &MissionEventProjection.project_operational_event/1)

    overrides =
      MissionEvents.fetch_many_for_mission(
        organization_id,
        mission_id,
        Enum.map(operational_entries, & &1.mission_event_id)
      )

    entries =
      (operational_entries ++ overrides ++ projected)
      |> Map.new(&{&1.mission_event_id, &1})
      |> Map.values()

    endpoints = endpoint_spacecraft(organization_id, mission_id, entries)

    matching =
      entries
      |> Enum.map(&enrich_spacecraft(&1, endpoints))
      |> Enum.filter(
        &(matches?(&1, opts) and before_cursor?(&1, Keyword.get(opts, :cursor)) and
            covered?(&1, frontier))
      )
      |> Enum.sort_by(&entry_key/1, :desc)

    visible = Enum.take(matching, limit)

    next_cursor =
      cond do
        length(matching) > limit and visible != [] -> cursor(List.last(visible))
        frontier != nil and visible != [] -> cursor(List.last(visible))
        frontier != nil -> frontier
        true -> nil
      end

    %{entries: visible, next_cursor: next_cursor}
  end

  defp portion(entries, limit, to_cursor) do
    visible = Enum.take(entries, limit)
    frontier = if length(entries) > limit, do: to_cursor.(List.last(visible)), else: nil
    {visible, frontier}
  end

  defp cursor(entry),
    do: %{occurred_at: entry.occurred_at, mission_event_id: entry.mission_event_id}

  defp operational_cursor(event),
    do: %{
      occurred_at: event.effective_at || event.occurred_at,
      mission_event_id: "mission_event:" <> event.event_id
    }

  defp entry_key(entry),
    do: {DateTime.to_unix(entry.occurred_at, :microsecond), entry.mission_event_id}

  defp cursor_key(cursor),
    do: {DateTime.to_unix(cursor.occurred_at, :microsecond), cursor.mission_event_id}

  defp covered?(_entry, nil), do: true
  defp covered?(entry, frontier), do: entry_key(entry) >= cursor_key(frontier)
  defp before_cursor?(_entry, nil), do: true
  defp before_cursor?(entry, cursor), do: entry_key(entry) < cursor_key(cursor)

  @spec fetch_for_mission(binary(), binary(), binary()) ::
          {:ok, Entry.t()} | {:error, :mission_event_not_found}
  def fetch_for_mission(organization_id, mission_id, mission_event_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(mission_event_id) do
    result =
      case MissionEvents.fetch_for_mission(organization_id, mission_id, mission_event_id) do
        {:ok, %Entry{} = entry} ->
          {:ok, entry}

        {:error, :mission_event_not_found} ->
          fetch_operational_event(organization_id, mission_id, mission_event_id)
      end

    case result do
      {:ok, entry} ->
        {:ok, enrich_spacecraft(entry, endpoint_spacecraft(organization_id, mission_id, [entry]))}

      error ->
        error
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
      :cursor,
      :from_occurred_at,
      :to_occurred_at
    ])
    |> Keyword.put(:limit, source_limit)
    |> Keyword.put(:order, :desc)
  end

  defp operational_read_opts(opts, source_limit) do
    opts
    |> Keyword.take([:kind, :from_occurred_at, :to_occurred_at, :cursor])
    |> Keyword.put(:category, operational_categories(Keyword.get(opts, :category)))
    |> Keyword.put(:time_axis, :effective)
    |> Keyword.put(:limit, source_limit)
    |> Keyword.put(:order, :desc)
  end

  defp operational_categories(nil), do: nil

  defp operational_categories(categories) do
    categories = Enum.map(List.wrap(categories), &to_string/1)

    if "runtime" in categories,
      do: nil,
      else: Enum.flat_map(categories, &operational_category/1) |> Enum.uniq()
  end

  defp operational_category("operations"), do: [:contact, :commanding, :dashboard]
  defp operational_category("health"), do: [:limits, :data_source, :source_credential]
  defp operational_category("transport"), do: [:comms]
  defp operational_category(_), do: []

  defp endpoint_spacecraft(organization_id, mission_id, entries) do
    ids =
      entries |> Enum.filter(&is_nil(&1.spacecraft_id)) |> Enum.flat_map(&source_endpoint_refs/1)

    SourceEndpoints.spacecraft_for_source_endpoints(organization_id, mission_id, ids)
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

  defp source_endpoint_refs(%Entry{} = entry) do
    metadata = if is_map(entry.metadata), do: entry.metadata, else: %{}
    scope = map_value(metadata, "scope", :scope)
    payload = map_value(metadata, "payload", :payload)

    references =
      map_value(scope, "source_endpoint_refs", :source_endpoint_refs) ||
        map_value(payload, "source_endpoint_refs", :source_endpoint_refs) || []

    [entry.source_endpoint_ref | List.wrap(references)]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp map_value(map, string_key, atom_key) when is_map(map),
    do: Map.get(map, string_key) || Map.get(map, atom_key)

  defp map_value(_, _, _), do: nil

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
