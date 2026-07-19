defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Comms.{GroundStationStore, TransportStore}

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow
  }

  alias Cadence.Comms.{GroundStation, Transport}
  alias Cadence.Contacts.{Path, RealizedContact}

  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, SourceHealth}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  alias Cadence.Persistence.Schemas.{
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
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

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
             GroundStationStore.persist_ground_station(
               org.organization_id,
               ground_station
             )

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "replay-source-health-endpoint",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Endpoint",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

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

    assert {:ok, transport} =
             TransportStore.persist_transport(org.organization_id, transport)

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
end
