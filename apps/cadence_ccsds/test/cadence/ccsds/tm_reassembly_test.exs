defmodule Cadence.CCSDS.SDLP.TM.ReassemblyTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.TM.Reassembly

  test "extracts SDU octets from a single frame payload" do
    {:ok, state} = Reassembly.init([])

    frame = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 10,
      payload_octets: <<0xAA, 0xBB, 0xCC>>,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 0}
    }

    assert {:ok, [sdu], _state} = Reassembly.ingest(frame, %{direction: :downlink}, state)
    assert sdu.octets == <<0xAA, 0xBB, 0xCC>>
    assert sdu.scid == 1
    assert sdu.vcid == 2
  end

  test "reassembles a space packet that spans multiple frames" do
    {:ok, state} = Reassembly.init(default_sdu_type: :space_packet)

    payload = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
    packet_id = 0
    seq_control = 0
    length = byte_size(payload) - 1
    packet = <<packet_id::16, seq_control::16, length::16>> <> payload

    <<segment1::binary-size(10), segment2::binary>> = packet

    frame1 = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 10,
      payload_octets: segment1,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 0}
    }

    frame2 = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 11,
      payload_octets: segment2,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 2047}
    }

    assert {:ok, [], state} = Reassembly.ingest(frame1, %{direction: :downlink}, state)
    assert {:ok, [sdu], _state} = Reassembly.ingest(frame2, %{direction: :downlink}, state)
    assert sdu.octets == packet
  end
end
