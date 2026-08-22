defmodule Cadence.CCSDS.SpacePacketTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.{Codec, Idle, Sequence, Stream}

  test "encodes and decodes the CCSDS primary-header fields" do
    packet =
      SpacePacket.new(%{
        packet_type: :telemetry,
        secondary_header?: false,
        apid: 0x123,
        sequence_flag: :unsegmented,
        sequence_count: 0x42,
        data: <<0xAA, 0xBB, 0xCC>>
      })

    expected = <<0x01, 0x23, 0xC0, 0x42, 0x00, 0x02, 0xAA, 0xBB, 0xCC>>

    assert {:ok, ^expected} = Codec.encode(packet)
    assert {:ok, ^packet} = Codec.decode(expected)
  end

  test "preserves command, secondary-header, and segmentation indicators" do
    encoded = <<0x1C, 0x56, 0x40, 0x05, 0x00, 0x00, 0x7E>>

    assert {:ok, packet} = Codec.decode(encoded)
    assert packet.packet_type == :command
    assert packet.secondary_header?
    assert packet.apid == 0x456
    assert packet.sequence_flag == :first
    assert packet.sequence_count == 5
    assert packet.data == <<0x7E>>
  end

  test "rejects malformed, incomplete, oversized, and trailing packet bytes" do
    assert Codec.encode(SpacePacket.new(%{apid: 1, data: <<>>})) ==
             {:error, {:invalid_field, :data, <<>>}}

    assert Codec.decode(<<0x20, 0, 0xC0, 0, 0, 0, 0>>) ==
             {:error, {:unsupported_version, 1}}

    assert Codec.decode(<<0, 1, 0xC0, 0, 0, 2, 0xAA>>) ==
             {:error, {:truncated_packet, 9, 7}}

    assert Codec.decode(<<0, 1, 0xC0, 0, 0, 0, 0xAA, 0xBB>>) ==
             {:error, {:trailing_bytes, 7, 8}}

    assert Codec.decode_prefix(<<0, 1, 0xC0, 0, 0, 10>>, max_packet_size: 12) ==
             {:error, {:packet_size_exceeds_managed_maximum, 17, 12}}
  end

  test "stream decoder returns complete packets and preserves an incomplete suffix" do
    {:ok, first} =
      Codec.encode(SpacePacket.new(%{apid: 1, sequence_count: 7, data: <<1, 2>>}))

    {:ok, second} =
      Codec.encode(SpacePacket.new(%{apid: 2, sequence_count: 8, data: <<3, 4, 5>>}))

    split_at = byte_size(second) - 2
    <<second_prefix::binary-size(^split_at), second_suffix::binary>> = second

    assert {:ok, [first_packet], ^second_prefix} = Stream.decode(first <> second_prefix)
    assert first_packet.apid == 1

    assert {:ok, [^first], ^second_prefix} = Stream.extract(first <> second_prefix)
    assert {:ok, [second_packet], <<>>} = Stream.decode(second_prefix <> second_suffix)
    assert second_packet.apid == 2
  end

  test "idle helper fills the required size with a repeating mission pattern" do
    assert {:ok, encoded} = Idle.encode(11, pattern: <<0xAA, 0x55>>)
    assert byte_size(encoded) == 11

    assert {:ok, packet} = Codec.decode(encoded)
    assert SpacePacket.idle?(packet)
    refute packet.secondary_header?
    assert packet.data == <<0xAA, 0x55, 0xAA, 0x55, 0xAA>>
  end

  test "sequence helpers keep independent counts per APID and wrap modulo 16384" do
    {first, counters} = Sequence.take(%{}, 1)
    {second, counters} = Sequence.take(counters, 1)
    {other, _counters} = Sequence.take(counters, 2)

    assert {first, second, other} == {0, 1, 0}
    assert Sequence.next(0x3FFF) == 0
  end
end
