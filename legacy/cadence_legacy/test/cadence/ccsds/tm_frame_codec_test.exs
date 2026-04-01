defmodule Cadence.CCSDS.SDLP.TM.FrameCodecTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.TM.FrameCodec

  test "decodes TM frame into LinkFrame" do
    packet = build_space_packet(10, 1)
    frame_size = 6 + byte_size(packet)
    scid = 1
    vcid = 2

    frame = build_tm_frame(packet, frame_size, scid, vcid)

    assert {:ok, [link], <<>>} = FrameCodec.decode(frame, frame_size: frame_size)
    assert link.profile == :tm
    assert link.scid == scid
    assert link.vcid == vcid
    assert link.payload_octets == packet
    assert link.meta.fhp == 0
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

  defp build_tm_frame(packet, frame_size, scid, vcid) do
    frame = %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      payload_octets: packet,
      quality: :good,
      meta: %{fhp: 0}
    }

    {:ok, encoded} = FrameCodec.encode(frame, frame_size: frame_size)
    encoded
  end
end
