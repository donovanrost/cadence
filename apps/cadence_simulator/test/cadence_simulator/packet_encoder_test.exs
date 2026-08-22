defmodule CadenceSimulator.PacketEncoderTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.PacketEncoder
  alias CCSDS.SpacePacket.Codec

  @definitions """
  version: "1.0.0"
  packets:
    - name: FIRST
      apid: 1
      items:
        - name: count
          bit_offset: 0
          bit_size: 8
          data_type: uint
          endianness: big

    - name: SECOND
      apid: 2
      items:
        - name: mode
          bit_offset: 0
          bit_size: 8
          data_type: uint
          endianness: big
          conversion:
            type: state_table
            states:
              0: "SAFE"
              1: "NOMINAL"

    - name: SPARSE
      apid: 3
      items:
        - name: lead
          bit_offset: 0
          bit_size: 8
          data_type: uint
          endianness: big

        - name: tail
          bit_offset: 16
          bit_size: 8
          data_type: uint
          endianness: big
  """

  test "encode_with_sequence emits only active packets in yaml order" do
    {:ok, encoder} = PacketEncoder.load_string(@definitions)

    {:ok, packets} =
      PacketEncoder.encode_with_sequence(
        encoder,
        "SIM-1",
        %{
          "SECOND.mode" => "NOMINAL",
          "FIRST.count" => 7
        },
        fn _apid -> 0 end
      )

    assert PacketEncoder.packet_names(encoder) == ["FIRST", "SECOND", "SPARSE"]
    assert Enum.map(packets, &elem(&1, 0)) == ["FIRST", "SECOND"]

    assert Enum.all?(packets, fn {_name, binary} ->
             is_binary(binary) and byte_size(binary) > 0
           end)

    [{"FIRST", first}, {"SECOND", second}] = packets
    assert {:ok, first_packet} = Codec.decode(first)
    assert {:ok, second_packet} = Codec.decode(second)
    assert first_packet.packet_type == :telemetry
    assert first_packet.apid == 1
    assert first_packet.sequence_count == 0
    assert first_packet.data == <<7>>
    assert second_packet.apid == 2
    assert second_packet.data == <<1>>
  end

  test "encode_packet_values_with_sequence emits the same packets without rescanning flat values" do
    {:ok, encoder} = PacketEncoder.load_string(@definitions)

    {:ok, packets_from_values} =
      PacketEncoder.encode_with_sequence(
        encoder,
        "SIM-1",
        %{
          "SECOND.mode" => "NOMINAL",
          "FIRST.count" => 7
        },
        fn _apid -> 0 end
      )

    {:ok, packets_from_packet_values} =
      PacketEncoder.encode_packet_values_with_sequence(
        encoder,
        "SIM-1",
        [
          {"FIRST", [7]},
          {"SECOND", ["NOMINAL"]}
        ],
        fn _apid -> 0 end
      )

    assert packets_from_packet_values == packets_from_values
  end

  test "encode_with_sequence ignores unknown values instead of emitting empty packets" do
    {:ok, encoder} = PacketEncoder.load_string(@definitions)

    assert PacketEncoder.encode_with_sequence(
             encoder,
             "SIM-1",
             %{"UNKNOWN.value" => 1},
             fn _apid -> 0 end
           ) == {:ok, []}
  end

  test "encode_with_sequence preserves zero-filled gaps and missing fields" do
    {:ok, encoder} = PacketEncoder.load_string(@definitions)

    {:ok, [{"SPARSE", packet}]} =
      PacketEncoder.encode_with_sequence(
        encoder,
        "SIM-1",
        %{"SPARSE.tail" => 5},
        fn _apid -> 0 end
      )

    assert binary_part(packet, 6, 3) == <<0, 0, 5>>
  end
end
