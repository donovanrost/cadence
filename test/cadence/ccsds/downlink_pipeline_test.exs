defmodule Cadence.CCSDS.Downlink.PipelineTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.Downlink.Pipeline
  alias Cadence.CCSDS.SDLP.TM.FrameCodec
  alias Cadence.CCSDS.SDU.Mapping
  alias Cadence.Telemetry.Packet

  test "decodes TM frame stream into telemetry packets" do
    packet = build_space_packet(42, 7)
    frame_size = 6 + byte_size(packet)

    frame = build_tm_frame(packet, frame_size, 3, 4)

    mapping = Mapping.new(%{{3, 4, nil, :downlink} => :space_packet})
    opts = [profile: :tm, frame_size: frame_size]
    {:ok, state} = Pipeline.init(opts)

    assert {:ok, [result], _state} = Pipeline.decode(frame, %{}, mapping, state, opts)
    assert %Packet{} = result
    assert result.ccsds_header.apid == 42
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
