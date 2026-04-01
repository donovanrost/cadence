defmodule Cadence.CCSDS.Transport.COP1.CLCWTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Transport.COP1.CLCW

  test "encodes and decodes CLCW fields" do
    clcw = %CLCW{
      control_word_type: 0,
      version: 1,
      status: 5,
      cop_in_effect: 1,
      vcid: 12,
      spare_1: 2,
      no_rf_available: 1,
      no_bit_lock: 0,
      lockout: 1,
      wait: 0,
      retransmit: 1,
      farm_busy: 0,
      spare_2: 3,
      report_value: 200
    }

    {:ok, encoded} = CLCW.encode(clcw)

    expected =
      <<
        0::2,
        1::2,
        5::3,
        1::1,
        12::6,
        2::2,
        1::1,
        0::1,
        1::1,
        0::1,
        1::1,
        0::1,
        3::2,
        200::8
      >>

    assert encoded == expected
    assert {:ok, decoded} = CLCW.decode(encoded)
    assert decoded == clcw
  end

  test "rejects invalid length" do
    assert {:error, :invalid_length} = CLCW.decode(<<1, 2, 3>>)
  end

  test "rejects out-of-range fields" do
    assert {:error, {:invalid_field, :vcid, 70}} = CLCW.encode(%CLCW{vcid: 70})
  end
end
