defmodule Cadence.Dashboards.Sources.OperationalObservables.IngressProcessingLatencyRows do
  @moduledoc """
  Normalizes ingress processing latency snapshots and materializes latest and
  historical dashboard rows.
  """

  alias Cadence.Dashboards.{DataContext, PlannedSourceRequest, ScopeContext}

  @observable_id "ingress.processing_latency_ms"

  @spec latest([term()], PlannedSourceRequest.t(), term()) :: [map()]
  def latest(snapshots, request, mission_id) do
    snapshots
    |> Enum.map(&normalize_snapshot/1)
    |> Enum.filter(
      &(attr(&1, :mission_id) == mission_id and
          matches_request_replay_context?(&1, request) and
          matches_scope?(&1, request))
    )
    |> Enum.map(&latest_row/1)
  end

  @spec history([term()], PlannedSourceRequest.t(), term()) :: [map()]
  def history(snapshots, request, mission_id) do
    rows =
      snapshots
      |> Enum.map(&normalize_snapshot/1)
      |> Enum.filter(
        &(attr(&1, :mission_id) == mission_id and
            matches_request_replay_context?(&1, request) and
            matches_scope?(&1, request))
      )
      |> Enum.map(&history_row/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&history_row_in_request?(&1, request))
      |> Enum.sort_by(&history_sort_key/1)
      |> apply_request_limit(request)

    rows ++ empty_history_rows(rows, request)
  end

  @spec normalize_snapshot(term()) :: map()
  def normalize_snapshot(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id) || @observable_id,
      mission_id: attr(snapshot, :mission_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) ||
          attr(snapshot, :source_endpoint_ref) ||
          attr(snapshot, :source_ref),
      spacecraft_id: attr(snapshot, :spacecraft_id),
      contact_id:
        attr(snapshot, :contact_id) ||
          attr(snapshot, :scheduled_contact_id) ||
          attr(snapshot, :realized_contact_id),
      transport_id: attr(snapshot, :transport_id),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: value(snapshot),
      unit: attr(snapshot, :unit) || "ms",
      observed_at: attr(snapshot, :observed_at),
      error?: attr(snapshot, :error?) || false,
      replay_run_id: attr(snapshot, :replay_run_id),
      source_event_id: attr(snapshot, :source_event_id),
      source: snapshot
    }
  end

  @spec value(term()) :: number() | nil
  def value(snapshot) do
    [
      attr(snapshot, :value),
      attr(snapshot, :latency_ms),
      attr(snapshot, :processing_latency_ms),
      attr(snapshot, :end_to_end_ms)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp latest_row(snapshot) do
    source_endpoint_id = attr(snapshot, :source_endpoint_id)
    resource_id = source_endpoint_id || attr(snapshot, :mission_id)

    %{
      observable_id: @observable_id,
      resource_id: resource_id,
      label: label(source_endpoint_id),
      scope_kind: scope_kind(source_endpoint_id),
      source_endpoint_id: source_endpoint_id,
      transport_id: attr(snapshot, :transport_id),
      ground_station_id: attr(snapshot, :ground_station_id),
      link_id: attr(snapshot, :link_id),
      contact_id: attr(snapshot, :contact_id),
      adapter_key: attr(snapshot, :adapter_key),
      spacecraft_id: attr(snapshot, :spacecraft_id),
      value: attr(snapshot, :value),
      unit: attr(snapshot, :unit) || "ms",
      observed_at: attr(snapshot, :observed_at),
      error?: attr(snapshot, :error?) || false,
      source_event_id: attr(snapshot, :source_event_id),
      source: attr(snapshot, :source) || snapshot
    }
  end

  defp history_row(snapshot) do
    with value when is_number(value) <- attr(snapshot, :value),
         %DateTime{} = observed_at <- attr(snapshot, :observed_at) do
      source_endpoint_id = attr(snapshot, :source_endpoint_id)
      resource_id = source_endpoint_id || attr(snapshot, :mission_id)

      %{
        observable_id: @observable_id,
        resource_id: resource_id,
        label: label(source_endpoint_id),
        scope_kind: scope_kind(source_endpoint_id),
        source_endpoint_id: source_endpoint_id,
        transport_id: attr(snapshot, :transport_id),
        ground_station_id: attr(snapshot, :ground_station_id),
        link_id: attr(snapshot, :link_id),
        contact_id: attr(snapshot, :contact_id),
        adapter_key: attr(snapshot, :adapter_key),
        spacecraft_id: attr(snapshot, :spacecraft_id),
        value: value,
        unit: attr(snapshot, :unit) || "ms",
        observed_at: observed_at,
        source_event_id: attr(snapshot, :source_event_id),
        source: attr(snapshot, :source) || snapshot
      }
    else
      _missing -> nil
    end
  end

  defp empty_history_rows(rows, request) do
    present_series = MapSet.new(Enum.map(rows, &history_series_key/1))

    request
    |> empty_series_candidates()
    |> Enum.reject(&(history_series_key(&1) in present_series))
    |> Enum.map(&Map.put(&1, :empty_series?, true))
  end

  defp empty_series_candidates(request) do
    request
    |> scope_ids(:source_endpoint)
    |> Enum.map(fn source_endpoint_id ->
      %{
        observable_id: @observable_id,
        resource_id: source_endpoint_id,
        label: label(source_endpoint_id),
        scope_kind: :source_endpoint,
        source_endpoint_id: source_endpoint_id,
        transport_id: nil,
        ground_station_id: nil,
        link_id: nil,
        contact_id: nil,
        adapter_key: nil,
        spacecraft_id: nil,
        value: nil,
        unit: "ms",
        observed_at: nil
      }
    end)
  end

  defp history_row_in_request?(row, request) do
    match?(%DateTime{}, row.observed_at) and is_number(row.value) and
      row.observable_id in request.observables and
      matches_scope?(row, request) and
      time_in_request_window?(row.observed_at, request)
  end

  defp history_sort_key(row), do: {history_series_key(row), datetime_sort_key(row.observed_at)}
  defp history_series_key(row), do: {row.observable_id, row.resource_id}

  defp matches_scope?(sample, request) do
    matches_scope_id?(attr(sample, :source_endpoint_id), scope_ids(request, :source_endpoint)) and
      matches_scope_id?(attr(sample, :spacecraft_id), scope_ids(request, :spacecraft)) and
      matches_scope_id?(attr(sample, :contact_id), scope_ids(request, :contact)) and
      matches_scope_id?(attr(sample, :transport_id), scope_ids(request, :transport)) and
      matches_scope_id?(attr(sample, :ground_station_id), scope_ids(request, :ground_station)) and
      matches_scope_id?(attr(sample, :link_id), scope_ids(request, :link))
  end

  defp matches_request_replay_context?(sample, request) do
    case replay_run_id(request) do
      nil -> is_nil(attr(sample, :replay_run_id))
      replay_run_id -> attr(sample, :replay_run_id) == replay_run_id
    end
  end

  defp replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      context_value(request.time_context, :replay_run_id)
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

  defp scope_kind(source_endpoint_id)
       when is_binary(source_endpoint_id) and source_endpoint_id != "",
       do: :source_endpoint

  defp scope_kind(_source_endpoint_id), do: :mission

  defp label(source_endpoint_id)
       when is_binary(source_endpoint_id) and source_endpoint_id != "" do
    "Ingress latency / #{source_endpoint_id}"
  end

  defp label(_source_endpoint_id), do: "Ingress latency"

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
