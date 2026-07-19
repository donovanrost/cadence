defmodule Cadence.Dashboards.Sources.OperationalObservablesReplayFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Comms.Transport

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding
  }

  alias Cadence.Dashboards.Sources.OperationalObservables
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Runtime.TransportCapabilityRecord

  def persist_default_metric_samples!(organization_id, mission_id) do
    for metric_attrs <-
          [
            metric_sample("rf-snr-live-1", "link.snr_db", 11.5, ~U[2026-06-30 12:00:00Z]),
            metric_sample("rf-snr-replay-1", "link.snr_db", 12.25, ~U[2026-06-30 12:01:00Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-snr-other-replay",
              "link.snr_db",
              7.5,
              ~U[2026-06-30 12:02:00Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample("rf-snr-replay-2", "link.snr_db", 14.0, ~U[2026-06-30 12:03:00Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample("rf-ebn0-live-1", "link.eb_n0_db", 8.75, ~U[2026-06-30 12:00:30Z]),
            metric_sample("rf-ebn0-replay-1", "link.eb_n0_db", 9.25, ~U[2026-06-30 12:01:30Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-ebn0-other-replay",
              "link.eb_n0_db",
              5.5,
              ~U[2026-06-30 12:02:30Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample("rf-ebn0-replay-2", "link.eb_n0_db", 10.0, ~U[2026-06-30 12:03:30Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-doppler-live-1",
              "link.doppler_hz",
              -42.5,
              ~U[2026-06-30 12:00:45Z]
            ),
            metric_sample(
              "rf-doppler-replay-1",
              "link.doppler_hz",
              -40.25,
              ~U[2026-06-30 12:01:45Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-doppler-other-replay",
              "link.doppler_hz",
              11.5,
              ~U[2026-06-30 12:02:45Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample(
              "rf-doppler-replay-2",
              "link.doppler_hz",
              -38.0,
              ~U[2026-06-30 12:03:45Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-symbol-rate-live-1",
              "link.symbol_rate_sps",
              1_024_000.0,
              ~U[2026-06-30 12:00:50Z]
            ),
            metric_sample(
              "rf-symbol-rate-replay-1",
              "link.symbol_rate_sps",
              1_048_000.0,
              ~U[2026-06-30 12:01:50Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-symbol-rate-other-replay",
              "link.symbol_rate_sps",
              512_000.0,
              ~U[2026-06-30 12:02:50Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample(
              "rf-symbol-rate-replay-2",
              "link.symbol_rate_sps",
              2_048_000.0,
              ~U[2026-06-30 12:03:50Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "bitrate-live-1",
              "comms.transport.downlink_bitrate",
              64_000.0,
              ~U[2026-06-30 12:00:15Z]
            ),
            metric_sample(
              "uplink-bitrate-live-1",
              "comms.transport.uplink_bitrate",
              4_800.0,
              ~U[2026-06-30 12:00:20Z]
            ),
            metric_sample(
              "bitrate-replay-1",
              "comms.transport.downlink_bitrate",
              72_000.0,
              ~U[2026-06-30 12:01:15Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "uplink-bitrate-replay-1",
              "comms.transport.uplink_bitrate",
              5_600.0,
              ~U[2026-06-30 12:01:20Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "bitrate-other-replay",
              "comms.transport.downlink_bitrate",
              48_000.0,
              ~U[2026-06-30 12:02:15Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample(
              "uplink-bitrate-other-replay",
              "comms.transport.uplink_bitrate",
              3_200.0,
              ~U[2026-06-30 12:02:20Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample(
              "bitrate-replay-2",
              "comms.transport.downlink_bitrate",
              96_000.0,
              ~U[2026-06-30 12:03:15Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "uplink-bitrate-replay-2",
              "comms.transport.uplink_bitrate",
              8_400.0,
              ~U[2026-06-30 12:03:20Z],
              replay_run_id: "replay-run-1"
            )
          ] do
      assert {:ok, _event} =
               operational_observable_metric_event(organization_id, mission_id, metric_attrs)
               |> OperationalEvents.persist_event()
    end

    :ok
  end

  def source_request(organization_id, mission_id) do
    %PlannedSourceRequest{
      request_id: "ops-request-1",
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :operational_observables,
      observables: [],
      data_context: %{realm: :flight},
      sampling: %{mode: :constellation_health}
    }
  end

  def transport_execution_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["comms.transport.execution_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :transport, mode: :one, ids: ["uplink-heartbeat"]}
    })
  end

  def ingress_latency_request(%PlannedSourceRequest{} = request, source_endpoint_id) do
    request
    |> Map.put(:observables, ["ingress.processing_latency_ms"])
    |> Map.put(:sampling, %{mode: :latest})
    |> Map.put(:scope_context, %{
      primary: %{kind: :source_endpoint, mode: :one, ids: [source_endpoint_id]}
    })
  end

  def connection_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["comms.transport.connection_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
    })
  end

  def link_rf_lock_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.rf_lock_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  def link_rf_frame_sync_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.frame_sync_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  def antenna_pointing_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["ground.station.antenna_pointing_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}
    })
  end

  def link_rf_metric_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.snr_db"])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  def link_rf_eb_n0_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.eb_n0_db"])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  def link_rf_doppler_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.doppler_hz"])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  def link_rf_symbol_rate_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.symbol_rate_sps"])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  def transport_bitrate_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, [
      "comms.transport.downlink_bitrate",
      "comms.transport.uplink_bitrate"
    ])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
    })
  end

  def replay_request_context(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:time_context, %{
      mode: :replay_run,
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z],
      replay_run_id: "replay-run-1"
    })
    |> Map.put(:data_context, replay_data_context())
  end

  def replay_data_context do
    %{
      realm: :replay,
      replay_run_id: "replay-run-1",
      source_contexts: %{
        operational_observables: %{
          data_source_id: "managed_operational_observables_replay",
          source_binding_id: "replay-operational-observables",
          dataset: "operational_observables_replay"
        }
      }
    }
  end

  def source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "flight-operational-observables",
        realm: :flight,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables",
        dataset: "operational_observables"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables",
        adapter: OperationalObservables
      },
      realm: :flight,
      dataset: "operational_observables"
    }
  end

  def replay_source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay-operational-observables",
        realm: :replay,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables_replay",
        dataset: "operational_observables_replay"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables_replay",
        adapter: OperationalObservables
      },
      realm: :replay,
      dataset: "operational_observables_replay"
    }
  end

  def transports_fun(organization_id, mission_id) do
    fn ^organization_id, ^mission_id, _opts ->
      [
        Transport.new(%{
          transport_id: "transport-alpha",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "Lab TCP",
          adapter_key: :tcp_socket,
          metadata: %{
            source_endpoint_id: "endpoint-alpha",
            ground_station_id: "dss-14",
            link_assignment_id: "link-alpha"
          }
        })
      ]
    end
  end

  def source_endpoints_fun(organization_id, mission_id) do
    fn ^organization_id, ^mission_id, _opts ->
      [
        %{
          source_endpoint_id: "endpoint-alpha",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "DSS-14 endpoint",
          metadata: %{
            "ground_station_id" => "dss-14",
            "transport_id" => "transport-alpha",
            "link_assignment_id" => "link-alpha"
          }
        }
      ]
    end
  end

  def transport_capability_record(
        mission_id,
        transport_record_id,
        capability_instance_id,
        event_kind,
        recorded_at,
        opts
      ) do
    %TransportCapabilityRecord{
      transport_record_id: transport_record_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      event_kind: event_kind,
      timer_key: Keyword.get(opts, :timer_key),
      emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
      emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
      action_request_count: Keyword.get(opts, :action_request_count, 0),
      state_snapshot: Keyword.fetch!(opts, :state_snapshot),
      recorded_at: recorded_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def operational_observable_state_event(
        organization_id,
        mission_id,
        snapshot_id,
        state,
        observed_at,
        opts \\ []
      ) do
    observable_id = Keyword.get(opts, :observable_id, "comms.transport.connection_state")

    Event.from_operational_observable_state_snapshot(%{
      snapshot_id: snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: Keyword.get(opts, :resource_id, "transport-alpha"),
      scope_kind: Keyword.get(opts, :scope_kind, :transport),
      transport_id: "transport-alpha",
      source_endpoint_id: "endpoint-alpha",
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :tcp_socket,
      connection_state: connection_state(observable_id, state),
      state: operational_observable_state(observable_id, state),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  def connection_state("comms.transport.connection_state", state), do: state
  def connection_state(_observable_id, _state), do: nil

  def operational_observable_state("comms.transport.connection_state", _state), do: nil
  def operational_observable_state(_observable_id, state), do: state

  def metric_sample(sample_id, observable_id, value, observed_at, opts \\ []) do
    source_endpoint_id = Keyword.get(opts, :source_endpoint_id, "endpoint-alpha")

    %{
      sample_id: sample_id,
      observable_id: observable_id,
      resource_id: operational_observable_metric_resource_id(observable_id, source_endpoint_id),
      scope_kind: operational_observable_metric_scope_kind(observable_id),
      value_key: operational_observable_metric_value_key(observable_id),
      value: value,
      source_endpoint_id: source_endpoint_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      observed_at: observed_at,
      replay_run_id: Keyword.get(opts, :replay_run_id)
    }
  end

  def operational_observable_metric_event(organization_id, mission_id, metric_attrs) do
    attrs = %{
      sample_id: metric_attrs.sample_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: metric_attrs.observable_id,
      resource_id: metric_attrs.resource_id,
      scope_kind: metric_attrs.scope_kind,
      transport_id: "transport-alpha",
      spacecraft_id: metric_attrs.spacecraft_id,
      source_endpoint_id: metric_attrs.source_endpoint_id,
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :tcp_socket,
      unit: operational_observable_metric_unit(metric_attrs.observable_id),
      replay_run_id: metric_attrs.replay_run_id,
      observed_at: metric_attrs.observed_at
    }

    attrs
    |> Map.put(metric_attrs.value_key, metric_attrs.value)
    |> Event.from_operational_observable_metric_sample()
  end

  def operational_observable_metric_resource_id("link.snr_db", _source_endpoint_id),
    do: "link-alpha"

  def operational_observable_metric_resource_id("link.eb_n0_db", _source_endpoint_id),
    do: "link-alpha"

  def operational_observable_metric_resource_id("link.doppler_hz", _source_endpoint_id),
    do: "link-alpha"

  def operational_observable_metric_resource_id("link.symbol_rate_sps", _source_endpoint_id),
    do: "link-alpha"

  def operational_observable_metric_resource_id(
        "ingress.processing_latency_ms",
        source_endpoint_id
      ),
      do: source_endpoint_id

  def operational_observable_metric_resource_id(_observable_id, _source_endpoint_id),
    do: "transport-alpha"

  def operational_observable_metric_scope_kind("link.snr_db"), do: :link
  def operational_observable_metric_scope_kind("link.eb_n0_db"), do: :link
  def operational_observable_metric_scope_kind("link.doppler_hz"), do: :link
  def operational_observable_metric_scope_kind("link.symbol_rate_sps"), do: :link

  def operational_observable_metric_scope_kind("ingress.processing_latency_ms"),
    do: :source_endpoint

  def operational_observable_metric_scope_kind(_observable_id), do: :transport

  def operational_observable_metric_value_key("link.snr_db"), do: :snr_db
  def operational_observable_metric_value_key("link.eb_n0_db"), do: :value
  def operational_observable_metric_value_key("link.doppler_hz"), do: :doppler_hz
  def operational_observable_metric_value_key("link.symbol_rate_sps"), do: :symbol_rate_sps
  def operational_observable_metric_value_key("ingress.processing_latency_ms"), do: :value

  def operational_observable_metric_value_key("comms.transport.uplink_bitrate"),
    do: :uplink_bitrate

  def operational_observable_metric_value_key(_observable_id), do: :downlink_bitrate

  def operational_observable_metric_unit("link.snr_db"), do: "dB"
  def operational_observable_metric_unit("link.eb_n0_db"), do: "dB"
  def operational_observable_metric_unit("link.doppler_hz"), do: "Hz"
  def operational_observable_metric_unit("link.symbol_rate_sps"), do: "sym/s"
  def operational_observable_metric_unit("comms.transport.downlink_bitrate"), do: "bit/s"
  def operational_observable_metric_unit("comms.transport.uplink_bitrate"), do: "bit/s"
  def operational_observable_metric_unit("ingress.processing_latency_ms"), do: "ms"
  def operational_observable_metric_unit(_observable_id), do: nil

  def replay_scoped_event(%TransportCapabilityRecord{} = record, replay_run_id) do
    Event.from_transport_capability_record(record, replay_run_id)
  end

  def field_values(%Frame{} = frame, name) do
    frame.fields
    |> Enum.find(&match?(%Field{name: ^name}, &1))
    |> case do
      %Field{values: values} -> values
      nil -> flunk("expected frame field #{inspect(name)}")
    end
  end

  def frame_by_observable!(frames, observable_id) when is_list(frames) do
    Enum.find(frames, &(&1.meta.observable_id == observable_id)) ||
      flunk("expected frame for observable #{inspect(observable_id)}")
  end

  def operational_event_link_ids(%Frame{} = frame) do
    frame.meta
    |> Map.get(:links, [])
    |> Enum.filter(&(&1.target == :operational_event))
    |> Enum.map(& &1.target_id)
  end

  def operational_event_evidence_ids(%Frame{} = frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.filter(&(&1.kind == :operational_event))
    |> Enum.map(& &1.id)
  end

  def evidence_ref_kinds(%Frame{} = frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.map(& &1.kind)
  end
end
