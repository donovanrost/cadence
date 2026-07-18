defmodule Cadence.CommandingTest do
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.Transport.COP1.CLCW

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandStage,
    CommandVerifierInstance,
    StagedCommandItem
  }

  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact, TransportBinding}
  alias Cadence.OperationalEvents
  alias Cadence.Persistence.Schemas.{CommandQueueEntryRow, TransportActionRequestRow}
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.Sample

  @organization_id "org-alpha"
  @mission_id "mission-alpha"
  @spacecraft_id "spacecraft-alpha"
  @source_endpoint_id "source-endpoint-alpha"

  setup do
    previous_importers = Application.get_env(:cadence, :catalog_importers, [])

    Application.put_env(:cadence, :catalog_importers, [
      Cadence.Catalog.Importers.CadenceYamlDatabase
    ])

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
    end)

    persist_mission_scope(@organization_id, @mission_id)
    cleanup_static_command_queue_scope()

    source_endpoint = persist_source_endpoint()
    command_snapshot = import_command_snapshot()

    {:ok, source_endpoint: source_endpoint, command_snapshot: command_snapshot}
  end

  test "persists and updates command stages and staged command items", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    command_stage =
      CommandStage.new(%{
        mission_id: @mission_id,
        stage_name: "Flight Director Review",
        description: "Shared workbench for reviewed commands",
        owner: %{"user_id" => "user-123"},
        visibility: :shared
      })

    assert {:ok, persisted_stage} = Cadence.persist_command_stage(@organization_id, command_stage)

    staged_command_item =
      StagedCommandItem.new(%{
        mission_id: @mission_id,
        command_stage_id: persisted_stage.command_stage_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{"mode" => 2},
        priority: 4,
        item_order: 1,
        notes: "Initial draft"
      })

    assert {:ok, %StagedCommandItem{} = persisted_item} =
             Cadence.persist_staged_command_item(@organization_id, staged_command_item)

    updated_item = %StagedCommandItem{
      persisted_item
      | argument_values: %{"mode" => 3},
        priority: 1,
        notes: "Reviewed by FDO"
    }

    assert {:ok, fetched_stage} =
             Cadence.fetch_command_stage(
               @organization_id,
               @mission_id,
               persisted_stage.command_stage_id
             )

    assert fetched_stage.visibility == :shared

    assert {:ok, updated_persisted_item} =
             Cadence.update_staged_command_item(@organization_id, updated_item)

    assert updated_persisted_item.argument_values == %{"mode" => 3}
    assert updated_persisted_item.priority == 1
    assert updated_persisted_item.notes == "Reviewed by FDO"

    [listed_item] =
      Cadence.list_staged_command_items(
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
         command_snapshot: command_snapshot
       } do
    command_stage =
      CommandStage.new(%{
        mission_id: @mission_id,
        stage_name: "Pass Load",
        owner: %{"user_id" => "user-456"},
        visibility: :shared
      })

    assert {:ok, persisted_stage} = Cadence.persist_command_stage(@organization_id, command_stage)

    staged_command_item =
      StagedCommandItem.new(%{
        mission_id: @mission_id,
        command_stage_id: persisted_stage.command_stage_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{"mode" => 1},
        priority: 2,
        item_order: 0,
        notes: "Checked by ops"
      })

    assert {:ok, persisted_item} =
             Cadence.persist_staged_command_item(@organization_id, staged_command_item)

    assert {:ok, [command_request]} =
             Cadence.submit_staged_command_items(
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
             Cadence.fetch_staged_command_item(
               @organization_id,
               @mission_id,
               persisted_item.staged_command_item_id
             )

    assert fetched_item.lifecycle_state == :submitted
    assert fetched_item.submitted_command_request_id == command_request.command_request_id

    assert {:ok, fetched_stage} =
             Cadence.fetch_command_stage(
               @organization_id,
               @mission_id,
               persisted_stage.command_stage_id
             )

    assert fetched_stage.lifecycle_state == :submitted

    [listed_request] =
      Cadence.list_command_requests(
        @organization_id,
        @mission_id,
        command_stage_id: persisted_stage.command_stage_id
      )

    assert listed_request.command_request_id == command_request.command_request_id
  end

  test "approves hazardous command requests with separation of duties and then enqueues them", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{"mode" => 2},
        requested_by: %{"user_id" => "requester-1"}
      })

    assert {:ok, persisted_request} =
             Cadence.persist_command_request(@organization_id, command_request)

    assert persisted_request.lifecycle_state == :approval_pending

    persisted_request_id = persisted_request.command_request_id

    assert {:error, {:command_request_self_approval_not_allowed, ^persisted_request_id}} =
             Cadence.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "requester-1"}
             )

    assert {:error, {:command_request_requires_approval, ^persisted_request_id}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{approval: approval, command_request: approved_request}} =
             Cadence.approve_command_request(
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

    assert {:ok, fetched_approval} =
             Cadence.fetch_command_approval(
               @organization_id,
               @mission_id,
               approval.command_approval_id
             )

    assert fetched_approval.command_request_id == persisted_request.command_request_id

    [listed_approval] =
      Cadence.list_command_approvals(
        @organization_id,
        @mission_id,
        command_request_id: persisted_request.command_request_id
      )

    assert listed_approval.command_approval_id == approval.command_approval_id

    assert {:ok, %{queue_entry: queue_entry, command_request: queued_request}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert %CommandQueueEntry{} = queue_entry
    assert queue_entry.queue_lane_key == source_endpoint.source_endpoint_id
    assert queue_entry.priority == persisted_request.priority
    assert queued_request.lifecycle_state == :queued
  end

  test "queues safe command requests by priority within a source endpoint lane", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    low_priority_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 5, %{"label" => "low"})

    first_high_priority_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{"label" => "high-a"})

    second_high_priority_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{"label" => "high-b"})

    assert low_priority_request.lifecycle_state == :validated
    assert first_high_priority_request.lifecycle_state == :validated
    assert second_high_priority_request.lifecycle_state == :validated

    assert {:ok, %{queue_entry: low_priority_queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               low_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: first_high_priority_queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               first_high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: second_high_priority_queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               second_high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    listed_queue_entries =
      Cadence.list_command_queue_entries(
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
  end

  test "rejects invalid direct command requests", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    missing_required_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{}
      })

    assert {:error, {:missing_required_command_argument, "mode"}} =
             Cadence.persist_command_request(@organization_id, missing_required_request)

    unknown_argument_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{"mode" => 2, "bogus" => 9}
      })

    assert {:error, {:unknown_command_arguments, ["bogus"]}} =
             Cadence.persist_command_request(@organization_id, unknown_argument_request)
  end

  test "releases the next queued command through the selected uplink transport and persists an uplink request",
       %{
         source_endpoint: source_endpoint,
         command_snapshot: command_snapshot
       } do
    persisted_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{"label" => "release"})

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    assert {:ok,
            %{
              release_attempt: %CommandReleaseAttempt{} = release_attempt,
              queue_entry: released_queue_entry,
              command_request: released_request
            }} =
             Cadence.release_command_queue_entry(
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
             Cadence.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.command_request_id == persisted_request.command_request_id

    [listed_release_attempt] =
      Cadence.list_command_release_attempts(
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
             TransferFrame.decode(Base.decode64!(encoded_transfer_frame), frame_size: 32)

    assert decoded_transfer_frame.scid == 0
    assert decoded_transfer_frame.vcid == 0
    assert decoded_transfer_frame.payload |> binary_part(0, 1) == <<0x01>>
  end

  test "delivers framed uplink bytes through the configured tcp provider adapter", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    on_exit(fn ->
      :gen_tcp.close(listener)
    end)

    persisted_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{
        "label" => "tcp-provider"
      })

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
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
      :gen_tcp.close(provider_socket)
    end)

    assert {:ok, %{release_attempt: release_attempt}} =
             Cadence.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-operator"}
             )

    assert {:ok, delivered_frame} = :gen_tcp.recv(provider_socket, 32, 1_000)

    assert {:ok, [decoded_transfer_frame], <<>>} =
             TransferFrame.decode(delivered_frame, frame_size: 32)

    assert decoded_transfer_frame.payload |> binary_part(0, 1) == <<0x01>>

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
  end

  test "enforces queue-lane priority order at release time", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    low_priority_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 5, %{"label" => "low"})

    high_priority_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{"label" => "high"})

    assert {:ok, %{queue_entry: low_priority_queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               low_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: high_priority_queue_entry}} =
             Cadence.enqueue_command_request(
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
             Cadence.release_command_queue_entry(
               @organization_id,
               @mission_id,
               low_priority_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-operator"}
             )

    assert {:ok, %{release_attempt: release_attempt}} =
             Cadence.release_command_queue_entry(
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
         command_snapshot: command_snapshot
       } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{"mode" => 2},
        requested_by: %{"user_id" => "requester-verify"}
      })

    assert {:ok, persisted_request} =
             Cadence.persist_command_request(@organization_id, command_request)

    assert {:ok, %{command_request: approved_request}} =
             Cadence.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "reviewer-verify"}
             )

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               approved_request.command_request_id,
               %{"user_id" => "queue-verify"}
             )

    realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    assert {:ok, %{release_attempt: release_attempt, command_request: released_request}} =
             Cadence.release_command_queue_entry(
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
      Cadence.list_command_verifier_instances(
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

    assert {:ok, [%CommandVerifierInstance{} = satisfied_verifier_instance]} =
             Cadence.Commanding.evaluate_command_verifiers([sample])

    assert satisfied_verifier_instance.command_verifier_instance_id ==
             completion_verifier_instance.command_verifier_instance_id

    assert satisfied_verifier_instance.lifecycle_state == :satisfied
    assert satisfied_verifier_instance.matched_record_kind == :telemetry_sample
    assert satisfied_verifier_instance.matched_record_id == sample.sample_id

    assert {:ok, fetched_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               @organization_id,
               @mission_id,
               completion_verifier_instance.command_verifier_instance_id
             )

    assert fetched_verifier_instance.lifecycle_state == :satisfied

    assert {:ok, fetched_request} =
             Cadence.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert fetched_request.verification_state == :satisfied

    assert {:ok, fetched_release_attempt} =
             Cadence.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.verification_state == :satisfied
  end

  test "times out pending verifier instances and rolls timeout state onto the request and release attempt",
       %{
         source_endpoint: source_endpoint,
         command_snapshot: command_snapshot
       } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "SET_MODE"),
        argument_values: %{"mode" => 1},
        requested_by: %{"user_id" => "requester-timeout"}
      })

    assert {:ok, persisted_request} =
             Cadence.persist_command_request(@organization_id, command_request)

    assert {:ok, %{command_request: approved_request}} =
             Cadence.approve_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "reviewer-timeout"}
             )

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               approved_request.command_request_id,
               %{"user_id" => "queue-timeout"}
             )

    realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    assert {:ok, %{release_attempt: release_attempt, command_request: released_request}} =
             Cadence.release_command_queue_entry(
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
             Cadence.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert fetched_request.verification_state == :timed_out

    assert {:ok, fetched_release_attempt} =
             Cadence.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.verification_state == :timed_out
  end

  test "cop1 clcw reports satisfy start immediately and completion after acknowledgement", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "TRANSMIT_BURST"),
        requested_by: %{"user_id" => "requester-transport-phases"}
      })

    assert {:ok, persisted_request} =
             Cadence.persist_command_request(@organization_id, command_request)

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
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
             Cadence.release_command_queue_entry(
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
      Cadence.list_command_verifier_instances(
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
             Cadence.fetch_command_request(
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
               %{kind: :cop1_clcw, clcw: CLCW.new(vcid: 0, report_value: 0)},
               []
             )

    completed_verifier_instance =
      Cadence.list_command_verifier_instances(
        @organization_id,
        @mission_id,
        command_request_id: released_request.command_request_id
      )
      |> Enum.find(&(&1.phase == :completion))

    assert %CommandVerifierInstance{} = completed_verifier_instance
    assert completed_verifier_instance.lifecycle_state == :satisfied
    assert completed_verifier_instance.matched_record_kind == :transport_capability_record

    assert {:ok, request_after_completion} =
             Cadence.fetch_command_request(
               @organization_id,
               @mission_id,
               released_request.command_request_id
             )

    assert request_after_completion.verification_state == :satisfied

    assert {:ok, release_attempt_after_completion} =
             Cadence.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               release_attempt.command_release_attempt_id
             )

    assert release_attempt_after_completion.verification_state == :satisfied
  end

  test "cop1 timeout retransmits the framed uplink request", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    persisted_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{
        "label" => "cop1-timeout"
      })

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
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
             Cadence.release_command_queue_entry(
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

  defp persist_source_endpoint do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: @mission_id,
        display_name: "SC Alpha"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(@organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: @source_endpoint_id,
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        source_ref: "SC-ALPHA",
        display_name: "SC Alpha Endpoint"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(@organization_id, source_endpoint)

    persisted_source_endpoint
  end

  defp import_command_snapshot do
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
             Cadence.persist_catalog_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.start_catalog_import_run(
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
    assert {:ok, completed_job} = Cadence.Jobs.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_catalog_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    command_snapshot_id = completed_run.result_document["command_snapshot"]["snapshot_id"]

    assert {:ok, %CommandSnapshot{} = command_snapshot} =
             Cadence.fetch_catalog_command_snapshot(
               @organization_id,
               @mission_id,
               command_snapshot_id
             )

    command_snapshot
  end

  defp persist_safe_command_request(command_snapshot, source_endpoint, priority, metadata) do
    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "NOOP"),
        priority: priority,
        requested_by: %{"user_id" => "requester-safe"},
        metadata: metadata
      })

    assert {:ok, persisted_request} =
             Cadence.persist_command_request(@organization_id, command_request)

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
                configuration: transport_configuration
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.persist_realized_contact(@organization_id, realized_contact)

    assert {:ok, _pid} =
             Cadence.start_realized_contact(
               @organization_id,
               @mission_id,
               realized_contact.realized_contact_id
             )

    realized_contact
  end

  defp fetch_command_id(%CommandSnapshot{} = command_snapshot, command_name) do
    command_snapshot.command_definitions
    |> Enum.find(&(&1.name == command_name))
    |> then(& &1.command_id)
  end

  defp operational_event_value(event, key) when is_atom(key) do
    Map.get(event.current, key) || Map.get(event.current, Atom.to_string(key))
  end
end
