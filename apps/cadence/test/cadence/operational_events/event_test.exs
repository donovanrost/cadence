defmodule Cadence.OperationalEvents.EventTest do
  use ExUnit.Case, async: true

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Catalog.Revision
  alias Cadence.Contacts.{ContactAction, RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DataBindingEvent,
    LifecycleEvent,
    SourceHealthEvent,
    SourceWatermarkEvent
  }

  alias Cadence.Limits.DefinitionLifecycleEvent
  alias Cadence.OperationalEvents.Event

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  alias Cadence.Telemetry.Storage.{BackfillLifecycleEvent, ObservationIdentityDecisionEvent}

  test "builds a canonical binding-set activation envelope" do
    activated_at = DateTime.from_unix!(1_700_060_100, :second)

    activation =
      BindingSetActivation.new(%{
        activation_id: "activation-runtime-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        binding_set_id: "runtime-basis",
        binding_set_version: 3,
        activated_at: activated_at,
        metadata: %{"change_request" => "CR-17"}
      })

    event = Event.from_binding_set_activation(activation)

    assert event.event_id == "operational_event:binding_set_activation:activation-runtime-1"
    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == activated_at
    assert event.recorded_at == activated_at
    assert event.effective_at == activated_at
    assert event.category == :runtime
    assert event.kind == :binding_set_activated
    assert event.severity == :info
    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :binding_set, id: "runtime-basis"}

    assert event.causality == %{
             correlation_id: "runtime-basis",
             source_record_kind: :binding_set_activation,
             source_record_id: "activation-runtime-1"
           }

    assert event.payload == %{
             binding_set_id: "runtime-basis",
             binding_set_version: 3,
             activation_id: "activation-runtime-1"
           }

    assert event.current == event.payload
    assert event.metadata == %{"change_request" => "CR-17"}
  end

  test "builds a canonical catalog revision envelope" do
    occurred_at = ~U[2026-06-22 12:00:00Z]

    revision =
      Revision.new(%{
        catalog_revision_id: "catalog-revision-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        catalog_database_id: "bus-catalog",
        revision_number: 3,
        revision_label: "FSW 3.7",
        catalog_family: :telemetry,
        artifact_id: "artifact-1",
        import_run_id: "import-run-1",
        telemetry_snapshot_id: "telemetry-snapshot-1",
        content_sha256: "sha256:abc",
        created_by: %{"service_identity_id" => "svc-importer"},
        notes: "flight software update",
        metadata: %{"source_artifact_name" => "bus.json"}
      })

    event = Event.from_catalog_revision(revision, occurred_at)

    assert event.event_id == "operational_event:catalog_revision:catalog-revision-1"
    assert event.category == :catalog
    assert event.kind == :catalog_revision_registered
    assert event.severity == :info
    assert event.actor == %{kind: :service, id: "svc-importer"}
    assert event.subject == %{kind: :catalog_revision, id: "catalog-revision-1"}
    assert event.scope == %{catalog_database_id: "bus-catalog", catalog_family: :telemetry}

    assert event.causality == %{
             correlation_id: "bus-catalog",
             source_record_kind: :catalog_revision,
             source_record_id: "catalog-revision-1",
             import_run_id: "import-run-1"
           }

    assert event.payload.catalog_revision_id == "catalog-revision-1"
    assert event.payload.catalog_database_id == "bus-catalog"
    assert event.payload.revision_number == 3
    assert event.payload.revision_label == "FSW 3.7"
    assert event.payload.catalog_family == :telemetry
    assert event.payload.telemetry_snapshot_id == "telemetry-snapshot-1"
    assert event.current.revision_number == 3
    assert event.metadata == %{"source_artifact_name" => "bus.json"}
  end

  test "builds canonical contact interval envelopes" do
    starts_at = ~U[2026-06-30 12:00:00Z]
    ends_at = ~U[2026-06-30 12:10:00Z]
    recorded_at = ~U[2026-06-30 11:59:58Z]

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        source_endpoint_refs: ["endpoint-a"],
        starts_at: starts_at,
        ends_at: ends_at,
        provider_contact_ref: "provider-pass-1",
        lifecycle_state: :scheduled,
        metadata: %{"operator_label" => "alpha"}
      })

    scheduled_event = Event.from_scheduled_contact_interval(scheduled_contact, recorded_at)

    assert scheduled_event.event_id ==
             "operational_event:scheduled_contact_interval:scheduled-contact-1"

    assert scheduled_event.organization_id == "org-1"
    assert scheduled_event.mission_id == "mission-1"
    assert scheduled_event.occurred_at == starts_at
    assert scheduled_event.recorded_at == recorded_at
    assert scheduled_event.effective_at == starts_at
    assert scheduled_event.category == :contact
    assert scheduled_event.kind == :scheduled_contact_interval
    assert scheduled_event.subject == %{kind: :contact, id: "scheduled-contact-1"}
    assert scheduled_event.scope.contact_id == "scheduled-contact-1"
    assert scheduled_event.scope.source_endpoint_refs == ["endpoint-a"]

    assert scheduled_event.causality == %{
             correlation_id: "scheduled-contact-1",
             source_record_kind: :scheduled_contact,
             source_record_id: "scheduled-contact-1"
           }

    assert scheduled_event.current.scheduled_contact_id == "scheduled-contact-1"
    assert scheduled_event.current.starts_at == starts_at
    assert scheduled_event.current.ends_at == ends_at
    assert scheduled_event.current.status == :scheduled
    assert scheduled_event.current.provider_contact_ref == "provider-pass-1"

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-contact-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        scheduled_contact_id: "scheduled-contact-1",
        source_endpoint_refs: ["endpoint-a"],
        realized_at: starts_at,
        initial_time: starts_at,
        lifecycle_state: :active,
        clock_mode: :replay,
        metadata: %{"stopped_at" => DateTime.to_iso8601(ends_at)}
      })

    realized_event = Event.from_realized_contact_interval(realized_contact, recorded_at)

    assert realized_event.event_id ==
             "operational_event:realized_contact_interval:realized-contact-1"

    assert realized_event.category == :contact
    assert realized_event.kind == :realized_contact_interval
    assert realized_event.subject == %{kind: :contact, id: "realized-contact-1"}

    assert realized_event.causality == %{
             correlation_id: "realized-contact-1",
             source_record_kind: :realized_contact,
             source_record_id: "realized-contact-1"
           }

    assert realized_event.current.realized_contact_id == "realized-contact-1"
    assert realized_event.current.scheduled_contact_id == "scheduled-contact-1"
    assert realized_event.current.starts_at == starts_at
    assert realized_event.current.ends_at == DateTime.to_iso8601(ends_at)
    assert realized_event.current.status == :active
    assert realized_event.current.clock_mode == :replay
  end

  test "builds canonical contact action envelopes" do
    occurred_at = ~U[2026-06-30 12:08:00Z]

    contact_action =
      ContactAction.new(%{
        contact_action_id: "contact-action-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        scheduled_contact_id: "scheduled-contact-1",
        realized_contact_id: "realized-contact-1",
        action_kind: :realized_contact_ended_early,
        reason: "operator stop",
        actor: %{kind: :user, id: "operator-1"},
        metadata: %{ended_early?: true},
        occurred_at: occurred_at
      })

    event = Event.from_contact_action(contact_action)

    assert event.event_id == "operational_event:contact_action:contact-action-1"
    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == occurred_at
    assert event.recorded_at == occurred_at
    assert event.effective_at == occurred_at
    assert event.category == :contact
    assert event.kind == :realized_contact_ended_early
    assert event.severity == :warning
    assert event.actor == %{kind: :user, id: "operator-1"}
    assert event.subject == %{kind: :contact, id: "realized-contact-1"}

    assert event.scope == %{
             contact_id: "realized-contact-1",
             scheduled_contact_id: "scheduled-contact-1",
             realized_contact_id: "realized-contact-1"
           }

    assert event.causality == %{
             correlation_id: "realized-contact-1",
             source_record_kind: :contact_action,
             source_record_id: "contact-action-1"
           }

    assert event.current.contact_action_id == "contact-action-1"
    assert event.current.action_kind == :realized_contact_ended_early
    assert event.current.reason == "operator stop"
    assert event.current.actor == %{kind: :user, id: "operator-1"}
    assert event.current.action_metadata == %{ended_early?: true}
    assert event.metadata == %{ended_early?: true}
  end

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

  test "builds a canonical dashboard lifecycle event envelope" do
    occurred_at = DateTime.from_unix!(1_700_060_100, :second)

    lifecycle_event =
      LifecycleEvent.new(%{
        dashboard_lifecycle_event_id: "dashboard-lifecycle-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: "dashboard-1",
        event_type: :published,
        dashboard_version: 3,
        previous_lifecycle_state: "active",
        current_lifecycle_state: "active",
        previous_published_version: 2,
        current_published_version: 3,
        actor_id: "operator-1",
        occurred_at: occurred_at,
        payload: %{"dashboard_name" => "Power"}
      })

    event = Event.from_dashboard_lifecycle_event(lifecycle_event)

    assert event.event_id == "operational_event:dashboard_lifecycle_event:dashboard-lifecycle-1"
    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert event.occurred_at == occurred_at
    assert event.recorded_at == occurred_at
    assert event.effective_at == occurred_at
    assert event.category == :dashboard
    assert event.kind == :dashboard_published
    assert event.severity == :info
    assert event.actor == %{kind: :user, id: "operator-1"}
    assert event.subject == %{kind: :dashboard, id: "dashboard-1"}

    assert event.causality == %{
             correlation_id: "dashboard-1",
             source_record_kind: :dashboard_lifecycle_event,
             source_record_id: "dashboard-lifecycle-1"
           }

    assert event.payload == %{
             dashboard_lifecycle_event_id: "dashboard-lifecycle-1",
             dashboard_id: "dashboard-1",
             event_type: :published,
             dashboard_version: 3,
             lifecycle_payload: %{"dashboard_name" => "Power"}
           }

    assert event.previous == %{lifecycle_state: "active", published_version: 2}

    assert event.current == %{
             lifecycle_state: "active",
             published_version: 3,
             dashboard_version: 3
           }

    assert event.metadata == %{"dashboard_name" => "Power"}
  end

  test "builds a canonical source-binding lifecycle event envelope" do
    occurred_at = ~U[2026-06-21 21:00:00Z]

    binding_event =
      DataBindingEvent.new(%{
        data_binding_event_id: "data-binding-event-1",
        binding_id: "flight-telemetry",
        organization_id: "org-1",
        mission_id: "mission-1",
        event_type: :changed,
        previous_status: :active,
        current_status: :active,
        previous_binding_version: 1,
        current_binding_version: 2,
        previous_logical_source: :telemetry,
        current_logical_source: :telemetry,
        previous_realm: :flight,
        current_realm: :flight,
        previous_data_source_id: "questdb-v1",
        current_data_source_id: "questdb-v2",
        previous_dataset: "flight-v1",
        current_dataset: "flight-v2",
        previous_priority: 0,
        current_priority: 1,
        previous_active_from: ~U[2026-06-21 20:00:00Z],
        current_active_from: ~U[2026-06-21 21:00:00Z],
        actor_id: "operator-1",
        occurred_at: occurred_at,
        payload: %{"change_request_id" => "CR-42"}
      })

    event = Event.from_data_binding_event(binding_event)

    assert event.event_id == "operational_event:dashboard_data_binding_event:data-binding-event-1"
    assert event.category == :data_source
    assert event.kind == :source_binding_changed
    assert event.severity == :info
    assert event.actor == %{kind: :user, id: "operator-1"}
    assert event.subject == %{kind: :source_binding, id: "flight-telemetry"}

    assert event.scope == %{
             logical_source: :telemetry,
             source_binding_id: "flight-telemetry",
             data_source_id: "questdb-v2",
             data_realm: :flight,
             dataset: "flight-v2"
           }

    assert event.causality == %{
             correlation_id: "flight-telemetry",
             source_record_kind: :dashboard_data_binding_event,
             source_record_id: "data-binding-event-1"
           }

    assert Map.delete(event.previous, :active_from) == %{
             status: :active,
             binding_version: 1,
             logical_source: :telemetry,
             realm: :flight,
             data_source_id: "questdb-v1",
             dataset: "flight-v1",
             priority: 0,
             active_to: nil
           }

    assert DateTime.compare(event.previous.active_from, ~U[2026-06-21 20:00:00Z]) == :eq

    assert Map.delete(event.current, :active_from) == %{
             status: :active,
             binding_version: 2,
             logical_source: :telemetry,
             realm: :flight,
             data_source_id: "questdb-v2",
             dataset: "flight-v2",
             priority: 1,
             active_to: nil
           }

    assert DateTime.compare(event.current.active_from, ~U[2026-06-21 21:00:00Z]) == :eq

    assert event.payload.lifecycle_payload == %{"change_request_id" => "CR-42"}
    assert event.metadata == %{"change_request_id" => "CR-42"}
  end

  test "maps every dashboard lifecycle event type to a stable operational kind" do
    occurred_at = DateTime.from_unix!(1_700_060_100, :second)

    expected_kinds = %{
      published: :dashboard_published,
      archived: :dashboard_archived,
      restored: :dashboard_restored,
      reverted: :dashboard_reverted,
      comparison_review_requested: :dashboard_comparison_review_requested,
      comparison_review_resolved: :dashboard_comparison_review_resolved,
      health_snapshot_captured: :dashboard_health_snapshot_captured,
      publish_readiness_checked: :dashboard_publish_readiness_checked
    }

    for {event_type, expected_kind} <- expected_kinds do
      lifecycle_event =
        LifecycleEvent.new(%{
          organization_id: "org-1",
          mission_id: "mission-1",
          dashboard_id: "dashboard-1",
          event_type: event_type,
          dashboard_version: 1,
          current_lifecycle_state: "active",
          occurred_at: occurred_at
        })

      assert %Event{kind: ^expected_kind} = Event.from_dashboard_lifecycle_event(lifecycle_event)
    end
  end

  test "builds a canonical source health event envelope" do
    observed_at = DateTime.from_unix!(1_700_060_100, :second)

    source_event =
      SourceHealthEvent.new(%{
        source_health_event_id: "source-health-event-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :telemetry,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry",
        realm: :flight,
        replay_run_id: "replay-1",
        dataset: "flight",
        event_type: :unavailable,
        source_health: :unavailable,
        previous_source_health: :degraded,
        reason: :source_connection_failed,
        observed_at: observed_at,
        payload: %{"probe_id" => "probe-1"}
      })

    event = Event.from_source_health_event(source_event)

    assert event.event_id ==
             "operational_event:source_health_event:replay-1:source-health-event-1"

    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert DateTime.compare(event.occurred_at, observed_at) == :eq
    assert DateTime.compare(event.effective_at, observed_at) == :eq
    assert event.category == :data_source
    assert event.kind == :source_health_unavailable
    assert event.severity == :error
    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :data_source, id: "flight-questdb"}

    assert event.scope == %{
             logical_source: :telemetry,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-telemetry",
             data_realm: :flight,
             replay_run_id: "replay-1",
             dataset: "flight"
           }

    assert event.causality == %{
             correlation_id: source_event.source_health_key,
             source_record_kind: :source_health_event,
             source_record_id: "source-health-event-1",
             replay_run_id: "replay-1"
           }

    assert event.previous == %{source_health: :degraded}
    assert event.current == %{source_health: :unavailable, reason: :source_connection_failed}
    assert event.metadata == %{"probe_id" => "probe-1"}
  end

  test "builds a canonical source watermark event envelope" do
    observed_at = DateTime.from_unix!(1_700_060_100, :second)

    source_event =
      SourceWatermarkEvent.new(%{
        source_watermark_event_id: "source-watermark-event-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :telemetry,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry",
        realm: :flight,
        replay_run_id: "replay-1",
        dataset: "flight",
        event_type: :retreated,
        complete_through: ~U[2026-06-21 12:00:00Z],
        previous_complete_through: ~U[2026-06-21 12:05:00Z],
        latest_receipt_time: ~U[2026-06-21 12:01:00Z],
        previous_latest_receipt_time: ~U[2026-06-21 12:06:00Z],
        retention_starts_at: ~U[2026-06-21 11:00:00Z],
        previous_retention_starts_at: ~U[2026-06-21 10:00:00Z],
        sample_count: 10,
        confidence: :best_effort,
        reason: :telemetry_storage_repaired,
        observed_at: observed_at,
        payload: %{"write_id" => "write-1"}
      })

    event = Event.from_source_watermark_event(source_event)

    assert event.event_id ==
             "operational_event:source_watermark_event:replay-1:source-watermark-event-1"

    assert event.category == :data_source
    assert event.kind == :source_watermark_retreated
    assert event.severity == :warning
    assert event.subject == %{kind: :data_source, id: "flight-questdb"}

    assert event.causality == %{
             correlation_id: source_event.source_watermark_key,
             source_record_kind: :source_watermark_event,
             source_record_id: "source-watermark-event-1",
             replay_run_id: "replay-1"
           }

    assert event.previous == %{
             complete_through: ~U[2026-06-21 12:05:00.000000Z],
             latest_receipt_time: ~U[2026-06-21 12:06:00.000000Z],
             retention_starts_at: ~U[2026-06-21 10:00:00.000000Z]
           }

    assert event.current == %{
             complete_through: ~U[2026-06-21 12:00:00.000000Z],
             latest_receipt_time: ~U[2026-06-21 12:01:00.000000Z],
             retention_starts_at: ~U[2026-06-21 11:00:00.000000Z],
             sample_count: 10,
             confidence: :best_effort,
             reason: :telemetry_storage_repaired
           }

    assert event.metadata == %{"write_id" => "write-1"}
  end

  test "builds a canonical source capability posture event envelope" do
    observed_at = DateTime.from_unix!(1_700_060_100, :second)

    event =
      Event.from_source_capability_posture(%{
        source_capability_posture_id: "dashboard-1:resolve-1:req-telemetry",
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: "dashboard-1",
        dashboard_version: 4,
        resolve_id: "resolve-1",
        source_request_id: "req-telemetry",
        logical_source: :telemetry,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry",
        realm: :flight,
        replay_run_id: "replay-1",
        dataset: "flight",
        status: :fallback,
        requested_sampling: :latest,
        supported_sampling: [:latest],
        requested_products: [:link_rf_metric_history],
        supported_products: [:transport_bitrate_history],
        requested_time_axis: :generation_time,
        executed_time_axis: :receipt_time,
        supported_time_axes: [:receipt_time],
        fallbacks: [
          %{
            capability: :time_axis,
            requested: :generation_time,
            executed: :receipt_time,
            reason: :unsupported_time_axis
          }
        ],
        source_execution_status: :cache_hit,
        source_execution_cache_status: :hit,
        source_execution_operator_action: :none,
        source_execution_runtime_action: :none,
        source_execution_warning_codes: [],
        observed_at: observed_at,
        metadata: %{resolve_mode: :live_tick}
      })

    assert event.event_id ==
             "operational_event:source_capability_posture:replay-1:dashboard-1:resolve-1:req-telemetry"

    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert DateTime.compare(event.occurred_at, observed_at) == :eq
    assert event.category == :data_source
    assert event.kind == :source_capability_fallback
    assert event.severity == :warning
    assert event.subject == %{kind: :data_source, id: "flight-questdb"}

    assert event.scope == %{
             logical_source: :telemetry,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-telemetry",
             data_realm: :flight,
             replay_run_id: "replay-1",
             dataset: "flight",
             dashboard_id: "dashboard-1",
             source_request_id: "req-telemetry"
           }

    assert event.causality == %{
             correlation_id: "resolve-1",
             source_record_kind: :source_capability_posture,
             source_record_id: "dashboard-1:resolve-1:req-telemetry",
             replay_run_id: "replay-1"
           }

    assert event.payload.source_request_id == "req-telemetry"
    assert event.payload.status == :fallback
    assert event.payload.requested_products == [:link_rf_metric_history]
    assert event.payload.supported_products == [:transport_bitrate_history]
    assert event.payload.requested_time_axis == :generation_time
    assert event.payload.executed_time_axis == :receipt_time
    assert event.payload.source_execution_cache_status == :hit

    assert event.current == %{
             capability_status: :fallback,
             requested_sampling: :latest,
             supported_sampling: [:latest],
             requested_products: [:link_rf_metric_history],
             supported_products: [:transport_bitrate_history],
             requested_time_axis: :generation_time,
             executed_time_axis: :receipt_time,
             supported_time_axes: [:receipt_time],
             fallbacks: [
               %{
                 capability: :time_axis,
                 requested: :generation_time,
                 executed: :receipt_time,
                 reason: :unsupported_time_axis
               }
             ]
           }

    assert event.metadata == %{resolve_mode: :live_tick}
  end

  test "builds a canonical telemetry backfill lifecycle event envelope" do
    occurred_at = ~U[2026-06-22 12:21:00Z]

    lifecycle_event =
      BackfillLifecycleEvent.new(%{
        backfill_lifecycle_event_id: "backfill-event-1",
        backfill_run_id: "backfill-run-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        replay_run_id: "replay-1",
        data_source_id: "flight-questdb",
        binding_id: "flight-telemetry",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        spacecraft_id: "sc-1",
        event_type: :backfill_failed,
        source_from: ~U[2026-06-22 11:00:00Z],
        source_to: ~U[2026-06-22 12:00:00Z],
        receipt_from: ~U[2026-06-22 12:10:00Z],
        receipt_to: ~U[2026-06-22 12:20:00Z],
        sample_count: 42,
        authority: :advisory,
        reason: :writer_failed,
        actor_id: "backfill-worker-1",
        actor_kind: "service",
        occurred_at: occurred_at,
        payload: %{"job_id" => "job-1", "error" => "write_failed"}
      })

    event = Event.from_backfill_lifecycle_event(lifecycle_event)

    assert event.event_id ==
             "operational_event:telemetry_backfill_lifecycle_event:backfill-event-1"

    assert event.category == :telemetry
    assert event.kind == :telemetry_backfill_failed
    assert event.severity == :error
    assert event.actor == %{kind: :service, id: "backfill-worker-1"}
    assert event.subject == %{kind: :telemetry_point, id: "HK.counter"}

    assert event.scope == %{
             logical_source: :telemetry,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-telemetry",
             data_realm: :flight,
             replay_run_id: "replay-1",
             point_id: "HK.counter",
             spacecraft_id: "sc-1"
           }

    assert event.causality == %{
             correlation_id: "backfill-run-1",
             source_record_kind: :telemetry_backfill_lifecycle_event,
             source_record_id: "backfill-event-1",
             job_id: "job-1",
             replay_run_id: "replay-1"
           }

    assert event.current == %{
             event_type: :backfill_failed,
             authority: :advisory,
             reason: :writer_failed,
             source_from: ~U[2026-06-22 11:00:00.000000Z],
             source_to: ~U[2026-06-22 12:00:00.000000Z],
             sample_count: 42
           }

    assert event.payload.lifecycle_payload == %{"job_id" => "job-1", "error" => "write_failed"}
    assert event.metadata == %{"job_id" => "job-1", "error" => "write_failed"}
  end

  test "builds canonical missing replacement inspection lifecycle envelopes" do
    occurred_at = ~U[2026-06-22 12:24:00Z]

    backfill_lifecycle_event =
      BackfillLifecycleEvent.new(%{
        backfill_lifecycle_event_id: "backfill-missing-replacement-inspection-1",
        backfill_run_id: "backfill-replacement-run-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :backfill,
        replay_run_id: "replay-1",
        data_source_id: "backfill-questdb",
        binding_id: "backfill-telemetry",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        event_type: :backfill_missing_replacement_inspected,
        authority: :advisory,
        reason: "dashboard_historical_workflow_missing_replacement_inspected",
        actor_id: "ops-1",
        actor_kind: "operator",
        occurred_at: occurred_at,
        payload: %{
          "missing_replacement_action" => "inspect_missing_replacement_job",
          "missing_replacement_source_event_id" => "failed-source-event-1",
          "missing_replacement_source_event_type" => "backfill_failed",
          "missing_replacement_run_id" => "backfill-replacement-run-1",
          "missing_replacement_expected_job_type" => "telemetry_historical_data_workflow"
        }
      })

    import_lifecycle_event = %{
      backfill_lifecycle_event
      | backfill_lifecycle_event_id: "import-missing-replacement-inspection-1",
        backfill_run_id: "import-replacement-run-1",
        realm: :import,
        replay_run_id: nil,
        event_type: :import_missing_replacement_inspected,
        payload: %{
          backfill_lifecycle_event.payload
          | "missing_replacement_run_id" => "import-replacement-run-1",
            "missing_replacement_source_event_type" => "import_failed"
        }
    }

    backfill_event = Event.from_backfill_lifecycle_event(backfill_lifecycle_event)
    import_event = Event.from_backfill_lifecycle_event(import_lifecycle_event)

    assert backfill_event.kind == :telemetry_backfill_missing_replacement_inspected
    assert import_event.kind == :telemetry_import_missing_replacement_inspected
    assert backfill_event.severity == :info
    assert import_event.severity == :info

    assert backfill_event.current == %{
             event_type: :backfill_missing_replacement_inspected,
             authority: :advisory,
             reason: "dashboard_historical_workflow_missing_replacement_inspected",
             source_from: nil,
             source_to: nil,
             sample_count: nil
           }

    assert backfill_event.causality == %{
             correlation_id: "backfill-replacement-run-1",
             source_record_kind: :telemetry_backfill_lifecycle_event,
             source_record_id: "backfill-missing-replacement-inspection-1",
             replay_run_id: "replay-1"
           }

    assert backfill_event.payload.lifecycle_payload["missing_replacement_action"] ==
             "inspect_missing_replacement_job"

    assert backfill_event.payload.lifecycle_payload["missing_replacement_source_event_id"] ==
             "failed-source-event-1"

    assert backfill_event.payload.lifecycle_payload["missing_replacement_expected_job_type"] ==
             "telemetry_historical_data_workflow"
  end

  test "builds a canonical observation identity decision event envelope" do
    occurred_at = ~U[2026-06-22 12:10:00Z]

    decision_event =
      ObservationIdentityDecisionEvent.new(%{
        decision_event_id: "decision-event-1",
        observation_identity_id: "identity-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :replay,
        replay_run_id: "replay-1",
        data_source_id: "replay-questdb",
        binding_id: "replay-telemetry",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        spacecraft_id: "sc-1",
        decision: :mark_conflict,
        decision_reason: "operator_reviewed_conflict",
        actor_id: "ops-1",
        actor_kind: "operator",
        evidence_ref: %{"ticket_id" => "ticket-1"},
        previous_state: %{"validity_state" => "canonical"},
        new_state: %{"validity_state" => "conflict"},
        occurred_at: occurred_at
      })

    event = Event.from_observation_identity_decision_event(decision_event)

    assert event.event_id ==
             "operational_event:telemetry_observation_identity_decision_event:decision-event-1"

    assert event.category == :telemetry
    assert event.kind == :telemetry_observation_marked_conflict
    assert event.severity == :warning
    assert event.actor == %{kind: :user, id: "ops-1"}
    assert event.subject == %{kind: :telemetry_point, id: "HK.counter"}

    assert event.scope == %{
             logical_source: :telemetry,
             data_source_id: "replay-questdb",
             source_binding_id: "replay-telemetry",
             data_realm: :replay,
             replay_run_id: "replay-1",
             point_id: "HK.counter",
             spacecraft_id: "sc-1"
           }

    assert event.causality == %{
             correlation_id: "identity-1",
             source_record_kind: :telemetry_observation_identity_decision_event,
             source_record_id: "decision-event-1",
             replay_run_id: "replay-1"
           }

    assert event.payload.decision == :mark_conflict
    assert event.payload.decision_reason == "operator_reviewed_conflict"
    assert event.previous == %{"validity_state" => "canonical"}
    assert event.current == %{"validity_state" => "conflict"}
    assert event.metadata == %{evidence_ref: %{"ticket_id" => "ticket-1"}}
  end

  test "builds a canonical limit definition lifecycle event envelope" do
    observed_at = DateTime.from_unix!(1_700_060_100, :second)
    active_from = DateTime.from_unix!(1_700_060_200, :second)

    lifecycle_event =
      DefinitionLifecycleEvent.new(%{
        limit_definition_lifecycle_event_id: "limit-lifecycle-1",
        definition_activation_key: "limit-activation-key-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        point_id: "HK.counter",
        limit_set_name: "ops",
        scope_type: :spacecraft,
        scope_ref: "SC-1",
        realm: :flight,
        event_type: :activated,
        limit_definition_id: "counter-limits",
        limit_definition_version: 2,
        previous_limit_definition_id: "counter-limits",
        previous_limit_definition_version: 1,
        active_from: active_from,
        reason: :definition_persisted,
        observed_at: observed_at,
        payload: %{"change_request" => "CR-17"}
      })

    event = Event.from_limit_definition_lifecycle_event(lifecycle_event)

    assert event.event_id ==
             "operational_event:limit_definition_lifecycle_event:limit-lifecycle-1"

    assert event.organization_id == "org-1"
    assert event.mission_id == "mission-1"
    assert DateTime.compare(event.occurred_at, observed_at) == :eq
    assert DateTime.compare(event.effective_at, active_from) == :eq
    assert event.category == :limits
    assert event.kind == :limit_definition_activated
    assert event.severity == :info
    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :limit_definition, id: "counter-limits"}

    assert event.scope == %{
             point_id: "HK.counter",
             limit_set_name: "ops",
             scope_type: :spacecraft,
             scope_ref: "SC-1",
             data_realm: :flight
           }

    assert event.causality == %{
             correlation_id: "limit-activation-key-1",
             source_record_kind: :limit_definition_lifecycle_event,
             source_record_id: "limit-lifecycle-1"
           }

    assert event.previous == %{
             limit_definition_id: "counter-limits",
             limit_definition_version: 1
           }

    assert event.current == %{
             limit_definition_id: "counter-limits",
             limit_definition_version: 2,
             active_from: lifecycle_event.active_from,
             active_to: nil,
             reason: :definition_persisted
           }

    assert event.metadata == %{"change_request" => "CR-17"}
  end

  test "normalizes only known envelope fields when given string-keyed documents" do
    event =
      Event.new(%{
        "event_id" => "operational-event-string-doc",
        "organization_id" => "org-1",
        "mission_id" => "mission-1",
        "occurred_at" => DateTime.from_unix!(1_700_060_100, :second),
        "category" => "runtime",
        "kind" => "binding_set_activated",
        "actor" => %{"kind" => "system"},
        "subject" => %{"kind" => "binding_set", "id" => "runtime-basis"},
        "causality" => %{
          "source_record_kind" => "binding_set_activation",
          "source_record_id" => "activation-runtime-1"
        },
        "payload" => %{"arbitrary_payload_key" => "kept"},
        "metadata" => %{"operator supplied key" => "kept"}
      })

    assert event.actor == %{kind: :system}
    assert event.subject == %{kind: :binding_set, id: "runtime-basis"}

    assert event.causality == %{
             source_record_kind: :binding_set_activation,
             source_record_id: "activation-runtime-1"
           }

    assert event.payload == %{"arbitrary_payload_key" => "kept"}
    assert event.metadata == %{"operator supplied key" => "kept"}
  end
end
