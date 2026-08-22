defmodule Cadence.OperationalEventsFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision
  alias Cadence.DataSources.{SourceHealthEvent, SourceWatermarkEvent}
  alias Cadence.OperationalEvents.Event
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord, TransportTimerEvent}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

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

  def transport_action_request(mission_id, action_request_id, requested_at, opts \\ []) do
    %TransportActionRequest{
      action_request_id: action_request_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: Keyword.get(opts, :capability_instance_id, "uplink-heartbeat"),
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      command_release_attempt_id: Keyword.get(opts, :command_release_attempt_id),
      command_request_id: Keyword.get(opts, :command_request_id),
      source_endpoint_ref: "source-endpoint-alpha",
      command_name: Keyword.get(opts, :command_name),
      signal_phase: Keyword.get(opts, :signal_phase),
      action_kind: Keyword.get(opts, :action_kind, :uplink_request),
      request_document: Keyword.get(opts, :request_document, %{}),
      requested_at: requested_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def transport_timer_event(mission_id, timer_event_id, occurred_at, opts \\ []) do
    %TransportTimerEvent{
      timer_event_id: timer_event_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: Keyword.get(opts, :capability_instance_id, "uplink-heartbeat"),
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      timer_key: Keyword.get(opts, :timer_key, "health-check"),
      event_kind: Keyword.get(opts, :event_kind, :fired),
      due_at: Keyword.get(opts, :due_at),
      occurred_at: occurred_at,
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

  def connection_state(observable_id, state)
      when observable_id in [
             "comms.transport.connection_state",
             "ground.station.connection_state"
           ],
      do: state

  def connection_state(_observable_id, _state), do: nil

  def operational_observable_state(observable_id, state)
      when observable_id in [
             "link.rf_lock_state",
             "link.frame_sync_state",
             "ground.station.antenna_pointing_state"
           ],
      do: state

  def operational_observable_state(_observable_id, _state), do: nil

  def operational_observable_metric_event(
        organization_id,
        mission_id,
        sample_id,
        snr_db,
        observed_at,
        opts \\ []
      ) do
    Event.from_operational_observable_metric_sample(%{
      sample_id: sample_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: "link.snr_db",
      resource_id: "link-alpha",
      scope_kind: :link,
      transport_id: "transport-alpha",
      source_endpoint_id: "endpoint-alpha",
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :rf_adapter,
      snr_db: snr_db,
      unit: "dB",
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  def replay_scoped_event(%TransportCapabilityRecord{} = record, replay_run_id) do
    Event.from_transport_capability_record(record, replay_run_id)
  end

  def source_capability_posture_event(
        organization_id,
        mission_id,
        posture_id,
        replay_run_id,
        observed_at
      ) do
    Event.from_source_capability_posture(%{
      source_capability_posture_id: posture_id,
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: "dashboard-capability-events",
      dashboard_version: 4,
      resolve_id: "resolve-capability-events",
      source_request_id: "req-telemetry",
      logical_source: :telemetry,
      data_source_id: "flight-questdb",
      source_binding_id: "flight-telemetry",
      realm: :replay,
      replay_run_id: replay_run_id,
      dataset: "flight",
      status: :fallback,
      requested_sampling: :latest,
      supported_sampling: [:latest],
      requested_products: [:link_rf_metric_history],
      supported_products: [:transport_bitrate_history],
      requested_time_axis: :generation_time,
      executed_time_axis: :receipt_time,
      supported_time_axes: [:receipt_time],
      source_execution_status: :cache_hit,
      source_execution_cache_status: :hit,
      source_execution_operator_action: :none,
      source_execution_runtime_action: :none,
      source_execution_warning_codes: [],
      observed_at: observed_at
    })
  end

  def source_health_event(
        organization_id,
        mission_id,
        source_health_event_id,
        replay_run_id,
        observed_at
      ) do
    %{
      source_health_event_id: source_health_event_id,
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "replay-questdb",
      source_binding_id: "replay-telemetry",
      realm: :replay,
      replay_run_id: replay_run_id,
      dataset: "replay",
      source_health: :degraded,
      previous_source_health: :healthy,
      reason: :source_probe_failed,
      observed_at: observed_at
    }
    |> SourceHealthEvent.new()
    |> Event.from_source_health_event()
  end

  def source_health_transition_event(
        organization_id,
        mission_id,
        source_health_event_id,
        data_source_id,
        replay_run_id,
        observed_at,
        source_health,
        previous_source_health
      ) do
    realm = if replay_run_id, do: :replay, else: :live

    dataset =
      if replay_run_id, do: "operational_observables_replay", else: "operational_observables"

    %{
      source_health_event_id: source_health_event_id,
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :operational_observables,
      data_source_id: data_source_id,
      source_binding_id: "operational-observables",
      realm: realm,
      replay_run_id: replay_run_id,
      dataset: dataset,
      source_health: source_health,
      previous_source_health: previous_source_health,
      reason: :source_probe_failed,
      observed_at: observed_at
    }
    |> SourceHealthEvent.new()
    |> Event.from_source_health_event()
  end

  def source_watermark_event(
        organization_id,
        mission_id,
        source_watermark_event_id,
        replay_run_id,
        observed_at
      ) do
    %{
      source_watermark_event_id: source_watermark_event_id,
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "replay-questdb",
      source_binding_id: "replay-telemetry",
      realm: :replay,
      replay_run_id: replay_run_id,
      dataset: "replay",
      event_type: :observed,
      complete_through: observed_at,
      latest_receipt_time: observed_at,
      sample_count: 42,
      confidence: :best_effort,
      reason: :source_watermark_observed,
      observed_at: observed_at
    }
    |> SourceWatermarkEvent.new()
    |> Event.from_source_watermark_event()
  end

  def catalog_revision(organization_id, mission_id, catalog_revision_id, opts) do
    Revision.new(%{
      catalog_revision_id: catalog_revision_id,
      organization_id: organization_id,
      mission_id: mission_id,
      catalog_database_id: "bus-catalog",
      revision_number: Keyword.fetch!(opts, :revision_number),
      revision_label: Keyword.fetch!(opts, :revision_label),
      catalog_family: :telemetry,
      artifact_id: "#{catalog_revision_id}-artifact",
      import_run_id: Keyword.fetch!(opts, :import_run_id),
      mission_model_revision_id: Keyword.fetch!(opts, :mission_model_revision_id),
      content_sha256: "#{catalog_revision_id}-sha",
      created_by: %{"service_identity_id" => "svc-importer"},
      metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
    })
  end

  def telemetry_binding_set(mission_id, binding_set_id, apid) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: binding_set_id <> "-packet",
        packet_name: binding_set_id,
        apid: apid,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: 1,
      rules: [
        BindingRule.new(%{
          handler_key: :definition_bound_telemetry,
          selector: %{match: %{packet_kind: :space_packet, apid: apid}},
          handler_configuration: packet_definition
        })
      ]
    })
  end

  def application_binding_set(mission_id, binding_set_id, opts) do
    source_endpoint_ref = Keyword.fetch!(opts, :source_endpoint_ref)
    apid = Keyword.fetch!(opts, :apid)
    metric_name = Keyword.fetch!(opts, :metric_name)

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "#{binding_set_id}-packet-counter",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => metric_name,
              "flush_interval_ms" => 25
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "#{binding_set_id}-packet-counter-rule",
          capability_instance_id: "#{binding_set_id}-packet-counter",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: apid}
          },
          priority: 10,
          fanout_mode: :multi
        })
      ]
    })
  end

  def persist_source_endpoint_scope(organization_id, mission_id, source_endpoint_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: "SC-001"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_ref,
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: "sc-001",
        source_ref: "provider/#{source_endpoint_ref}"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint)
  end
end
