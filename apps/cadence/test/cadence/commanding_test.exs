defmodule Cadence.CommandingTest do
  use Cadence.ConfigCase, async: false

  import Ecto.Query

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog.Artifact
  alias CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias CCSDS.TC.TransferFrame
  alias CCSDS.Transport.COP1.CLCW

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandStage,
    CommandVerifierInstance,
    ReleaseStore,
    ReleaseTargetGuard,
    ReleaseTargetSelection,
    RequestQueueStore,
    RequestStore,
    StagedCommandItem
  }

  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact, TransportBinding}
  alias Cadence.Management.Commanding, as: ManagementCommanding
  alias Cadence.OperationalEvents
  alias Cadence.Repo
  alias Cadence.Runtime.TransportRecords.TransportActionRequestRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.Sample

  @organization_id "org-alpha"
  @mission_id "mission-alpha"
  @spacecraft_id "spacecraft-alpha"
  @source_endpoint_id "source-endpoint-alpha"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    cleanup_static_command_queue_scope()

    source_endpoint = persist_source_endpoint()
    command_model = import_command_model()

    {:ok, source_endpoint: source_endpoint, command_model: command_model}
  end

  test "persists and updates command stages and staged command items", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    command_stage =
      CommandStage.new(%{
        mission_id: @mission_id,
        stage_name: "Flight Director Review",
        description: "Shared workbench for reviewed commands",
        owner: %{"user_id" => "user-123"},
        visibility: :shared
      })

    assert {:ok, persisted_stage} =
             ManagementCommanding.persist_command_stage(@organization_id, command_stage)

    staged_command_item =
      StagedCommandItem.new(%{
        mission_id: @mission_id,
        command_stage_id: persisted_stage.command_stage_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{"mode" => 2},
        priority: 4,
        item_order: 1,
        notes: "Initial draft"
      })

    assert {:ok, %StagedCommandItem{} = persisted_item} =
             ManagementCommanding.persist_staged_command_item(
               @organization_id,
               staged_command_item
             )

    updated_item = %StagedCommandItem{
      persisted_item
      | argument_values: %{"mode" => 3},
        priority: 1,
        notes: "Reviewed by FDO"
    }

    assert {:ok, fetched_stage} =
             ManagementCommanding.fetch_command_stage(
               @organization_id,
               @mission_id,
               persisted_stage.command_stage_id
             )

    assert fetched_stage.visibility == :shared

    assert {:ok, updated_persisted_item} =
             ManagementCommanding.update_staged_command_item(@organization_id, updated_item)

    assert updated_persisted_item.argument_values == %{"mode" => 3}
    assert updated_persisted_item.priority == 1
    assert updated_persisted_item.notes == "Reviewed by FDO"

    [listed_item] =
      ManagementCommanding.list_staged_command_items(
        @organization_id,
        @mission_id,
        command_stage_id: persisted_stage.command_stage_id
      )

    assert listed_item.staged_command_item_id == persisted_item.staged_command_item_id
    assert listed_item.argument_values == %{"mode" => 3}
    assert listed_item.priority == 1
  end

  test "submits staged command items into approval-pending command requests when review is required",
       %{
         source_endpoint: source_endpoint,
         command_model: command_model
       } do
    command_stage =
      CommandStage.new(%{
        mission_id: @mission_id,
        stage_name: "Pass Load",
        owner: %{"user_id" => "user-456"},
        visibility: :shared
      })

    assert {:ok, persisted_stage} =
             ManagementCommanding.persist_command_stage(@organization_id, command_stage)

    staged_command_item =
      StagedCommandItem.new(%{
        mission_id: @mission_id,
        command_stage_id: persisted_stage.command_stage_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{"mode" => 1},
        priority: 2,
        item_order: 0,
        notes: "Checked by ops"
      })

    assert {:ok, persisted_item} =
             ManagementCommanding.persist_staged_command_item(
               @organization_id,
               staged_command_item
             )

    assert {:ok, [command_request]} =
             ManagementCommanding.submit_staged_command_items(
               @organization_id,
               @mission_id,
               persisted_stage.command_stage_id,
               [persisted_item.staged_command_item_id],
               %{"user_id" => "user-789"}
             )

    assert command_request.lifecycle_state == :approval_pending
    assert command_request.command_name == "SET_MODE"
    assert command_request.source_command_stage_id == persisted_stage.command_stage_id
    assert command_request.source_staged_command_item_id == persisted_item.staged_command_item_id
    assert command_request.argument_values == %{"mode" => 1}
    assert command_request.resolved_argument_values == %{"delay_s" => 5, "mode" => 1}
    assert command_request.priority == 2
    assert command_request.significance == :hazardous
    assert command_request.critical == true
    assert command_request.hazardous == true
    assert command_request.release_policy_hint == "confirmation_required"
    assert command_request.requested_by == %{"user_id" => "user-789"}

    assert {:ok, fetched_item} =
             ManagementCommanding.fetch_staged_command_item(
               @organization_id,
               @mission_id,
               persisted_item.staged_command_item_id
             )

    assert fetched_item.lifecycle_state == :submitted
    assert fetched_item.submitted_command_request_id == command_request.command_request_id

    assert {:ok, fetched_stage} =
             ManagementCommanding.fetch_command_stage(
               @organization_id,
               @mission_id,
               persisted_stage.command_stage_id
             )

    assert fetched_stage.lifecycle_state == :submitted

    [listed_request] =
      ManagementCommanding.list_command_requests(
        @organization_id,
        @mission_id,
        command_stage_id: persisted_stage.command_stage_id
      )

    assert listed_request.command_request_id == command_request.command_request_id
  end

  test "approves hazardous command requests with separation of duties and then enqueues them", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{"mode" => 2},
        requested_by: %{"user_id" => "requester-1"}
      })

    assert {:ok, persisted_request} =
             ManagementCommanding.persist_command_request(@organization_id, command_request)

    assert persisted_request.lifecycle_state == :approval_pending

    persisted_request_id = persisted_request.command_request_id

    assert {:error, {:command_request_self_approval_not_allowed, ^persisted_request_id}} =
             ManagementCommanding.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "requester-1"}
             )

    assert {:error, {:command_request_requires_approval, ^persisted_request_id}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok,
            %{
              approval: approval,
              command_request: approved_request,
              approved_command: approved_command
            }} =
             ManagementCommanding.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "reviewer-1"},
               reason: "Reviewed by flight director"
             )

    assert %CommandApproval{} = approval
    assert approval.decision == :approved
    assert approval.reason == "Reviewed by flight director"
    assert approved_request.lifecycle_state == :approved
    assert approved_command.command_request_id == persisted_request.command_request_id
    assert is_binary(approved_command.content_sha256)

    assert {:ok, fetched_approval} =
             ManagementCommanding.fetch_command_approval(
               @organization_id,
               @mission_id,
               approval.command_approval_id
             )

    assert fetched_approval.command_request_id == persisted_request.command_request_id

    [listed_approval] =
      ManagementCommanding.list_command_approvals(
        @organization_id,
        @mission_id,
        command_request_id: persisted_request.command_request_id
      )

    assert listed_approval.command_approval_id == approval.command_approval_id

    assert {:ok, %{queue_entry: queue_entry, command_request: queued_request}} =
             Cadence.Control.Commanding.enqueue(
               approved_command,
               %{"user_id" => "queue-operator"}
             )

    assert %CommandQueueEntry{} = queue_entry
    assert queue_entry.queue_lane_key == source_endpoint.source_endpoint_id
    assert queue_entry.priority == persisted_request.priority
    assert queued_request.lifecycle_state == :queued
  end

  test "queues safe command requests by priority within a source endpoint lane", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    low_priority_request =
      persist_safe_command_request(command_model, source_endpoint, 5, %{"label" => "low"})

    first_high_priority_request =
      persist_safe_command_request(command_model, source_endpoint, 1, %{"label" => "high-a"})

    second_high_priority_request =
      persist_safe_command_request(command_model, source_endpoint, 1, %{"label" => "high-b"})

    assert low_priority_request.lifecycle_state == :validated
    assert first_high_priority_request.lifecycle_state == :validated
    assert second_high_priority_request.lifecycle_state == :validated

    assert {:ok, %{queue_entry: low_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               low_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: first_high_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               first_high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: second_high_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               second_high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    listed_queue_entries =
      Cadence.Commanding.list_command_queue_entries(
        @organization_id,
        @mission_id,
        queue_lane_key: source_endpoint.source_endpoint_id
      )

    expected_queue_entry_ids = [
      first_high_priority_queue_entry.command_queue_entry_id,
      second_high_priority_queue_entry.command_queue_entry_id,
      low_priority_queue_entry.command_queue_entry_id
    ]

    listed_queue_entry_ids = Enum.map(listed_queue_entries, & &1.command_queue_entry_id)

    assert Enum.filter(listed_queue_entry_ids, &(&1 in expected_queue_entry_ids)) ==
             expected_queue_entry_ids

    assert [filtered_queue_entry] =
             Cadence.Commanding.list_command_queue_entries(
               @organization_id,
               @mission_id,
               command_request_id: first_high_priority_request.command_request_id
             )

    assert filtered_queue_entry.command_queue_entry_id ==
             first_high_priority_queue_entry.command_queue_entry_id
  end

  test "rejects invalid direct command requests", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    missing_required_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{}
      })

    assert {:error, {:missing_required_command_argument, "mode"}} =
             Cadence.Commanding.persist_command_request(
               @organization_id,
               missing_required_request
             )

    unknown_argument_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{"mode" => 2, "bogus" => 9}
      })

    assert {:error, {:unknown_command_arguments, ["bogus"]}} =
             Cadence.Commanding.persist_command_request(
               @organization_id,
               unknown_argument_request
             )
  end

  test "releases the next queued command through the selected uplink transport and persists an uplink request",
       %{
         source_endpoint: source_endpoint,
         command_model: command_model
       } do
    persisted_request =
      persist_safe_command_request(command_model, source_endpoint, 1, %{"label" => "release"})

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    realized_contact =
      persist_active_uplink_contact(
        source_endpoint.source_endpoint_id,
        %{"service_name" => "gateway", "fecf" => true}
      )

    assert {:ok,
            %{
              release_attempt: %CommandReleaseAttempt{} = release_attempt,
              queue_entry: released_queue_entry,
              command_request: released_request
            }} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-operator"}
             )

    assert release_attempt.lifecycle_state == :released
    assert release_attempt.command_queue_entry_id == queue_entry.command_queue_entry_id
    assert release_attempt.path_id == "uplink-path-alpha"
    assert release_attempt.transport_binding_id == "uplink-gateway-alpha"
    assert Base.decode64!(release_attempt.encoded_binary_base64) == <<0x01>>

    assert released_queue_entry.lifecycle_state == :released
    assert released_request.lifecycle_state == :released
    assert release_attempt.verification_state == :not_required
    assert released_request.verification_state == :not_required

    assert {:ok, fetched_release_attempt} =
             Cadence.Commanding.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.command_request_id == persisted_request.command_request_id

    [listed_release_attempt] =
      Cadence.Commanding.list_command_release_attempts(
        @organization_id,
        @mission_id,
        command_queue_entry_id: queue_entry.command_queue_entry_id
      )

    assert listed_release_attempt.command_release_attempt_id ==
             release_attempt.command_release_attempt_id

    persisted_transport_action_request =
      TransportActionRequestRow
      |> where([row], row.mission_id == ^@mission_id and row.action_kind == "uplink_request")
      |> order_by([row], asc: row.requested_at)
      |> Repo.one!()

    assert persisted_transport_action_request.path_id == "uplink-path-alpha"
    assert persisted_transport_action_request.capability_instance_id == "uplink-gateway-alpha"

    assert persisted_transport_action_request.request_document["command_request_id"] ==
             persisted_request.command_request_id

    assert persisted_transport_action_request.request_document["encoded_binary_base64"] ==
             release_attempt.encoded_binary_base64

    assert persisted_transport_action_request.request_document["transport_profile"] == "tc"
    assert persisted_transport_action_request.request_document["transfer_frame_count"] == 1
    assert persisted_transport_action_request.request_document["transfer_frame_size_bytes"] == 32
    assert persisted_transport_action_request.request_document["first_frame_seq"] == 0
    assert persisted_transport_action_request.request_document["last_frame_seq"] == 0

    assert [operational_event] =
             OperationalEvents.list_events(@organization_id, @mission_id,
               source_record_kind: :transport_action_request,
               source_record_id: persisted_transport_action_request.action_request_id
             )

    assert operational_event.event_id ==
             "operational_event:transport_action_request:#{persisted_transport_action_request.action_request_id}"

    assert operational_event.category == :comms
    assert operational_event.kind == :transport_action_requested

    assert operational_event.subject == %{
             kind: :transport,
             id: persisted_transport_action_request.capability_instance_id
           }

    assert operational_event.causality.source_record_kind == :transport_action_request

    assert operational_event.causality.source_record_id ==
             persisted_transport_action_request.action_request_id

    assert operational_event.causality.correlation_id ==
             release_attempt.command_release_attempt_id

    assert operational_event_value(operational_event, :action_kind) == "uplink_request"

    assert operational_event_value(operational_event, :command_release_attempt_id) ==
             release_attempt.command_release_attempt_id

    assert operational_event_value(operational_event, :command_request_id) ==
             persisted_request.command_request_id

    assert operational_event_value(operational_event, :source_endpoint_ref) == @source_endpoint_id

    [encoded_transfer_frame] =
      persisted_transport_action_request.request_document["transfer_frames_base64"]

    assert {:ok, [decoded_transfer_frame], <<>>} =
             TransferFrame.decode(Base.decode64!(encoded_transfer_frame),
               frame_size: 32,
               fecf: true
             )

    assert decoded_transfer_frame.scid == 0
    assert decoded_transfer_frame.vcid == 0
    assert is_integer(decoded_transfer_frame.fecf)
    assert {:ok, command_packet} = SpacePacketCodec.decode(decoded_transfer_frame.payload)
    assert command_packet.packet_type == :command
    assert command_packet.apid == 0
    assert command_packet.sequence_count == 0
    assert command_packet.data == <<0x01>>
  end

  test "delivers framed uplink bytes through the configured tcp provider adapter", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    on_exit(fn ->
      :gen_tcp.close(listener)
    end)

    persisted_request =
      persist_safe_command_request(command_model, source_endpoint, 1, %{
        "label" => "tcp-provider"
      })

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    provider_binding =
      ProviderBinding.new(%{
        provider_binding_id: "tcp-uplink-provider-alpha",
        adapter_key: :tcp_socket,
        configuration: %{
          mode: :connect,
          host: "127.0.0.1",
          port: port
        }
      })

    realized_contact =
      persist_active_uplink_contact(
        source_endpoint.source_endpoint_id,
        %{
          "service_name" => "gateway",
          "provider_binding_id" => provider_binding.provider_binding_id,
          "provider_adapter_key" => "tcp_socket"
        },
        [provider_binding]
      )

    {:ok, provider_socket} = :gen_tcp.accept(listener)

    on_exit(fn ->
      :ok =
        Cadence.Runtime.stop_realized_contact_sync(
          realized_contact.mission_id,
          realized_contact.realized_contact_id
        )

      :gen_tcp.close(provider_socket)
    end)

    assert {:ok, %{release_attempt: release_attempt}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-operator"}
             )

    assert {:ok, delivered_frame} = :gen_tcp.recv(provider_socket, 0, 1_000)

    assert {:ok, [decoded_transfer_frame], <<>>} =
             TransferFrame.decode(delivered_frame, frame_size: 32)

    assert {:ok, command_packet} = SpacePacketCodec.decode(decoded_transfer_frame.payload)
    assert command_packet.packet_type == :command
    assert command_packet.apid == 0
    assert command_packet.data == <<0x01>>

    provider_request_row =
      TransportActionRequestRow
      |> where(
        [row],
        row.mission_id == ^@mission_id and row.action_kind == "provider_request"
      )
      |> order_by([row], asc: row.requested_at)
      |> Repo.one!()

    assert provider_request_row.path_id == "uplink-path-alpha"

    assert provider_request_row.request_document["provider_binding_id"] ==
             provider_binding.provider_binding_id

    assert provider_request_row.request_document["provider_adapter_key"] == "tcp_socket"

    assert provider_request_row.command_release_attempt_id ==
             release_attempt.command_release_attempt_id

    assert provider_request_row.request_document["payload_count"] == 1

    assert :ok =
             Cadence.Runtime.stop_realized_contact_sync(
               realized_contact.mission_id,
               realized_contact.realized_contact_id
             )
  end

  test "enforces queue-lane priority order at release time", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    low_priority_request =
      persist_safe_command_request(command_model, source_endpoint, 5, %{"label" => "low"})

    high_priority_request =
      persist_safe_command_request(command_model, source_endpoint, 1, %{"label" => "high"})

    assert {:ok, %{queue_entry: low_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               low_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: high_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    low_priority_queue_entry_id = low_priority_queue_entry.command_queue_entry_id
    high_priority_queue_entry_id = high_priority_queue_entry.command_queue_entry_id

    assert {:error,
            {:command_queue_entry_not_next_for_release, ^low_priority_queue_entry_id,
             ^high_priority_queue_entry_id}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               low_priority_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-operator"}
             )

    assert {:ok, %{release_attempt: release_attempt}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               high_priority_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-operator"}
             )

    assert release_attempt.command_queue_entry_id == high_priority_queue_entry_id
  end

  test "creates transport and telemetry verifier instances on release and rolls them up as each phase satisfies",
       %{
         source_endpoint: source_endpoint,
         command_model: command_model
       } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{"mode" => 2},
        requested_by: %{"user_id" => "requester-verify"}
      })

    assert {:ok, persisted_request} =
             Cadence.Commanding.persist_command_request(@organization_id, command_request)

    assert {:ok, %{command_request: approved_request}} =
             Cadence.Commanding.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "reviewer-verify"}
             )

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               approved_request.command_request_id,
               %{"user_id" => "queue-verify"}
             )

    realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    assert {:ok, %{release_attempt: release_attempt, command_request: released_request}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-verify"}
             )

    assert release_attempt.lifecycle_state == :released
    assert release_attempt.verification_state == :pending
    assert released_request.verification_state == :pending

    verifier_instances =
      Cadence.Commanding.list_command_verifier_instances(
        @organization_id,
        @mission_id,
        command_request_id: released_request.command_request_id
      )

    assert length(verifier_instances) == 2

    acceptance_verifier_instance =
      Enum.find(verifier_instances, &(&1.phase == :acceptance))

    completion_verifier_instance =
      Enum.find(verifier_instances, &(&1.phase == :completion))

    assert %CommandVerifierInstance{} = acceptance_verifier_instance
    assert acceptance_verifier_instance.lifecycle_state == :satisfied
    assert acceptance_verifier_instance.verifier_name == "Release Accepted"
    assert acceptance_verifier_instance.matched_record_kind == :transport_action_request
    assert is_binary(acceptance_verifier_instance.matched_record_id)

    assert %CommandVerifierInstance{} = completion_verifier_instance
    assert completion_verifier_instance.lifecycle_state == :pending
    assert completion_verifier_instance.phase == :completion
    assert completion_verifier_instance.verifier_name == "Mode Applied"

    sample =
      %Sample{
        sample_id: "sample-mode-applied",
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        point_id: "mode_state",
        point_name: "mode_state",
        packet_definition_id: "packet-def-mode",
        packet_definition_version: 1,
        packet_id: "packet-mode-applied",
        evidence_id: "evidence-mode-applied",
        raw_value: 2,
        engineering_value: 2,
        quality_state: :good,
        receipt_time: DateTime.add(release_attempt.released_at, 1, :second)
      }

    # #38: the same point from another spacecraft, or from no known spacecraft, verifies nothing.
    for other <- ["spacecraft-bravo", nil] do
      assert {:ok, []} =
               Cadence.Commanding.evaluate_command_verifiers([
                 %Sample{sample | sample_id: "sample-mode-#{other}", spacecraft_id: other}
               ])
    end

    assert {:ok, %{lifecycle_state: :pending}} =
             Cadence.Commanding.fetch_command_verifier_instance(
               @organization_id,
               @mission_id,
               completion_verifier_instance.command_verifier_instance_id
             )

    assert {:ok, [%CommandVerifierInstance{} = satisfied_verifier_instance]} =
             Cadence.Commanding.evaluate_command_verifiers([sample])

    assert satisfied_verifier_instance.command_verifier_instance_id ==
             completion_verifier_instance.command_verifier_instance_id

    assert satisfied_verifier_instance.lifecycle_state == :satisfied
    assert satisfied_verifier_instance.matched_record_kind == :telemetry_sample
    assert satisfied_verifier_instance.matched_record_id == sample.sample_id

    assert {:ok, fetched_verifier_instance} =
             Cadence.Commanding.fetch_command_verifier_instance(
               @organization_id,
               @mission_id,
               completion_verifier_instance.command_verifier_instance_id
             )

    assert fetched_verifier_instance.lifecycle_state == :satisfied

    assert {:ok, fetched_request} =
             Cadence.Commanding.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert fetched_request.verification_state == :satisfied

    assert {:ok, fetched_release_attempt} =
             Cadence.Commanding.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.verification_state == :satisfied
  end

  test "times out pending verifier instances and rolls timeout state onto the request and release attempt",
       %{
         source_endpoint: source_endpoint,
         command_model: command_model
       } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "SET_MODE"),
        argument_values: %{"mode" => 1},
        requested_by: %{"user_id" => "requester-timeout"}
      })

    assert {:ok, persisted_request} =
             Cadence.Commanding.persist_command_request(@organization_id, command_request)

    assert {:ok, %{command_request: approved_request}} =
             Cadence.Commanding.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "reviewer-timeout"}
             )

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               approved_request.command_request_id,
               %{"user_id" => "queue-timeout"}
             )

    realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    assert {:ok, %{release_attempt: release_attempt, command_request: released_request}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-timeout"}
             )

    assert release_attempt.verification_state == :pending
    assert released_request.verification_state == :pending

    assert {:ok, [%CommandVerifierInstance{} = timed_out_verifier_instance]} =
             Cadence.Commanding.timeout_command_verifier_instances(
               DateTime.add(release_attempt.released_at, 10, :second)
             )

    assert timed_out_verifier_instance.lifecycle_state == :timed_out
    assert timed_out_verifier_instance.failure_reason == "timed_out"

    assert {:ok, fetched_request} =
             Cadence.Commanding.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert fetched_request.verification_state == :timed_out

    assert {:ok, fetched_release_attempt} =
             Cadence.Commanding.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.verification_state == :timed_out
  end

  test "cop1 clcw reports satisfy start immediately and completion after acknowledgement", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "TRANSMIT_BURST"),
        requested_by: %{"user_id" => "requester-transport-phases"}
      })

    assert {:ok, persisted_request} =
             Cadence.Commanding.persist_command_request(@organization_id, command_request)

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-transport-phases"}
             )

    realized_contact =
      persist_active_uplink_contact(source_endpoint.source_endpoint_id, %{
        "service_name" => "cop1",
        "cop1_mode" => "fop",
        "cop1_timeout_ms" => 500,
        "cop1_max_retransmit" => 2
      })

    attempted_at = DateTime.from_unix!(1_700_400_000, :second)

    assert {:ok, %{release_attempt: release_attempt, command_request: released_request}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-transport-phases"},
               attempted_at: attempted_at
             )

    assert release_attempt.verification_state == :pending
    assert released_request.verification_state == :pending

    initial_verifier_instances =
      Cadence.Commanding.list_command_verifier_instances(
        @organization_id,
        @mission_id,
        command_request_id: released_request.command_request_id
      )

    assert length(initial_verifier_instances) == 2

    started_verifier_instance =
      Enum.find(initial_verifier_instances, &(&1.phase == :start))

    assert %CommandVerifierInstance{} = started_verifier_instance
    assert started_verifier_instance.lifecycle_state == :satisfied
    assert started_verifier_instance.matched_record_kind == :transport_capability_record

    assert {:ok, request_after_start} =
             Cadence.Commanding.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert request_after_start.verification_state == :pending

    assert {:ok, []} =
             Cadence.handle_path_transport_event(
               @organization_id,
               @mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha",
               "uplink-gateway-alpha",
               %{kind: :cop1_clcw, clcw: CLCW.new(vcid: 0, report_value: 1)},
               []
             )

    completed_verifier_instance =
      Cadence.Commanding.list_command_verifier_instances(
        @organization_id,
        @mission_id,
        command_request_id: released_request.command_request_id
      )
      |> Enum.find(&(&1.phase == :completion))

    assert %CommandVerifierInstance{} = completed_verifier_instance
    assert completed_verifier_instance.lifecycle_state == :satisfied
    assert completed_verifier_instance.matched_record_kind == :transport_capability_record

    assert {:ok, request_after_completion} =
             Cadence.Commanding.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert request_after_completion.verification_state == :satisfied

    assert {:ok, release_attempt_after_completion} =
             Cadence.Commanding.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert release_attempt_after_completion.verification_state == :satisfied
  end

  test "cop1 timeout retransmits the framed uplink request", %{
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    persisted_request =
      persist_safe_command_request(command_model, source_endpoint, 1, %{
        "label" => "cop1-timeout"
      })

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-cop1-timeout"}
             )

    realized_contact =
      persist_active_uplink_contact(source_endpoint.source_endpoint_id, %{
        "service_name" => "cop1",
        "cop1_mode" => "fop",
        "cop1_timeout_ms" => 100,
        "cop1_max_retransmit" => 2
      })

    attempted_at = DateTime.from_unix!(1_700_410_000, :second)

    assert {:ok, %{release_attempt: release_attempt}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-cop1-timeout"},
               attempted_at: attempted_at
             )

    assert :ok =
             Cadence.advance_realized_contact_time(
               @organization_id,
               @mission_id,
               realized_contact.realized_contact_id,
               DateTime.add(attempted_at, 100, :millisecond)
             )

    persisted_transport_action_requests =
      TransportActionRequestRow
      |> where(
        [row],
        row.mission_id == ^@mission_id and
          row.action_kind == "uplink_request" and
          row.command_release_attempt_id == ^release_attempt.command_release_attempt_id
      )
      |> order_by([row], asc: row.requested_at)
      |> Repo.all()

    assert length(persisted_transport_action_requests) == 2

    [initial_request, retransmit_request] = persisted_transport_action_requests

    assert initial_request.request_document["metadata"]["cop1_release_kind"] == "initial"
    assert initial_request.request_document["first_frame_seq"] == 0
    assert retransmit_request.request_document["metadata"]["cop1_release_kind"] == "retransmit"
    assert retransmit_request.request_document["first_frame_seq"] == 0
  end

  describe "#38 a command releases only over its target spacecraft's uplink" do
    setup %{source_endpoint: source_endpoint, command_model: command_model} do
      {:ok, _} =
        Cadence.SpacecraftStore.persist_spacecraft(
          @organization_id,
          Spacecraft.new(%{
            spacecraft_id: "spacecraft-bravo",
            mission_id: @mission_id,
            display_name: "SC Bravo",
            scid: 1
          })
        )

      {:ok, bravo} =
        Cadence.SourceEndpoints.persist_source_endpoint(
          @organization_id,
          SourceEndpoint.new(%{
            source_endpoint_id: "source-endpoint-bravo",
            mission_id: @mission_id,
            spacecraft_id: "spacecraft-bravo",
            source_ref: "SC-BRAVO",
            display_name: "SC Bravo Endpoint"
          })
        )

      request =
        persist_safe_command_request(command_model, source_endpoint, 1, %{"label" => "38"})

      {:ok, %{queue_entry: entry}} =
        Cadence.Commanding.enqueue_command_request(
          @organization_id,
          @mission_id,
          request.command_request_id,
          %{"user_id" => "queue-38"}
        )

      %{
        alpha: source_endpoint.source_endpoint_id,
        bravo: bravo.source_endpoint_id,
        request: request,
        entry: entry
      }
    end

    test "qa's 004-on-007: only another spacecraft's pass is active, so nothing releases", c do
      # Bravo's pass, its uplink path materialized from a route (no source endpoint of its own).
      bravo = uplink_contact_38([c.bravo], nil)

      assert {:error, {:command_queue_lane_no_release_target, _, _}} =
               ReleaseTargetSelection.resolve_dispatch(
                 @organization_id,
                 @mission_id,
                 CommandRequest.new(Map.from_struct(c.request))
               )

      # Even named explicitly, bravo's pass refuses alpha's command before anything is sent.
      assert {:error,
              {:command_release_refused, attempt_id, {:release_contact_not_target_spacecraft, _}}} =
               release_38(c, bravo)

      assert {:ok, %{lifecycle_state: :release_failed}} =
               Cadence.Commanding.fetch_command_release_attempt(
                 @organization_id,
                 @mission_id,
                 attempt_id
               )

      assert uplinks_sent_38(attempt_id) == 0

      # main: the refusal closes the command; it doesn't go back to pending to be refused again.
      assert {:ok, %{lifecycle_state: :canceled}} =
               Cadence.Commanding.fetch_command_queue_entry(
                 @organization_id,
                 @mission_id,
                 c.entry.command_queue_entry_id
               )

      assert {:ok, %{lifecycle_state: :canceled}} =
               Cadence.Commanding.fetch_command_request(
                 @organization_id,
                 @mission_id,
                 c.request.command_request_id
               )
    end

    test "qa's 001-on-009: the contact is the target's but its uplink path belongs to another spacecraft",
         c do
      # A path that names another spacecraft's endpoint was never selectable: no attempt.
      foreign_path = uplink_contact_38([c.alpha], c.bravo)

      assert {:error, {:selected_uplink_path_not_found, _, _}} = release_38(c, foreign_path)

      # A path that names no spacecraft at all (no endpoint, no route) is refused too.
      unowned = uplink_contact_38([c.alpha], nil)

      assert {:error, {:command_release_refused, _, {:release_path_not_target_spacecraft, _}}} =
               release_38(c, unowned)
    end

    test "with both spacecraft's passes active, the lane picks the target's own", c do
      _bravo = uplink_contact_38([c.bravo], nil)
      alpha = uplink_contact_38([c.alpha], c.alpha)

      assert {:ok, %{realized_contact: %{realized_contact_id: id}}} =
               ReleaseTargetSelection.resolve_dispatch(
                 @organization_id,
                 @mission_id,
                 CommandRequest.new(Map.from_struct(c.request))
               )

      assert id == alpha.realized_contact_id
    end

    test "a gateway that doesn't name a SCID is refused, never sent", c do
      contact = uplink_contact_38([c.alpha], c.alpha, %{})

      assert {:error,
              {:command_release_refused, attempt_id,
               {:uplink_gateway_scid_unknown, "uplink-gateway-alpha"}}} =
               release_38(c, contact)

      assert {:ok, %{lifecycle_state: :release_failed}} =
               Cadence.Commanding.fetch_command_release_attempt(
                 @organization_id,
                 @mission_id,
                 attempt_id
               )

      assert uplinks_sent_38(attempt_id) == 0
    end

    test "the lane never cancels over a gateway with no SCID: the command waits, queued", c do
      # A main deployment whose gateway bindings predate SCIDs: selection skips the pass.
      _alpha = uplink_contact_38([c.alpha], c.alpha, %{})

      assert {:error, {:command_queue_lane_no_release_target, _, _}} =
               Cadence.Commanding.dispatch_queue_lane(
                 @organization_id,
                 @mission_id,
                 c.entry.queue_lane_key,
                 %{"user_id" => "lane-38"},
                 attempted_at: DateTime.from_unix!(1_700_400_000, :second)
               )

      assert {:ok, %{lifecycle_state: :pending}} = fetch_entry_38(c.entry)
      assert {:ok, %{lifecycle_state: :queued}} = fetch_request_38(c.request)
      assert attempts_38(c.request) == []
    end

    test "a refusal never overwrites what happened to the command meanwhile", c do
      # Another path completed this release between the claim and the refusal.
      {claimed, request_row, attempt} = claim_38(c.entry, c.request)
      set_state_38(CommandQueueEntryRow, :command_queue_entry_id, claimed, "released")
      set_state_38(CommandRequestRow, :command_request_id, request_row, "released")
      set_state_38(CommandReleaseAttemptRow, :command_release_attempt_id, attempt, "released")

      assert {:ok, %{closed: false}} =
               ReleaseStore.mark_refused(claimed, request_row, attempt, :refused_38)

      assert {:ok, %{lifecycle_state: :released}} = fetch_entry_38(c.entry)
      assert {:ok, %{lifecycle_state: :released}} = fetch_request_38(c.request)
      assert [%{lifecycle_state: "released"}] = attempts_38(c.request)

      # An operator canceled this one meanwhile: it stays canceled; the unsent attempt fails.
      other = persist_safe_command_request(c.command_model, c.source_endpoint, 1, %{"n" => "2"})

      {:ok, %{queue_entry: other_entry}} =
        Cadence.Commanding.enqueue_command_request(
          @organization_id,
          @mission_id,
          other.command_request_id,
          %{"user_id" => "queue-38"}
        )

      {claimed, request_row, attempt} = claim_38(other_entry, other)
      set_state_38(CommandQueueEntryRow, :command_queue_entry_id, claimed, "canceled")
      set_state_38(CommandRequestRow, :command_request_id, request_row, "canceled")

      assert {:ok, %{closed: false}} =
               ReleaseStore.mark_refused(claimed, request_row, attempt, :refused_38)

      assert {:ok, %{lifecycle_state: :canceled}} = fetch_entry_38(other_entry)

      assert [%{lifecycle_state: "release_failed", failure_reason: "refused: " <> _}] =
               attempts_38(other)
    end

    test "a gateway SCID is compared exactly: integer or whole-number string, else refused", c do
      check = fn scid ->
        config = if scid == :none, do: %{}, else: %{"scid" => scid}

        contact =
          RealizedContact.new(%{
            realized_contact_id: "rc-38",
            organization_id: @organization_id,
            mission_id: @mission_id,
            source_endpoint_refs: [c.alpha],
            clock_mode: :replay,
            initial_time: DateTime.from_unix!(1_700_400_000, :second)
          })

        ReleaseTargetGuard.check(
          @organization_id,
          @mission_id,
          c.alpha,
          contact,
          Path.new(%{path_id: "uplink-38", direction: :uplink, source_endpoint_ref: c.alpha}),
          TransportBinding.new(%{
            transport_binding_id: "gw-38",
            family_key: :uplink_gateway,
            target_scope: :path,
            configuration: config
          })
        )
      end

      assert check.(0) == :ok
      assert check.("0") == :ok

      for foreign <- [1, "1"],
          do:
            assert(check.(foreign) == {:error, {:release_gateway_not_target_spacecraft, "gw-38"}})

      for unknown <- [:none, nil, "", "0x", " 0", "0 ", "zero", 0.0, [0]],
          do: assert(check.(unknown) == {:error, {:uplink_gateway_scid_unknown, "gw-38"}})
    end
  end

  defp uplink_contact_38(contact_endpoints, path_endpoint, gateway_config \\ %{"scid" => 0}) do
    contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-38-" <> Integer.to_string(System.unique_integer([:positive])),
        organization_id: @organization_id,
        mission_id: @mission_id,
        source_endpoint_refs: contact_endpoints,
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_400_000, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: path_endpoint,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-gateway-alpha",
                family_key: :uplink_gateway,
                target_scope: :path,
                configuration: Map.put(gateway_config, "service_name", "gateway")
              })
            ]
          })
        ]
      })

    assert {:ok, _} = Cadence.Contacts.persist_realized_contact(@organization_id, contact)

    assert {:ok, _pid} =
             Cadence.Contacts.start_realized_contact(
               @organization_id,
               @mission_id,
               contact.realized_contact_id
             )

    contact
  end

  defp release_38(c, contact),
    do:
      Cadence.Commanding.release_command_queue_entry(
        @organization_id,
        @mission_id,
        c.entry.command_queue_entry_id,
        contact.realized_contact_id,
        %{"user_id" => "release-38"},
        attempted_at: DateTime.from_unix!(1_700_400_000, :second)
      )

  defp fetch_entry_38(entry),
    do:
      Cadence.Commanding.fetch_command_queue_entry(
        @organization_id,
        @mission_id,
        entry.command_queue_entry_id
      )

  defp fetch_request_38(request),
    do:
      Cadence.Commanding.fetch_command_request(
        @organization_id,
        @mission_id,
        request.command_request_id
      )

  defp attempts_38(request) do
    CommandReleaseAttemptRow
    |> where([row], row.command_request_id == ^request.command_request_id)
    |> Repo.all()
  end

  # The state a release holds just before its pre-transmit check: entry claimed, attempt pending.
  defp claim_38(entry, request) do
    {:ok, row} =
      RequestQueueStore.fetch_queue_entry_row(
        @organization_id,
        @mission_id,
        entry.command_queue_entry_id
      )

    {:ok, claimed} = RequestQueueStore.claim_for_release(row)

    {:ok, request_row} =
      RequestStore.fetch_request_row(@organization_id, @mission_id, request.command_request_id)

    {:ok, attempt} =
      ReleaseStore.persist(
        @organization_id,
        CommandReleaseAttempt.new(%{
          organization_id: @organization_id,
          mission_id: @mission_id,
          command_queue_entry_id: entry.command_queue_entry_id,
          command_request_id: request.command_request_id,
          source_endpoint_ref: request.source_endpoint_ref,
          realized_contact_id: "realized-contact-38",
          mission_model_revision_id: request.mission_model_revision_id,
          command_id: request.command_id,
          command_name: request.command_name,
          lifecycle_state: :release_pending,
          released_by: %{"user_id" => "release-38"},
          attempted_at: DateTime.from_unix!(1_700_400_000, :second)
        })
      )

    {claimed, request_row, attempt}
  end

  # Another writer changes the row; the caller keeps its stale copy.
  defp set_state_38(schema, id_field, row, state) do
    id = Map.fetch!(row, id_field)

    {1, _} =
      schema
      |> where([r], r.mission_id == ^@mission_id and field(r, ^id_field) == ^id)
      |> Repo.update_all(set: [lifecycle_state: state])

    :ok
  end

  defp uplinks_sent_38(attempt_id) do
    TransportActionRequestRow
    |> where([row], row.command_release_attempt_id == ^attempt_id)
    |> Repo.aggregate(:count)
  end

  defp persist_source_endpoint do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: @mission_id,
        display_name: "SC Alpha",
        scid: 0
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: @source_endpoint_id,
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        source_ref: "SC-ALPHA",
        display_name: "SC Alpha Endpoint"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(@organization_id, source_endpoint)

    persisted_source_endpoint
  end

  defp import_command_model do
    artifact =
      Artifact.new(%{
        artifact_id: "artifact-commanding-alpha",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "commanding-dev.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        version: "1.0.0"

        commands:
          - name: NOOP
            opcode: 0x01
            parameters: []
          - name: TRANSMIT_BURST
            opcode: 0x02
            parameters: []
            verifiers:
              - name: Uplink Started
                phase: start
                timeout_ms: 5000
                success_criteria:
                  criteria_type: comparison
                  subject_ref: transport:started
                  comparison: equal
                  value: true
              - name: Uplink Completed
                phase: completion
                timeout_ms: 5000
                success_criteria:
                  criteria_type: comparison
                  subject_ref: transport:completed
                  comparison: equal
                  value: true
          - name: SET_MODE
            opcode: 0x03
            is_hazardous: true
            hazard_description: "Mode changes affect vehicle safing behavior"
            requires_confirmation: true
            parameters:
              - name: mode
                data_type: uint
                required: true
                bit_offset: 0
                bit_length: 8
              - name: delay_s
                data_type: uint
                required: false
                default_value: 5
                bit_offset: 8
                bit_length: 8
            verifiers:
              - name: Release Accepted
                phase: acceptance
                timeout_ms: 1000
                success_criteria:
                  criteria_type: comparison
                  subject_ref: transport:accepted
                  comparison: equal
                  value: true
              - name: Mode Applied
                phase: completion
                timeout_ms: 5000
                success_criteria:
                  criteria_type: comparison
                  subject_ref: mode_state
                  comparison: equal
                  value: 2
        """,
        uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
      })

    assert {:ok, persisted_artifact} =
             Cadence.Catalog.persist_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.Catalog.start_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml",
               requested_by: %{"service_identity_id" => "svc-bootstrap"}
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = JobRunner.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.Catalog.fetch_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    Cadence.MissionModelFixtures.activate_imported_model!(
      @organization_id,
      @mission_id,
      completed_run.result_document
    )
  end

  defp persist_safe_command_request(command_model, source_endpoint, priority, metadata) do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "NOOP"),
        priority: priority,
        requested_by: %{"user_id" => "requester-safe"},
        metadata: metadata
      })

    assert {:ok, persisted_request} =
             Cadence.Commanding.persist_command_request(@organization_id, command_request)

    persisted_request
  end

  defp cleanup_static_command_queue_scope do
    Repo.delete_all(
      from(row in TransportActionRequestRow,
        where: row.mission_id == ^@mission_id
      )
    )

    Repo.delete_all(
      from(row in CommandQueueEntryRow,
        where: row.organization_id == ^@organization_id and row.mission_id == ^@mission_id
      )
    )
  end

  defp persist_active_uplink_contact(
         source_endpoint_ref,
         transport_configuration \\ %{"service_name" => "gateway"},
         provider_bindings \\ []
       ) do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-uplink-" <> Integer.to_string(System.unique_integer([:positive])),
        organization_id: @organization_id,
        mission_id: @mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_400_000, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: source_endpoint_ref,
            provider_bindings: provider_bindings,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-gateway-alpha",
                family_key: :uplink_gateway,
                target_scope: :path,
                # #38: a release gateway names its spacecraft (SC Alpha's SCID).
                configuration: Map.put_new(transport_configuration, "scid", 0)
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.Contacts.persist_realized_contact(@organization_id, realized_contact)

    assert {:ok, _pid} =
             Cadence.Contacts.start_realized_contact(
               @organization_id,
               @mission_id,
               realized_contact.realized_contact_id
             )

    realized_contact
  end

  defp fetch_command_id(command_model, command_name),
    do: Cadence.MissionModelFixtures.command_id!(command_model, command_name)

  defp operational_event_value(event, key) when is_atom(key) do
    Map.get(event.current, key) || Map.get(event.current, Atom.to_string(key))
  end
end
