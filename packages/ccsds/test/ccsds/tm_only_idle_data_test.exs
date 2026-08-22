defmodule CCSDS.SDLP.TM.OnlyIdleDataTest do
  use ExUnit.Case, async: true

  alias CCSDS.SDLP.TM.OnlyIdleData

  test "matches the annex D published prefix" do
    expected = <<0xFF, 0xFF, 0xFF, 0xFF, 0x6D, 0xB6, 0xD8, 0x61, 0x45, 0x1F>>
    assert {^expected, _state} = OnlyIdleData.take(10)
  end

  test "does not restart between subsequent OID data fields" do
    {first, state} = OnlyIdleData.take(7)
    {second, final_state} = OnlyIdleData.take(13, state)
    {combined, expected_final_state} = OnlyIdleData.take(20)

    assert first <> second == combined
    assert final_state == expected_final_state
  end

  test "reports the first mismatched octet" do
    {expected, _state} = OnlyIdleData.take(12)
    <<prefix::binary-size(5), byte, suffix::binary>> = expected
    corrupt = prefix <> <<Bitwise.bxor(byte, 1)>> <> suffix

    assert {:error, {:oid_pn_mismatch, %{offset: 5, expected: ^byte, observed: observed}}} =
             OnlyIdleData.validate(corrupt)

    assert observed != byte
  end
end
