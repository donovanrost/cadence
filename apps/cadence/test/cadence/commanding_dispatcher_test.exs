defmodule Cadence.CommandingDispatcherTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Commanding.{CommandRequest, Dispatcher, DispatchSupervisor}
  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}
  alias Cadence.Persistence.Schemas.TransportActionRequestRow
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @organization_id "org-dispatcher"
  @mission_id "mission-dispatcher"
  @spacecraft_id "spacecraft-dispatcher"
  @source_endpoint_id "source-endpoint-dispatcher"

  setup do
    previous_importers = Application.get_env(:cadence, :catalog_importers, [])

    Application.put_env(:cadence, :catalog_importers, [
      Cadence.Catalog.Importers.CadenceYamlDatabase
    ])

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
    end)

    persist_mission_scope(@organization_id, @mission_id)

    source_endpoint = persist_source_endpoint()
    command_snapshot = import_command_snapshot()

    {:ok, source_endpoint: source_endpoint, command_snapshot: command_snapshot}
  end

  test "dispatcher releases queued commands automatically in priority order within a lane", %{
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

    _realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    start_supervised!(
      {DispatchSupervisor,
       poll_interval_ms: 1_000,
       lane_poll_interval_ms: 20,
       run_on_boot?: false,
       auto_schedule?: false}
    )

    assert {:ok, _summary} = Dispatcher.reconcile_now()

    release_attempts =
      wait_until(fn ->
        attempts = Cadence.list_command_release_attempts(@organization_id, @mission_id)

        if length(attempts) == 2 and Enum.all?(attempts, &(&1.lifecycle_state == :released)) do
          {:ok, attempts}
        else
          :retry
        end
      end)

    assert Enum.map(release_attempts, & &1.command_request_id) == [
             high_priority_request.command_request_id,
             low_priority_request.command_request_id
           ]

    assert {:ok, released_high_priority_queue_entry} =
             Cadence.fetch_command_queue_entry(
               @organization_id,
               @mission_id,
               high_priority_queue_entry.command_queue_entry_id
             )

    assert {:ok, released_low_priority_queue_entry} =
             Cadence.fetch_command_queue_entry(
               @organization_id,
               @mission_id,
               low_priority_queue_entry.command_queue_entry_id
             )

    assert released_high_priority_queue_entry.lifecycle_state == :released
    assert released_low_priority_queue_entry.lifecycle_state == :released

    transport_action_request_count =
      TransportActionRequestRow
      |> where([row], row.mission_id == ^@mission_id and row.action_kind == "uplink_request")
      |> select([row], count(row.action_request_id))
      |> Repo.one!()

    assert transport_action_request_count == 2
  end

  test "dispatcher retries pending commands until an uplink contact becomes available", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    command_request =
      persist_safe_command_request(command_snapshot, source_endpoint, 1, %{"label" => "delayed"})

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.enqueue_command_request(
               @organization_id,
               @mission_id,
               command_request.command_request_id,
               %{"user_id" => "queue-operator"}
             )

    start_supervised!(
      {DispatchSupervisor,
       poll_interval_ms: 1_000,
       lane_poll_interval_ms: 20,
       run_on_boot?: false,
       auto_schedule?: false}
    )

    assert {:ok, _summary} = Dispatcher.reconcile_now()

    Process.sleep(80)
    assert Cadence.list_command_release_attempts(@organization_id, @mission_id) == []

    _realized_contact = persist_active_uplink_contact(source_endpoint.source_endpoint_id)

    release_attempt =
      wait_until(fn ->
        case Cadence.list_command_release_attempts(@organization_id, @mission_id) do
          [release_attempt] when release_attempt.lifecycle_state == :released ->
            {:ok, release_attempt}

          _other ->
            :retry
        end
      end)

    assert release_attempt.command_queue_entry_id == queue_entry.command_queue_entry_id
    assert release_attempt.lifecycle_state == :released

    assert {:ok, released_queue_entry} =
             Cadence.fetch_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id
             )

    assert released_queue_entry.lifecycle_state == :released
  end

  defp wait_until(fun, attempts_left \\ 40)

  defp wait_until(_fun, 0), do: flunk("condition not met before timeout")

  defp wait_until(fun, attempts_left) when is_function(fun, 0) and attempts_left > 0 do
    case fun.() do
      {:ok, value} ->
        value

      :retry ->
        Process.sleep(25)
        wait_until(fun, attempts_left - 1)
    end
  end

  defp persist_source_endpoint do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: @mission_id,
        display_name: "SC Dispatcher"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(@organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: @source_endpoint_id,
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        source_ref: "SC-DISPATCHER",
        display_name: "SC Dispatcher Endpoint"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(@organization_id, source_endpoint)

    persisted_source_endpoint
  end

  defp import_command_snapshot do
    artifact =
      Artifact.new(%{
        artifact_id: "artifact-command-dispatcher",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "command-dispatcher.yaml",
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

  defp persist_active_uplink_contact(source_endpoint_ref) do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-dispatcher-" <> Integer.to_string(System.unique_integer([:positive])),
        organization_id: @organization_id,
        mission_id: @mission_id,
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
             Cadence.persist_realized_contact(@organization_id, realized_contact)

    realized_contact
  end

  defp fetch_command_id(%CommandSnapshot{} = command_snapshot, command_name) do
    command_snapshot.command_definitions
    |> Enum.find(&(&1.name == command_name))
    |> then(& &1.command_id)
  end
end
