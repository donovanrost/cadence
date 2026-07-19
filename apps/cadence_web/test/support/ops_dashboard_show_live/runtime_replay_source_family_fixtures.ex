defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures do
  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import ExUnit.Callbacks
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance
  }

  alias Cadence.Comms.{GroundStation, Transport}
  alias Cadence.Contacts.{Path, RealizedContact}

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    RenderItem,
    SourceHealth
  }

  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Ingress.RawEvidence
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    PacketRecordRow,
    RawEvidenceRow,
    ReplayRunRow
  }

  alias Cadence.Protocol.PacketRecord
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Telemetry.{Sample, Storage}

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  def signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  def persist_replay_run!(mission, replay_run_id) do
    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: "#{replay_run_id}-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 1,
        replayed_packet_count: 0,
        replayed_sample_count: 0,
        started_at: ~U[2026-06-17 11:59:00Z],
        completed_at: ~U[2026-06-17 12:06:00Z]
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
  end

  def persist_command_queue_entry!(
        org,
        mission,
        command_queue_entry_id,
        source_endpoint_ref,
        lifecycle_state \\ :pending
      ) do
    requested_at = ~U[2026-06-17 12:00:00Z]
    command_request_id = "#{command_queue_entry_id}-request"

    command_request =
      CommandRequest.new(%{
        command_request_id: command_request_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_ref,
        command_snapshot_id: "#{command_queue_entry_id}-snapshot",
        command_id: "#{command_queue_entry_id}-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 3,
        requested_by: %{"user_id" => "dashboard-test"},
        requested_at: requested_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: command_queue_entry_id,
        mission_id: mission.mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: source_endpoint_ref,
        queue_lane_key: source_endpoint_ref,
        priority: 3,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: lifecycle_state,
        enqueued_by: %{"user_id" => "dashboard-test"},
        enqueued_at: requested_at,
        metadata: %{}
      })

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    command_queue_entry
  end

  def persist_replay_command_verifier_telemetry_sample!(
        org,
        mission,
        replay_run_id,
        telemetry_replay_source,
        receipt_time
      ) do
    sample = %Sample{
      sample_id: "verifier-telemetry-sample-1",
      mission_id: mission.mission_id,
      spacecraft_id: "spacecraft-alpha",
      point_id: "CMD.release_confirmed",
      point_name: "CMD.release_confirmed",
      packet_definition_id: "packet-def-command-verifier",
      packet_definition_version: 1,
      packet_id: "packet-command-verifier",
      evidence_id: "evidence-command-verifier",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      generation_time: DateTime.add(receipt_time, -2, :second),
      receipt_time: receipt_time,
      provenance: %{"command_release_attempt_id" => "release-attempt-1"}
    }

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: sample.evidence_id,
        mission_id: mission.mission_id,
        spacecraft_id: sample.spacecraft_id,
        protocol_family: :space_packet,
        direction: :downlink,
        raw: <<0, 1, 2, 3>>,
        source_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        source_ref: "command-verifier-telemetry-test",
        metadata: %{}
      })

    packet_record = %PacketRecord{
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: mission.mission_id,
      spacecraft_id: sample.spacecraft_id,
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 1,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<0, 1, 2, 3>>,
      source_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: %{}
    }

    assert %RawEvidenceRow{} = Repo.insert!(RawEvidenceRow.changeset(raw_evidence))
    assert %PacketRecordRow{} = Repo.insert!(PacketRecordRow.changeset(packet_record))

    assert :ok =
             Storage.persist_samples([sample],
               organization_id: org.organization_id,
               realm: :replay,
               replay_run_id: replay_run_id,
               data_source_id: telemetry_replay_source.data_source_id,
               binding_id: telemetry_replay_source.binding_id,
               recorded_at: receipt_time,
               source_watermark_events?: false,
               dashboard_runtime_invalidation?: false
             )

    sample
  end

  def persist_transport_command_release_attempt!(org, mission, attempted_at) do
    command_request =
      CommandRequest.new(%{
        command_request_id: "command-request-1",
        mission_id: mission.mission_id,
        source_endpoint_ref: "endpoint-alpha",
        command_snapshot_id: "transport-command-snapshot-1",
        command_id: "transport-command-1",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        verification_state: :failed,
        priority: 2,
        requested_by: %{"user_id" => "transport-runtime-test"},
        requested_at: attempted_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: "command-queue-entry-1",
        mission_id: mission.mission_id,
        command_request_id: command_request.command_request_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        queue_lane_key: command_request.source_endpoint_ref,
        priority: 2,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: :released,
        enqueued_by: %{"user_id" => "transport-runtime-test"},
        enqueued_at: attempted_at,
        metadata: %{}
      })

    release_attempt =
      CommandReleaseAttempt.new(%{
        command_release_attempt_id: "release-attempt-1",
        mission_id: mission.mission_id,
        command_queue_entry_id: command_queue_entry.command_queue_entry_id,
        command_request_id: command_request.command_request_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        transport_binding_id: "transport-binding-alpha",
        command_snapshot_id: command_request.command_snapshot_id,
        command_id: command_request.command_id,
        command_name: command_request.command_name,
        layout_kind: :ccsds_space_packet,
        encoded_binary_base64: Base.encode64("NOOP"),
        encoded_size_bytes: 4,
        lifecycle_state: :released,
        verification_state: :failed,
        released_by: %{"user_id" => "transport-runtime-test"},
        attempted_at: attempted_at,
        released_at: attempted_at,
        metadata: %{"transport_action_request_id" => "transport-action-request-1"}
      })

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: command_request.source_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Transport Runtime Endpoint",
        source_ref: "provider/#{command_request.source_endpoint_ref}",
        metadata: %{"contact_id" => release_attempt.realized_contact_id}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: release_attempt.realized_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [command_request.source_endpoint_ref],
        contact_intents: [:command_window],
        paths: [
          Path.new(%{
            path_id: release_attempt.path_id,
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: command_request.source_endpoint_ref
          })
        ],
        clock_mode: :replay,
        lifecycle_state: :active,
        initial_time: DateTime.add(attempted_at, -60, :second),
        realized_at: DateTime.add(attempted_at, -60, :second),
        metadata: %{"command_release_attempt_id" => release_attempt.command_release_attempt_id}
      })

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    assert %CommandReleaseAttemptRow{} =
             Repo.insert!(
               CommandReleaseAttemptRow.changeset(%CommandReleaseAttempt{
                 release_attempt
                 | organization_id: org.organization_id
               })
             )

    %CommandReleaseAttempt{release_attempt | organization_id: org.organization_id}
  end

  def persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        matched_at,
        opts \\ []
      ) do
    verifier_instance =
      CommandVerifierInstance.new(%{
        command_verifier_instance_id:
          Keyword.get(opts, :command_verifier_instance_id, "verifier-instance-satisfied"),
        mission_id: mission.mission_id,
        command_request_id: release_attempt.command_request_id,
        command_release_attempt_id: release_attempt.command_release_attempt_id,
        source_endpoint_ref: release_attempt.source_endpoint_ref,
        command_snapshot_id: release_attempt.command_snapshot_id,
        command_id: release_attempt.command_id,
        command_name: release_attempt.command_name,
        verifier_id: Keyword.get(opts, :verifier_id, "transport-verifier-1"),
        verifier_name: Keyword.get(opts, :verifier_name, "Transport action accepted"),
        phase: Keyword.get(opts, :phase, :start),
        severity: Keyword.get(opts, :severity, :info),
        lifecycle_state: Keyword.get(opts, :lifecycle_state, :satisfied),
        matched_record_kind: Keyword.get(opts, :matched_record_kind, :transport_action_request),
        matched_record_id: Keyword.get(opts, :matched_record_id, "transport-action-request-1"),
        matched_at: matched_at,
        failure_reason: Keyword.get(opts, :failure_reason),
        metadata: %{"transport_action_request_id" => "transport-action-request-1"}
      })

    assert %CommandVerifierInstanceRow{} =
             Repo.insert!(
               CommandVerifierInstanceRow.changeset(%CommandVerifierInstance{
                 verifier_instance
                 | organization_id: org.organization_id
               })
             )

    %CommandVerifierInstance{verifier_instance | organization_id: org.organization_id}
  end

  def persist_replay_managed_runtime_events!(org, mission, replay_run_id, action_at, timer_at) do
    action_request =
      %ManagedActionRequest{
        action_request_id: "managed-action-request-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        action_kind: :schedule_timer,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        request_document: %{"timer_key" => "flush", "delay_ms" => 1_000},
        requested_at: action_at
      }

    timer_event =
      %ManagedTimerEvent{
        timer_event_id: "managed-timer-event-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        timer_key: "flush",
        event_kind: :fired,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"scheduled_by" => action_request.action_request_id}
      }

    action_event =
      action_request
      |> Event.from_managed_action_request(replay_run_id)
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    timer_event =
      timer_event
      |> Event.from_managed_timer_event(replay_run_id)
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    {action_event, timer_event}
  end

  def persist_live_managed_runtime_events!(org, mission, action_at, timer_at) do
    action_request =
      %ManagedActionRequest{
        action_request_id: "managed-action-request-live-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        action_kind: :schedule_timer,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        request_document: %{"timer_key" => "flush", "delay_ms" => 1_000},
        requested_at: action_at
      }

    timer_event =
      %ManagedTimerEvent{
        timer_event_id: "managed-timer-event-live-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        timer_key: "flush",
        event_kind: :fired,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"scheduled_by" => action_request.action_request_id}
      }

    action_event =
      action_request
      |> Event.from_managed_action_request()
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    timer_event =
      timer_event
      |> Event.from_managed_timer_event()
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    {action_event, timer_event}
  end

  def persist_replay_managed_capability_record_events!(
        org,
        mission,
        replay_run_id,
        initialized_at,
        record_at,
        timer_at
      ) do
    [
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-initialized-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :initialized,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        timer_key: nil,
        emitted_record_kinds: [],
        emitted_record_count: 0,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 0},
        recorded_at: initialized_at,
        metadata: %{}
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :record_handled,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        timer_key: nil,
        emitted_record_kinds: [:derived_metric, :limit_state],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["managed-action-request-2"],
          "emitted_record_refs" => ["limit-state-1", "derived-metric-1"]
        }
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-timer-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :timer_handled,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        timer_key: "flush",
        emitted_record_kinds: [:flush_summary],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: false, heartbeat_count: 2},
        recorded_at: timer_at,
        metadata: %{}
      }
    ]
    |> Enum.map(fn capability_record ->
      capability_record
      |> Event.from_managed_capability_record(replay_run_id)
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()
    end)
  end

  def persist_live_managed_capability_record_events!(
        org,
        mission,
        initialized_at,
        record_at,
        timer_at
      ) do
    [
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-live-initialized-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :initialized,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        timer_key: nil,
        emitted_record_kinds: [],
        emitted_record_count: 0,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 0},
        recorded_at: initialized_at,
        metadata: %{}
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-live-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :record_handled,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        timer_key: nil,
        emitted_record_kinds: [:derived_metric, :limit_state],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["managed-action-request-live-2"],
          "emitted_record_refs" => ["limit-state-live-1", "derived-metric-live-1"]
        }
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-live-timer-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :timer_handled,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        timer_key: "flush",
        emitted_record_kinds: [:flush_summary],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: false, heartbeat_count: 2},
        recorded_at: timer_at,
        metadata: %{}
      }
    ]
    |> Enum.map(fn capability_record ->
      capability_record
      |> Event.from_managed_capability_record()
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()
    end)
  end

  def persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      ) do
    [
      %TransportCapabilityRecord{
        transport_record_id: "transport-runtime-live-record-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: "transport-live-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-live-activation-alpha",
        binding_set_id: "transport-live-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-live-alpha",
        event_kind: :control_input_handled,
        timer_key: nil,
        emitted_record_kinds: [:uplink_frame],
        emitted_record_count: 1,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", vcid: 7},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["transport-action-request-live-1"],
          "emitted_record_refs" => ["uplink-frame-live-1"]
        }
      },
      %TransportActionRequest{
        action_request_id: "transport-action-request-live-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: "transport-live-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-live-activation-alpha",
        binding_set_id: "transport-live-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-live-alpha",
        command_release_attempt_id: "release-attempt-live-1",
        command_request_id: "command-request-live-1",
        source_endpoint_ref: "endpoint-live-alpha",
        command_name: "NOOP",
        signal_phase: :start,
        action_kind: :release_command,
        request_document: %{"command_request_id" => "command-request-live-1", "frame_count" => 1},
        requested_at: action_at,
        metadata: %{"release_attempt_id" => "release-attempt-live-1"}
      },
      %TransportTimerEvent{
        timer_event_id: "transport-timer-event-live-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: "transport-live-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-live-activation-alpha",
        binding_set_id: "transport-live-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-live-alpha",
        timer_key: "cop1_timeout",
        event_kind: :fired,
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"action_request_id" => "transport-action-request-live-1"}
      }
    ]
    |> Enum.map(fn
      %TransportCapabilityRecord{} = capability_record ->
        capability_record
        |> Event.from_transport_capability_record()
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportActionRequest{} = action_request ->
        action_request
        |> Event.from_transport_action_request()
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportTimerEvent{} = timer_event ->
        timer_event
        |> Event.from_transport_timer_event()
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()
    end)
  end

  def persist_replay_transport_runtime_events!(
        org,
        mission,
        replay_run_id,
        record_at,
        action_at,
        timer_at
      ) do
    [
      %TransportCapabilityRecord{
        transport_record_id: "transport-runtime-record-1",
        mission_id: mission.mission_id,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: "transport-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-activation-alpha",
        binding_set_id: "transport-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha",
        event_kind: :control_input_handled,
        timer_key: nil,
        emitted_record_kinds: [:uplink_frame],
        emitted_record_count: 1,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", vcid: 7},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["transport-action-request-1"],
          "emitted_record_refs" => ["uplink-frame-1"]
        }
      },
      %TransportActionRequest{
        action_request_id: "transport-action-request-1",
        mission_id: mission.mission_id,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: "transport-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-activation-alpha",
        binding_set_id: "transport-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha",
        command_release_attempt_id: "release-attempt-1",
        command_request_id: "command-request-1",
        source_endpoint_ref: "endpoint-alpha",
        command_name: "NOOP",
        signal_phase: :start,
        action_kind: :release_command,
        request_document: %{"command_request_id" => "command-request-1", "frame_count" => 1},
        requested_at: action_at,
        metadata: %{"release_attempt_id" => "release-attempt-1"}
      },
      %TransportTimerEvent{
        timer_event_id: "transport-timer-event-1",
        mission_id: mission.mission_id,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: "transport-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-activation-alpha",
        binding_set_id: "transport-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha",
        timer_key: "cop1_timeout",
        event_kind: :fired,
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"action_request_id" => "transport-action-request-1"}
      }
    ]
    |> Enum.map(fn
      %TransportCapabilityRecord{} = capability_record ->
        capability_record
        |> Event.from_transport_capability_record(replay_run_id)
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportActionRequest{} = action_request ->
        action_request
        |> Event.from_transport_action_request(replay_run_id)
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportTimerEvent{} = timer_event ->
        timer_event
        |> Event.from_transport_timer_event(replay_run_id)
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()
    end)
  end

  def persist_operational_event!(%Event{} = event) do
    assert {:ok, %Event{} = persisted_event} = OperationalEvents.persist_event(event)
    persisted_event
  end

  def contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "dashboard-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "dashboard-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  def persist_dashboard_realm!(
        mission,
        realm,
        capabilities \\ %{range_scan?: true, latest?: true}
      ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    binding_id = "test-#{realm}-binding-#{System.unique_integer([:positive])}"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id, binding_id: binding_id}
  end

  def persist_replay_event_and_operational_sources!(mission) do
    unique = System.unique_integer([:positive])

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    operational_binding_id = "replay-operational-observables-#{unique}"
    events_binding_id = "replay-events-#{unique}"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | binding_id: operational_binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "operational_observables_replay",
                 metadata: %{bootstrap_default?: false}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_events_binding()
               | binding_id: events_binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "mission_events_replay",
                 metadata: %{bootstrap_default?: false}
             })

    %{
      operational_binding_id: operational_binding_id,
      operational_data_source_id:
        DataSources.default_operational_observables_data_source().data_source_id,
      events_binding_id: events_binding_id,
      events_data_source_id: DataSources.default_events_data_source().data_source_id
    }
  end

  def persist_replay_connection_state_resources!(org, mission) do
    ground_station =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "replay-source-health-endpoint",
          "transport_id" => "replay-source-health-transport"
        }
      })

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, ground_station)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "replay-source-health-endpoint",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Endpoint",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    transport =
      Transport.new(%{
        transport_id: "replay-source-health-transport",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Transport",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => source_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-14",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, transport} = Cadence.persist_transport(org.organization_id, transport)

    {source_endpoint, transport}
  end

  def record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      ) do
    assert {:ok, event, _status} =
             SourceHealth.record_source_health(
               %{
                 source_health_event_id: "source-health-rendered-replay-operational-observables",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: observed_at,
                 payload: %{
                   probe_kind: :connection_test,
                   probe_message: "Replay operational observables source probe degraded"
                 }
               },
               invalidate_runtime_cache?: false
             )

    intervals =
      Cadence.operational_source_health_intervals(org.organization_id, mission.mission_id,
        data_source_id: event.data_source_id,
        source_binding_id: event.source_binding_id,
        realm: event.realm,
        dataset: event.dataset,
        replay_run_id: replay_run_id,
        at: observed_at,
        order: :asc
      )

    interval =
      case intervals do
        [interval] ->
          interval

        other ->
          flunk("expected one filtered replay source-health interval, got #{inspect(other)}")
      end

    {event, interval}
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
      realized_contact_id: Keyword.get(opts, :contact_id, "replay-contact-alpha"),
      path_id: Keyword.get(opts, :path_id, "replay-uplink-path"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "replay-activation-1",
      binding_set_id: "replay-binding-set-1",
      binding_set_version: 1,
      partition_affinity: :source_endpoint,
      partition_value: "replay-source-health-endpoint",
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

  def assert_transport_action_runtime_context!(
        view,
        release_attempt_id,
        command_request_id,
        replay_run_id
      ) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             command_request_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             release_attempt_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  def assert_live_transport_action_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             "release-attempt-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             "command-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-live-1"
           )
  end

  def assert_live_transport_capability_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-runtime-live-record-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "cop1_state"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "vcid"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "transport-action-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )
  end

  def assert_live_transport_timer_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"]),
             "transport-timer-event-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "cop1_timeout"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "transport-action-request-live-1"
           )
  end

  def assert_transport_timer_runtime_context!(view, replay_run_id) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"]),
             "transport-timer-event-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "cop1_timeout"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "transport-action-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  def assert_managed_timer_runtime_context!(view, replay_run_id) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"]),
             "managed-timer-event-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "flush"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "managed-action-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  def assert_live_managed_timer_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"]),
             "managed-timer-event-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "flush"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "managed-action-request-live-1"
           )
  end

  def configure_dashboard_source_health!(now) do
    previous = Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:now, now)
      |> Keyword.put(:source_health_freshness, %{default_max_age_ms: 86_400_000})
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :dashboard_engine_source_execution, previous)
    end)
  end

  def operational_observable_state_event(
        organization_id,
        mission_id,
        snapshot_id,
        state,
        observed_at,
        opts
      ) do
    transport_id = Keyword.fetch!(opts, :transport_id)
    observable_id = Keyword.get(opts, :observable_id, "comms.transport.connection_state")
    resource_id = Keyword.get(opts, :resource_id, transport_id)
    scope_kind = Keyword.get(opts, :scope_kind, :transport)

    Event.from_operational_observable_state_snapshot(%{
      snapshot_id: snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: transport_id,
      source_endpoint_id: "replay-source-health-endpoint",
      ground_station_id: "dss-14",
      link_id: Keyword.get(opts, :link_id),
      adapter_key: :tcp_socket,
      connection_state: connection_state_value(observable_id, state),
      rf_lock_state: rf_lock_state_value(observable_id, state),
      frame_sync_state: frame_sync_state_value(observable_id, state),
      state: state,
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  def connection_state_value("comms.transport.connection_state", state), do: state
  def connection_state_value("ground.station.connection_state", state), do: state
  def connection_state_value(_observable_id, _state), do: nil

  def rf_lock_state_value("link.rf_lock_state", state), do: state
  def rf_lock_state_value(_observable_id, _state), do: nil

  def frame_sync_state_value("link.frame_sync_state", state), do: state
  def frame_sync_state_value(_observable_id, _state), do: nil

  def open_and_assert_replay_rf_evidence!(view, conn, attrs) do
    row_selector = Map.fetch!(attrs, :row_selector)
    widget_id = Map.fetch!(attrs, :widget_id)
    observable_id = Map.fetch!(attrs, :observable_id)
    replay_sources = Map.fetch!(attrs, :replay_sources)
    replay_run_id = Map.fetch!(attrs, :replay_run_id)
    interval = Map.fetch!(attrs, :interval)
    expected_snapshot_id = Map.fetch!(attrs, :expected_snapshot_id)
    expected_state = Map.fetch!(attrs, :expected_state)
    expected_transport_id = Map.fetch!(attrs, :expected_transport_id)

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form(observable_id)}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="#{rf_interval_evidence_kind(observable_id)}"][data-evidence-ref-id="#{interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form(observable_id)}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    rf_operational_event_id = interval.source_event_id
    rf_operational_event_route_id = URI.encode_www_form(rf_operational_event_id)
    rf_event_at_ms = DateTime.to_unix(interval.starts_at, :millisecond)

    rf_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{rf_operational_event_id}"][data-evidence-ref-link-target="operational_event"])

    view
    |> element(rf_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{rf_operational_event_id}",
      "target" => "operational_event",
      "target-id" => rf_operational_event_id,
      "timestamp-ms" => rf_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    rf_event_path = assert_patch(view)
    assert rf_event_path =~ "panel=data_link"
    assert rf_event_path =~ "selected_target=operational_event"
    assert rf_event_path =~ "selected_id=#{rf_operational_event_route_id}"
    assert rf_event_path =~ "selected_time=#{rf_event_at_ms}"
    assert rf_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    rf_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert rf_event_copied_path =~ "panel=data_link"
    assert rf_event_copied_path =~ "selected_target=operational_event"
    assert rf_event_copied_path =~ "selected_id=#{rf_operational_event_route_id}"
    assert rf_event_copied_path =~ "selected_time=#{rf_event_at_ms}"
    assert rf_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert rf_event_copied_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert rf_event_copied_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_rf_event_view, _html} = live(conn, rf_event_copied_path)

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="selected_time=#{rf_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
             expected_snapshot_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             observable_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             expected_transport_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state"]),
             expected_state
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
             expected_snapshot_id
           )

    stop_dashboard_view(reopened_rf_event_view)
  end

  def rf_interval_evidence_kind("link.rf_lock_state"), do: "link rf lock state interval"
  def rf_interval_evidence_kind("link.frame_sync_state"), do: "link frame sync state interval"

  def show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  def element_attribute(html, selector, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    value
  end

  def fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  def replace_dashboard_row_document!(org, mission, %Document{} = document) do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{document: JsonDocument.encode(Document.to_map(document))})
    |> Repo.update!()

    document
  end

  def render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  def render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  def track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  def stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  def drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def enable_dashboard_engine_inline_resolves! do
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end
end
