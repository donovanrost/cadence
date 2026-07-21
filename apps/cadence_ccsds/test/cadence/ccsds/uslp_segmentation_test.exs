defmodule Cadence.CCSDS.USLPSegmentationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.USLP.{Configuration, FrameCodec, Segmentation}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec

  test "segments variable-length MAP access data and advances each QoS counter independently" do
    configuration =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 16,
        scid: 100,
        vcid: 4,
        map_id: 2,
        sequence_count_octets: 1,
        expedited_count_octets: 2,
        data_field_content: :mapa_sdu
      )

    {:ok, state} = Segmentation.init(sequence_count: 254, expedited_count: 65_534)
    sdu = sdu(:mapa_sdu, :binary.copy(<<0xAA>>, 20), configuration)

    assert {:ok, sequence_frames, state} =
             Segmentation.segment(sdu, %{configuration: configuration}, state)

    assert Enum.map(sequence_frames, & &1.meta.construction_rule) == [
             :start_segment,
             :continue_segment,
             :last_segment
           ]

    assert Enum.map(sequence_frames, & &1.frame_seq) == [254, 255, 0]

    assert {:ok, expedited_frames, _state} =
             Segmentation.segment(
               %{sdu | octets: <<1, 2>>},
               %{configuration: configuration, qos: :expedited},
               state
             )

    assert Enum.map(expedited_frames, & &1.frame_seq) == [65_534]
    assert hd(expedited_frames).meta.construction_rule == :unsegmented
  end

  test "fixed access frames carry LVO, idle fill, Insert Zone, OCF, and FECF" do
    configuration =
      Configuration.new!(
        frame_type: :fixed,
        frame_size: 28,
        scid: 1,
        vcid: 2,
        map_id: 3,
        insert_zone_length: 2,
        fecf?: true,
        ocf?: true,
        data_field_content: :mapa_sdu
      )

    {:ok, state} = Segmentation.init()
    sdu = sdu(:mapa_sdu, :binary.copy(<<0x11>>, 15), configuration)

    assert {:ok, frames, _state} =
             Segmentation.segment(
               sdu,
               %{
                 configuration: configuration,
                 insert_zone_sdus: [<<1, 2>>, <<3, 4>>],
                 ocf_sdus: [<<5, 6, 7, 8>>, <<9, 10, 11, 12>>],
                 idle_pattern: <<0xEE>>
               },
               state
             )

    assert length(frames) == 2

    assert Enum.map(frames, & &1.meta.construction_rule) == [
             :start_access_sdu,
             :continue_access_sdu
           ]

    assert Enum.map(frames, & &1.meta.tfdf_pointer) == [0xFFFF, 5]
    assert :binary.last(List.last(frames).payload_octets) == 0xEE

    assert Enum.all?(frames, fn frame ->
             match?(
               {:ok, encoded} when byte_size(encoded) == 28,
               FrameCodec.encode(frame, configuration: configuration)
             )
           end)
  end

  test "fixed packet generation inserts a Space Packet Idle Packet and correct FHPs" do
    configuration =
      Configuration.new!(
        frame_type: :fixed,
        frame_size: 24,
        scid: 1,
        vcid: 2,
        map_id: 3
      )

    packet = space_packet(20)
    {:ok, state} = Segmentation.init()

    assert {:ok, frames, _state} =
             Segmentation.segment(
               sdu(:space_packet, packet, configuration),
               %{configuration: configuration},
               state
             )

    assert Enum.map(frames, & &1.meta.tfdf_pointer) == [0, 7, 0xFFFF]
    assert Enum.all?(frames, &(byte_size(&1.payload_octets) == 13))
  end

  test "truncated generation enforces the managed expedited size" do
    configuration =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 64,
        scid: 1,
        vcid: 2,
        map_id: 3,
        data_field_content: :mapa_sdu,
        truncated_frame_length: 10
      )

    {:ok, state} = Segmentation.init()

    assert {:ok, [frame], ^state} =
             Segmentation.segment(
               sdu(:mapa_sdu, <<1, 2, 3, 4, 5>>, configuration),
               %{configuration: configuration, qos: :expedited, truncated?: true},
               state
             )

    assert frame.meta.truncated?
    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    assert byte_size(encoded) == 10
  end

  test "OID frames use the continuous annex-H sequence on each physical channel" do
    configuration =
      Configuration.new!(
        physical_channel: "return",
        frame_type: :fixed,
        frame_size: 20,
        scid: 1,
        vcid: 63,
        map_id: 0,
        data_field_content: :idle_data
      )

    {:ok, state} = Segmentation.init()
    assert {:ok, first, state} = Segmentation.only_idle(%{configuration: configuration}, state)
    assert {:ok, second, _state} = Segmentation.only_idle(%{configuration: configuration}, state)

    assert first.payload_octets <> second.payload_octets ==
             <<
               0xFF,
               0xFF,
               0xFF,
               0xFF,
               0x6D,
               0xB6,
               0xD8,
               0x61,
               0x45,
               0x1F,
               0x11,
               0xF1,
               0x97,
               0x16,
               0x72,
               0x3C,
               0xBE,
               0x7E
             >>

    assert first.frame_seq == 0
    assert second.frame_seq == 1
    assert {:ok, _wire} = FrameCodec.encode(first, configuration: configuration)
  end

  defp sdu(kind, octets, configuration) do
    %SDUOctets{
      profile: :uslp,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      direction: :uplink,
      sdu_kind_hint: kind,
      octets: octets,
      quality: :good,
      source_frames: [],
      meta: %{}
    }
  end

  defp space_packet(total_octets) do
    packet =
      SpacePacket.new(%{
        packet_type: :command,
        secondary_header?: false,
        apid: 7,
        sequence_flag: :unsegmented,
        sequence_count: 1,
        data: :binary.copy(<<0xAB>>, total_octets - 6)
      })

    {:ok, encoded} = SpacePacketCodec.encode(packet)
    encoded
  end
end
