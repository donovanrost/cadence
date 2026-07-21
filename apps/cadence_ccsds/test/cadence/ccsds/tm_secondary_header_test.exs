defmodule Cadence.CCSDS.SDLP.TM.SecondaryHeaderTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLP.TM.SecondaryHeader

  test "encodes the version and total length and preserves trailing input" do
    assert {:ok, header} = SecondaryHeader.new(<<1, 2, 3>>)
    assert {:ok, <<0::2, 3::6, 1, 2, 3>>} = SecondaryHeader.encode(header)

    assert {:ok, ^header, <<9, 8>>} =
             SecondaryHeader.decode(<<0::2, 3::6, 1, 2, 3, 9, 8>>)
  end

  test "supports the full normative two through 64 octet range" do
    for data_length <- 1..63 do
      data = :binary.copy(<<data_length>>, data_length)
      assert {:ok, header} = SecondaryHeader.new(data)
      assert {:ok, encoded} = SecondaryHeader.encode(header)
      assert byte_size(encoded) == data_length + 1
      assert {:ok, ^header} = SecondaryHeader.decode_exact(encoded)
    end
  end

  test "rejects unsupported versions and inconsistent lengths" do
    assert {:error, {:unsupported_secondary_header_version, 1}} =
             SecondaryHeader.decode_exact(<<1::2, 1::6, 0>>)

    assert {:error, {:invalid_secondary_header_length, 1}} =
             SecondaryHeader.decode_exact(<<0::2, 0::6>>)

    assert {:error, {:incomplete_secondary_header, 4, 2}} =
             SecondaryHeader.decode_exact(<<0::2, 3::6, 1>>)
  end
end
