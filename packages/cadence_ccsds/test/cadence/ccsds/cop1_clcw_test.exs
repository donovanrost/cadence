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
        farm_b_counter: 2,
        report_value: 17
      })

    assert {:ok, encoded} = CLCW.encode(clcw)
    assert {:ok, decoded} = CLCW.decode(encoded)
    assert decoded.vcid == 3
    assert decoded.retransmit == 1
    assert decoded.farm_b_counter == 2
    assert decoded.report_value == 17
  end

  test "uses the CCSDS CLCW bit layout" do
    clcw =
      CLCW.new(%{
        control_word_type: 0,
        version: 0,
        status: 5,
        cop_in_effect: 1,
        vcid: 17,
        spare_1: 0,
        no_rf_available: 1,
        no_bit_lock: 0,
        lockout: 1,
        wait: 0,
        retransmit: 1,
        farm_b_counter: 2,
        spare_2: 0,
        report_value: 99
      })

    assert {:ok,
            <<
              0::1,
              0::2,
              5::3,
              1::2,
              17::6,
              0::2,
              1::1,
              0::1,
              1::1,
              0::1,
              1::1,
              2::2,
              0::1,
              99::8
            >>} = CLCW.encode(clcw)
  end
end
