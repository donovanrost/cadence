defmodule Cadence.Dashboards.Sources.OperationalObservables.TransportBitrateRows do
  @moduledoc """
  Materializes latest and historical transport bitrate rows.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ScopeContext}

  @observable_ids [
    "comms.transport.downlink_bitrate",
    "comms.transport.uplink_bitrate"
  ]

  @spec latest([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def latest(transports, snapshots, request) do
    snapshots = Enum.flat_map(snapshots, &normalize_snapshots/1)

    transports
    |> Enum.flat_map(&transport_rows(&1, snapshots, request))
    |> Enum.filter(&matches_scope?(&1, request))
  end

  @spec history([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def history(transports, snapshots, request) do
    rows =
      snapshots
      |> Enum.flat_map(&normalize_snapshots/1)
      |> Enum.map(&history_row(transports, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&history_row_in_request?(&1, request))
      |> Enum.sort_by(&history_sort_key/1)
      |> apply_request_limit(request)

    rows ++ empty_history_rows(transports, rows, request)
  end

  @spec value(term(), binary() | nil) :: number() | nil
  def value(snapshot, "comms.transport.uplink_bitrate") do
    [
      attr(snapshot, :uplink_bitrate),
      attr(snapshot, :uplink_bitrate_bps),
      attr(snapshot, :bitrate),
      attr(snapshot, :bit_rate),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  def value(snapshot, _observable_id) do
    [
      attr(snapshot, :downlink_bitrate),
      attr(snapshot, :downlink_bitrate_bps),
      attr(snapshot, :bitrate),
      attr(snapshot, :bit_rate),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp empty_history_rows(transports, rows, request) do
    present_series = MapSet.new(Enum.map(rows, &history_series_key/1))

    transports
    |> Enum.flat_map(&transport_rows(&1, [], request))
    |> Enum.filter(&matches_scope?(&1, request))
    |> Enum.reject(&(history_series_key(&1) in present_series))
    |> Enum.map(&Map.put(&1, :empty_series?, true))
  end

  defp transport_rows(transport, snapshots, request) do
    request.observables
    |> Enum.filter(&(&1 in @observable_ids))
    |> Enum.map(&latest_row(transport, snapshots, &1))
  end

  defp latest_row(transport, snapshots, observable_id) do
    transport_id = attr(transport, :transport_id)

    source_endpoint_id =
      metadata_attr(transport, :source_endpoint_id) ||
        metadata_attr(transport, :source_endpoint_ref)

    ground_station_id =
      metadata_attr(transport, :ground_station_id) || metadata_attr(transport, :antenna_id)

    snapshot = snapshot(snapshots, transport_id, observable_id)

    %{
      observable_id: observable_id,
      resource_id: transport_id,
      label: attr(transport, :display_name) || transport_id,
      scope_kind: :transport,
      transport_id: transport_id,
      source_endpoint_id: source_endpoint_id,
      ground_station_id: ground_station_id,
      link_id: link_id_for([snapshot, transport]),
      adapter_key: attr(transport, :adapter_key),
      value: attr(snapshot, :value),
      unit: attr(snapshot, :unit) || "bit/s",
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id),
      source: transport
    }
  end

  defp history_row(transports, snapshot) do
    with transport when not is_nil(transport) <- find_transport(transports, snapshot),
         value when is_number(value) <- attr(snapshot, :value),
         %DateTime{} = observed_at <- attr(snapshot, :observed_at) do
      transport_id = attr(transport, :transport_id)

      %{
        observable_id: attr(snapshot, :observable_id),
        resource_id: transport_id,
        label: attr(transport, :display_name) || transport_id,
        scope_kind: :transport,
        transport_id: transport_id,
        source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
        ground_station_id: transport_ground_station_id(transport, snapshot),
        link_id: link_id_for([snapshot, transport]),
        adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
        value: value,
        unit: attr(snapshot, :unit) || "bit/s",
        observed_at: observed_at,
        source_event_id: attr(snapshot, :source_event_id),
        source: transport
      }
    else
      _missing -> nil
    end
  end

  defp normalize_snapshots(snapshot) do
    base = %{
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
    }

    snapshot
    |> observable_ids()
    |> Enum.map(fn observable_id ->
      base
      |> Map.put(:observable_id, observable_id)
      |> Map.put(:value, value(snapshot, observable_id))
    end)
  end

  defp snapshot(snapshots, transport_id, observable_id)
       when is_binary(transport_id) and transport_id != "" do
    Enum.find(
      snapshots,
      &((attr(&1, :transport_id) == transport_id or attr(&1, :resource_id) == transport_id) and
          attr(&1, :observable_id) == observable_id)
    )
  end

  defp snapshot(_snapshots, _transport_id, _observable_id), do: nil

  defp observable_ids(snapshot) do
    case attr(snapshot, :observable_id) do
      observable_id when observable_id in @observable_ids ->
        [observable_id]

      _observable_id ->
        inferred =
          [
            {"comms.transport.downlink_bitrate",
             value(snapshot, "comms.transport.downlink_bitrate")},
            {"comms.transport.uplink_bitrate", value(snapshot, "comms.transport.uplink_bitrate")}
          ]
          |> Enum.filter(fn {_observable_id, value} -> is_number(value) end)
          |> Enum.map(fn {observable_id, _value} -> observable_id end)

        case inferred do
          [] -> ["comms.transport.downlink_bitrate"]
          observable_ids -> observable_ids
        end
    end
  end

  defp find_transport(transports, snapshot) do
    transport_id = attr(snapshot, :transport_id)
    link_id = attr(snapshot, :link_id) || attr(snapshot, :resource_id)

    Enum.find(transports, fn transport ->
      attr(transport, :transport_id) == transport_id or
        (present_text?(link_id) and link_id_for([transport]) == link_id)
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

  defp history_row_in_request?(row, request) do
    match?(%DateTime{}, row.observed_at) and is_number(row.value) and
      row.observable_id in request.observables and matches_scope?(row, request) and
      time_in_request_window?(row.observed_at, request)
  end

  defp history_sort_key(row), do: {history_series_key(row), datetime_sort_key(row.observed_at)}
  defp history_series_key(row), do: {row.observable_id, row.resource_id}

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

  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value

  defp normalize_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp normalize_number(_value), do: nil

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
