defmodule CCSDS.ChannelCoding.LDPCTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias CCSDS.ChannelCoding.LDPC

  @row_1_64 <<0x0E69_166B_EF4C_0BC2::64>>
  @row_17_64 <<0x7766_137E_BB24_8418::64>>

  @row_1_256 <<
    0x1D21794A22761FAE_59945014257E130D_74D6054003794014_2DADEB9CA25EF12E::256
  >>

  test "uses the normative generator rows for LDPC(128,64)" do
    first_information_bit = <<0x80, 0, 0, 0, 0, 0, 0, 0>>
    seventeenth_information_bit = <<0, 0, 0x80, 0, 0, 0, 0, 0>>

    assert {:ok, <<^first_information_bit::binary-size(8), @row_1_64::binary>>} =
             LDPC.encode(first_information_bit, :ldpc_128_64)

    assert {:ok, <<^seventeenth_information_bit::binary-size(8), @row_17_64::binary>>} =
             LDPC.encode(seventeenth_information_bit, :ldpc_128_64)
  end

  test "constructs subsequent rows as right circular shifts" do
    second_information_bit = <<0x40, 0, 0, 0, 0, 0, 0, 0>>
    <<row::64>> = @row_1_64
    expected = bor(row >>> 1, band(row, 1) <<< 63)

    assert {:ok, <<^second_information_bit::binary-size(8), ^expected::64>>} =
             LDPC.encode(second_information_bit, :ldpc_128_64)
  end

  test "uses the normative first generator row for LDPC(512,256)" do
    information = <<0x80, 0::size(248)>>

    assert {:ok, <<^information::binary-size(32), @row_1_256::binary>>} =
             LDPC.encode(information, :ldpc_512_256)
  end

  test "decodes clean codewords and corrects one hard-decision error" do
    for code <- [:ldpc_128_64, :ldpc_512_256] do
      information = deterministic_information(LDPC.information_octets(code))
      assert {:ok, codeword} = LDPC.encode(information, code)
      assert LDPC.valid?(codeword, code)

      assert {:ok, ^information, %{status: :clean}} = LDPC.decode(codeword, code)

      for bit <- [0, div(bit_size(codeword), 2), bit_size(codeword) - 1] do
        corrupted = flip_bit(codeword, bit)

        assert {:ok, ^information, %{status: :corrected, corrected_bit: ^bit}} =
                 LDPC.decode(corrupted, code)
      end
    end
  end

  test "rejects uncorrectable hard-decision errors with syndrome evidence" do
    information = deterministic_information(8)
    assert {:ok, codeword} = LDPC.encode(information, :ldpc_128_64)
    corrupted = codeword |> flip_bit(1) |> flip_bit(9)

    assert {:error,
            {:ldpc_codeword_rejected,
             %{status: :rejected, code: :ldpc_128_64, syndrome: syndrome}}} =
             LDPC.decode(corrupted, :ldpc_128_64)

    assert syndrome > 0
  end

  defp deterministic_information(octets) do
    0..(octets - 1) |> Enum.map(&Integer.mod(&1 * 37 + 11, 256)) |> :binary.list_to_bin()
  end

  defp flip_bit(binary, wire_bit) do
    <<prefix::bitstring-size(^wire_bit), bit::1, suffix::bitstring>> = binary
    <<prefix::bitstring, Bitwise.bxor(bit, 1)::1, suffix::bitstring>>
  end
end
