defmodule Cadence.Dashboards.Sources.OperationalObservables.ConnectionRows do
  @moduledoc """
  Materializes latest and historical operational connection-state rows.

  This module normalizes connection snapshots, joins them to transports and
  source endpoints, applies request scope and time windows, and returns the row
  contract consumed by connection frames.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ScopeContext}

  @connection_states [:connected, :connecting, :degraded, :disconnected, :unknown]

  @spec latest([binary()], [term()], [term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def latest(observables, transports, source_endpoints, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_snapshot/1)

    transport_rows =
      if "comms.transport.connection_state" in observables do
        Enum.map(transports, &transport_row(&1, snapshots))
      else
        []
      end

    ground_station_rows =
      if "ground.station.connection_state" in observables do
        Enum.map(source_endpoints, &ground_station_row(&1, snapshots))
      else
        []
      end

    Enum.filter(transport_rows ++ ground_station_rows, &matches_scope?(&1, request))
  end

  @spec history([binary()], [term()], [term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def history(observables, transports, source_endpoints, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_snapshot/1)

    transport_rows =
      if "comms.transport.connection_state" in observables do
        snapshots
        |> Enum.filter(&observable_matches?(&1, "comms.transport.connection_state"))
        |> Enum.map(&transport_history_row(transports, &1))
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    ground_station_rows =
      if "ground.station.connection_state" in observables do
        snapshots
        |> Enum.filter(&observable_matches?(&1, "ground.station.connection_state"))
        |> Enum.map(&ground_station_history_row(source_endpoints, &1))
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    (transport_rows ++ ground_station_rows)
    |> Enum.filter(
      &(match?(%DateTime{}, &1.observed_at) and matches_scope?(&1, request) and
          time_in_request_window?(&1.observed_at, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.observed_at))
    |> apply_request_limit(request)
  end

  defp transport_row(transport, snapshots) do
    transport_id = attr(transport, :transport_id)

    source_endpoint_id =
      metadata_attr(transport, :source_endpoint_id) ||
        metadata_attr(transport, :source_endpoint_ref)

    ground_station_id =
      metadata_attr(transport, :ground_station_id) || metadata_attr(transport, :antenna_id)

    snapshot =
      snapshot(
        snapshots,
        :transport_id,
        transport_id,
        "comms.transport.connection_state"
      )

    %{
      observable_id: "comms.transport.connection_state",
      resource_id: transport_id,
      label: attr(transport, :display_name) || transport_id,
      scope_kind: :transport,
      transport_id: transport_id,
      source_endpoint_id: source_endpoint_id,
      ground_station_id: ground_station_id,
      link_id: link_id_for([snapshot, transport]),
      adapter_key: attr(transport, :adapter_key),
      connection_state:
        connection_state(snapshot) || connection_state(attr(transport, :metadata)) || :unknown,
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: transport
    }
  end

  defp transport_history_row(transports, snapshot) do
    with transport_id when is_binary(transport_id) <-
           attr(snapshot, :transport_id) || attr(snapshot, :resource_id),
         transport when not is_nil(transport) <- find_transport(transports, transport_id) do
      build_transport_history_row(transport, snapshot)
    else
      _missing -> nil
    end
  end

  defp build_transport_history_row(transport, snapshot) do
    transport_id = attr(transport, :transport_id)

    %{
      observable_id: "comms.transport.connection_state",
      resource_id: transport_id,
      label: attr(transport, :display_name) || transport_id,
      scope_kind: :transport,
      transport_id: transport_id,
      source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
      ground_station_id: transport_ground_station_id(transport, snapshot),
      link_id: link_id_for([snapshot, transport]),
      adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
      connection_state:
        connection_state(snapshot) || connection_state(attr(transport, :metadata)) || :unknown,
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: transport
    }
  end

  defp ground_station_row(source_endpoint, snapshots) do
    source_endpoint_id = attr(source_endpoint, :source_endpoint_id)

    ground_station_id =
      metadata_attr(source_endpoint, :ground_station_id) ||
        metadata_attr(source_endpoint, :antenna_id)

    snapshot =
      snapshot(
        snapshots,
        :source_endpoint_id,
        source_endpoint_id,
        "ground.station.connection_state"
      )

    resource_id = ground_station_id || source_endpoint_id

    %{
      observable_id: "ground.station.connection_state",
      resource_id: resource_id,
      label: attr(source_endpoint, :display_name) || resource_id,
      scope_kind: :ground_station,
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id: source_endpoint_id,
      ground_station_id: ground_station_id,
      link_id: link_id_for([snapshot, source_endpoint]),
      adapter_key: attr(snapshot, :adapter_key),
      connection_state:
        connection_state(snapshot) || connection_state(attr(source_endpoint, :metadata)) ||
          :unknown,
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: source_endpoint
    }
  end

  defp ground_station_history_row(source_endpoints, snapshot) do
    source_endpoint =
      find_source_endpoint(
        source_endpoints,
        attr(snapshot, :source_endpoint_id),
        attr(snapshot, :ground_station_id) || attr(snapshot, :resource_id)
      )

    if source_endpoint do
      source_endpoint_id = attr(source_endpoint, :source_endpoint_id)

      ground_station_id =
        attr(snapshot, :ground_station_id) ||
          metadata_attr(source_endpoint, :ground_station_id) ||
          metadata_attr(source_endpoint, :antenna_id)

      resource_id = ground_station_id || source_endpoint_id

      %{
        observable_id: "ground.station.connection_state",
        resource_id: resource_id,
        label: attr(source_endpoint, :display_name) || resource_id,
        scope_kind: :ground_station,
        transport_id: attr(snapshot, :transport_id),
        source_endpoint_id: source_endpoint_id,
        ground_station_id: ground_station_id,
        link_id: link_id_for([snapshot, source_endpoint]),
        adapter_key: attr(snapshot, :adapter_key),
        connection_state:
          connection_state(snapshot) || connection_state(attr(source_endpoint, :metadata)) ||
            :unknown,
        observed_at: attr(snapshot, :observed_at),
        interval_id: attr(snapshot, :interval_id),
        source_event_id: attr(snapshot, :source_event_id),
        interval: attr(snapshot, :interval),
        source: source_endpoint
      }
    end
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
      connection_state: connection_state(snapshot),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval)
    }
  end

  defp observable_matches?(snapshot, observable_id) do
    snapshot_observable_id = attr(snapshot, :observable_id)

    is_nil(snapshot_observable_id) or snapshot_observable_id == observable_id
  end

  defp snapshot(snapshots, key, value, observable_id)
       when is_binary(value) and value != "" do
    Enum.find(
      snapshots,
      &((attr(&1, key) == value or attr(&1, :resource_id) == value) and
          observable_matches?(&1, observable_id))
    )
  end

  defp snapshot(_snapshots, _key, _value, _observable_id), do: nil

  defp find_transport(transports, transport_id)
       when is_binary(transport_id) and transport_id != "" do
    Enum.find(transports, &(attr(&1, :transport_id) == transport_id))
  end

  defp find_transport(_transports, _transport_id), do: nil

  defp find_source_endpoint(source_endpoints, source_endpoint_id, ground_station_id) do
    Enum.find(source_endpoints, fn source_endpoint ->
      attr(source_endpoint, :source_endpoint_id) == source_endpoint_id or
        metadata_attr(source_endpoint, :ground_station_id) == ground_station_id or
        metadata_attr(source_endpoint, :antenna_id) == ground_station_id
    end)
  end

  defp transport_source_endpoint_id(transport, snapshot) do
    attr(snapshot, :source_endpoint_id) ||
      metadata_attr(transport, :source_endpoint_id) ||
      metadata_attr(transport, :source_endpoint_ref)
  end

  defp transport_ground_station_id(transport, snapshot) do
    attr(snapshot, :ground_station_id) ||
      metadata_attr(transport, :ground_station_id) ||
      metadata_attr(transport, :antenna_id)
  end

  defp connection_state(value) do
    value
    |> attr(:connection_state)
    |> normalize_connection_state()
  end

  defp normalize_connection_state(value) when value in @connection_states, do: value

  defp normalize_connection_state(value) when is_binary(value) do
    Enum.find(@connection_states, &(Atom.to_string(&1) == value))
  end

  defp normalize_connection_state(_value), do: nil

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
