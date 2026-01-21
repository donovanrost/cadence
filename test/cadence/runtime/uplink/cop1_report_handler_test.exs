defmodule Cadence.Runtime.Transport.COP1.ReportHandlerTest do
  use Cadence.PureCase, async: true

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.ReportHandler

  test "accepts when apid is configured for reports" do
    pdu = %PDU{type: :space_packet, value: %SpacePacket{apid: 42}}

    assert ReportHandler.accepts?(pdu, %{cop1_report_apids: MapSet.new([42])})
    refute ReportHandler.accepts?(pdu, %{cop1_report_apids: [7]})
  end

  test "decodes clcw payload and ingests report" do
    clcw = %CLCW{vcid: 3, report_value: 7}
    {:ok, payload} = CLCW.encode(clcw)

    pdu = %PDU{type: :space_packet, value: %SpacePacket{apid: 42, user_data: payload}}

    ctx = %{
      mission_id: "mission-1",
      interface_id: "iface-1",
      cop1_report_apids: [42]
    }

    ingest_fun = fn mission_id, interface_id, report ->
      send(self(), {:ingest, mission_id, interface_id, report})
    end

    {:ok, state} = ReportHandler.init(cop1_ingest_fun: ingest_fun)

    assert ReportHandler.accepts?(pdu, ctx)
    assert {:ok, [], ^state} = ReportHandler.handle_pdu(pdu, ctx, state)

    assert_receive {:ingest, "mission-1", "iface-1", %CLCW{vcid: 3, report_value: 7}}
  end
end
