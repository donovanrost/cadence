defmodule Cadence.Protocol.ScidRoutingTest do
  @moduledoc """
  #1078 P5 slice E1b-1: a source endpoint's partition accepts a frame by its SCID. Its own craft's
  frames are direct; a relay endpoint's declared origins' are relayed (decoded, with the origin
  craft and a relayed origin, but never in `packet_records`: they aren't routed yet); any other
  SCID is refused before reassembly as `scid_mismatch`, an archived origin's as
  `relay_origin_archived`, and each refusal is counted by a telemetry event so a misconfigured SCID
  shows in metrics, not only as missing data.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{Origin, ScidRoutes, TMFrameIngress}

  @own 11
  @active 21
  @archived 31

  setup do
    parent = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach_many(
      handler,
      [[:cadence, :protocol, :scid_check, :refused], [:cadence, :protocol, :relay, :not_routed]],
      fn event, measurements, metadata, _ ->
        send(parent, {:event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  describe "a relay endpoint" do
    test "keeps its own craft's frames, and decodes a declared origin's apart, as relayed" do
      result = decode(frame(@own, 1) <> frame(@active, 2), relay())

      assert [own] = result.packet_records
      assert own.sequence_count == 1
      assert own.spacecraft_id == "sc-own"
      assert own.provenance.origin.kind == :direct

      assert [relayed] = result.relayed_packet_records
      assert relayed.sequence_count == 2

      # The packet is the origin craft's; it arrived on this endpoint, through its own craft's SCID.
      assert relayed.spacecraft_id == "sc-active"
      assert relayed.source_endpoint_ref == "endpoint-relay"

      assert Origin.from_packet(relayed) == %{
               v: 1,
               kind: :relayed,
               source_endpoint_id: "endpoint-relay",
               scid: @active,
               vcid: 2,
               map_id: nil,
               apid: 42,
               relay: %{via_source_endpoint_id: "endpoint-relay", via_scid: @own}
             }

      assert_received {:event, [:cadence, :protocol, :relay, :not_routed], %{packets: 1},
                       %{origin_spacecraft_id: "sc-active", source_endpoint_id: "endpoint-relay"}}
    end

    test "refuses an SCID outside its declared set, and counts it" do
      result = decode(frame(@own, 1) <> frame(99, 2) <> frame(99, 3), relay())

      assert Enum.map(result.packet_records, & &1.sequence_count) == [1]
      assert result.relayed_packet_records == []

      assert [%{anomaly_kind: :scid_mismatch, scid: 99, metadata: %{frames: 2}}] =
               result.protocol_anomalies |> Enum.map(&Map.from_struct/1)

      assert result.scid_check.refused == %{99 => 2}

      assert_received {:event, [:cadence, :protocol, :scid_check, :refused], %{frames: 2},
                       %{
                         reason: :scid_mismatch,
                         scid: 99,
                         expected_scid: @own,
                         mission_id: "mission-scid"
                       }}
    end

    test "refuses an archived origin craft's frames as relay_origin_archived" do
      result = decode(frame(@archived, 1) <> frame(@active, 2), relay())

      assert [%{anomaly_kind: :relay_origin_archived, scid: @archived, metadata: meta}] =
               Enum.map(result.protocol_anomalies, &Map.from_struct/1)

      assert meta.origin_spacecraft_id == "sc-archived"
      assert Enum.map(result.relayed_packet_records, & &1.sequence_count) == [2]

      assert_received {:event, [:cadence, :protocol, :scid_check, :refused], %{frames: 1},
                       %{reason: :relay_origin_archived, scid: @archived}}
    end

    test "the pass's one-spacecraft SCID does not refuse a relay's origins" do
      result =
        decode(frame(@own, 1) <> frame(@active, 2), relay(), %{"spacecraft_scid" => @own})

      assert length(result.packet_records) == 1
      assert length(result.relayed_packet_records) == 1
      assert result.protocol_anomalies == []
    end
  end

  describe "a non-relay endpoint" do
    test "refuses any SCID but its own craft's, with no pass metadata naming it" do
      routes = ScidRoutes.new("endpoint-relay", "sc-own", @own, [])
      result = decode(frame(@own, 1) <> frame(3, 2), routes)

      assert Enum.map(result.packet_records, & &1.sequence_count) == [1]

      assert [%{anomaly_kind: :scid_mismatch, scid: 3}] =
               Enum.map(result.protocol_anomalies, &Map.from_struct/1)

      assert_received {:event, [:cadence, :protocol, :scid_check, :refused], %{frames: 1},
                       %{reason: :scid_mismatch, scid: 3, expected_scid: @own}}
    end

    test "checks nothing when its craft has no SCID, or there are no routes" do
      for routes <- [ScidRoutes.new("endpoint-relay", "sc-own", nil, []), ScidRoutes.none(), nil] do
        result = decode(frame(@own, 1) <> frame(3, 2), routes)

        assert Enum.map(result.packet_records, & &1.sequence_count) == [1, 2]
        assert result.protocol_anomalies == []
        refute_received {:event, [:cadence, :protocol, :scid_check, :refused], _, _}
      end
    end

    test "the pass's SCID still decides when the evidence names one, as before" do
      routes = ScidRoutes.new("endpoint-relay", "sc-own", @own, [])
      result = decode(frame(@own, 1) <> frame(3, 2), routes, %{"spacecraft_scid" => @own})

      assert Enum.map(result.packet_records, & &1.sequence_count) == [1]

      assert result.scid_check == %{
               expected_scid: @own,
               frames: 2,
               refused: %{3 => 1},
               spacecraft_id: "sc-own"
             }
    end
  end

  describe "ScidRoutes" do
    test "classifies by SCID: own first, then the declared origins, else a mismatch" do
      routes = relay()

      assert ScidRoutes.classify(routes, @own) == :direct
      assert ScidRoutes.classify(routes, @active) == {:relayed, "sc-active"}
      assert ScidRoutes.classify(routes, @archived) == {:archived, "sc-archived"}
      assert ScidRoutes.classify(routes, 5) == :mismatch
      assert ScidRoutes.classify(ScidRoutes.none(), 5) == :direct
    end

    test "leaves out an origin without a SCID, and the endpoint's own craft listed as an origin" do
      routes =
        ScidRoutes.new("e", "sc-own", @own, [
          {"sc-none", nil, :active},
          {"sc-own", @own, :active},
          {"sc-a", @active, :active}
        ])

      assert Map.keys(routes.routes) == [@active]
    end
  end

  defp relay do
    ScidRoutes.new("endpoint-relay", "sc-own", @own, [
      {"sc-active", @active, :active},
      {"sc-archived", @archived, :archived}
    ])
  end

  defp decode(bytes, routes, extra_metadata \\ %{}) do
    {:ok, pipeline} = TMFrameIngress.init()

    evidence =
      RawEvidence.new(%{
        mission_id: "mission-scid",
        source_endpoint_ref: "endpoint-relay",
        spacecraft_id: "sc-own",
        protocol_family: :tm,
        receipt_time: ~U[2026-11-28 12:00:00.000000Z],
        raw: bytes,
        metadata: Map.merge(%{"frame_size" => 14, "ocf_length" => 0}, extra_metadata)
      })

    opts = if routes, do: [scid_routes: routes], else: []

    {:ok, result, _rest, _pipeline, _continuity} =
      TMFrameIngress.process(evidence, pipeline, %{}, <<>>, opts)

    result
  end

  # One 14-byte TM frame (VC 2) carrying one complete 7-byte space packet.
  defp frame(scid, count) do
    <<0::2, scid::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, 1::16, 0, 21>>
  end
end
