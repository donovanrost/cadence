defmodule Cadence.Runtime.MissionCoordinatorTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  setup do
    mission_id = "mission-runtime-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      Runtime.stop_mission(mission_id)
    end)

    %{mission_id: mission_id}
  end

  test "processes ingress against the active mission runtime and reconciles partition owners on activation changes",
       %{mission_id: mission_id} do
    source_endpoint = persist_source_endpoint(mission_id)
    binding_set_v1 = persisted_binding_set(mission_id, 1, "HK")
    binding_set_v2 = persisted_binding_set(mission_id, 2, "THERMAL")

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               binding_set_v1.binding_set_id,
               binding_set_v1.version
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, result_v1} = Cadence.process_telemetry_ingress(raw_evidence)
    assert Enum.map(result_v1.outputs, & &1.point_name) == ["HK.counter"]
    assert result_v1.raw_evidence.source_endpoint_ref == source_endpoint.source_endpoint_id

    assert {:ok, partition_snapshot_v1} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert partition_snapshot_v1.binding_set_version == 1

    assert partition_snapshot_v1.partition_key ==
             "source_endpoint:" <> source_endpoint.source_endpoint_id

    assert partition_snapshot_v1.rule_count == 1

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               binding_set_v2.binding_set_id,
               binding_set_v2.version
             )

    assert {:ok, result_v2} = Cadence.process_telemetry_ingress(raw_evidence)
    assert Enum.map(result_v2.outputs, & &1.point_name) == ["THERMAL.counter"]

    assert {:ok, partition_snapshot_v2} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert partition_snapshot_v2.binding_set_version == 2
    assert partition_snapshot_v2.handler_keys == [:definition_bound_telemetry]
  end

  test "instantiates only mission-default and matching endpoint-scoped rules in each partition",
       %{mission_id: mission_id} do
    source_endpoint_alpha =
      persist_source_endpoint(mission_id, "endpoint-sc-alpha", "sc-alpha", "provider/station-a")

    source_endpoint_beta =
      persist_source_endpoint(mission_id, "endpoint-sc-beta", "sc-beta", "provider/station-b")

    mission_definition =
      packet_definition(mission_id, "mission-default", "MISSION", 42, 1)

    beta_definition =
      packet_definition(mission_id, "beta-specific", "BETA", 42, 1)

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "runtime-scope-basis",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "mission-default-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: mission_definition
          }),
          BindingRule.new(%{
            binding_rule_id: "beta-specific-rule",
            handler_key: :definition_bound_telemetry,
            source_endpoint_ref: source_endpoint_beta.source_endpoint_id,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: beta_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    alpha_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    beta_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-b",
        raw: build_space_packet(42, 2, <<0, 9>>)
      })

    assert {:ok, alpha_result} = Cadence.process_telemetry_ingress(alpha_evidence)
    assert Enum.map(alpha_result.outputs, & &1.point_name) == ["MISSION.counter"]

    assert {:ok, beta_result} = Cadence.process_telemetry_ingress(beta_evidence)
    assert Enum.map(beta_result.outputs, & &1.point_name) == ["BETA.counter"]

    assert {:ok, alpha_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint_alpha.source_endpoint_id)

    assert alpha_snapshot.rule_count == 1

    assert {:ok, beta_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint_beta.source_endpoint_id)

    assert beta_snapshot.rule_count == 2
  end

  test "reassembles TM transfer frames across ingress calls inside the active partition",
       %{mission_id: mission_id} do
    source_endpoint = persist_source_endpoint(mission_id)
    binding_set = persisted_binding_set(mission_id, 1, "TMHK")
    frame_size = 10
    [frame_one, frame_two] = build_tm_space_packet_frames(42, 5, <<0, 11>>, frame_size)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "provider/station-a",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: frame_one
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "provider/station-a",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: frame_two
      })

    assert {:ok, first_result} = Cadence.process_telemetry_ingress(raw_evidence_one)
    assert first_result.packet_records == []
    assert first_result.dispatch_decisions == []
    assert length(first_result.transfer_frame_records) == 1
    assert first_result.protocol_anomalies == []
    assert first_result.outputs == []

    assert {:ok, first_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert first_snapshot.tm_packet_buffer_vcid_count == 1
    assert first_snapshot.tm_frame_remainder_bytes == 0

    assert {:ok, second_result} = Cadence.process_telemetry_ingress(raw_evidence_two)
    [packet_record] = second_result.packet_records
    [dispatch_decision] = second_result.dispatch_decisions

    assert length(second_result.transfer_frame_records) == 1
    assert second_result.protocol_anomalies == []
    assert Enum.map(second_result.outputs, & &1.point_name) == ["TMHK.counter"]
    assert packet_record.apid == 42
    assert dispatch_decision.status == :matched
    assert packet_record.protocol_family == :tm

    assert {:ok, second_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert second_snapshot.tm_packet_buffer_vcid_count == 0
    assert second_snapshot.tm_frame_remainder_bytes == 0
  end

  defp persisted_binding_set(mission_id, version, packet_name) do
    packet_definition =
      packet_definition(
        mission_id,
        "packet-" <> Integer.to_string(version),
        packet_name,
        42,
        version
      )

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "runtime-basis",
        version: version,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "telemetry-rule-" <> Integer.to_string(version),
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)
    binding_set
  end

  defp persist_source_endpoint(mission_id) do
    persist_source_endpoint(mission_id, "endpoint-sc-alpha", "sc-alpha", "provider/station-a")
  end

  defp persist_source_endpoint(mission_id, source_endpoint_id, spacecraft_id, source_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: spacecraft_id,
        mission_id: mission_id,
        display_name: spacecraft_id
      })

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        source_ref: source_ref
      })

    assert {:ok, persisted_source_endpoint} = Cadence.persist_source_endpoint(source_endpoint)
    persisted_source_endpoint
  end

  defp packet_definition(mission_id, packet_definition_id, packet_name, apid, version) do
    PacketDefinition.new(%{
      mission_id: mission_id,
      packet_definition_id: packet_definition_id,
      packet_name: packet_name,
      apid: apid,
      version: version,
      fields: [
        %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
      ]
    })
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
