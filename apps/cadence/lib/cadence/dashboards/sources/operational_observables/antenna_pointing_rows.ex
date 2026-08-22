defmodule Cadence.Dashboards.Sources.OperationalObservables.AntennaPointingRows do
  @moduledoc """
  Materializes latest and historical ground-station antenna-pointing rows.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ScopeContext}

  @antenna_pointing_states [:idle, :slewing, :acquiring, :tracking, :stowed, :degraded, :unknown]

  @spec latest([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def latest(source_endpoints, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_snapshot/1)

    source_endpoints
    |> Enum.map(&latest_row(&1, snapshots))
    |> Enum.filter(&matches_scope?(&1, request))
  end

  @spec history([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def history(source_endpoints, snapshots, request) do
    snapshots
    |> Enum.map(&normalize_snapshot/1)
    |> Enum.map(&history_row(source_endpoints, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(
      &(match?(%DateTime{}, &1.observed_at) and matches_scope?(&1, request) and
          time_in_request_window?(&1.observed_at, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.observed_at))
    |> apply_request_limit(request)
  end

  @spec state(term()) :: atom() | nil
  def state(value) do
    [
      attr(value, :antenna_pointing_state),
      attr(value, :pointing_state),
      attr(value, :acquisition_state),
      attr(value, :state),
      attr(value, :value)
    ]
    |> Enum.find_value(&normalize_state/1)
  end

  defp latest_row(source_endpoint, snapshots) do
    source_endpoint_id = attr(source_endpoint, :source_endpoint_id)

    ground_station_id =
      metadata_attr(source_endpoint, :ground_station_id) ||
        metadata_attr(source_endpoint, :antenna_id)

    snapshot = snapshot(snapshots, source_endpoint_id, ground_station_id)

    build_row(source_endpoint, snapshot)
  end

  defp history_row(source_endpoints, snapshot) do
    source_endpoint =
      find_source_endpoint(
        source_endpoints,
        attr(snapshot, :source_endpoint_id),
        attr(snapshot, :ground_station_id) || attr(snapshot, :resource_id)
      )

    if source_endpoint do
      build_row(source_endpoint, snapshot)
    end
  end

  defp build_row(source_endpoint, snapshot) do
    source_endpoint_id = attr(source_endpoint, :source_endpoint_id)

    ground_station_id =
      attr(snapshot, :ground_station_id) ||
        metadata_attr(source_endpoint, :ground_station_id) ||
        metadata_attr(source_endpoint, :antenna_id)

    resource_id = ground_station_id || source_endpoint_id
    state = state(snapshot) || state(attr(source_endpoint, :metadata)) || :unknown

    %{
      observable_id: "ground.station.antenna_pointing_state",
      resource_id: resource_id,
      label: "Antenna pointing / #{attr(source_endpoint, :display_name) || resource_id}",
      scope_kind: :ground_station,
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id: source_endpoint_id,
      ground_station_id: ground_station_id,
      link_id: link_id_for([snapshot, source_endpoint]),
      adapter_key: attr(snapshot, :adapter_key) || attr(source_endpoint, :adapter_key),
      state: state,
      normalized_state: normalized_state(state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: source_endpoint
    }
  end

  defp normalize_snapshot(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: state(snapshot),
      normalized_state: attr(snapshot, :normalized_state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval)
    }
  end

  defp snapshot(snapshots, source_endpoint_id, ground_station_id) do
    Enum.find(snapshots, fn snapshot ->
      attr(snapshot, :observable_id) in [nil, "ground.station.antenna_pointing_state"] and
        ((present_text?(source_endpoint_id) and
            (attr(snapshot, :source_endpoint_id) == source_endpoint_id or
               attr(snapshot, :resource_id) == source_endpoint_id)) or
           (present_text?(ground_station_id) and
              (attr(snapshot, :ground_station_id) == ground_station_id or
                 attr(snapshot, :resource_id) == ground_station_id)))
    end)
  end

  defp find_source_endpoint(source_endpoints, source_endpoint_id, ground_station_id) do
    Enum.find(source_endpoints, fn source_endpoint ->
      attr(source_endpoint, :source_endpoint_id) == source_endpoint_id or
        metadata_attr(source_endpoint, :ground_station_id) == ground_station_id or
        metadata_attr(source_endpoint, :antenna_id) == ground_station_id
    end)
  end

  defp normalize_state(value) when value in @antenna_pointing_states, do: value

  defp normalize_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@antenna_pointing_states, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_state(_value), do: nil

  defp normalized_state(:tracking), do: :green
  defp normalized_state(:acquiring), do: :blue
  defp normalized_state(:slewing), do: :blue
  defp normalized_state(:idle), do: :unknown
  defp normalized_state(:stowed), do: :unknown
  defp normalized_state(:degraded), do: :yellow
  defp normalized_state(_state), do: :unknown

  defp matches_scope?(row, request) do
    matches_scope_id?(row.transport_id, scope_ids(request, :transport)) and
      matches_scope_id?(row.source_endpoint_id, scope_ids(request, :source_endpoint)) and
      matches_scope_id?(row.ground_station_id, scope_ids(request, :ground_station)) and
      matches_scope_id?(row.link_id, scope_ids(request, :link))
  end

  defp scope_ids(%PlannedSourceRequest{} = request, kind) do
    primary_ids =
      if ScopeContext.primary_kind(request.scope_context) in [kind, Atom.to_string(kind)] do
        ScopeContext.primary_ids(request.scope_context)
      else
        []
      end

    typed_id = ScopeContext.scope_id(request.scope_context, kind)

    [typed_id | primary_ids]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp matches_scope_id?(_value, []), do: true
  defp matches_scope_id?(value, ids), do: value in ids

  defp link_id_for(values), do: Enum.find_value(values, &link_id/1)

  defp link_id(value) do
    [
      attr(value, :link_id),
      attr(value, :link_assignment_id),
      attr(value, :link_assignment_ref),
      attr(value, :materialized_link_assignment_id),
      metadata_attr(value, :link_id),
      metadata_attr(value, :link_assignment_id),
      metadata_attr(value, :link_assignment_ref),
      metadata_attr(value, :materialized_link_assignment_id)
    ]
    |> Enum.find(&present_text?/1)
  end

  defp time_in_request_window?(%DateTime{} = time, %PlannedSourceRequest{} = request) do
    from_time = request_time_bound(request, [:from, :start, :start_time])
    to_time = request_time_bound(request, [:to, :end, :end_time])

    after_from? = is_nil(from_time) or DateTime.compare(time, from_time) != :lt
    before_to? = is_nil(to_time) or DateTime.compare(time, to_time) != :gt

    after_from? and before_to?
  end

  defp time_in_request_window?(_time, _request), do: false

  defp request_time_bound(%PlannedSourceRequest{} = request, keys) do
    request.time_context
    |> first_context_value(keys)
    |> normalize_time_bound()
  end

  defp first_context_value(context, keys), do: Enum.find_value(keys, &context_value(context, &1))

  defp normalize_time_bound(nil), do: nil
  defp normalize_time_bound(%DateTime{} = value), do: value

  defp normalize_time_bound(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp normalize_time_bound(_value), do: nil

  defp apply_request_limit(rows, %PlannedSourceRequest{} = request) do
    case context_value(request.sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(rows, limit)
      _other -> rows
    end
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_key(_datetime), do: 0

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp metadata_attr(value, key), do: value |> attr(:metadata) |> attr(key)

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""
end
