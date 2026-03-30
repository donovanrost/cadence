defmodule Cadence.Runtime.TCPSocketProviderTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact}
  alias Cadence.Persistence.Schemas.{RawEvidenceRow, TelemetrySampleRow, TransferFrameRecordRow}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  test "tcp provider ingests fixed-size TM frames into the active mission runtime" do
    organization_id = "org-tcp-provider"
    mission_id = "mission-tcp-provider-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-tcp-provider",
        mission_id: mission_id,
        display_name: "SC TCP"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-tcp-provider",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "provider/tcp"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-tcp-provider",
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
        binding_set_id: "tcp-provider-basis",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "tcp-provider-telemetry-rule",
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

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "tcp-provider-contact",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [persisted_source_endpoint.source_endpoint_id],
        clock_mode: :live,
        initial_time: DateTime.utc_now(),
        paths: [
          Path.new(%{
            path_id: "tcp-uplink-path",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id
          }),
          Path.new(%{
            path_id: "tcp-downlink-path",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: persisted_source_endpoint.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: "tcp-downlink-provider",
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
               "tcp-downlink-path"
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
      Repo.aggregate(TelemetrySampleRow, :count, :sample_id) == 1
    end)

    assert Repo.aggregate(RawEvidenceRow, :count, :evidence_id) == 2
    assert Repo.aggregate(TransferFrameRecordRow, :count, :frame_record_id) == 2

    assert {:ok, refreshed_snapshot} =
             Cadence.path_runtime_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               "tcp-downlink-path"
             )

    [refreshed_provider_runtime_snapshot] = refreshed_snapshot.provider_runtimes
    assert refreshed_provider_runtime_snapshot.ingress_executor.processed_count == 2
    assert refreshed_provider_runtime_snapshot.ingress_executor.failed_count == 0
    assert refreshed_provider_runtime_snapshot.ingress_persistence_projector.persisted_count == 2
    assert refreshed_provider_runtime_snapshot.ingress_persistence_projector.failed_count == 0

    sample_row =
      TelemetrySampleRow
      |> where([row], row.mission_id == ^mission_id and row.point_name == "TMHK.counter")
      |> Repo.one!()

    assert sample_row.raw_value == %{"value" => 21}
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

    for <<frame::binary-size(frame_size) <- encoded_frames>>, do: frame
  end
end
