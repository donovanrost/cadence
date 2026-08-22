defmodule CCSDS.SDLP.TM.SegmentationTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.{FrameCodec, OnlyIdleData, Reassembly, Segmentation}
  alias CCSDS.SpacePacket
  alias CCSDS.SpacePacket.Codec, as: SpacePacketCodec

  test "single-frame payloads are padded with an idle packet and keep fhp at zero" do
    payload = :binary.copy(<<0xAB>>, 16)
    frame_size = 64

    sdu = %SDUOctets{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: payload,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, state} = Segmentation.init([])

    assert {:ok, [frame], next_state} =
             Segmentation.segment(sdu, %{frame_size: frame_size}, state)

    assert frame.meta.fhp == 0
    assert byte_size(frame.payload_octets) == frame_size - 6
    assert binary_part(frame.payload_octets, 0, byte_size(payload)) == payload

    idle_packet = binary_part(frame.payload_octets, byte_size(payload), 42)
    assert {:ok, idle} = SpacePacketCodec.decode(idle_packet)
    assert SpacePacket.idle?(idle)

    assert next_state.mcfc == 1
    assert next_state.vcfc == 1
  end

  test "multi-frame payloads point to an Idle Packet beginning in a continuation frame" do
    frame_size = 32
    payload = :binary.copy(<<0xCD>>, 40)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 5,
      vcid: 1,
      map_id: nil,
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: payload,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, state} = Segmentation.init([])

    assert {:ok, [first, second], next_state} =
             Segmentation.segment(sdu, %{frame_size: frame_size}, state)

    assert first.meta.fhp == 0
    assert second.meta.fhp == 14
    assert byte_size(first.payload_octets) == frame_size - 6
    assert byte_size(second.payload_octets) == frame_size - 6
    assert next_state.mcfc == 2
    assert next_state.vcfc == 2
  end

  test "one through six octet tails spill an Idle Packet into a following frame" do
    frame_size = 26
    max_payload = frame_size - 6

    for tail_size <- 1..6 do
      packet = build_space_packet_of_size(max_payload - tail_size, tail_size)
      sdu = sdu(packet, 7, 3)
      {:ok, state} = Segmentation.init([])

      assert {:ok, [first, second], _state} =
               Segmentation.segment(sdu, %{frame_size: frame_size}, state)

      assert first.meta.fhp == 0
      assert second.meta.fhp == 2047

      framed_stream = first.payload_octets <> second.payload_octets

      idle =
        binary_part(
          framed_stream,
          byte_size(packet),
          byte_size(framed_stream) - byte_size(packet)
        )

      assert byte_size(idle) == max_payload + tail_size
      assert {:ok, idle_packet} = SpacePacketCodec.decode(idle)
      assert SpacePacket.idle?(idle_packet)

      {:ok, reassembly} = Reassembly.init(default_sdu_type: :space_packet)

      assert {:ok, [decoded], reassembly} =
               Reassembly.ingest(first, %{direction: :downlink}, reassembly)

      assert decoded.octets == packet

      assert {:ok, [], _reassembly} =
               Reassembly.ingest(second, %{direction: :downlink}, reassembly)
    end
  end

  test "increments MCFC per Master Channel and VCFC per Virtual Channel" do
    payload = :binary.copy(<<0xAA>>, 20)
    {:ok, state} = Segmentation.init(mcfc: 250, vcfc: 40)

    assert {:ok, [vc1_first], state} =
             Segmentation.segment(sdu(payload, 5, 1), %{frame_size: 26}, state)

    assert vc1_first.meta.mcfc == 250
    assert vc1_first.meta.vcfc == 40

    assert {:ok, [vc2_first], state} =
             Segmentation.segment(sdu(payload, 5, 2), %{frame_size: 26}, state)

    assert vc2_first.meta.mcfc == 251
    assert vc2_first.meta.vcfc == 40

    assert {:ok, [vc1_second], _state} =
             Segmentation.segment(sdu(payload, 5, 1), %{frame_size: 26}, state)

    assert vc1_second.meta.mcfc == 252
    assert vc1_second.meta.vcfc == 41
  end

  test "generates continuous Only Idle Data frames with FHP 2046" do
    {:ok, state} = Segmentation.init([])
    context = %{frame_size: 16, scid: 9, vcid: 2}

    assert {:ok, first, state} = Segmentation.only_idle(context, state)
    assert {:ok, second, _state} = Segmentation.only_idle(context, state)
    assert first.meta.fhp == 2046
    assert second.meta.fhp == 2046

    {expected, _lfsr} = OnlyIdleData.take(20)
    assert first.payload_octets <> second.payload_octets == expected
  end

  test "segment_encode matches frame-by-frame TM encoding" do
    frame_size = 36
    payload = :binary.copy(<<0xEF>>, 40)
    ocf = <<1, 2, 3, 4>>
    ctx = %{frame_size: frame_size, scid: 9, vcid: 3, ocf: ocf, fecf: true}

    sdu = %SDUOctets{
      profile: :tm,
      scid: 9,
      vcid: 3,
      map_id: nil,
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: payload,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, state} = Segmentation.init([])
    {:ok, frames, frame_state} = Segmentation.segment(sdu, ctx, state)

    expected =
      frames
      |> Enum.map(fn frame ->
        {:ok, encoded} =
          FrameCodec.encode(frame, frame_size: frame_size, ocf_length: 4, fecf: true)

        encoded
      end)
      |> IO.iodata_to_binary()

    assert {:ok, encoded, direct_state} =
             Segmentation.segment_encode(sdu, ctx, state, frame_size: frame_size, ocf_length: 4)

    assert IO.iodata_to_binary(encoded) == expected
    assert direct_state == frame_state
  end

  defp sdu(payload, scid, vcid) do
    %SDUOctets{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: payload,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }
  end

  defp build_space_packet_of_size(total_size, sequence_count) do
    data_size = total_size - 6

    <<
      0::3,
      0::1,
      0::1,
      42::11,
      3::2,
      sequence_count::14,
      data_size - 1::16,
      :binary.copy(<<sequence_count>>, data_size)::binary
    >>
  end
end
