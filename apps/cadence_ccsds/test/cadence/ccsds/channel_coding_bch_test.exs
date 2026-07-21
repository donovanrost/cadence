defmodule Cadence.CCSDS.ChannelCoding.BCHTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.ChannelCoding.BCH

  test "encodes systematic codewords with complemented parity and zero filler" do
    assert {:ok, <<0, 0, 0, 0, 0, 0, 0, 0xFE>>} = BCH.encode(<<0::56>>)
    assert {:ok, <<1, 2, 3, 4, 5, 6, 7, 0x70>>} = BCH.encode(<<1, 2, 3, 4, 5, 6, 7>>)

    assert {:error, {:invalid_bch_information_length, 6}} = BCH.encode(<<0::48>>)
  end

  test "detect mode accepts clean codewords and rejects channel errors" do
    information = <<1, 2, 3, 4, 5, 6, 7>>
    assert {:ok, codeword} = BCH.encode(information)

    assert {:ok, ^information, %{status: :clean, corrected_bit: nil}} =
             BCH.decode(codeword, :detect)

    assert {:error, {:bch_codeword_rejected, %{status: :rejected}}} =
             codeword |> flip_bit(12) |> BCH.decode(:detect)
  end

  test "correct mode repairs one information, parity, or filler-bit error" do
    information = <<0xA5, 2, 3, 4, 5, 6, 7>>
    assert {:ok, codeword} = BCH.encode(information)

    for bit <- [0, 31, 56, 62, 63] do
      assert {:ok, ^information, %{status: :corrected, corrected_bit: ^bit}} =
               codeword |> flip_bit(bit) |> BCH.decode(:correct)
    end
  end

  test "correct mode rejects an uncorrectable two-bit error" do
    assert {:ok, codeword} = BCH.encode(<<1, 2, 3, 4, 5, 6, 7>>)
    corrupted = codeword |> flip_bit(2) |> flip_bit(19)

    assert {:error, {:bch_codeword_rejected, %{status: :rejected}}} =
             BCH.decode(corrupted, :correct)
  end

  defp flip_bit(binary, wire_bit) do
    <<prefix::bitstring-size(^wire_bit), bit::1, suffix::bitstring>> = binary
    <<prefix::bitstring, Bitwise.bxor(bit, 1)::1, suffix::bitstring>>
  end
end
