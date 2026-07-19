defmodule CadenceSimulator.CoordinatorTest do
  use CadenceSimulator.DataCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact}
  alias Cadence.Persistence.Schemas.TelemetrySampleRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceSimulator.Coordinator
  alias CadenceSimulator.Providers.DatabaseDynamics

  @definitions """
  version: "1.0.0"
  packets:
    - name: TMHK
      apid: 42
      items:
        - name: uptime_seconds
          bit_offset: 0
          bit_size: 16
          data_type: uint
          endianness: big
  """

  test "simulator coordinator feeds TM frames into the Cadence tcp provider boundary" do
    organization_id = "org-sim"
    mission_id = "mission-sim-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-sim",
        mission_id: mission_id,
        display_name: "SC SIM"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sim",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "provider/tcp/sim"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-sim",
        packet_name: "TMHK",
        apid: 42,
        version: 1,
        fields: [
          %{
            field_id: "uptime_seconds",
            name: "uptime_seconds",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "sim-basis",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "sim-telemetry-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted_binding_set} =
             Cadence.persist_binding_set(organization_id, binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version,
               activated_by: %{"service_identity_id" => "svc-simulator-test"}
             )

    frame_size = 10

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "sim-contact",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [persisted_source_endpoint.source_endpoint_id],
        clock_mode: :live,
        initial_time: DateTime.utc_now(),
        paths: [
          Path.new(%{
            path_id: "sim-uplink-path",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id
          }),
          Path.new(%{
            path_id: "sim-downlink-path",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: "sim-downlink-provider",
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  port: 0,
                  ingress_protocol_family: :tm,
                  frame_size: frame_size,
                  ingress_metadata: %{frame_size: frame_size, ocf_length: 0}
                }
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.persist_realized_contact(organization_id, realized_contact)

    assert {:ok, _pid} =
             Cadence.start_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert {:ok, path_snapshot} =
             Cadence.path_runtime_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               "sim-downlink-path"
             )

    [provider_runtime_snapshot] = path_snapshot.provider_runtimes
    port = provider_runtime_snapshot.port

    assert {:ok, simulator} =
             Coordinator.start_link(
               target_id: persisted_source_endpoint.source_endpoint_id,
               rate_hz: 5.0,
               output: {:tcp, "127.0.0.1", port},
               definitions_content: @definitions,
               provider: DatabaseDynamics,
               frame: %{format: :tm, frame_size: frame_size, scid: 11, vcid: 2}
             )

    on_exit(fn ->
      stop_coordinator(simulator)
    end)

    assert_eventually(fn ->
      persisted_tm_sample?(mission_id)
    end)

    assert %TelemetrySampleRow{} =
             TelemetrySampleRow
             |> where(
               [row],
               row.mission_id == ^mission_id and row.point_name == "TMHK.uptime_seconds"
             )
             |> first()
             |> Repo.one()
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

  defp persisted_tm_sample?(mission_id) do
    TelemetrySampleRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.point_name == "TMHK.uptime_seconds"
    )
    |> Repo.exists?()
  end

  defp stop_coordinator(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Coordinator.stop(pid)
  catch
    :exit, reason when reason in [:noproc, :normal, :shutdown] -> :ok
    :exit, {:noproc, _} -> :ok
    :exit, {:shutdown, _} -> :ok
    :exit, reason -> exit(reason)
  end
end
