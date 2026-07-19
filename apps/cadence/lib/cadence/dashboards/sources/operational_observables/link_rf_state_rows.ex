defmodule Cadence.Dashboards.Sources.OperationalObservables.LinkRfStateRows do
  @moduledoc """
  Materializes latest and historical RF lock and frame-synchronization rows.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ScopeContext}

  @rf_lock_states [:locked, :acquiring, :degraded, :unlocked, :unknown]
  @frame_sync_states [:synchronized, :acquiring, :degraded, :lost, :unknown]

  @spec lock_latest([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def lock_latest(transports, snapshots, request) do
    latest(:lock, transports, snapshots, request)
  end

  @spec lock_history([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def lock_history(transports, snapshots, request) do
    history(:lock, transports, snapshots, request)
  end

  @spec frame_sync_latest([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def frame_sync_latest(transports, snapshots, request) do
    latest(:frame_sync, transports, snapshots, request)
  end

  @spec frame_sync_history([term()], [term()], PlannedSourceRequest.t()) :: [map()]
  def frame_sync_history(transports, snapshots, request) do
    history(:frame_sync, transports, snapshots, request)
  end

  @spec find_transport([term()], term()) :: term() | nil
  def find_transport(transports, snapshot) do
    transport_id = attr(snapshot, :transport_id)
    link_id = attr(snapshot, :link_id) || attr(snapshot, :resource_id)

    Enum.find(transports, fn transport ->
      attr(transport, :transport_id) == transport_id or link_id_for([transport]) == link_id
    end)
  end

  @spec lock_state(term()) :: atom() | nil
  def lock_state(value) do
    [
      attr(value, :rf_lock_state),
      attr(value, :lock_state),
      attr(value, :state),
      attr(value, :value)
    ]
    |> Enum.find_value(&normalize_lock_state/1)
  end

  @spec frame_sync_state(term()) :: atom() | nil
  def frame_sync_state(value) do
    [
      attr(value, :frame_sync_state),
      attr(value, :sync_state),
      attr(value, :state),
      attr(value, :value)
    ]
    |> Enum.find_value(&normalize_frame_sync_state/1)
  end

  defp latest(kind, transports, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_snapshot(kind, &1))

    transports
    |> Enum.map(&latest_row(kind, &1, snapshots))
    |> Enum.filter(&matches_scope?(&1, request))
  end

  defp history(kind, transports, snapshots, request) do
    snapshots
    |> Enum.map(&normalize_snapshot(kind, &1))
    |> Enum.map(&history_row(kind, transports, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(
      &(match?(%DateTime{}, &1.observed_at) and matches_scope?(&1, request) and
          time_in_request_window?(&1.observed_at, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.observed_at))
    |> apply_request_limit(request)
  end

  defp latest_row(kind, transport, snapshots) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([transport])
    snapshot = snapshot(snapshots, transport_id, link_id)

    build_row(kind, transport, snapshot)
  end

  defp history_row(kind, transports, snapshot) do
    case find_transport(transports, snapshot) do
      nil -> nil
      transport -> build_row(kind, transport, snapshot)
    end
  end

  defp build_row(kind, transport, snapshot) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([snapshot, transport])
    state = state(kind, snapshot) || state(kind, attr(transport, :metadata)) || :unknown

    %{
      observable_id: observable_id(kind),
      resource_id: link_id || transport_id,
      label: label(kind, transport, link_id),
      scope_kind: :link,
      transport_id: transport_id,
      source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
      ground_station_id: transport_ground_station_id(transport, snapshot),
      link_id: link_id,
      adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
      state: state,
      normalized_state: normalized_state(kind, state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: transport
    }
  end

  defp normalize_snapshot(kind, snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: state(kind, snapshot),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval)
    }
  end

  defp snapshot(snapshots, transport_id, link_id) do
    Enum.find(snapshots, fn snapshot ->
      (present_text?(transport_id) and
         (attr(snapshot, :transport_id) == transport_id or
            attr(snapshot, :resource_id) == transport_id)) or
        (present_text?(link_id) and
           (attr(snapshot, :link_id) == link_id or attr(snapshot, :resource_id) == link_id))
    end)
  end

  defp state(:lock, value), do: lock_state(value)
  defp state(:frame_sync, value), do: frame_sync_state(value)

  defp observable_id(:lock), do: "link.rf_lock_state"
  defp observable_id(:frame_sync), do: "link.frame_sync_state"

  defp label(kind, transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "#{label_prefix(kind)} / #{resource_label}"
  end

  defp label_prefix(:lock), do: "RF lock"
  defp label_prefix(:frame_sync), do: "Frame sync"

  defp normalize_lock_state(value) when value in @rf_lock_states, do: value

  defp normalize_lock_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@rf_lock_states, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_lock_state(_value), do: nil

  defp normalize_frame_sync_state(value) when value in @frame_sync_states, do: value

  defp normalize_frame_sync_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@frame_sync_states, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_frame_sync_state(_value), do: nil

  defp normalized_state(:lock, :locked), do: :green
  defp normalized_state(:lock, :acquiring), do: :blue
  defp normalized_state(:lock, :degraded), do: :yellow
  defp normalized_state(:lock, :unlocked), do: :red
  defp normalized_state(:frame_sync, :synchronized), do: :green
  defp normalized_state(:frame_sync, :acquiring), do: :blue
  defp normalized_state(:frame_sync, :degraded), do: :yellow
  defp normalized_state(:frame_sync, :lost), do: :red
  defp normalized_state(_kind, _state), do: :unknown

  defp transport_source_endpoint_id(transport, snapshot) do
    attr(snapshot, :source_endpoint_id) ||
      attr(snapshot, :source_endpoint_ref) ||
      metadata_attr(transport, :source_endpoint_id)
  end

  defp transport_ground_station_id(transport, snapshot) do
    attr(snapshot, :ground_station_id) ||
      attr(snapshot, :antenna_id) ||
      metadata_attr(transport, :ground_station_id)
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
