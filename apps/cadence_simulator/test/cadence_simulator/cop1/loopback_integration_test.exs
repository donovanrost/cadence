defmodule CadenceSimulator.COP1.LoopbackIntegrationTest do
  use CadenceSimulator.DataCase, async: false

  @moduletag :integration

  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact, TransportBinding}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias CadenceSimulator.COP1.LoopbackPeer

  @organization_id "org-sim-cop1"
  @mission_id "mission-sim-cop1"
  @spacecraft_id "sc-sim-cop1"
  @source_endpoint_id "source-endpoint-sim-cop1"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    source_endpoint = persist_source_endpoint()
    command_snapshot = import_command_snapshot()
    {:ok, source_endpoint: source_endpoint, command_snapshot: command_snapshot}
  end

  test "loopback peer satisfies cop1 completion through the tcp provider", %{
    source_endpoint: source_endpoint,
    command_snapshot: command_snapshot
  } do
    provider_binding =
      ProviderBinding.new(%{
        provider_binding_id: "tcp-uplink-provider-alpha",
        adapter_key: :tcp_socket,
        configuration: %{
          mode: :listen,
          port: 0,
          ingress_protocol_family: :cop1_clcw,
          fixed_message_bytes: 4,
          ingress_transport_binding_id: "uplink-gateway-alpha"
        }
      })

    realized_contact =
      persist_active_uplink_contact(
        source_endpoint.source_endpoint_id,
        %{
          "service_name" => "cop1",
          "cop1_mode" => "fop",
          "cop1_timeout_ms" => 500,
          "cop1_max_retransmit" => 2,
          "provider_binding_id" => provider_binding.provider_binding_id,
          "provider_adapter_key" => "tcp_socket"
        },
        [provider_binding]
      )

    assert {:ok, path_snapshot} =
             Cadence.path_runtime_snapshot(
               @organization_id,
               @mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha"
             )

    [provider_runtime_snapshot] = path_snapshot.provider_runtimes

    {:ok, loopback_peer} =
      CadenceSimulator.start_cop1_loopback_peer(
        host: "127.0.0.1",
        port: provider_runtime_snapshot.port,
        tc_frame_size: 32
      )

    on_exit(fn ->
      if Process.alive?(loopback_peer), do: CadenceSimulator.stop_simulator(loopback_peer)
    end)

    assert_eventually(fn -> LoopbackPeer.snapshot(loopback_peer).connected? end)

    command_request =
      CommandRequest.new(%{
        mission_id: @mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        command_snapshot_id: command_snapshot.snapshot_id,
        command_id: fetch_command_id(command_snapshot, "TRANSMIT_BURST"),
        requested_by: %{"user_id" => "requester-loopback"}
      })

    assert {:ok, persisted_request} =
             Cadence.Commanding.persist_command_request(@organization_id, command_request)

    assert {:ok, %{queue_entry: queue_entry}} =
             Cadence.Commanding.enqueue_command_request(
               @organization_id,
               @mission_id,
               persisted_request.command_request_id,
               %{"user_id" => "queue-loopback"}
             )

    assert {:ok, %{release_attempt: release_attempt, command_request: released_request}} =
             Cadence.Commanding.release_command_queue_entry(
               @organization_id,
               @mission_id,
               queue_entry.command_queue_entry_id,
               realized_contact.realized_contact_id,
               %{"user_id" => "release-loopback"}
             )

    assert released_request.verification_state in [:pending, :satisfied]
    assert release_attempt.verification_state in [:pending, :satisfied]

    assert_eventually(fn ->
      case Cadence.Commanding.fetch_command_request(
             @organization_id,
             @mission_id,
             released_request.command_request_id
           ) do
        {:ok, request} -> request.verification_state == :satisfied
        _other -> false
      end
    end)

    assert_eventually(fn ->
      case Cadence.Commanding.fetch_command_release_attempt(
             @organization_id,
             @mission_id,
             release_attempt.command_release_attempt_id
           ) do
        {:ok, attempt} -> attempt.verification_state == :satisfied
        _other -> false
      end
    end)

    assert_eventually(fn ->
      snapshot = LoopbackPeer.snapshot(loopback_peer)

      snapshot.tc_frame_count == 1 and snapshot.clcw_count == 1 and
        is_integer(snapshot.last_tc_frame_seq)
    end)
  end

  defp persist_source_endpoint do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: @mission_id,
        display_name: "SC Simulator"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(@organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: @source_endpoint_id,
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        source_ref: "SC-SIM",
        display_name: "SC Simulator Endpoint"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(@organization_id, source_endpoint)

    persisted_source_endpoint
  end

  defp import_command_snapshot do
    artifact =
      Artifact.new(%{
        artifact_id: "artifact-simulator-loopback-commanding",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "simulator-commanding-dev.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        version: "1.0.0"

        commands:
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
        """,
        uploaded_by: %{"service_identity_id" => "svc-simulator-loopback"}
      })

    assert {:ok, persisted_artifact} =
             Cadence.persist_catalog_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.start_catalog_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml",
               requested_by: %{"service_identity_id" => "svc-simulator-loopback"}
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

  defp persist_active_uplink_contact(
         source_endpoint_ref,
         transport_configuration,
         provider_bindings
       ) do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-uplink-" <> Integer.to_string(System.unique_integer([:positive])),
        organization_id: @organization_id,
        mission_id: @mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        clock_mode: :live,
        initial_time: DateTime.utc_now(),
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

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) when is_function(fun, 0) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end
end
