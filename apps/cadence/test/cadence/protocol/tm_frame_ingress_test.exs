defmodule Cadence.Protocol.TMFrameIngressTest do
  use Cadence.UnitCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.TMFrameIngress

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
  end

  test "a returning receiver establishes a new baseline and still detects gaps within it" do
    state = initial_state()
    {first, state} = decode(frame(94), metadata("journal-a", "socket-a", 0), state)
    assert first.protocol_anomalies == []

    {replacement, state} = decode(frame(43), metadata("journal-b", "socket-b", 0), state)
    assert replacement.protocol_anomalies == []

    {returning, state} = decode(frame(247), metadata("journal-a", "socket-c", 14), state)
    assert returning.protocol_anomalies == []

    {gap, _state} = decode(frame(249), metadata("journal-a", "socket-c", 28), state)

    assert Enum.map(gap.protocol_anomalies, & &1.anomaly_kind) == [
             :master_channel_frame_count_discontinuity,
             :frame_sequence_discontinuity
           ]

    assert Enum.all?(gap.protocol_anomalies, &(&1.metadata.expected == 248))
  end

  test "connection changes clear partial frames and packets even when the journal stays open" do
    # The first frame contains only the packet header and two of its four data bytes.
    partial_packet_frame = frame(94, 3)
    bytes = partial_packet_frame <> binary_part(frame(95), 0, 7)
    {first, state} = decode(bytes, metadata("journal", "old-socket", 0, 21), initial_state())
    assert first.packet_records == []

    log =
      capture_log([level: :info], fn ->
        {reconnected, {_, _, remainder}} =
          decode(frame(43), metadata("journal", "new-socket", 21), state)

        assert reconnected.protocol_anomalies == []
        assert length(reconnected.packet_records) == 1
        assert hd(reconnected.transfer_frame_records).raw_frame_offset_bytes == 21
        assert remainder == <<>>
      end)

    assert log =~ "connection_changed"
    assert log =~ "discarded_frame_bytes=7 discarded_packet_bytes=8"
  end

  test "socket reads preserve partial framing and modulo wrap within the same connection" do
    <<prefix::binary-size(7), suffix::binary>> = frame(255)
    {partial, state} = decode(prefix, metadata("journal", "socket", 0, 7), initial_state())
    assert partial.transfer_frame_records == []
    {complete, state} = decode(suffix, metadata("journal", "socket", 7, 7), state)
    assert length(complete.packet_records) == 1
    assert complete.protocol_anomalies == []
    {wrapped, _} = decode(frame(0), metadata("journal", "socket", 14), state)
    assert wrapped.protocol_anomalies == []
  end

  test "missing journal bytes do not hide protocol gaps within a connection" do
    {_, state} = decode(frame(94), metadata("journal", "socket", 0), initial_state())
    {result, _} = decode(frame(97), metadata("journal", "socket", 42), state)
    assert length(result.protocol_anomalies) == 2
    assert Enum.all?(result.protocol_anomalies, &(&1.metadata.expected == 95))
  end

  test "legacy callers without session metadata retain gap detection" do
    {_, state} = decode(frame(1), %{}, initial_state())
    {result, _} = decode(frame(3), %{}, state)
    assert length(result.protocol_anomalies) == 2
  end

  defp initial_state do
    {:ok, pipeline} = TMFrameIngress.init()
    {pipeline, %{}, <<>>}
  end

  defp decode(bytes, metadata, {pipeline, continuity, remainder}) do
    evidence =
      RawEvidence.new(%{
        mission_id: "mission",
        source_endpoint_ref: "endpoint",
        protocol_family: :tm,
        raw: bytes,
        metadata: Map.merge(%{frame_size: 14, ocf_length: 0}, metadata)
      })

    assert {:ok, result, rest, next_pipeline, next_continuity} =
             TMFrameIngress.process(evidence, pipeline, continuity, remainder)

    {result, {next_pipeline, next_continuity, rest}}
  end

  defp metadata(journal, session, offset, size \\ 14) do
    %{
      "journal_stream_id" => journal,
      "transport_session_id" => session,
      "journal_start_offset" => offset,
      "journal_end_offset" => offset + size
    }
  end

  defp frame(count, packet_length \\ 1) do
    <<0::2, 11::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, packet_length::16, 0, 21>>
  end
end
