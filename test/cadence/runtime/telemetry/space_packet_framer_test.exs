defmodule Cadence.Runtime.Telemetry.SpacePacketFramerTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Cadence.Runtime.Telemetry.SpacePacketFramer

  describe "ingest/2" do
    test "returns a single packet when the buffer contains a full space packet" do
      packet = build_packet(:crypto.strong_rand_bytes(12))

      {packets, state, errors} = SpacePacketFramer.ingest(SpacePacketFramer.new(), packet)

      assert packets == [packet]
      assert state.buffer == <<>>
      assert errors == []
    end

    test "accumulates fragments across ingests" do
      packet = build_packet(:crypto.strong_rand_bytes(20))
      <<chunk1::binary-size(4), chunk2::binary>> = packet

      {packets1, state1, errors1} = SpacePacketFramer.ingest(SpacePacketFramer.new(), chunk1)
      {packets2, state2, errors2} = SpacePacketFramer.ingest(state1, chunk2)

      assert packets1 == []
      assert packets2 == [packet]
      assert state2.buffer == <<>>
      assert errors1 == []
      assert errors2 == []
    end

    test "returns multiple packets when available" do
      packet1 = build_packet(<<1, 2, 3, 4>>)
      packet2 = build_packet(<<5, 6, 7, 8, 9>>)

      {packets, state, errors} =
        SpacePacketFramer.ingest(SpacePacketFramer.new(), packet1 <> packet2)

      assert packets == [packet1, packet2]
      assert state.buffer == <<>>
      assert errors == []
    end
  end

  defp build_packet(payload) do
    apid = 0x01
    seq_count = 0x002A
    packet_id = 0 <<< 13 ||| 0 <<< 12 ||| 1 <<< 11 ||| apid
    seq_control = 3 <<< 14 ||| seq_count
    packet_length = byte_size(payload) - 1

    <<packet_id::16, seq_control::16, packet_length::16, payload::binary>>
  end
end
