defmodule Cadence.OperationalEvents.EventRuntimeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.OperationalEvents.Event

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  test "builds canonical operational observable state envelopes" do
    observed_at = ~U[2026-06-30 12:10:00Z]

    event =
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "connection-snapshot-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        connection_state: :connected,
        replay_run_id: "replay-run-1",
        observed_at: observed_at
      })

    assert event.event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:connection-snapshot-1"

    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == observed_at
    assert event.recorded_at == observed_at
    assert event.effective_at == observed_at
    assert event.category == :comms
    assert event.kind == :operational_observable_state_changed
    assert event.subject == %{kind: :transport, id: "transport-alpha"}

    assert event.scope == %{
             logical_source: :operational_observables,
             scope_type: :transport,
             scope_ref: "transport-alpha",
             transport_id: "transport-alpha",
             source_endpoint_id: "endpoint-alpha",
             ground_station_id: "dss-14",
             link_id: "link-alpha",
             replay_run_id: "replay-run-1"
           }

    assert event.causality == %{
             correlation_id: "comms.transport.connection_state:transport-alpha",
             source_record_kind: :connection_state_snapshot,
             source_record_id: "connection-snapshot-1",
             replay_run_id: "replay-run-1"
           }

    assert event.current.observable_id == "comms.transport.connection_state"
    assert event.current.resource_id == "transport-alpha"
    assert event.current.connection_state == :connected
    assert event.current.observed_at == observed_at
  end

  test "builds canonical antenna pointing state envelopes" do
    observed_at = ~U[2026-06-30 12:10:05Z]

    event =
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "antenna-pointing-snapshot-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "ground.station.antenna_pointing_state",
        resource_id: "dss-14",
        scope_kind: :ground_station,
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :antenna_adapter,
        state: :tracking,
        normalized_state: :green,
        observed_at: observed_at
      })

    assert event.event_id ==
             "operational_event:operational_observable_snapshot:antenna-pointing-snapshot-1"

    assert event.subject == %{kind: :ground_station, id: "dss-14"}

    assert event.causality == %{
             correlation_id: "ground.station.antenna_pointing_state:dss-14",
             source_record_kind: :operational_observable_snapshot,
             source_record_id: "antenna-pointing-snapshot-1"
           }

    assert event.current.observable_id == "ground.station.antenna_pointing_state"
    assert event.current.resource_id == "dss-14"
    assert event.current.scope_kind == :ground_station
    assert event.current.state == :tracking
    assert event.current.normalized_state == :green
    assert event.current.observed_at == observed_at
  end

  test "classifies canonical link state snapshots by operational source-record family" do
    observed_at = ~U[2026-06-30 12:10:10Z]

    rf_lock =
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "rf-lock-snapshot-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        state: :locked,
        normalized_state: :green,
        replay_run_id: "replay-run-1",
        observed_at: observed_at
      })

    frame_sync =
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "frame-sync-snapshot-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        state: :synchronized,
        normalized_state: :green,
        replay_run_id: "replay-run-1",
        observed_at: DateTime.add(observed_at, 5, :second)
      })

    assert rf_lock.event_id ==
             "operational_event:link_rf_lock_state_snapshot:replay-run-1:rf-lock-snapshot-1"

    assert rf_lock.causality.source_record_kind == :link_rf_lock_state_snapshot
    assert rf_lock.subject == %{kind: :link, id: "link-alpha"}
    assert rf_lock.current.observable_id == "link.rf_lock_state"
    assert rf_lock.current.state == :locked

    assert frame_sync.event_id ==
             "operational_event:link_frame_sync_state_snapshot:replay-run-1:frame-sync-snapshot-1"

    assert frame_sync.causality.source_record_kind == :link_frame_sync_state_snapshot
    assert frame_sync.subject == %{kind: :link, id: "link-alpha"}
    assert frame_sync.current.observable_id == "link.frame_sync_state"
    assert frame_sync.current.state == :synchronized
  end

  test "builds canonical operational observable metric envelopes" do
    observed_at = ~U[2026-06-30 12:10:30Z]

    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-snr-sample-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :rf_adapter,
        snr_db: 12.75,
        unit: "dB",
        replay_run_id: "replay-run-1",
        observed_at: observed_at
      })

    assert event.event_id ==
             "operational_event:operational_observable_snapshot:replay-run-1:rf-snr-sample-1"

    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == observed_at
    assert event.recorded_at == observed_at
    assert event.effective_at == observed_at
    assert event.category == :comms
    assert event.kind == :operational_observable_metric_sampled
    assert event.subject == %{kind: :link, id: "link-alpha"}

    assert event.scope == %{
             logical_source: :operational_observables,
             scope_type: :link,
             scope_ref: "link-alpha",
             transport_id: "transport-alpha",
             source_endpoint_id: "endpoint-alpha",
             ground_station_id: "dss-14",
             link_id: "link-alpha",
             replay_run_id: "replay-run-1"
           }

    assert event.causality == %{
             correlation_id: "link.snr_db:link-alpha",
             source_record_kind: :operational_observable_snapshot,
             source_record_id: "rf-snr-sample-1",
             replay_run_id: "replay-run-1"
           }

    assert event.current.observable_id == "link.snr_db"
    assert event.current.resource_id == "link-alpha"
    assert event.current.snr_db == 12.75
    assert event.current.unit == "dB"
    assert event.current.observed_at == observed_at
  end

  test "preserves uplink bitrate metric values in canonical operational observable envelopes" do
    observed_at = ~U[2026-06-30 12:10:45Z]

    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "uplink-bitrate-sample-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        uplink_bitrate: 4_800.0,
        uplink_bitrate_bps: 4_800.0,
        unit: "bit/s",
        observed_at: observed_at
      })

    assert event.current.observable_id == "comms.transport.uplink_bitrate"
    assert event.current.resource_id == "transport-alpha"
    assert event.current.uplink_bitrate == 4_800.0
    assert event.current.uplink_bitrate_bps == 4_800.0
    assert event.current.unit == "bit/s"
    assert event.current.observed_at == observed_at
  end

  test "preserves RF Eb/N0 metric values in canonical operational observable envelopes" do
    observed_at = ~U[2026-06-30 12:11:00Z]

    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-ebn0-sample-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :rf_adapter,
        eb_n0_db: 8.25,
        ebn0_db: 8.25,
        energy_per_bit_to_noise_density_db: 8.25,
        unit: "dB",
        replay_run_id: "replay-run-1",
        observed_at: observed_at
      })

    assert event.event_id ==
             "operational_event:operational_observable_snapshot:replay-run-1:rf-ebn0-sample-1"

    assert event.subject == %{kind: :link, id: "link-alpha"}
    assert event.causality.correlation_id == "link.eb_n0_db:link-alpha"
    assert event.current.observable_id == "link.eb_n0_db"
    assert event.current.resource_id == "link-alpha"
    assert event.current.eb_n0_db == 8.25
    assert event.current.ebn0_db == 8.25
    assert event.current.energy_per_bit_to_noise_density_db == 8.25
    assert event.current.unit == "dB"
    assert event.current.observed_at == observed_at
  end

  test "preserves RF symbol-rate metric values in canonical operational observable envelopes" do
    observed_at = ~U[2026-06-30 12:11:15Z]

    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-symbol-rate-sample-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :rf_adapter,
        symbol_rate_sps: 1_024_000.0,
        symbol_rate: 1_024_000.0,
        symbols_per_second: 1_024_000.0,
        unit: "sym/s",
        replay_run_id: "replay-run-1",
        observed_at: observed_at
      })

    assert event.event_id ==
             "operational_event:operational_observable_snapshot:replay-run-1:rf-symbol-rate-sample-1"

    assert event.subject == %{kind: :link, id: "link-alpha"}
    assert event.causality.correlation_id == "link.symbol_rate_sps:link-alpha"
    assert event.current.observable_id == "link.symbol_rate_sps"
    assert event.current.resource_id == "link-alpha"
    assert event.current.symbol_rate_sps == 1_024_000.0
    assert event.current.symbol_rate == 1_024_000.0
    assert event.current.symbols_per_second == 1_024_000.0
    assert event.current.unit == "sym/s"
    assert event.current.observed_at == observed_at
  end

  test "preserves RF Doppler metric values in canonical operational observable envelopes" do
    observed_at = ~U[2026-06-30 12:11:30Z]

    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-doppler-sample-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :rf_adapter,
        doppler_hz: -42.5,
        frequency_offset_hz: -42.5,
        carrier_frequency_offset_hz: -42.5,
        unit: "Hz",
        replay_run_id: "replay-run-1",
        observed_at: observed_at
      })

    assert event.event_id ==
             "operational_event:operational_observable_snapshot:replay-run-1:rf-doppler-sample-1"

    assert event.subject == %{kind: :link, id: "link-alpha"}
    assert event.causality.correlation_id == "link.doppler_hz:link-alpha"
    assert event.current.observable_id == "link.doppler_hz"
    assert event.current.resource_id == "link-alpha"
    assert event.current.doppler_hz == -42.5
    assert event.current.frequency_offset_hz == -42.5
    assert event.current.carrier_frequency_offset_hz == -42.5
    assert event.current.unit == "Hz"
    assert event.current.observed_at == observed_at
  end

  test "builds canonical transport action request envelopes" do
    requested_at = ~U[2026-06-30 12:09:00Z]

    action_request = %TransportActionRequest{
      action_request_id: "transport-action-1",
      mission_id: "mission-1",
      realized_contact_id: "realized-contact-1",
      path_id: "uplink-path-1",
      capability_instance_id: "uplink-gateway-1",
      family_key: :uplink_gateway,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      source_endpoint_ref: "endpoint-a",
      command_name: "NOOP",
      signal_phase: :completion,
      action_kind: :uplink_request,
      request_document: %{"transfer_frame_count" => 1},
      requested_at: requested_at,
      metadata: %{timer_key: "cop1"}
    }

    event = Event.from_transport_action_request(action_request)

    assert event.event_id == "operational_event:transport_action_request:transport-action-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == requested_at
    assert event.recorded_at == requested_at
    assert event.effective_at == requested_at
    assert event.category == :comms
    assert event.kind == :transport_action_requested
    assert event.severity == :info
    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :transport, id: "uplink-gateway-1"}

    assert event.scope == %{
             contact_id: "realized-contact-1",
             realized_contact_id: "realized-contact-1",
             path_id: "uplink-path-1",
             capability_instance_id: "uplink-gateway-1",
             source_endpoint_ref: "endpoint-a",
             binding_set_id: "binding-set-1",
             activation_id: "activation-1"
           }

    assert event.causality == %{
             correlation_id: "release-attempt-1",
             causation_event_id: "release-attempt-1",
             source_record_kind: :transport_action_request,
             source_record_id: "transport-action-1"
           }

    assert event.current.action_request_id == "transport-action-1"
    assert event.current.action_kind == :uplink_request
    assert event.current.command_release_attempt_id == "release-attempt-1"
    assert event.current.command_request_id == "command-request-1"
    assert event.current.request_document == %{"transfer_frame_count" => 1}
    assert event.metadata == %{timer_key: "cop1"}
  end

  test "builds canonical transport capability record envelopes" do
    recorded_at = ~U[2026-06-30 12:08:30Z]

    capability_record = %TransportCapabilityRecord{
      transport_record_id: "transport-record-1",
      mission_id: "mission-1",
      realized_contact_id: "realized-contact-1",
      path_id: "uplink-path-1",
      capability_instance_id: "uplink-gateway-1",
      family_key: :uplink_gateway,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      event_kind: :control_input_handled,
      timer_key: "cop1-timeout",
      emitted_record_kinds: [:transfer_frame],
      emitted_record_count: 1,
      action_request_count: 2,
      state_snapshot: %{active?: true, last_control_command: :resume},
      recorded_at: recorded_at,
      metadata: %{interaction: :control_input}
    }

    event = Event.from_transport_capability_record(capability_record)

    assert event.event_id == "operational_event:transport_capability_record:transport-record-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == recorded_at
    assert event.recorded_at == recorded_at
    assert event.effective_at == recorded_at
    assert event.category == :comms
    assert event.kind == :transport_control_input_handled
    assert event.severity == :info
    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :transport, id: "uplink-gateway-1"}

    assert event.scope == %{
             contact_id: "realized-contact-1",
             realized_contact_id: "realized-contact-1",
             path_id: "uplink-path-1",
             capability_instance_id: "uplink-gateway-1",
             binding_set_id: "binding-set-1",
             activation_id: "activation-1",
             timer_key: "cop1-timeout"
           }

    assert event.causality == %{
             correlation_id: "uplink-gateway-1",
             source_record_kind: :transport_capability_record,
             source_record_id: "transport-record-1"
           }

    assert event.current.transport_record_id == "transport-record-1"
    assert event.current.event_kind == :control_input_handled
    assert event.current.emitted_record_kinds == [:transfer_frame]
    assert event.current.emitted_record_count == 1
    assert event.current.action_request_count == 2
    assert event.current.state_snapshot == %{active?: true, last_control_command: :resume}
    assert event.current.record_metadata == %{interaction: :control_input}
    assert event.metadata == %{interaction: :control_input}
  end

  test "builds canonical transport timer event envelopes" do
    due_at = ~U[2026-06-30 12:10:00Z]
    occurred_at = ~U[2026-06-30 12:10:01Z]

    timer_event = %TransportTimerEvent{
      timer_event_id: "transport-timer-1",
      mission_id: "mission-1",
      realized_contact_id: "realized-contact-1",
      path_id: "uplink-path-1",
      capability_instance_id: "uplink-gateway-1",
      family_key: :uplink_gateway,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      timer_key: "cop1-timeout",
      event_kind: :fired,
      due_at: due_at,
      occurred_at: occurred_at,
      metadata: %{sequence_number: 42}
    }

    event = Event.from_transport_timer_event(timer_event)

    assert event.event_id == "operational_event:transport_timer_event:transport-timer-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == occurred_at
    assert event.recorded_at == occurred_at
    assert event.effective_at == occurred_at
    assert event.category == :comms
    assert event.kind == :transport_timer_fired
    assert event.severity == :info
    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :transport, id: "uplink-gateway-1"}

    assert event.scope == %{
             contact_id: "realized-contact-1",
             realized_contact_id: "realized-contact-1",
             path_id: "uplink-path-1",
             capability_instance_id: "uplink-gateway-1",
             binding_set_id: "binding-set-1",
             activation_id: "activation-1",
             timer_key: "cop1-timeout"
           }

    assert event.causality == %{
             correlation_id: "uplink-gateway-1:cop1-timeout",
             source_record_kind: :transport_timer_event,
             source_record_id: "transport-timer-1"
           }

    assert event.current.timer_event_id == "transport-timer-1"
    assert event.current.event_kind == :fired
    assert event.current.due_at == due_at
    assert event.current.occurred_at == occurred_at
    assert event.current.timer_metadata == %{sequence_number: 42}
    assert event.metadata == %{sequence_number: 42}
  end

  test "builds replay-scoped native transport event envelopes" do
    occurred_at = ~U[2026-06-30 12:10:01Z]

    capability_record = %TransportCapabilityRecord{
      transport_record_id: "transport-record-1",
      mission_id: "mission-1",
      realized_contact_id: "realized-contact-1",
      path_id: "uplink-path-1",
      capability_instance_id: "uplink-gateway-1",
      family_key: :uplink_gateway,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      event_kind: :initialized,
      emitted_record_kinds: [],
      emitted_record_count: 0,
      action_request_count: 0,
      state_snapshot: %{active?: true},
      recorded_at: occurred_at,
      metadata: %{source: :replay}
    }

    action_request = %TransportActionRequest{
      action_request_id: "transport-action-1",
      mission_id: "mission-1",
      realized_contact_id: "realized-contact-1",
      path_id: "uplink-path-1",
      capability_instance_id: "uplink-gateway-1",
      family_key: :uplink_gateway,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      action_kind: :uplink_request,
      request_document: %{"frame_count" => 1},
      requested_at: occurred_at,
      metadata: %{source: :replay}
    }

    timer_event = %TransportTimerEvent{
      timer_event_id: "transport-timer-1",
      mission_id: "mission-1",
      realized_contact_id: "realized-contact-1",
      path_id: "uplink-path-1",
      capability_instance_id: "uplink-gateway-1",
      family_key: :uplink_gateway,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      timer_key: "cop1-timeout",
      event_kind: :fired,
      occurred_at: occurred_at,
      metadata: %{source: :replay}
    }

    capability_event = Event.from_transport_capability_record(capability_record, "replay-1")
    action_event = Event.from_transport_action_request(action_request, "replay-1")
    timer_event = Event.from_transport_timer_event(timer_event, "replay-1")

    assert capability_event.event_id ==
             "operational_event:transport_capability_record:replay-1:transport-record-1"

    assert action_event.event_id ==
             "operational_event:transport_action_request:replay-1:transport-action-1"

    assert timer_event.event_id ==
             "operational_event:transport_timer_event:replay-1:transport-timer-1"

    for event <- [capability_event, action_event, timer_event] do
      assert event.actor == %{kind: :replay, id: "replay-1"}
      assert event.scope.replay_run_id == "replay-1"
      assert event.causality.replay_run_id == "replay-1"
      assert event.payload.replay_run_id == "replay-1"
      assert event.current.replay_run_id == "replay-1"
      assert event.metadata.replay_run_id == "replay-1"
    end
  end

  test "builds replay-scoped managed runtime event envelopes" do
    occurred_at = ~U[2026-06-30 12:10:01Z]

    capability_record = %ManagedCapabilityRecord{
      capability_record_id: "managed-record-1",
      mission_id: "mission-1",
      capability_instance_id: "packet-counter-1",
      family_key: :packet_counter,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      event_kind: :record_handled,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      emitted_record_kinds: [:telemetry_sample],
      emitted_record_count: 1,
      action_request_count: 1,
      state_snapshot: %{count: 1},
      recorded_at: occurred_at,
      metadata: %{source: :replay}
    }

    action_request = %ManagedActionRequest{
      action_request_id: "managed-action-1",
      mission_id: "mission-1",
      capability_instance_id: "packet-counter-1",
      family_key: :packet_counter,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      action_kind: :schedule_timer,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      request_document: %{"timer_key" => "flush"},
      requested_at: occurred_at
    }

    timer_record = %ManagedTimerEvent{
      timer_event_id: "managed-timer-1",
      mission_id: "mission-1",
      capability_instance_id: "packet-counter-1",
      family_key: :packet_counter,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-a",
      timer_key: "flush",
      event_kind: :fired,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      due_at: occurred_at,
      occurred_at: occurred_at,
      metadata: %{attempt: 1}
    }

    capability_event = Event.from_managed_capability_record(capability_record, "replay-run-1")
    action_event = Event.from_managed_action_request(action_request, "replay-run-1")
    timer_event = Event.from_managed_timer_event(timer_record, "replay-run-1")

    assert capability_event.event_id ==
             "operational_event:managed_capability_record:replay-run-1:managed-record-1"

    assert capability_event.category == :runtime
    assert capability_event.kind == :managed_capability_record_handled
    assert capability_event.actor == %{kind: :replay, id: "replay-run-1"}
    assert capability_event.subject == %{kind: :capability_instance, id: "packet-counter-1"}
    assert capability_event.scope.replay_run_id == "replay-run-1"
    assert capability_event.causality.replay_run_id == "replay-run-1"
    assert capability_event.causality.source_record_kind == :managed_capability_record
    assert capability_event.current.state_snapshot == %{count: 1}

    assert action_event.kind == :managed_action_requested
    assert action_event.causality.source_record_kind == :managed_action_request
    assert action_event.current.request_document == %{"timer_key" => "flush"}
    assert action_event.current.replay_run_id == "replay-run-1"

    assert timer_event.kind == :managed_timer_fired
    assert timer_event.causality.source_record_kind == :managed_timer_event
    assert timer_event.current.timer_key == "flush"
    assert timer_event.current.replay_run_id == "replay-run-1"
  end
end
