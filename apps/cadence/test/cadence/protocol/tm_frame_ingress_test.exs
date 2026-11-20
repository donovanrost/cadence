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

  # 11-14 00:38:36–00:40:40Z: under persistence backpressure the journal consumer merged ~8 s of
  # records into one evidence and every frame took the first record's receipt time.
  test "a merged batch of journal records keeps each frame's own receipt time" do
    t0 = ~U[2026-11-14 00:38:40.869209Z]
    times = for i <- 0..7, do: DateTime.add(t0, i, :second)
    bytes = Enum.map_join(0..7, &frame(100 + &1))

    evidence =
      RawEvidence.new(%{
        mission_id: "mission",
        source_endpoint_ref: "endpoint",
        protocol_family: :tm,
        raw: bytes,
        receipt_time: t0,
        receipt_times: Enum.with_index(times, fn time, i -> {i * 14, time} end),
        metadata: Map.merge(%{frame_size: 14, ocf_length: 0}, metadata("j", "s", 0, 8 * 14))
      })

    {pipeline, continuity, remainder} = initial_state()

    assert {:ok, result, <<>>, _pipeline, _continuity} =
             TMFrameIngress.process(evidence, pipeline, continuity, remainder)

    assert Enum.map(result.packet_records, & &1.receipt_time) == times
    assert Enum.map(result.packet_records, & &1.source_time) == times
    assert Enum.map(result.packet_records, & &1.sequence_count) == Enum.to_list(100..107)
    assert Enum.all?(result.packet_records, &(&1.provenance.generation_time_source == :receipt))
    assert Enum.map(result.transfer_frame_records, & &1.receipt_time) == times
  end

  test "evidence with its own source time keeps it and reads as on-board time" do
    source_time = ~U[2026-11-14 00:00:00Z]

    evidence =
      RawEvidence.new(%{
        mission_id: "mission",
        source_endpoint_ref: "endpoint",
        protocol_family: :tm,
        raw: frame(7),
        source_time: source_time,
        metadata: Map.merge(%{frame_size: 14, ocf_length: 0}, metadata("j", "s", 0))
      })

    {pipeline, continuity, remainder} = initial_state()

    assert {:ok, %{packet_records: [packet]}, _rest, _pipeline, _continuity} =
             TMFrameIngress.process(evidence, pipeline, continuity, remainder)

    assert packet.source_time == source_time
    assert packet.provenance.generation_time_source == :onboard
  end

  test "a replay that batches the journal differently gives its packets the same ids (#71)" do
    bytes = Enum.map_join(0..7, &frame(100 + &1))
    whole = journal_evidence(bytes, 0, "evidence-whole")
    {:ok, once, <<>>, _pipeline, _continuity} = process(whole, initial_state())

    {first_half, second_half} = String.split_at(bytes, 4 * 14)
    first = journal_evidence(first_half, 0, "evidence-first")
    {:ok, a, rest, pipeline, continuity} = process(first, initial_state())
    second = journal_evidence(second_half, 4 * 14, "evidence-second")
    {:ok, b, <<>>, _pipeline, _continuity} = process(second, {pipeline, continuity, rest})

    ids = Enum.map(once.packet_records, & &1.packet_id)
    assert length(Enum.uniq(ids)) == 8
    assert ids == Enum.map(a.packet_records ++ b.packet_records, & &1.packet_id)

    refute Enum.any?(
             once.packet_records,
             &Map.has_key?(&1.provenance.tm.metadata, :raw_frame_offset_bytes)
           )

    # Without a journal stream there is no position: the evidence-scoped id, as before.
    unjournaled = %{whole | metadata: %{frame_size: 14, ocf_length: 0}}
    {:ok, plain, _rest, _pipeline, _continuity} = process(unjournaled, initial_state())
    refute Enum.map(plain.packet_records, & &1.packet_id) == ids
  end

  # DECISIONS #99: monitoring effects are keyed on the frame that completed the packet. The key must
  # not depend on how a replay batches the journal, including a frame split across two evidences
  # and its receipt time (the record holding its LAST byte), and must stay out of what is archived.
  test "a packet's journal frame is the same however the journal is batched (#99)" do
    t0 = ~U[2026-11-17 01:00:00.000000Z]
    bytes = Enum.map_join(0..7, &frame(100 + &1))
    # Socket reads of 10 bytes, so frames (14 bytes) straddle records and the split below.
    records =
      for start <- 0..(byte_size(bytes) - 1)//10,
          do: {start, DateTime.add(t0, start, :millisecond)}

    whole = records_evidence(bytes, 0, records)
    {:ok, once, <<>>, _pipeline, _continuity} = process(whole, initial_state())

    {head, tail} = String.split_at(bytes, 50)
    {head_records, tail_records} = Enum.split_with(records, fn {start, _time} -> start < 50 end)

    {:ok, a, rest, pipeline, continuity} =
      process(records_evidence(head, 0, head_records), initial_state())

    {:ok, b, <<>>, _pipeline, _continuity} =
      process(records_evidence(tail, 50, tail_records), {pipeline, continuity, rest})

    frames = Enum.map(once.packet_records, & &1.journal_frame)
    assert frames == Enum.map(a.packet_records ++ b.packet_records, & &1.journal_frame)

    expected =
      for k <- 0..7 do
        last_byte = k * 14 + 13
        {"j", k * 14, DateTime.add(t0, div(last_byte, 10) * 10, :millisecond)}
      end

    assert frames == expected

    # Not archived: neither the frame position nor its length reaches the packet's provenance.
    refute Enum.any?(once.packet_records, fn packet ->
             Map.has_key?(packet.provenance.tm.metadata, :raw_frame_offset_bytes) or
               Map.has_key?(packet.provenance.tm.metadata, :raw_frame_length_bytes)
           end)

    # Without a journal stream there is no frame key.
    unjournaled = %{whole | metadata: %{frame_size: 14, ocf_length: 0}}
    {:ok, plain, _rest, _pipeline, _continuity} = process(unjournaled, initial_state())
    assert Enum.all?(plain.packet_records, &is_nil(&1.journal_frame))
  end

  # director 11-15: the processing ack ran past a partial frame or packet held in memory.
  describe "resume_offset" do
    test "an evidence ending mid-frame resumes at that frame's start" do
      bytes = frame(1) <> frame(2)
      {first, second} = String.split_at(bytes, 20)

      {:ok, a, rest, pipeline, continuity} =
        process(journal_evidence(first, 0, "e1"), initial_state())

      assert byte_size(rest) == 6
      assert a.resume_offset == 14

      {:ok, b, <<>>, _pipeline, _continuity} =
        process(journal_evidence(second, 20, "e2"), {pipeline, continuity, rest})

      assert b.resume_offset == 28
      assert length(a.packet_records ++ b.packet_records) == 2
    end

    test "a frame holding only the start of a packet resumes at that frame until it completes" do
      # A packet with 10 data bytes: its header and 2 bytes in frame 1, the other 8 in frame 2.
      packet = <<0::3, 0::1, 0::1, 42::11, 3::2, 7::14, 9::16>> <> :binary.copy(<<7>>, 10)
      <<head::binary-size(8), tail::binary-size(8)>> = packet

      {:ok, a, <<>>, pipeline, continuity} =
        process(journal_evidence(raw_frame(1, 0, head), 0, "e1"), initial_state())

      assert a.packet_records == []
      assert a.resume_offset == 0

      {:ok, b, <<>>, _pipeline, continuity} =
        process(
          journal_evidence(raw_frame(2, 2047, tail), 14, "e2"),
          {pipeline, continuity, <<>>}
        )

      assert [_packet] = b.packet_records
      assert b.resume_offset == 28
      assert continuity.pending_frame_offsets == %{}
    end

    test "without journal offsets there is no resume point" do
      {result, _state} = decode(frame(1), %{}, initial_state())
      assert result.resume_offset == nil
    end
  end

  defp raw_frame(count, fhp, payload) when byte_size(payload) == 8 do
    <<0::2, 11::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, fhp::11,
      payload::binary>>
  end

  defp journal_evidence(bytes, offset, evidence_id) do
    RawEvidence.new(%{
      evidence_id: evidence_id,
      mission_id: "mission",
      source_endpoint_ref: "endpoint",
      protocol_family: :tm,
      raw: bytes,
      receipt_time: ~U[2026-11-14 01:35:54Z],
      metadata:
        Map.merge(%{frame_size: 14, ocf_length: 0}, metadata("j", "s", offset, byte_size(bytes)))
    })
  end

  defp records_evidence(bytes, offset, [{_start, first} | _] = records) do
    RawEvidence.new(%{
      evidence_id: "evidence-#{offset}",
      mission_id: "mission",
      source_endpoint_ref: "endpoint",
      protocol_family: :tm,
      raw: bytes,
      receipt_time: first,
      receipt_times: records,
      metadata:
        Map.merge(%{frame_size: 14, ocf_length: 0}, metadata("j", "s", offset, byte_size(bytes)))
    })
  end

  defp process(evidence, {pipeline, continuity, remainder}),
    do: TMFrameIngress.process(evidence, pipeline, continuity, remainder)

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
