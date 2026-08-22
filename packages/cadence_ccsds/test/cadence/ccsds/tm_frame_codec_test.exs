defmodule Cadence.CCSDS.SDLP.TM.FrameCodecTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.TM.{Configuration, FrameCodec, SecondaryHeader}

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

  test "round-trips a managed Transfer Frame Secondary Header" do
    assert {:ok, configuration} =
             Configuration.new(
               frame_size: 32,
               scid: 4,
               vcid: 1,
               secondary_header_source: :virtual_channel,
               secondary_header_length: 4,
               maximum_packet_octets: 128
             )

    assert {:ok, secondary_header} = SecondaryHeader.new(<<1, 2, 3>>)

    frame = %LinkFrame{
      profile: :tm,
      scid: 4,
      vcid: 1,
      frame_seq: 7,
      payload_octets: :binary.copy(<<0xAA>>, 22),
      quality: :good,
      meta: %{mcfc: 9, vcfc: 7, fhp: 0, secondary_header: secondary_header}
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)

    assert {:ok, [decoded], <<>>} =
             FrameCodec.decode(encoded, configuration: configuration)

    assert decoded.payload_octets == frame.payload_octets
    assert decoded.meta.secondary_header == secondary_header
    assert decoded.meta.secondary_header_data == <<1, 2, 3>>
    assert decoded.meta.secondary_header_length == 4

    <<primary::binary-size(6), _id, rest::binary>> = encoded
    malformed = primary <> <<0::2, 4::6>> <> rest

    assert {:ok, [], [anomaly], <<>>} =
             FrameCodec.decode_detailed(malformed, configuration: configuration)

    assert anomaly.metadata.reason == {:incomplete_secondary_header, 5, 4}
  end

  test "round-trips VCA status fields without assigning their semantics" do
    assert {:ok, configuration} =
             Configuration.new(
               frame_size: 20,
               scid: 12,
               vcid: 6,
               data_field_content: :vca_sdu,
               valid_packet_version_numbers: [],
               maximum_packet_octets: nil
             )

    frame = %LinkFrame{
      profile: :tm,
      scid: 12,
      vcid: 6,
      frame_seq: 44,
      payload_octets: :binary.copy(<<0x5A>>, 14),
      quality: :good,
      meta: %{mcfc: 30, vcfc: 44, sync_flag: 1, vca_status_fields: 0x2A55}
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)

    assert {:ok, [decoded], <<>>} =
             FrameCodec.decode(encoded, configuration: configuration)

    assert decoded.meta.data_field_content == :vca_sdu
    assert decoded.meta.sync_flag == 1
    assert decoded.meta.vca_status_fields == 0x2A55
    assert decoded.payload_octets == frame.payload_octets
  end

  test "reports reserved Packet status bits as decode evidence" do
    packet = build_space_packet(10, 3)
    frame_size = 6 + byte_size(packet)
    encoded = build_tm_frame(packet, frame_size, 1, 2)

    <<prefix::bitstring-size(34), _packet_order_flag::1, rest::bitstring>> = encoded
    malformed = <<prefix::bitstring, 1::1, rest::bitstring>>

    assert {:ok, [], [anomaly], <<>>} =
             FrameCodec.decode_detailed(malformed, frame_size: frame_size)

    assert anomaly.metadata.reason == :packet_order_flag_reserved
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
