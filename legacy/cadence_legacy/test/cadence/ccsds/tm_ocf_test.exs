defmodule Cadence.CCSDS.SDLP.TM.OCFTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.{FrameCodec, Segmentation}

  test "segments TM frames with OCF and preserves it on decode" do
    packet = build_space_packet(10, 1)
    ocf = <<1, 2, 3, 4>>
    frame_size = 6 + byte_size(packet) + byte_size(ocf)
    ctx = %{frame_size: frame_size, scid: 1, vcid: 2, ocf: ocf}

    {:ok, seg_state} = Segmentation.init([])

    sdu = %SDUOctets{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil
    }

    assert {:ok, [frame], _next_state} = Segmentation.segment(sdu, ctx, seg_state)
    assert {:ok, encoded} = FrameCodec.encode(frame, frame_size: frame_size)
    assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, frame_size: frame_size)
    assert decoded.ocf == ocf
    assert decoded.meta.ocf_flag == 1
  end

  defp build_space_packet(apid, seq) do
    user_data = <<0xAB>>
    secondary_header = <<0::48, 0::16>>
    packet_length = byte_size(secondary_header <> user_data) - 1

    <<
      0::3,
      0::1,
      1::1,
      apid::11,
      3::2,
      seq::14,
      packet_length::16,
      secondary_header::binary,
      user_data::binary
    >>
  end
end
