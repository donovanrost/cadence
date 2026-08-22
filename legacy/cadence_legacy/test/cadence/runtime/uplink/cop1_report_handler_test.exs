defmodule Cadence.Runtime.Transport.COP1.ReportHandlerTest do
  use Cadence.PureCase, async: true

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.ReportHandler
  alias Cadence.Runtime.Transport.ProtocolEvent
  alias Cadence.Transport.TCStreamId

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
      transport_id: "transport-1",
      scid: 12,
      vcid: 3,
      cop1_report_apids: [42]
    }

    ingest_fun = fn report ->
      send(self(), {:ingest, report})
    end

    {:ok, state} = ReportHandler.init(cop1_ingest_fun: ingest_fun)

    assert ReportHandler.accepts?(pdu, ctx)
    assert {:ok, [], ^state} = ReportHandler.handle_pdu(pdu, ctx, state)

    assert_receive {:ingest, report}

    assert report.tc_stream_id ==
             TCStreamId.new!("mission-1", "transport-1", 12, 3)
  end

  test "vcid mismatch reports decode failure and records metric" do
    clcw = %CLCW{vcid: 3, report_value: 1}
    {:ok, payload} = CLCW.encode(clcw)

    pdu = %PDU{type: :space_packet, value: %SpacePacket{apid: 42, user_data: payload}}

    ctx = %{
      mission_id: "mission-2",
      transport_id: "transport-2",
      scid: 5,
      vcid: 2,
      cop1_report_apids: [42]
    }

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:mission-2:events")

    ingest_fun = fn report ->
      send(self(), {:ingest, report})
    end

    {:ok, state} = ReportHandler.init(cop1_ingest_fun: ingest_fun)

    assert ReportHandler.accepts?(pdu, ctx)
    assert {:skip, :vcid_mismatch, ^state} = ReportHandler.handle_pdu(pdu, ctx, state)

    refute_receive {:ingest, _report}
    assert_receive {:protocol_event, %ProtocolEvent{status: :cop1_report_decode_failed}}

    key = {"mission-2", "transport-2", 5, 2, :cop1_report_decode_failures_total}
    assert [{^key, 1}] = :ets.lookup(:cadence_cop1_metrics, key)
  end
end
