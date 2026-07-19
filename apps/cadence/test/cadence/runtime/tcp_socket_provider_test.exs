defmodule Cadence.Runtime.TCPSocketProviderTest do
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact}
  alias Cadence.Persistence.Schemas.{RawEvidenceRow, TelemetrySampleRow, TransferFrameRecordRow}
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  test "tcp provider ingests fixed-size TM frames into the active mission runtime" do
    organization_id = unique_id("org-tcp-provider")
    fixture_id = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-tcp-provider-" <> fixture_id

    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-tcp-provider-" <> fixture_id,
        mission_id: mission_id,
        display_name: "SC TCP"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-tcp-provider-" <> fixture_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "provider/tcp"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-tcp-provider-" <> fixture_id,
        packet_name: "TMHK",
        apid: 42,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "tcp-provider-basis-" <> fixture_id,
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "tcp-provider-telemetry-rule-" <> fixture_id,
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
               activated_by: %{"service_identity_id" => "svc-test"}
             )

    frame_size = 10
    downlink_path_id = "tcp-downlink-path-" <> fixture_id
    provider_binding_id = "tcp-downlink-provider-" <> fixture_id

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "tcp-provider-contact-" <> fixture_id,
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [persisted_source_endpoint.source_endpoint_id],
        clock_mode: :live,
        initial_time: DateTime.utc_now(),
        paths: [
          Path.new(%{
            path_id: "tcp-uplink-path-" <> fixture_id,
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id
          }),
          Path.new(%{
            path_id: downlink_path_id,
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: provider_binding_id,
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  port: 0,
                  ingress_protocol_family: :tm,
                  frame_size: frame_size,
                  ingress_metadata: %{
                    frame_size: frame_size,
                    ocf_length: 0
                  }
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
               downlink_path_id
             )

    assert path_snapshot.provider_runtime_count == 1
    [provider_runtime_snapshot] = path_snapshot.provider_runtimes
    port = provider_runtime_snapshot.port
    assert is_integer(port) and port > 0
    assert provider_runtime_snapshot.ingress_executor.queue_depth == 0
    assert provider_runtime_snapshot.ingress_executor.failed_count == 0
    assert provider_runtime_snapshot.ingress_persistence_projector.queue_depth == 0
    assert provider_runtime_snapshot.ingress_persistence_projector.failed_count == 0

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    [frame_one, frame_two] = build_tm_space_packet_frames(42, 4, <<0, 21>>, frame_size)
    assert :ok = :gen_tcp.send(socket, frame_one <> frame_two)

    assert_eventually(fn ->
      count_for_mission(TelemetrySampleRow, :sample_id, mission_id) == 1
    end)

    assert count_for_mission(RawEvidenceRow, :evidence_id, mission_id) == 2
    assert count_for_mission(TransferFrameRecordRow, :frame_record_id, mission_id) == 2

    assert {:ok, refreshed_snapshot} =
             Cadence.path_runtime_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               downlink_path_id
             )

    [refreshed_provider_runtime_snapshot] = refreshed_snapshot.provider_runtimes
    assert refreshed_provider_runtime_snapshot.ingress_executor.processed_count == 2
    assert refreshed_provider_runtime_snapshot.ingress_executor.failed_count == 0
    assert refreshed_provider_runtime_snapshot.ingress_persistence_projector.persisted_count == 2
    assert refreshed_provider_runtime_snapshot.ingress_persistence_projector.failed_count == 0
    assert refreshed_provider_runtime_snapshot.tcp_read_count >= 1
    assert refreshed_provider_runtime_snapshot.avg_tcp_read_bytes > 0.0

    sample_row =
      TelemetrySampleRow
      |> where([row], row.mission_id == ^mission_id and row.point_name == "TMHK.counter")
      |> Repo.one!()

    assert sample_row.raw_value == %{"value" => 21}

    [frame_three, frame_four] = build_tm_space_packet_frames(42, 5, <<0, 22>>, frame_size)
    assert :ok = :gen_tcp.send(socket, frame_three <> frame_four)

    assert_eventually(fn ->
      count_for_mission(TelemetrySampleRow, :sample_id, mission_id) == 2
    end)

    assert {:ok, final_snapshot} =
             Cadence.path_runtime_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               downlink_path_id
             )

    [final_provider_runtime_snapshot] = final_snapshot.provider_runtimes
    assert final_provider_runtime_snapshot.downlink_message_count == 4
    assert final_provider_runtime_snapshot.tcp_read_count >= 2
    assert final_provider_runtime_snapshot.ingress_executor.processed_count == 4
    assert final_provider_runtime_snapshot.ingress_persistence_projector.persisted_count == 4
  end

  test "tcp provider listen mode recovers when the socket receiver exits unexpectedly" do
    organization_id = unique_id("org-tcp-provider")
    fixture_id = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-tcp-provider-" <> fixture_id

    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-tcp-provider-" <> fixture_id,
        mission_id: mission_id,
        display_name: "SC TCP"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-tcp-provider-" <> fixture_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "provider/tcp"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-tcp-provider-" <> fixture_id,
        packet_name: "TMHK",
        apid: 42,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "tcp-provider-basis-" <> fixture_id,
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "tcp-provider-telemetry-rule-" <> fixture_id,
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
               activated_by: %{"service_identity_id" => "svc-test"}
             )

    frame_size = 10
    path_id = "tcp-downlink-path-" <> fixture_id
    provider_binding_id = "tcp-downlink-provider-" <> fixture_id

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "tcp-provider-contact-" <> fixture_id,
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [persisted_source_endpoint.source_endpoint_id],
        clock_mode: :live,
        initial_time: DateTime.utc_now(),
        paths: [
          Path.new(%{
            path_id: "tcp-uplink-path-" <> fixture_id,
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id
          }),
          Path.new(%{
            path_id: path_id,
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: provider_binding_id,
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  port: 0,
                  ingress_protocol_family: :tm,
                  frame_size: frame_size,
                  ingress_metadata: %{
                    frame_size: frame_size,
                    ocf_length: 0
                  }
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
               path_id
             )

    [provider_runtime_snapshot] = path_snapshot.provider_runtimes
    port = provider_runtime_snapshot.port
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    provider_name =
      MissionRuntime.provider_runtime_name(
        mission_id,
        realized_contact.realized_contact_id,
        path_id,
        provider_binding_id
      )

    assert_eventually(fn ->
      provider_name
      |> :sys.get_state()
      |> Map.fetch!(:socket_receiver_pid)
      |> is_pid()
    end)

    receiver_pid = provider_name |> :sys.get_state() |> Map.fetch!(:socket_receiver_pid)
    assert is_pid(receiver_pid)

    Process.exit(receiver_pid, :kill)

    assert_eventually(fn ->
      {:ok, snapshot} =
        Cadence.path_runtime_snapshot(
          organization_id,
          mission_id,
          realized_contact.realized_contact_id,
          path_id
        )

      [provider_snapshot] = snapshot.provider_runtimes
      provider_snapshot.connected? == false and is_binary(provider_snapshot.last_ingress_error)
    end)

    :gen_tcp.close(socket)

    {:ok, replacement_socket} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])

    on_exit(fn ->
      :gen_tcp.close(replacement_socket)
    end)

    [frame_one, frame_two] = build_tm_space_packet_frames(42, 4, <<0, 21>>, frame_size)
    assert :ok = :gen_tcp.send(replacement_socket, frame_one <> frame_two)

    assert_eventually(fn ->
      count_for_mission(TelemetrySampleRow, :sample_id, mission_id) == 1
    end)

    assert {:ok, recovered_snapshot} =
             Cadence.path_runtime_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               path_id
             )

    [recovered_provider_runtime_snapshot] = recovered_snapshot.provider_runtimes
    assert recovered_provider_runtime_snapshot.connected? == true
    assert recovered_provider_runtime_snapshot.downlink_message_count == 2
    assert recovered_provider_runtime_snapshot.ingress_executor.processed_count == 2
    assert recovered_provider_runtime_snapshot.ingress_persistence_projector.persisted_count == 2
  end

  test "tcp backpressure waits on executor capacity notifications instead of sleeping" do
    source =
      __DIR__
      |> Elixir.Path.join("../../../lib/cadence/provider_adapters/tcp_socket.ex")
      |> Elixir.Path.expand()
      |> File.read!()

    refute source =~ "Process.sleep"
    refute source =~ "@backpressure_poll_ms"
    assert source =~ "ProviderIngressExecutor.notify_when_below"
    assert source =~ ":provider_ingress_capacity_available"
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

  defp unique_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp count_for_mission(schema, field, mission_id) do
    schema
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.aggregate(:count, field)
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end

  defp build_tm_space_packet_frames(apid, sequence_count, packet_data, frame_size) do
    packet = build_space_packet(apid, sequence_count, packet_data)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init([])

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    for <<frame::binary-size(^frame_size) <- encoded_frames>>, do: frame
  end
end
