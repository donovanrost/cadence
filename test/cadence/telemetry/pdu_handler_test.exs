defmodule Cadence.Telemetry.PDUHandlerTest do
  use Cadence.PureCase, async: true

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Telemetry.PDUHandler

  test "skips cop1 report apids" do
    pdu = %PDU{type: :space_packet, value: %SpacePacket{apid: 10}}

    refute PDUHandler.accepts?(pdu, %{cop1_report_apids: [10]})
    assert PDUHandler.accepts?(pdu, %{cop1_report_apids: [11]})
  end
end
