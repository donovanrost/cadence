defmodule Cadence.CCSDS.USLPOnlyIdleDataTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLP.USLP.OnlyIdleData

  @published_prefix <<
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0x6D,
    0xB6,
    0xD8,
    0x61,
    0x45,
    0x1F,
    0x11,
    0xF1,
    0x97,
    0x16,
    0x72,
    0x3C,
    0xBE,
    0x7E,
    0x00,
    0xB1
  >>

  test "matches the published annex-H sequence and remains continuous" do
    {first, state} = OnlyIdleData.take(7)
    {second, state} = OnlyIdleData.take(13, state)
    assert first <> second == @published_prefix
    assert {:ok, ^state} = OnlyIdleData.validate(second, OnlyIdleData.take(7) |> elem(1))
  end

  test "reports the first corrupt octet" do
    <<first, rest::binary>> = @published_prefix

    assert {:error, {:invalid_uslp_only_idle_data, 0}} =
             OnlyIdleData.validate(<<Bitwise.bxor(first, 1), rest::binary>>)
  end
end
