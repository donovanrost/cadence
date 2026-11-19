defmodule Cadence.Protocol.TMFrameScidCheckTest do
  @moduledoc "The frame-SCID cross-check in TM ingress (DECISIONS #102)."
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.TMFrameIngress

  test "a frame of the pass's SCID decodes as before; the tally counts it" do
    {result, _rest} = decode(frame(11, 1) <> frame(11, 2), expected: 11)

    assert length(result.packet_records) == 2
    assert length(result.transfer_frame_records) == 2
    assert result.protocol_anomalies == []

    assert result.scid_check == %{
             expected_scid: 11,
             frames: 2,
             refused: %{},
             spacecraft_id: "sc-earendil-001"
           }
  end

  test "a frame of another SCID is refused before reassembly: no frame record, packet or sample" do
    {result, _rest} =
      decode(frame(11, 1) <> frame(3, 2) <> frame(3, 3) <> frame(7, 4), expected: 11)

    assert length(result.packet_records) == 1
    assert [%{scid: 11}] = result.transfer_frame_records

    assert [three, seven] = result.protocol_anomalies
    assert %{anomaly_kind: :scid_mismatch, scid: 3, spacecraft_id: "sc-earendil-001"} = three
    assert three.raw_frame_offset_bytes == 14

    assert three.metadata == %{
             expected_scid: 11,
             frames: 2,
             realized_contact_id: "rc-1",
             path_id: "path-1"
           }

    assert %{anomaly_kind: :scid_mismatch, scid: 7, metadata: %{frames: 1}} = seven
    assert result.scid_check.frames == 4
    assert result.scid_check.refused == %{3 => 2, 7 => 1}
  end

  test "integrity runs first: a frame failing the codec's checks is corrupt, not another craft" do
    <<_version::2, rest::bitstring>> = frame(3, 2)
    corrupt = <<1::2, rest::bitstring>>
    {result, _rest} = decode(frame(11, 1) <> corrupt, expected: 11)

    kinds = Enum.map(result.protocol_anomalies, & &1.anomaly_kind)
    refute :scid_mismatch in kinds
    assert :frame_decode_dropped in kinds
    assert result.scid_check == %{result.scid_check | frames: 1, refused: %{}}
  end

  test "without an expected SCID (no spacecraft or several on the path) nothing changes" do
    {result, _rest} = decode(frame(11, 1) <> frame(3, 2), expected: nil)

    assert length(result.packet_records) == 2
    assert result.protocol_anomalies == []
    assert result.scid_check == nil
  end

  defp decode(bytes, expected: expected) do
    {:ok, pipeline} = TMFrameIngress.init()

    metadata =
      %{
        "frame_size" => 14,
        "ocf_length" => 0,
        "realized_contact_id" => "rc-1",
        "path_id" => "path-1"
      }
      |> then(&if expected, do: Map.put(&1, "spacecraft_scid", expected), else: &1)

    evidence =
      RawEvidence.new(%{
        mission_id: "mission",
        source_endpoint_ref: "endpoint",
        spacecraft_id: "sc-earendil-001",
        protocol_family: :tm,
        raw: bytes,
        receipt_time: ~U[2026-11-16 18:00:00Z],
        metadata: metadata
      })

    assert {:ok, result, rest, _pipeline, _continuity} =
             TMFrameIngress.process(evidence, pipeline, %{}, <<>>)

    {result, rest}
  end

  # One 14-byte TM frame (VC 2) carrying one complete 7-byte space packet.
  defp frame(scid, count) do
    <<0::2, scid::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, 1::16, 0, 21>>
  end
end
