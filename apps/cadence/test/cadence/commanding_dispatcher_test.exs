defmodule Cadence.CommandingDispatcherTest do
  use Cadence.ProcessDataCase, async: false

  import Ecto.Query

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog.Artifact
  alias Cadence.Commanding.{CommandRequest, Dispatcher, DispatchSupervisor, ProcessNamespace}
  alias Cadence.Contacts.{ContactStore, Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Control.ContactFactConsumer
  alias Cadence.Platform.EventBus
  alias Cadence.Repo
  alias Cadence.Runtime.TransportRecords.TransportActionRequestRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @organization_id "org-dispatcher"
  @mission_id "mission-dispatcher"
  @spacecraft_id "spacecraft-dispatcher"
  @source_endpoint_id "source-endpoint-dispatcher"
  @lane_safety_poll_interval_ms :timer.hours(1)

  setup do
    dispatcher_scope = dispatcher_scope()
    event_bus = start_event_bus!()
    process_namespace = process_namespace()

    persist_mission_scope(dispatcher_scope.organization_id, dispatcher_scope.mission_id)

    source_endpoint = persist_source_endpoint(dispatcher_scope)
    command_model = import_command_model(dispatcher_scope)

    {:ok,
     dispatcher_scope: dispatcher_scope,
     event_bus: event_bus,
     process_namespace: process_namespace,
     source_endpoint: source_endpoint,
     command_model: command_model}
  end

  test "dispatcher releases queued commands automatically in priority order within a lane", %{
    dispatcher_scope: dispatcher_scope,
    event_bus: event_bus,
    process_namespace: process_namespace,
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
             Cadence.CommandMemberFixtures.enqueue_and_kick(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               low_priority_request.command_request_id,
               %{"user_id" => "queue-operator"},
               process_namespace: process_namespace,
               admin_mode: false
             )

    assert {:ok, %{queue_entry: high_priority_queue_entry}} =
             Cadence.CommandMemberFixtures.enqueue_and_kick(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               high_priority_request.command_request_id,
               %{"user_id" => "queue-operator"},
               process_namespace: process_namespace,
               admin_mode: false
             )

    assert Cadence.Commanding.list_command_release_attempts(
             dispatcher_scope.organization_id,
             dispatcher_scope.mission_id
           ) == []

    _realized_contact =
      persist_active_uplink_contact(
        event_bus,
        dispatcher_scope,
        source_endpoint.source_endpoint_id
      )

    start_dispatch_supervisor!(process_namespace)

    assert {:ok, %{released_count: 2, status: :empty}} =
             Dispatcher.drain_lane(
               process_namespace,
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

  # #1041: a group's lanes are woken after its commit by one message, not a drain per lane inside
  # the request.
  test "kick_lanes wakes the lane and returns at once; the lane releases on its own", %{
    dispatcher_scope: dispatcher_scope,
    event_bus: event_bus,
    process_namespace: process_namespace,
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    requests = enqueue_two!(dispatcher_scope, command_model, source_endpoint, process_namespace)

    persist_active_uplink_contact(event_bus, dispatcher_scope, source_endpoint.source_endpoint_id)
    start_dispatch_supervisor!(process_namespace)

    assert :ok =
             Dispatcher.kick_lanes(
               process_namespace,
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               [source_endpoint.source_endpoint_id, source_endpoint.source_endpoint_id]
             )

    assert_released(dispatcher_scope, requests)
  end

  test "a kick that is never delivered: the dispatcher's own reconcile still releases the group",
       %{
         dispatcher_scope: dispatcher_scope,
         event_bus: event_bus,
         process_namespace: process_namespace,
         source_endpoint: source_endpoint,
         command_model: command_model
       } do
    requests = enqueue_two!(dispatcher_scope, command_model, source_endpoint, process_namespace)
    persist_active_uplink_contact(event_bus, dispatcher_scope, source_endpoint.source_endpoint_id)

    # No dispatcher is running when the kick is sent: it is dropped, harmlessly.
    assert :ok =
             Dispatcher.kick_lanes(
               process_namespace,
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               [source_endpoint.source_endpoint_id]
             )

    assert Cadence.Commanding.list_command_release_attempts(
             dispatcher_scope.organization_id,
             dispatcher_scope.mission_id
           ) == []

    # What recovers it: the dispatcher (here, booting) finds every lane with a pending entry.
    start_supervised!(
      {DispatchSupervisor,
       process_namespace: process_namespace,
       safety_poll_interval_ms: @lane_safety_poll_interval_ms,
       lane_safety_poll_interval_ms: @lane_safety_poll_interval_ms,
       requeue_release_pending_fun: fn -> 0 end,
       run_on_boot?: true,
       auto_schedule?: false}
    )

    assert_released(dispatcher_scope, requests)
  end

  test "dispatcher retries pending commands until an uplink contact becomes available", %{
    dispatcher_scope: dispatcher_scope,
    event_bus: event_bus,
    process_namespace: process_namespace,
    source_endpoint: source_endpoint,
    command_model: command_model
  } do
    start_contact_fact_consumer!(event_bus, process_namespace)
    start_dispatch_supervisor!(process_namespace)
    attach_lane_timer_telemetry(dispatcher_scope, source_endpoint.source_endpoint_id)

    command_request =
      persist_safe_command_request(dispatcher_scope, command_model, source_endpoint, 1, %{
        "label" => "delayed"
      })

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.CommandMemberFixtures.enqueue_and_kick(
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               command_request.command_request_id,
               %{"user_id" => "queue-operator"},
               process_namespace: process_namespace,
               admin_mode: false
             )

    assert_received {:lane_timer_scheduled, %{delay_ms: @lane_safety_poll_interval_ms},
                     %{reason: :safety}}

    assert {:ok, _private_lane} =
             DispatchSupervisor.lane_dispatcher(
               process_namespace,
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               source_endpoint.source_endpoint_id
             )

    assert :error =
             DispatchSupervisor.lane_dispatcher(
               ProcessNamespace.default(),
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               source_endpoint.source_endpoint_id
             )

    assert Cadence.Commanding.list_command_release_attempts(
             dispatcher_scope.organization_id,
             dispatcher_scope.mission_id
           ) == []

    _realized_contact =
      persist_active_uplink_contact(
        event_bus,
        dispatcher_scope,
        source_endpoint.source_endpoint_id
      )

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

    assert :error =
             DispatchSupervisor.lane_dispatcher(
               process_namespace,
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               source_endpoint.source_endpoint_id
             )

    assert :error =
             DispatchSupervisor.lane_dispatcher(
               ProcessNamespace.default(),
               dispatcher_scope.organization_id,
               dispatcher_scope.mission_id,
               source_endpoint.source_endpoint_id
             )
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
        display_name: "SC Dispatcher",
        scid: 0
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
             Cadence.SourceEndpointFixtures.persist(
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
             Cadence.CommandMemberFixtures.persist(
               dispatcher_scope.organization_id,
               command_request
             )

    persisted_request
  end

  # The uplink contact realizes a scheduled pass that is on now: the lane releases by itself only
  # into a scheduled pass inside its window (0ab24ce0b, director 11-14); a hand-started contact
  # takes a command only when an operator names it.
  defp persist_active_uplink_contact(event_bus, dispatcher_scope, source_endpoint_ref) do
    paths = [
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
            configuration: %{"service_name" => "gateway", "scid" => 0}
          })
        ]
      })
    ]

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-dispatcher-#{dispatcher_scope.suffix}-" <>
            Integer.to_string(System.unique_integer([:positive])),
        organization_id: dispatcher_scope.organization_id,
        mission_id: dispatcher_scope.mission_id,
        scheduled_contact_id: persist_pass_on_now(dispatcher_scope, source_endpoint_ref, paths),
        source_endpoint_refs: [source_endpoint_ref],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_500_000, :second),
        paths: paths
      })

    assert {:ok, _persisted_realized_contact} =
             ContactStore.persist_realized(event_bus, realized_contact)

    realized_contact
  end

  defp persist_pass_on_now(dispatcher_scope, source_endpoint_ref, paths) do
    now = DateTime.utc_now()

    {:ok, scheduled} =
      Cadence.Contacts.persist_scheduled_contact(
        dispatcher_scope.organization_id,
        ScheduledContact.new(%{
          scheduled_contact_id:
            "scheduled-dispatcher-#{dispatcher_scope.suffix}-" <>
              Integer.to_string(System.unique_integer([:positive])),
          mission_id: dispatcher_scope.mission_id,
          source_endpoint_refs: [source_endpoint_ref],
          starts_at: DateTime.add(now, -300),
          ends_at: DateTime.add(now, 900),
          paths: paths
        })
      )

    scheduled.scheduled_contact_id
  end

  defp start_event_bus! do
    start_supervised!({EventBus, name: __MODULE__.EventBus, delivery: :sync, before_notify: nil})
  end

  defp start_dispatch_supervisor!(process_namespace) do
    start_supervised!(
      {DispatchSupervisor,
       process_namespace: process_namespace,
       safety_poll_interval_ms: @lane_safety_poll_interval_ms,
       lane_safety_poll_interval_ms: @lane_safety_poll_interval_ms,
       requeue_release_pending_fun: fn -> 0 end,
       list_pending_queue_lanes_fun: fn -> [] end,
       run_on_boot?: false,
       auto_schedule?: false}
    )
  end

  defp start_contact_fact_consumer!(event_bus, process_namespace) do
    start_supervised!(
      {ContactFactConsumer,
       name: __MODULE__.ContactFactConsumer,
       event_bus: event_bus,
       process_namespace: process_namespace}
    )
  end

  defp attach_lane_timer_telemetry(dispatcher_scope, queue_lane_key) do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :commanding, :lane_dispatcher, :timer_scheduled],
        fn _event, measurements, metadata, _config ->
          if metadata.organization_id == dispatcher_scope.organization_id and
               metadata.mission_id == dispatcher_scope.mission_id and
               metadata.queue_lane_key == queue_lane_key do
            send(test_pid, {:lane_timer_scheduled, measurements, metadata})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp process_namespace do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.DispatchSupervisor,
      registry: __MODULE__.DispatchRegistry,
      lane_supervisor: __MODULE__.LaneDispatcherSupervisor,
      dispatcher: __MODULE__.Dispatcher,
      verifier_scheduler: __MODULE__.VerifierScheduler
    )
  end

  defp fetch_command_id(command_model, command_name),
    do: Cadence.MissionModelFixtures.command_id!(command_model, command_name)

  defp enqueue_two!(dispatcher_scope, command_model, source_endpoint, _process_namespace) do
    for {priority, label} <- [{5, "low"}, {1, "high"}] do
      request =
        persist_safe_command_request(
          dispatcher_scope,
          command_model,
          source_endpoint,
          priority,
          %{
            "label" => label
          }
        )

      {:ok, _} =
        Cadence.CommandMemberFixtures.enqueue(
          dispatcher_scope.organization_id,
          dispatcher_scope.mission_id,
          request.command_request_id,
          %{"user_id" => "queue-operator"},
          admin_mode: false
        )

      request
    end
  end

  # The lane releases on its own, so wait for it (it isn't asked to answer).
  defp assert_released(dispatcher_scope, requests, tries \\ 100) do
    attempts =
      Cadence.Commanding.list_command_release_attempts(
        dispatcher_scope.organization_id,
        dispatcher_scope.mission_id
      )

    cond do
      length(attempts) == length(requests) ->
        assert Enum.sort(Enum.map(attempts, & &1.command_request_id)) ==
                 Enum.sort(Enum.map(requests, & &1.command_request_id))

      tries > 0 ->
        Process.sleep(50)
        assert_released(dispatcher_scope, requests, tries - 1)

      true ->
        flunk("expected #{length(requests)} release attempts, saw #{length(attempts)}")
    end
  end
end
