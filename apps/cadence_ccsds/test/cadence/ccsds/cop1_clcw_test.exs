defmodule Cadence.CCSDS.Transport.COP1.CLCWTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Transport.COP1.CLCW

  test "encodes and decodes a CLCW" do
    clcw =
      CLCW.new(%{
        control_word_type: 0,
        version: 0,
        status: 0,
        cop_in_effect: 1,
        vcid: 3,
        no_rf_available: 0,
        no_bit_lock: 0,
        lockout: 0,
        wait: 0,
        retransmit: 1,
        farm_busy: 0,
        report_value: 17
      })

    assert {:ok, encoded} = CLCW.encode(clcw)
    assert {:ok, decoded} = CLCW.decode(encoded)
    assert decoded.vcid == 3
    assert decoded.retransmit == 1
    assert decoded.report_value == 17
  end
end
