defmodule Cadence.Dashboards.Sources.OperationalObservables.LinkRfMetricRows do
  @moduledoc """
  Materializes latest and historical RF link metric rows.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ScopeContext}
  alias Cadence.Dashboards.Sources.OperationalObservables.LinkRfStateRows

  @observable_ids [
    "link.snr_db",
    "link.eb_n0_db",
    "link.symbol_rate_sps",
    "link.doppler_hz"
  ]

  @spec latest([binary()], [term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def latest(observables, transports, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_snapshot/1)

    observables
    |> Enum.filter(&(&1 in @observable_ids))
    |> Enum.flat_map(fn observable_id ->
      Enum.map(transports, &latest_row(observable_id, &1, snapshots))
    end)
    |> Enum.filter(&matches_scope?(&1, request))
  end

  @spec history([binary()], [term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def history(observables, transports, snapshots, request) do
    observables = Enum.filter(observables, &(&1 in @observable_ids))

    rows =
      snapshots
      |> Enum.map(&normalize_snapshot/1)
      |> Enum.filter(&(attr(&1, :observable_id) in observables))
      |> Enum.map(&history_row(transports, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&history_row_in_request?(&1, request))
      |> Enum.sort_by(&history_sort_key/1)
      |> apply_request_limit(request)

    rows ++ empty_history_rows(observables, transports, rows, request)
  end

  defp empty_history_rows(observables, transports, rows, request) do
    present_series = MapSet.new(Enum.map(rows, &history_series_key/1))

    for observable_id <- observables,
        transport <- transports,
        row = latest_row(observable_id, transport, []),
        matches_scope?(row, request),
        history_series_key(row) not in present_series do
      Map.put(row, :empty_series?, true)
    end
  end

  defp latest_row(observable_id, transport, snapshots) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([transport])
    snapshot = snapshot(snapshots, observable_id, transport_id, link_id)

    %{
      observable_id: observable_id,
      resource_id: link_id || transport_id,
      label: label(observable_id, transport, link_id),
      scope_kind: :link,
      transport_id: transport_id,
      source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
      ground_station_id: transport_ground_station_id(transport, snapshot),
      link_id: link_id_for([snapshot, transport]),
      adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
      value: value(snapshot, observable_id),
      unit: unit(snapshot, observable_id),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id),
      source: transport
    }
  end

  defp history_row(transports, snapshot) do
    observable_id = attr(snapshot, :observable_id)

    with transport when not is_nil(transport) <-
           LinkRfStateRows.find_transport(transports, snapshot),
         value when is_number(value) <- value(snapshot, observable_id),
         %DateTime{} = observed_at <- attr(snapshot, :observed_at) do
      transport_id = attr(transport, :transport_id)
      link_id = link_id_for([snapshot, transport])

      %{
        observable_id: observable_id,
        resource_id: link_id || transport_id,
        label: label(observable_id, transport, link_id),
        scope_kind: :link,
        transport_id: transport_id,
        source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
        ground_station_id: transport_ground_station_id(transport, snapshot),
        link_id: link_id,
        adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
        value: value,
        unit: unit(snapshot, observable_id),
        observed_at: observed_at,
        source_event_id: attr(snapshot, :source_event_id),
        source: transport
      }
    else
      _missing -> nil
    end
  end

  defp normalize_snapshot(snapshot) do
    %{
      observable_id: observable_id(snapshot),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: attr(snapshot, :value),
      snr_db: attr(snapshot, :snr_db),
      snr: attr(snapshot, :snr),
      signal_to_noise_ratio_db: attr(snapshot, :signal_to_noise_ratio_db),
      eb_n0_db: attr(snapshot, :eb_n0_db),
      ebn0_db: attr(snapshot, :ebn0_db),
      energy_per_bit_to_noise_density_db: attr(snapshot, :energy_per_bit_to_noise_density_db),
      symbol_rate_sps: attr(snapshot, :symbol_rate_sps),
      symbol_rate: attr(snapshot, :symbol_rate),
      symbols_per_second: attr(snapshot, :symbols_per_second),
      doppler_hz: attr(snapshot, :doppler_hz),
      doppler: attr(snapshot, :doppler),
      frequency_offset_hz: attr(snapshot, :frequency_offset_hz),
      carrier_frequency_offset_hz: attr(snapshot, :carrier_frequency_offset_hz),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
    }
  end

  @spec observable_id(term()) :: binary() | nil
  def observable_id(snapshot) do
    attr(snapshot, :observable_id) ||
      cond do
        Enum.any?(
          [:eb_n0_db, :ebn0_db, :energy_per_bit_to_noise_density_db],
          &present_metric?(snapshot, &1)
        ) ->
          "link.eb_n0_db"

        Enum.any?(
          [:symbol_rate_sps, :symbol_rate, :symbols_per_second],
          &present_metric?(snapshot, &1)
        ) ->
          "link.symbol_rate_sps"

        Enum.any?(
          [:doppler_hz, :doppler, :frequency_offset_hz, :carrier_frequency_offset_hz],
          &present_metric?(snapshot, &1)
        ) ->
          "link.doppler_hz"

        Enum.any?(
          [:snr_db, :snr, :signal_to_noise_ratio_db, :value],
          &present_metric?(snapshot, &1)
        ) ->
          "link.snr_db"

        true ->
          nil
      end
  end

  defp present_metric?(snapshot, key), do: not is_nil(attr(snapshot, key))

  defp snapshot(snapshots, observable_id, transport_id, link_id) do
    Enum.find(snapshots, fn snapshot ->
      attr(snapshot, :observable_id) == observable_id and
        ((present_text?(transport_id) and
            (attr(snapshot, :transport_id) == transport_id or
               attr(snapshot, :resource_id) == transport_id)) or
           (present_text?(link_id) and
              (attr(snapshot, :link_id) == link_id or attr(snapshot, :resource_id) == link_id)))
    end)
  end

  defp label("link.snr_db", transport, link_id), do: label("RF SNR", transport, link_id)
  defp label("link.eb_n0_db", transport, link_id), do: label("RF Eb/N0", transport, link_id)

  defp label("link.symbol_rate_sps", transport, link_id),
    do: label("RF Symbol Rate", transport, link_id)

  defp label("link.doppler_hz", transport, link_id), do: label("RF Doppler", transport, link_id)

  defp label(observable_id, transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "#{observable_id} / #{resource_label}"
  end

  @spec value(term(), binary() | nil) :: number() | term()
  def value(snapshot, "link.snr_db") do
    [
      attr(snapshot, :snr_db),
      attr(snapshot, :signal_to_noise_ratio_db),
      attr(snapshot, :snr),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  def value(snapshot, "link.eb_n0_db") do
    [
      attr(snapshot, :eb_n0_db),
      attr(snapshot, :ebn0_db),
      attr(snapshot, :energy_per_bit_to_noise_density_db),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  def value(snapshot, "link.symbol_rate_sps") do
    [
      attr(snapshot, :symbol_rate_sps),
      attr(snapshot, :symbols_per_second),
      attr(snapshot, :symbol_rate),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  def value(snapshot, "link.doppler_hz") do
    [
      attr(snapshot, :doppler_hz),
      attr(snapshot, :frequency_offset_hz),
      attr(snapshot, :carrier_frequency_offset_hz),
      attr(snapshot, :doppler),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  def value(snapshot, _observable_id), do: attr(snapshot, :value)

  @spec unit(term(), binary() | nil) :: binary() | nil
  def unit(snapshot, "link.snr_db"), do: attr(snapshot, :unit) || "dB"
  def unit(snapshot, "link.eb_n0_db"), do: attr(snapshot, :unit) || "dB"
  def unit(snapshot, "link.symbol_rate_sps"), do: attr(snapshot, :unit) || "sym/s"
  def unit(snapshot, "link.doppler_hz"), do: attr(snapshot, :unit) || "Hz"
  def unit(snapshot, _observable_id), do: attr(snapshot, :unit)

  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value

  defp normalize_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _invalid -> nil
    end
  end

  defp normalize_number(_value), do: nil

  defp history_row_in_request?(row, request) do
    match?(%DateTime{}, row.observed_at) and is_number(row.value) and
      row.observable_id in request.observables and matches_scope?(row, request) and
      time_in_request_window?(row.observed_at, request)
  end

  defp history_sort_key(row), do: {history_series_key(row), datetime_sort_key(row.observed_at)}
  defp history_series_key(row), do: {row.observable_id, row.resource_id}

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
