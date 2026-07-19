defmodule Cadence.Dashboards.Sources.OperationalObservables.OperationalEventSnapshots do
  @moduledoc """
  Reads projected operational intervals and samples as source-family snapshots.

  This module owns request-option projection and the shared conversion from
  OperationalEvents records into the maps consumed by operational-observable
  row materializers.
  """

  alias Cadence.OperationalEvents

  @connection_observable_ids [
    "comms.transport.connection_state",
    "ground.station.connection_state"
  ]
  @antenna_pointing_observable_ids ["ground.station.antenna_pointing_state"]
  @link_rf_lock_observable_ids ["link.rf_lock_state"]
  @link_rf_frame_sync_observable_ids ["link.frame_sync_state"]
  @link_rf_metric_observable_ids [
    "link.snr_db",
    "link.eb_n0_db",
    "link.symbol_rate_sps",
    "link.doppler_hz"
  ]
  @bitrate_observable_ids [
    "comms.transport.downlink_bitrate",
    "comms.transport.uplink_bitrate"
  ]
  @ingress_latency_observable_ids ["ingress.processing_latency_ms"]

  @spec connection(binary(), binary(), keyword()) :: [map()]
  def connection(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.connection_state_intervals(
      mission_id,
      state_interval_opts(@connection_observable_ids, opts)
    )
    |> Enum.map(&connection_snapshot/1)
  end

  @spec antenna_pointing(binary(), binary(), keyword()) :: [map()]
  def antenna_pointing(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.operational_observable_state_intervals(
      mission_id,
      state_interval_opts(@antenna_pointing_observable_ids, opts)
    )
    |> Enum.map(&antenna_pointing_snapshot/1)
  end

  @spec transport_bitrate(binary(), binary(), keyword()) :: [map()]
  def transport_bitrate(organization_id, mission_id, opts) do
    metric_snapshots(organization_id, mission_id, @bitrate_observable_ids, opts)
  end

  @spec link_rf_lock(binary(), binary(), keyword()) :: [map()]
  def link_rf_lock(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.link_rf_state_intervals(
      mission_id,
      state_interval_opts(@link_rf_lock_observable_ids, opts)
    )
    |> Enum.map(&rf_lock_snapshot/1)
  end

  @spec link_rf_frame_sync(binary(), binary(), keyword()) :: [map()]
  def link_rf_frame_sync(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.link_rf_state_intervals(
      mission_id,
      state_interval_opts(@link_rf_frame_sync_observable_ids, opts)
    )
    |> Enum.map(&rf_frame_sync_snapshot/1)
  end

  @spec link_rf_metric(binary(), binary(), keyword()) :: [map()]
  def link_rf_metric(organization_id, mission_id, opts) do
    metric_snapshots(organization_id, mission_id, @link_rf_metric_observable_ids, opts)
  end

  @spec ingress_latency(binary(), binary(), keyword()) :: [map()]
  def ingress_latency(organization_id, mission_id, opts) do
    metric_snapshots(organization_id, mission_id, @ingress_latency_observable_ids, opts)
  end

  defp metric_snapshots(organization_id, mission_id, observable_ids, opts) do
    organization_id
    |> OperationalEvents.operational_observable_metric_samples(
      mission_id,
      metric_sample_opts(observable_ids, opts)
    )
    |> Enum.map(&metric_snapshot/1)
  end

  defp metric_sample_opts(observable_ids, opts) do
    [
      observable_id: observable_ids,
      from_time: Keyword.get(opts, :from),
      to_time: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      event_limit: Keyword.get(opts, :event_limit, 1_000),
      order: historical_order(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp state_interval_opts(observable_ids, opts) do
    [
      observable_id: observable_ids,
      from_time: Keyword.get(opts, :from),
      to_time: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      event_limit: Keyword.get(opts, :event_limit, 1_000),
      order: historical_order(opts)
    ]
    |> maybe_add_latest_at(opts)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp historical_order(opts) do
    if Keyword.get(opts, :from) || Keyword.get(opts, :to), do: :asc, else: :desc
  end

  defp maybe_add_latest_at(interval_opts, opts) do
    if Keyword.get(opts, :from) || Keyword.get(opts, :to) do
      interval_opts
    else
      [{:at, Keyword.get(opts, :at, DateTime.utc_now())} | interval_opts]
    end
  end

  defp connection_snapshot(interval) do
    payload = attr(interval, :payload) || %{}

    %{
      observable_id: attr(payload, :observable_id),
      resource_id: attr(payload, :resource_id) || attr(interval, :subject_id),
      transport_id: attr(payload, :transport_id),
      source_endpoint_id: attr(payload, :source_endpoint_id),
      ground_station_id: attr(payload, :ground_station_id),
      link_id: attr(payload, :link_id),
      adapter_key: attr(payload, :adapter_key),
      connection_state: attr(payload, :connection_state),
      observed_at: attr(interval, :starts_at),
      interval_id: attr(interval, :interval_id),
      source_event_id: attr(interval, :source_event_id),
      replay_run_id: attr(payload, :replay_run_id),
      interval: interval
    }
  end

  defp metric_snapshot(sample) do
    %{
      observable_id: attr(sample, :observable_id),
      mission_id: attr(sample, :mission_id),
      organization_id: attr(sample, :organization_id),
      resource_id: attr(sample, :resource_id),
      transport_id: attr(sample, :transport_id),
      spacecraft_id: attr(sample, :spacecraft_id),
      contact_id:
        attr(sample, :contact_id) ||
          attr(sample, :scheduled_contact_id) ||
          attr(sample, :realized_contact_id),
      source_endpoint_id: attr(sample, :source_endpoint_id),
      ground_station_id: attr(sample, :ground_station_id),
      link_id: attr(sample, :link_id),
      link_assignment_id: attr(sample, :link_id),
      adapter_key: attr(sample, :adapter_key),
      value: attr(sample, :value),
      unit: attr(sample, :unit),
      downlink_bitrate: attr(sample, :downlink_bitrate),
      downlink_bitrate_bps: attr(sample, :downlink_bitrate_bps),
      uplink_bitrate: attr(sample, :uplink_bitrate),
      uplink_bitrate_bps: attr(sample, :uplink_bitrate_bps),
      bitrate: attr(sample, :bitrate),
      snr_db: attr(sample, :snr_db),
      snr: attr(sample, :snr),
      signal_to_noise_ratio_db: attr(sample, :signal_to_noise_ratio_db),
      eb_n0_db: attr(sample, :eb_n0_db),
      ebn0_db: attr(sample, :ebn0_db),
      energy_per_bit_to_noise_density_db: attr(sample, :energy_per_bit_to_noise_density_db),
      symbol_rate_sps: attr(sample, :symbol_rate_sps),
      symbol_rate: attr(sample, :symbol_rate),
      symbols_per_second: attr(sample, :symbols_per_second),
      doppler_hz: attr(sample, :doppler_hz),
      doppler: attr(sample, :doppler),
      frequency_offset_hz: attr(sample, :frequency_offset_hz),
      carrier_frequency_offset_hz: attr(sample, :carrier_frequency_offset_hz),
      observed_at: attr(sample, :observed_at),
      source_event_id: attr(sample, :source_event_id),
      replay_run_id: attr(sample, :replay_run_id)
    }
  end

  defp rf_lock_snapshot(interval) do
    payload = attr(interval, :payload) || %{}
    state = attr(payload, :state)

    interval
    |> state_snapshot(payload)
    |> Map.merge(%{lock_state: state, state: state})
  end

  defp rf_frame_sync_snapshot(interval) do
    payload = attr(interval, :payload) || %{}
    state = attr(payload, :state)

    interval
    |> state_snapshot(payload)
    |> Map.merge(%{frame_sync_state: state, state: state})
  end

  defp antenna_pointing_snapshot(interval) do
    payload = attr(interval, :payload) || %{}
    state = attr(payload, :state) || attr(payload, :normalized_state)

    interval
    |> state_snapshot(payload)
    |> Map.merge(%{antenna_pointing_state: state, state: state})
  end

  defp state_snapshot(interval, payload) do
    %{
      observable_id: attr(payload, :observable_id),
      resource_id: attr(payload, :resource_id) || attr(interval, :subject_id),
      transport_id: attr(payload, :transport_id),
      source_endpoint_id: attr(payload, :source_endpoint_id),
      ground_station_id: attr(payload, :ground_station_id),
      link_id: attr(payload, :link_id),
      link_assignment_id: attr(payload, :link_id),
      adapter_key: attr(payload, :adapter_key),
      normalized_state: attr(payload, :normalized_state),
      observed_at: attr(interval, :starts_at),
      interval_id: attr(interval, :interval_id),
      source_event_id: attr(interval, :source_event_id),
      replay_run_id: attr(payload, :replay_run_id),
      interval: interval
    }
  end

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
