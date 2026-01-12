defmodule Cadence.CCSDS.Uplink.PipelineTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.SDLP.TM.FrameCodec
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.Uplink.Pipeline

  test "encodes SDU octets into TM frame bytes" do
    payload = <<0xDE, 0xAD, 0xBE, 0xEF>>
    frame_size = 6 + byte_size(payload)

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

    opts = [profile: :tm, frame_size: frame_size]
    {:ok, state} = Pipeline.init(opts)

    assert {:ok, encoded, _state} = Pipeline.encode(sdu, %{frame_size: frame_size}, state, opts)
    assert {:ok, [frame], <<>>} = FrameCodec.decode(encoded, frame_size: frame_size)
    assert frame.payload_octets == payload
  end

  test "encodes Space Packet PDU into TM frame bytes" do
    frame_size = 6 + 14

    space_packet = %SpacePacket{
      apid: 5,
      sequence_flags: 3,
      sequence_count: 1,
      version: 0,
      type: 0,
      secondary_header_flag: 1,
      timestamp: ~U[1958-01-02 00:00:00Z],
      target_hash: 1,
      user_data: <<0x01>>
    }

    pdu = %PDU{
      type: :space_packet,
      value: space_packet,
      quality: :good,
      timestamp: nil,
      meta: %{}
    }

    opts = [profile: :tm, frame_size: frame_size]
    {:ok, state} = Pipeline.init(opts)

    assert {:ok, encoded, _state} = Pipeline.encode(pdu, %{frame_size: frame_size}, state, opts)
    assert {:ok, frames, <<>>} = FrameCodec.decode(encoded, frame_size: frame_size)
    assert length(frames) >= 1
    assert Enum.all?(frames, fn frame -> byte_size(frame.payload_octets) == frame_size - 6 end)
    assert Enum.at(frames, 0).meta.fhp == 0
  end
end
