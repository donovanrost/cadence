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

  test "generates and validates a managed FECF" do
    packet = build_space_packet(10, 2)
    frame_size = 6 + byte_size(packet) + 2

    frame = %LinkFrame{
      profile: :tm,
      scid: 4,
      vcid: 1,
      payload_octets: packet,
      quality: :good,
      meta: %{fhp: 0}
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, frame_size: frame_size, fecf: true)
    assert byte_size(encoded) == frame_size

    assert {:ok, [decoded], <<>>} =
             FrameCodec.decode(encoded, frame_size: frame_size, fecf: true)

    assert decoded.payload_octets == packet
    assert decoded.meta.fecf_present
    assert is_integer(decoded.meta.fecf)
  end

  test "drops a TM frame whose managed FECF does not validate" do
    packet = build_space_packet(10, 3)
    frame_size = 6 + byte_size(packet) + 2
    encoded = build_tm_frame(packet, frame_size, 1, 2, fecf: true)
    <<prefix::binary-size(7), byte, suffix::binary>> = encoded
    corrupted = prefix <> <<Bitwise.bxor(byte, 0x01)>> <> suffix

    assert {:ok, [], [anomaly], <<>>} =
             FrameCodec.decode_detailed(corrupted, frame_size: frame_size, fecf: true)

    assert anomaly.anomaly_kind == :frame_decode_dropped
    assert {:invalid_fecf, expected, received} = anomaly.metadata.reason
    assert expected != received
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

  defp build_tm_frame(packet, frame_size, scid, vcid, opts \\ []) do
    frame = %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      payload_octets: packet,
      quality: :good,
      meta: %{fhp: 0}
    }

    {:ok, encoded} = FrameCodec.encode(frame, [frame_size: frame_size] ++ opts)
    encoded
  end
end
