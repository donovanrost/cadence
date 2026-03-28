defmodule Cadence.Simulator.PacketEncoderTest do
  use Cadence.PureCase, async: true

  alias Cadence.Simulator.PacketEncoder

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

    assert binary_part(packet, 14, 3) == <<0, 0, 5>>
  end
end
