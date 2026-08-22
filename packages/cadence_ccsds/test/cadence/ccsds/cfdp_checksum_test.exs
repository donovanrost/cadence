defmodule Cadence.CCSDS.CFDP.ChecksumTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.Checksum

  test "matches the CCSDS modular checksum example" do
    file = 0x00..0x0E |> Enum.to_list() |> :binary.list_to_bin()

    assert Checksum.modular(file) == 0x181C2015
    assert Checksum.compute(0, file) == {:ok, 0x181C2015}
    assert Checksum.compute(15, file) == {:ok, 0}
  end

  test "accumulates offset segments in arbitrary order" do
    file = 0x00..0x0E |> Enum.to_list() |> :binary.list_to_bin()

    segments = [
      {0, binary_part(file, 0, 5)},
      {5, binary_part(file, 5, 4)},
      {9, binary_part(file, 9, 6)}
    ]

    checksum =
      segments
      |> Enum.reverse()
      |> Enum.reduce(0, fn {offset, data}, sum ->
        Checksum.update_modular(sum, offset, data)
      end)

    assert checksum == Checksum.modular(file)
  end

  test "delegates optional checksum types without owning their implementation" do
    assert {:error, {:unsupported_checksum_type, 7}} = Checksum.compute(7, <<1, 2, 3>>)

    assert {:ok, 0x01020307} =
             Checksum.compute(7, <<1, 2, 3>>, provider: Cadence.CCSDS.CFDP.ChecksumTestProvider)
  end
end
