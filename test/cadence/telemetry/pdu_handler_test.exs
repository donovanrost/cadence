defmodule Cadence.Telemetry.PDUHandlerTest do
  use Cadence.PureCase, async: true

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Telemetry.PDUHandler

  test "skips cop1 report apids" do
    pdu = %PDU{type: :space_packet, value: %SpacePacket{apid: 10}}

    refute PDUHandler.accepts?(pdu, %{cop1_report_apids: [10]})
    assert PDUHandler.accepts?(pdu, %{cop1_report_apids: [11]})
  end

  test "builds envelope evidence in stable order and omits nil values" do
    raw = <<1, 2, 3>>

    pdu = %PDU{
      type: :space_packet,
      quality: :good,
      value: %SpacePacket{apid: 42, raw: raw}
    }

    sdu = %SDUOctets{
      scid: 100,
      vcid: 2,
      map_id: nil,
      octets: raw,
      source_frames: []
    }

    received_at = ~U[2026-03-27 18:00:00Z]

    ctx = %{
      mission_id: "mission-1",
      transport_id: "transport-1",
      config_version: 7,
      sdu: sdu,
      base_meta: %{
        received_at: received_at,
        ingest_monotonic_ns: 123,
        target_id: "target-1",
        source: :udp,
        link_key: "link-a",
        channel_key: "channel-a",
        source_frames: [77],
        mode: :realtime
      }
    }

    assert {:ok, [envelope], %{}} = PDUHandler.handle_pdu(pdu, ctx, %{})

    assert envelope.mission_id == "mission-1"
    assert envelope.raw == raw
    assert envelope.ingest_ts == received_at
    assert envelope.ingest_monotonic_ns == 123
    assert envelope.quality == :good

    assert envelope.provenance == %{
             transport_id: "transport-1",
             source: :udp,
             link_key: "link-a",
             channel_key: "channel-a",
             source_frames: []
           }

    assert Enum.map(envelope.evidence, &{&1.kind, &1.value}) == [
             {:scid, 100},
             {:vcid, 2},
             {:transport_id, "transport-1"},
             {:apid, 42},
             {:target_hint, "target-1"}
           ]
  end

  test "uses metadata transport_id only for provenance fallback" do
    raw = <<4, 5, 6>>

    pdu = %PDU{
      type: :space_packet,
      value: %SpacePacket{apid: 9, raw: raw}
    }

    sdu = %SDUOctets{
      scid: 22,
      vcid: 3,
      map_id: 7,
      octets: raw,
      source_frames: [11]
    }

    ctx = %{
      mission_id: "mission-2",
      sdu: sdu,
      base_meta: %{
        transport_id: "transport-fallback",
        source_frames: [99]
      }
    }

    assert {:ok, [envelope], %{}} = PDUHandler.handle_pdu(pdu, ctx, %{})

    assert envelope.provenance == %{
             transport_id: "transport-fallback",
             source_frames: [11]
           }

    assert Enum.map(envelope.evidence, &{&1.kind, &1.value}) == [
             {:scid, 22},
             {:vcid, 3},
             {:map_id, 7},
             {:apid, 9}
           ]
  end
end
