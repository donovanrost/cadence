defmodule Cadence.CCSDS.SDLP.TM.SegmentationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.{FrameCodec, Segmentation}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec

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

  test "multi-frame payloads keep fhp zero for the first frame and no idle padding until the last" do
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
    assert second.meta.fhp == 2047
    assert byte_size(first.payload_octets) == frame_size - 6
    assert byte_size(second.payload_octets) == frame_size - 6
    assert next_state.mcfc == 2
    assert next_state.vcfc == 2
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
end
