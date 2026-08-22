defmodule CCSDS.ChannelCoding.RandomizerTest do
  use ExUnit.Case, async: true

  alias CCSDS.ChannelCoding.Randomizer

  test "matches the normative first 40 bits and repeats after 255 bits" do
    assert Randomizer.sequence(5) == <<0xFF, 0x39, 0x9E, 0x5A, 0x68>>

    sequence = Randomizer.sequence(64)
    <<first_255::bitstring-size(255), repeated::1, _rest::bitstring>> = sequence
    <<first::1, _rest::bitstring>> = first_255
    assert repeated == first
  end

  test "is self-inverse and resets for every call" do
    data = 0..255 |> Enum.to_list() |> :binary.list_to_bin()
    randomized = Randomizer.apply(data)

    refute randomized == data
    assert Randomizer.apply(randomized) == data
    assert Randomizer.apply(<<0, 0, 0, 0, 0>>) == <<0xFF, 0x39, 0x9E, 0x5A, 0x68>>
  end
end
