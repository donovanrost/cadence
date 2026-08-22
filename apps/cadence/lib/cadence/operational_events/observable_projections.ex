defmodule Cadence.OperationalEvents.ObservableProjections do
  @moduledoc false

  alias Cadence.OperationalEvents.{EffectiveInterval, Event, EventQuery}

  @spec operational_observable_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def operational_observable_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_operational_observable_state_intervals(nil, mission_id, opts)
  end

  @spec operational_observable_state_intervals(binary(), binary(), keyword()) :: [
          EffectiveInterval.t()
        ]
  def operational_observable_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_operational_observable_state_intervals(organization_id, mission_id, opts)
  end

  @spec connection_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def connection_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_connection_state_intervals(nil, mission_id, opts)
  end

  @spec connection_state_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def connection_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_connection_state_intervals(organization_id, mission_id, opts)
  end

  @spec link_rf_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def link_rf_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_link_rf_state_intervals(nil, mission_id, opts)
  end

  @spec link_rf_state_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def link_rf_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_link_rf_state_intervals(organization_id, mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_operational_observable_metric_samples(nil, mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_operational_observable_metric_samples(organization_id, mission_id, opts)
  end

  defp build_operational_observable_state_intervals(organization_id, mission_id, opts) do
    organization_id
    |> operational_observable_state_events(mission_id, opts)
    |> Enum.group_by(&operational_observable_state_key/1)
    |> Enum.flat_map(fn {_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> operational_observable_state_events_to_intervals()
    end)
    |> maybe_filter_interval_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_interval_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_interval_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_interval_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_interval_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_interval_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_interval_payload(:link_id, Keyword.get(opts, :link_id))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_connection_state_intervals(organization_id, mission_id, opts) do
    organization_id
    |> connection_state_events(mission_id, opts)
    |> Enum.group_by(&operational_observable_state_key/1)
    |> Enum.flat_map(fn {_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> connection_state_events_to_intervals()
    end)
    |> maybe_filter_interval_payload(
      :connection_state_family,
      Keyword.get(opts, :connection_state_family)
    )
    |> maybe_filter_interval_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_interval_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_interval_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_interval_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_interval_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_interval_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_interval_payload(:link_id, Keyword.get(opts, :link_id))
    |> maybe_filter_interval_payload(:connection_state, Keyword.get(opts, :connection_state))
    |> maybe_filter_interval_payload(:normalized_state, Keyword.get(opts, :normalized_state))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_link_rf_state_intervals(organization_id, mission_id, opts) do
    organization_id
    |> link_rf_state_events(mission_id, opts)
    |> Enum.group_by(&operational_observable_state_key/1)
    |> Enum.flat_map(fn {_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> link_rf_state_events_to_intervals()
    end)
    |> maybe_filter_interval_payload(:rf_state_family, Keyword.get(opts, :rf_state_family))
    |> maybe_filter_interval_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_interval_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_interval_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_interval_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_interval_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_interval_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_interval_payload(:link_id, Keyword.get(opts, :link_id))
    |> maybe_filter_interval_payload(:state, Keyword.get(opts, :state))
    |> maybe_filter_interval_payload(:normalized_state, Keyword.get(opts, :normalized_state))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_operational_observable_metric_samples(organization_id, mission_id, opts) do
    organization_id
    |> operational_observable_metric_events(mission_id, opts)
    |> Enum.map(&operational_observable_metric_sample/1)
    |> maybe_filter_sample_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_sample_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_sample_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_sample_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_sample_payload(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_sample_payload(
      :contact_id,
      Keyword.get(opts, :contact_id) || Keyword.get(opts, :scheduled_contact_id) ||
        Keyword.get(opts, :realized_contact_id)
    )
    |> maybe_filter_sample_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_sample_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_sample_payload(:link_id, Keyword.get(opts, :link_id))
    |> order_samples(Keyword.get(opts, :order, :asc))
  end

  defp operational_observable_state_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: operational_observable_state_source_record_kinds(),
      kind: :operational_observable_state_changed,
      order: :asc,
      replay_run_id: Keyword.get(opts, :replay_run_id, :none),
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      EventQuery.list_events(organization_id, mission_id, event_opts)
    else
      EventQuery.list_events(mission_id, event_opts)
    end
  end

  defp connection_state_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :connection_state_snapshot,
      kind: :operational_observable_state_changed,
      order: :asc,
      replay_run_id: Keyword.get(opts, :replay_run_id, :none),
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      EventQuery.list_events(organization_id, mission_id, event_opts)
    else
      EventQuery.list_events(mission_id, event_opts)
    end
  end

  defp link_rf_state_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: [:link_rf_lock_state_snapshot, :link_frame_sync_state_snapshot],
      kind: :operational_observable_state_changed,
      order: :asc,
      replay_run_id: Keyword.get(opts, :replay_run_id, :none),
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      EventQuery.list_events(organization_id, mission_id, event_opts)
    else
      EventQuery.list_events(mission_id, event_opts)
    end
  end

  defp operational_observable_state_source_record_kinds do
    [
      :connection_state_snapshot,
      :link_rf_lock_state_snapshot,
      :link_frame_sync_state_snapshot,
      :operational_observable_snapshot
    ]
  end

  defp operational_observable_metric_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :operational_observable_snapshot,
      kind: :operational_observable_metric_sampled,
      from_occurred_at: from_time(opts),
      to_occurred_at: to_time(opts),
      order: Keyword.get(opts, :order, :asc),
      replay_run_id: Keyword.get(opts, :replay_run_id, :none),
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      EventQuery.list_events(organization_id, mission_id, event_opts)
    else
      EventQuery.list_events(mission_id, event_opts)
    end
  end

  defp operational_observable_state_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      operational_observable_state_interval(event, next_event)
    end)
  end

  defp connection_state_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      connection_state_interval(event, next_event)
    end)
  end

  defp link_rf_state_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      link_rf_state_interval(event, next_event)
    end)
  end

  defp operational_observable_state_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    observable_id = payload_value(event, :observable_id)
    resource_id = payload_value(event, :resource_id) || subject_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:operational_observable_state:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :operational_observable_state,
      subject_kind: subject_kind(event),
      subject_id: resource_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "observable_id" => observable_id,
        "resource_id" => resource_id,
        "scope_kind" => payload_value(event, :scope_kind),
        "transport_id" => payload_value(event, :transport_id),
        "source_endpoint_id" => payload_value(event, :source_endpoint_id),
        "ground_station_id" => payload_value(event, :ground_station_id),
        "link_id" => payload_value(event, :link_id),
        "adapter_key" => payload_value(event, :adapter_key),
        "connection_state" => payload_value(event, :connection_state),
        "state" => payload_value(event, :state),
        "normalized_state" => payload_value(event, :normalized_state),
        "observed_at" => payload_value(event, :observed_at),
        "replay_run_id" =>
          causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
      },
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp connection_state_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    observable_id = payload_value(event, :observable_id)
    resource_id = payload_value(event, :resource_id) || subject_id(event)
    interval_kind = connection_interval_kind(observable_id)

    %EffectiveInterval{
      interval_id: "effective_interval:#{interval_kind}:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: interval_kind,
      subject_kind: connection_subject_kind(observable_id),
      subject_id: resource_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: connection_state_payload(event, observable_id, resource_id),
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp connection_state_payload(%Event{} = event, observable_id, resource_id) do
    connection_state = payload_value(event, :connection_state)

    %{
      "observable_id" => observable_id,
      "resource_id" => resource_id,
      "scope_kind" => payload_value(event, :scope_kind),
      "transport_id" => payload_value(event, :transport_id),
      "source_endpoint_id" => payload_value(event, :source_endpoint_id),
      "ground_station_id" => payload_value(event, :ground_station_id),
      "link_id" => payload_value(event, :link_id),
      "adapter_key" => payload_value(event, :adapter_key),
      "connection_state_family" => connection_state_family(observable_id),
      "transport_connection_state" => transport_connection_state(observable_id, connection_state),
      "ground_station_connection_state" =>
        ground_station_connection_state(observable_id, connection_state),
      "connection_state" => connection_state,
      "state" => payload_value(event, :state),
      "normalized_state" => payload_value(event, :normalized_state),
      "observed_at" => payload_value(event, :observed_at),
      "replay_run_id" =>
        causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
    }
  end

  defp connection_interval_kind("comms.transport.connection_state"),
    do: :transport_connection_state

  defp connection_interval_kind("ground.station.connection_state"),
    do: :ground_station_connection_state

  defp connection_subject_kind("comms.transport.connection_state"), do: :transport
  defp connection_subject_kind("ground.station.connection_state"), do: :ground_station

  defp connection_state_family("comms.transport.connection_state"), do: :transport
  defp connection_state_family("ground.station.connection_state"), do: :ground_station

  defp transport_connection_state("comms.transport.connection_state", state), do: state
  defp transport_connection_state(_observable_id, _state), do: nil

  defp ground_station_connection_state("ground.station.connection_state", state), do: state
  defp ground_station_connection_state(_observable_id, _state), do: nil

  defp link_rf_state_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    observable_id = payload_value(event, :observable_id)
    resource_id = payload_value(event, :resource_id) || subject_id(event)
    interval_kind = link_rf_interval_kind(observable_id)

    %EffectiveInterval{
      interval_id: "effective_interval:#{interval_kind}:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: interval_kind,
      subject_kind: :link,
      subject_id: resource_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: link_rf_state_payload(event, observable_id, resource_id),
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp link_rf_state_payload(%Event{} = event, observable_id, resource_id) do
    state = payload_value(event, :state)

    %{
      "observable_id" => observable_id,
      "resource_id" => resource_id,
      "scope_kind" => payload_value(event, :scope_kind),
      "transport_id" => payload_value(event, :transport_id),
      "source_endpoint_id" => payload_value(event, :source_endpoint_id),
      "ground_station_id" => payload_value(event, :ground_station_id),
      "link_id" => payload_value(event, :link_id),
      "adapter_key" => payload_value(event, :adapter_key),
      "rf_state_family" => link_rf_state_family(observable_id),
      "rf_lock_state" => rf_lock_state(observable_id, state),
      "frame_sync_state" => frame_sync_state(observable_id, state),
      "state" => state,
      "normalized_state" => payload_value(event, :normalized_state),
      "observed_at" => payload_value(event, :observed_at),
      "replay_run_id" =>
        causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
    }
  end

  defp link_rf_interval_kind("link.rf_lock_state"), do: :link_rf_lock_state
  defp link_rf_interval_kind("link.frame_sync_state"), do: :link_frame_sync_state

  defp link_rf_state_family("link.rf_lock_state"), do: :rf_lock
  defp link_rf_state_family("link.frame_sync_state"), do: :frame_sync

  defp rf_lock_state("link.rf_lock_state", state), do: state
  defp rf_lock_state(_observable_id, _state), do: nil

  defp frame_sync_state("link.frame_sync_state", state), do: state
  defp frame_sync_state(_observable_id, _state), do: nil

  defp operational_observable_metric_sample(%Event{} = event) do
    %{
      observable_id: payload_value(event, :observable_id),
      mission_id: event.mission_id,
      organization_id: event.organization_id,
      resource_id: payload_value(event, :resource_id) || subject_id(event),
      scope_kind: payload_value(event, :scope_kind),
      transport_id: payload_value(event, :transport_id),
      spacecraft_id: payload_value(event, :spacecraft_id),
      contact_id: payload_value(event, :contact_id),
      scheduled_contact_id: payload_value(event, :scheduled_contact_id),
      realized_contact_id: payload_value(event, :realized_contact_id),
      source_endpoint_id: payload_value(event, :source_endpoint_id),
      ground_station_id: payload_value(event, :ground_station_id),
      link_id: payload_value(event, :link_id),
      link_assignment_id: payload_value(event, :link_id),
      adapter_key: payload_value(event, :adapter_key),
      value: payload_value(event, :value),
      unit: payload_value(event, :unit),
      downlink_bitrate: payload_value(event, :downlink_bitrate),
      downlink_bitrate_bps: payload_value(event, :downlink_bitrate_bps),
      uplink_bitrate: payload_value(event, :uplink_bitrate),
      uplink_bitrate_bps: payload_value(event, :uplink_bitrate_bps),
      bitrate: payload_value(event, :bitrate),
      snr_db: payload_value(event, :snr_db),
      snr: payload_value(event, :snr),
      signal_to_noise_ratio_db: payload_value(event, :signal_to_noise_ratio_db),
      eb_n0_db: payload_value(event, :eb_n0_db),
      ebn0_db: payload_value(event, :ebn0_db),
      energy_per_bit_to_noise_density_db:
        payload_value(event, :energy_per_bit_to_noise_density_db),
      symbol_rate_sps: payload_value(event, :symbol_rate_sps),
      symbol_rate: payload_value(event, :symbol_rate),
      symbols_per_second: payload_value(event, :symbols_per_second),
      doppler_hz: payload_value(event, :doppler_hz),
      doppler: payload_value(event, :doppler),
      frequency_offset_hz: payload_value(event, :frequency_offset_hz),
      carrier_frequency_offset_hz: payload_value(event, :carrier_frequency_offset_hz),
      observed_at: payload_datetime_value(event, :observed_at) || event.occurred_at,
      source_event_id: event.event_id,
      replay_run_id:
        causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_filter_interval_payload(intervals, _key, nil), do: intervals

  defp maybe_filter_interval_payload(intervals, key, values) when is_list(values) do
    normalized_values = Enum.map(values, &normalize_filter_value/1)

    Enum.filter(intervals, fn %EffectiveInterval{} = interval ->
      normalized_payload_value =
        interval.payload
        |> map_value(key)
        |> normalize_payload_filter_value()

      normalized_payload_value in normalized_values
    end)
  end

  defp maybe_filter_interval_payload(intervals, key, value) do
    normalized_value = normalize_filter_value(value)

    Enum.filter(intervals, fn %EffectiveInterval{} = interval ->
      interval.payload
      |> map_value(key)
      |> normalize_payload_filter_value() == normalized_value
    end)
  end

  defp maybe_filter_sample_payload(samples, _key, nil), do: samples

  defp maybe_filter_sample_payload(samples, key, values) when is_list(values) do
    normalized_values = Enum.map(values, &normalize_filter_value/1)

    Enum.filter(samples, fn sample ->
      normalized_sample_value =
        sample
        |> map_value(key)
        |> normalize_payload_filter_value()

      normalized_sample_value in normalized_values
    end)
  end

  defp maybe_filter_sample_payload(samples, key, value) do
    normalized_value = normalize_filter_value(value)

    Enum.filter(samples, fn sample ->
      sample
      |> map_value(key)
      |> normalize_payload_filter_value() == normalized_value
    end)
  end

  defp maybe_filter_at(intervals, nil), do: intervals

  defp maybe_filter_at(intervals, %DateTime{} = at) do
    Enum.filter(intervals, &EffectiveInterval.contains?(&1, at))
  end

  defp order_intervals(intervals, order) when order in [:desc, "desc"] do
    Enum.sort_by(intervals, &interval_sort_key/1, :desc)
  end

  defp order_intervals(intervals, _order) do
    Enum.sort_by(intervals, &interval_sort_key/1, :asc)
  end

  defp order_samples(samples, order) when order in [:desc, "desc"] do
    Enum.sort_by(samples, &sample_sort_key/1, :desc)
  end

  defp order_samples(samples, _order) do
    Enum.sort_by(samples, &sample_sort_key/1, :asc)
  end

  defp sample_sort_key(sample) do
    observed_at = sample_datetime_value(sample, :observed_at)
    source_event_id = map_value(sample, :source_event_id) || ""

    {DateTime.to_unix(observed_at, :microsecond), source_event_id}
  end

  defp interval_sort_key(%EffectiveInterval{} = interval) do
    {DateTime.to_unix(interval.starts_at, :microsecond), interval.interval_id}
  end

  defp event_sort_key(%Event{} = event) do
    {DateTime.to_unix(event.occurred_at, :microsecond), event.event_id}
  end

  defp from_time(opts), do: Keyword.get(opts, :from_time) || Keyword.get(opts, :from_occurred_at)
  defp to_time(opts), do: Keyword.get(opts, :to_time) || Keyword.get(opts, :to_occurred_at)

  defp payload_value(%Event{payload: payload}, key), do: map_value(payload, key)

  defp payload_datetime_value(%Event{payload: payload}, key),
    do: datetime_value(map_value(payload, key))

  defp causality_value(%Event{causality: causality}, key), do: map_value(causality, key)

  defp subject_id(%Event{subject: %{id: id}}), do: id
  defp subject_id(%Event{subject: %{"id" => id}}), do: id
  defp subject_id(%Event{}), do: nil

  defp operational_observable_state_key(%Event{} = event) do
    {
      payload_value(event, :observable_id),
      payload_value(event, :resource_id) || subject_id(event)
    }
  end

  defp subject_kind(%Event{subject: %{kind: kind}}), do: kind
  defp subject_kind(%Event{subject: %{"kind" => kind}}), do: kind
  defp subject_kind(%Event{}), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp sample_datetime_value(sample, key), do: datetime_value(map_value(sample, key))

  defp datetime_value(%DateTime{} = datetime), do: datetime

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp datetime_value(_value), do: nil

  defp normalize_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_filter_value(value) when is_binary(value), do: value

  defp normalize_payload_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_payload_filter_value(value), do: value
end
