defmodule Cadence.CommandingDispatcherTest do
  use Cadence.ConfigCase, async: false

  import Ecto.Query

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog.Artifact
  alias Cadence.Commanding.{CommandRequest, Dispatcher, DispatchSupervisor}
  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}
  alias Cadence.Repo
  alias Cadence.Runtime.TransportRecords.TransportActionRequestRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @organization_id "org-dispatcher"
  @mission_id "mission-dispatcher"
  @spacecraft_id "spacecraft-dispatcher"
  @source_endpoint_id "source-endpoint-dispatcher"
  @lane_dispatcher_event_prefix [:cadence, :commanding, :lane_dispatcher]
  @lane_dispatcher_events [
    [:cadence, :commanding, :lane_dispatcher, :dispatch_attempt],
    [:cadence, :commanding, :lane_dispatcher, :dispatch_result],
    [:cadence, :commanding, :lane_dispatcher, :timer_scheduled]
  ]

  setup do
    dispatcher_scope = dispatcher_scope()

    persist_mission_scope(dispatcher_scope.organization_id, dispatcher_scope.mission_id)

    source_endpoint = persist_source_endpoint(dispatcher_scope)
    command_model = import_command_model(dispatcher_scope)

    {:ok,
     dispatcher_scope: dispatcher_scope,
     source_endpoint: source_endpoint,
     command_model: command_model}
  end

  test "dispatcher releases queued commands automatically in priority order within a lane", %{
    dispatcher_scope: dispatcher_scope,
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    low_priority_request =
      persist_safe_command_request(dispatcher_scope, command_model, source_endpoint, 5, %{
        "label" => "low"
      })

    high_priority_request =
      persist_safe_command_request(dispatcher_scope, command_model, source_endpoint, 1, %{
        "label" => "high"
      })

    assert {:ok, %{queue_entry: low_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               low_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert {:ok, %{queue_entry: high_priority_queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert Cadence.Commanding.list_command_release_attempts(
             dispatcher_scope.organization_id,
             dispatcher_scope.mission_id
           ) == []

    _realized_contact =
      persist_active_uplink_contact(dispatcher_scope, source_endpoint.source_endpoint_id)

    start_supervised!(
      {DispatchSupervisor,
       safety_poll_interval_ms: :timer.hours(1),
       lane_safety_poll_interval_ms: :timer.hours(1),
       run_on_boot?: false,
       auto_schedule?: false}
    )

    assert {:ok, %{released_count: 2, status: :empty}} =
             Dispatcher.drain_lane(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               source_endpoint.source_endpoint_id
             )

    release_attempts =
      Cadence.Commanding.list_command_release_attempts(
        dispatcher_scope.organization_id,
        dispatcher_scope.mission_id
      )

    assert Enum.map(release_attempts, & &1.command_request_id) == [
             high_priority_request.command_request_id,
             low_priority_request.command_request_id
           ]

    assert {:ok, released_high_priority_queue_entry} =
             Cadence.Commanding.fetch_command_queue_entry(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               high_priority_queue_entry.command_queue_entry_id
             )

    assert {:ok, released_low_priority_queue_entry} =
             Cadence.Commanding.fetch_command_queue_entry(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               low_priority_queue_entry.command_queue_entry_id
             )

    assert released_high_priority_queue_entry.lifecycle_state == :released
    assert released_low_priority_queue_entry.lifecycle_state == :released

    transport_action_request_count =
      TransportActionRequestRow
      |> where(
        [row],
        row.mission_id == ^dispatcher_scope.mission_id and row.action_kind == "uplink_request"
      )
      |> select([row], count(row.action_request_id))
      |> Repo.one!()

    assert transport_action_request_count == 2
  end

  test "dispatcher retries pending commands until an uplink contact becomes available", %{
    dispatcher_scope: dispatcher_scope,
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    attach_lane_dispatcher_telemetry(self())

    start_supervised!(
      {DispatchSupervisor,
       safety_poll_interval_ms: :timer.hours(1),
       lane_safety_poll_interval_ms: :timer.hours(1),
       run_on_boot?: false,
       auto_schedule?: false}
    )

    command_request =
      persist_safe_command_request(dispatcher_scope, command_model, source_endpoint, 1, %{
        "label" => "delayed"
      })

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               command_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    assert_lane_dispatcher_event(:dispatch_result, fn measurements, metadata ->
      measurements.count == 1 and metadata.result == :no_release_target and
        metadata.queue_lane_key == source_endpoint.source_endpoint_id
    end)

    assert {:ok, %{released_count: 0, status: :waiting_for_release_target}} =
             Dispatcher.drain_lane(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               source_endpoint.source_endpoint_id
             )

    assert Cadence.Commanding.list_command_release_attempts(
             dispatcher_scope.organization_id,
             dispatcher_scope.mission_id
           ) == []

    _realized_contact =
      persist_active_uplink_contact(dispatcher_scope, source_endpoint.source_endpoint_id)

    assert_lane_dispatcher_event(:dispatch_result, fn measurements, metadata ->
      measurements.count == 1 and metadata.result == :released and
        metadata.queue_lane_key == source_endpoint.source_endpoint_id
    end)

    assert [release_attempt] =
             Cadence.Commanding.list_command_release_attempts(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id
             )

    assert release_attempt.command_queue_entry_id == queue_entry.command_queue_entry_id
    assert release_attempt.lifecycle_state == :released

    assert {:ok, released_queue_entry} =
             Cadence.Commanding.fetch_command_queue_entry(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               queue_entry.command_queue_entry_id
             )

    assert released_queue_entry.lifecycle_state == :released
  end

  defp attach_lane_dispatcher_telemetry(test_pid) do
    handler_id = "command-lane-dispatcher-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @lane_dispatcher_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:lane_dispatcher_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_lane_dispatcher_event(event_name, predicate) do
    event = @lane_dispatcher_event_prefix ++ [event_name]

    receive do
      {:lane_dispatcher_telemetry, ^event, measurements, metadata} ->
        if predicate.(measurements, metadata) do
          {measurements, metadata}
        else
          assert_lane_dispatcher_event(event_name, predicate)
        end

      {:lane_dispatcher_telemetry, _other_event, _measurements, _metadata} ->
        assert_lane_dispatcher_event(event_name, predicate)
    after
      1_000 -> flunk("expected lane dispatcher telemetry event #{inspect(event)}")
    end
  end

  defp dispatcher_scope do
    suffix = System.unique_integer([:positive]) |> Integer.to_string()

    %{
      suffix: suffix,
      organization_id: "#{@organization_id}-#{suffix}",
      mission_id: "#{@mission_id}-#{suffix}",
      spacecraft_id: "#{@spacecraft_id}-#{suffix}",
      source_endpoint_id: "#{@source_endpoint_id}-#{suffix}"
    }
  end

  defp persist_source_endpoint(dispatcher_scope) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: dispatcher_scope.spacecraft_id,
        mission_id: dispatcher_scope.mission_id,
        display_name: "SC Dispatcher"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               dispatcher_scope.organization_id,
               spacecraft
             )

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: dispatcher_scope.source_endpoint_id,
        mission_id: dispatcher_scope.mission_id,
        spacecraft_id: dispatcher_scope.spacecraft_id,
        source_ref: "SC-DISPATCHER",
        display_name: "SC Dispatcher Endpoint"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(
               dispatcher_scope.organization_id,
               source_endpoint
             )

    persisted_source_endpoint
  end

  defp import_command_model(dispatcher_scope) do
    artifact =
      Artifact.new(%{
        artifact_id: "artifact-command-dispatcher-#{dispatcher_scope.suffix}",
        organization_id: dispatcher_scope.organization_id,
        mission_id: dispatcher_scope.mission_id,
        catalog_family: :combined,
        artifact_name: "command-dispatcher-#{dispatcher_scope.suffix}.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        version: "1.0.0"

        commands:
          - name: NOOP
            opcode: 0x01
            parameters: []
        """,
        uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
      })

    assert {:ok, persisted_artifact} =
             Cadence.Catalog.persist_artifact(dispatcher_scope.organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.Catalog.start_import_run(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
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
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               queued_run.import_run_id
             )

    Cadence.MissionModelFixtures.activate_imported_model!(
      dispatcher_scope.organization_id,
      dispatcher_scope.mission_id,
      completed_run.result_document
    )
  end

  defp persist_safe_command_request(
         dispatcher_scope,
         command_model,
         source_endpoint,
         priority,
         metadata
       ) do
    command_request =
      CommandRequest.new(%{
        mission_id: dispatcher_scope.mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        mission_model_revision_id: command_model.revision_id,
        command_id: fetch_command_id(command_model, "NOOP"),
        priority: priority,
        requested_by: %{"user_id" => "requester-safe"},
        metadata: metadata
      })

    assert {:ok, persisted_request} =
             Cadence.Commanding.persist_command_request(
               dispatcher_scope.organization_id,
               command_request
             )

    persisted_request
  end

  defp persist_active_uplink_contact(dispatcher_scope, source_endpoint_ref) do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-dispatcher-#{dispatcher_scope.suffix}-" <>
            Integer.to_string(System.unique_integer([:positive])),
        organization_id: dispatcher_scope.organization_id,
        mission_id: dispatcher_scope.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_500_000, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-dispatcher",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: source_endpoint_ref,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-gateway-dispatcher",
                family_key: :uplink_gateway,
                target_scope: :path,
                configuration: %{"service_name" => "gateway"}
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               dispatcher_scope.organization_id,
               realized_contact
             )

    realized_contact
  end

  defp fetch_command_id(command_model, command_name),
    do: Cadence.MissionModelFixtures.command_id!(command_model, command_name)
end
