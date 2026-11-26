defmodule Cadence.Protocol.TMFrameHashTest do
  @moduledoc "A transfer-frame record carries the sha256 of its own raw bytes (#738)."
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.TMFrameIngress

  test "each frame record is stamped with the hash of its own bytes" do
    first = frame(11, 1)
    second = frame(11, 2)
    {result, <<>>} = decode(first <> second)

    assert [a, b] = result.transfer_frame_records
    assert a.frame_sha256 == :crypto.hash(:sha256, first)
    assert b.frame_sha256 == :crypto.hash(:sha256, second)
    refute a.frame_sha256 == b.frame_sha256
  end

  test "the hash is of the frame, not of the evidence: regrouping the same frames keeps it" do
    first = frame(11, 1)
    second = frame(11, 2)

    {together, _} = decode(first <> second)
    {alone, _} = decode(second)

    assert [_, in_pair] = together.transfer_frame_records
    assert [in_single] = alone.transfer_frame_records
    assert in_pair.frame_sha256 == in_single.frame_sha256
  end

  test "a frame split across evidence is hashed over its whole bytes" do
    whole = frame(11, 7)
    <<head::binary-size(5), tail::binary>> = whole

    {:ok, pipeline} = TMFrameIngress.init()

    {:ok, first, rest, pipeline, continuity} =
      TMFrameIngress.process(evidence(head), pipeline, %{}, <<>>)

    assert first.transfer_frame_records == []

    assert {:ok, second, <<>>, _pipeline, _continuity} =
             TMFrameIngress.process(evidence(tail), pipeline, continuity, rest)

    assert [record] = second.transfer_frame_records
    assert record.frame_sha256 == :crypto.hash(:sha256, whole)
  end

  defp decode(bytes) do
    {:ok, pipeline} = TMFrameIngress.init()

    assert {:ok, result, rest, _pipeline, _continuity} =
             TMFrameIngress.process(evidence(bytes), pipeline, %{}, <<>>)

    {result, rest}
  end

  defp evidence(bytes) do
    RawEvidence.new(%{
      mission_id: "mission",
      source_endpoint_ref: "endpoint",
      spacecraft_id: "sc-earendil-001",
      protocol_family: :tm,
      raw: bytes,
      receipt_time: ~U[2026-11-16 18:00:00Z],
      metadata: %{"frame_size" => 14, "ocf_length" => 0}
    })
  end

  # One 14-byte TM frame (VC 2) carrying one complete 7-byte space packet.
  defp frame(scid, count) do
    <<0::2, scid::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, 1::16, 0, 21>>
  end
end
