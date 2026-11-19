defmodule Cadence.Runtime.IngressJournalResumeTest do
  @moduledoc """
  A restart resumes processing at the start of a frame or packet that was still incomplete, and
  decodes nothing twice (director 11-15: the processing ack ran past them, and they were lost).
  The test stands in for the executor and decodes each evidence with the real TM ingress, so the
  resume offsets are the partition's.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Protocol.TMFrameIngress
  alias Cadence.Runtime.IngressJournalConsumer

  @tag :tmp_dir
  test "a frame split across two entries decodes once across a restart", %{tmp_dir: dir} do
    bytes = frame(1) <> frame(2) <> frame(3)
    {first, second} = String.split_at(bytes, 20)

    assert [1, 2, 3] == run_with_restart(dir, [first, second])
  end

  @tag :tmp_dir
  test "a packet split across two frames in two entries decodes once across a restart", %{
    tmp_dir: dir
  } do
    # A packet with 10 data bytes: header + 2 bytes in frame 1, the other 8 in frame 2.
    packet = <<0::3, 0::1, 0::1, 42::11, 3::2, 7::14, 9::16>> <> :binary.copy(<<7>>, 10)
    <<head::binary-size(8), tail::binary-size(8)>> = packet
    entries = [raw_frame(1, 0, head), raw_frame(2, 2047, tail) <> frame(3)]

    assert [7, 3] == run_with_restart(dir, entries)
  end

  @tag :tmp_dir
  test "a stream ending mid-frame gives the partial frame up, counted, and drains", %{
    tmp_dir: dir
  } do
    name = :"resume_journal_#{System.unique_integer([:positive])}"
    start_journal(dir, name)
    {partial, _rest} = String.split_at(frame(1) <> frame(2), 20)
    append!(name, partial)

    {consumer, _consumer_id} = start_consumer(name)
    {[_packet], _state} = process_next(consumer, initial_state())

    assert {:ok, %{incomplete_at_end: %{frame_bytes: 6, packet_octets: 0, journal_bytes: 6}}} =
             IngressJournalConsumer.quiesce(consumer)

    assert {:ok, %{next_offset: tail, resume_points: %{processing: %{resume: tail}}}} =
             IngressJournal.snapshot(name)
  end

  # Appends the entries, processes the first one, "crashes" (journal and consumer stop; the
  # journal writes its checkpoint), restarts both and processes to the end. Returns the packet
  # sequence counts decoded, in order, across both runs.
  defp run_with_restart(dir, [first | rest]) do
    name = :"resume_journal_#{System.unique_integer([:positive])}"
    journal_id = start_journal(dir, name)
    Enum.each([first | rest], &append!(name, &1))

    {consumer, consumer_id} = start_consumer(name)
    {before, _state} = process_next(consumer, initial_state())
    # Let the ack land before the stop.
    _ = :sys.get_state(consumer)

    stop_supervised!(consumer_id)
    stop_supervised!(journal_id)

    start_journal(dir, name)
    {consumer, _consumer_id} = start_consumer(name)
    {after_restart, _state} = process_all(consumer, initial_state(), length(rest) + 1)

    assert {:ok, %{incomplete_at_end: %{journal_bytes: 0}}} =
             IngressJournalConsumer.quiesce(consumer)

    Enum.map(before ++ after_restart, & &1.sequence_count)
  end

  defp process_all(_consumer, state, 0), do: {[], state}

  defp process_all(consumer, state, remaining) do
    case process_next(consumer, state) do
      {[], state} when remaining == 0 ->
        {[], state}

      {packets, state} ->
        {more, state} = process_all(consumer, state, remaining - 1)
        {packets ++ more, state}
    end
  end

  # Receives the consumer's next evidence, decodes it like the partition, and completes it with
  # the partition's resume offset.
  defp process_next(consumer, {pipeline, continuity, remainder}) do
    receive do
      {:processing_enqueued, %RawEvidence{} = evidence, {^consumer, ref}} ->
        {:ok, result, rest, pipeline, continuity} =
          TMFrameIngress.process(evidence, pipeline, continuity, remainder)

        send(
          consumer,
          {:provider_ingress_persisted, self(), ref,
           %{resume_offset: result.resume_offset, incomplete: result.incomplete}}
        )

        {result.packet_records, {pipeline, continuity, rest}}
    after
      2_000 -> {[], {pipeline, continuity, remainder}}
    end
  end

  defp initial_state do
    {:ok, pipeline} = TMFrameIngress.init()
    {pipeline, %{}, <<>>}
  end

  defp start_journal(dir, name) do
    id = {:journal, System.unique_integer([:positive])}

    start_supervised!(
      {IngressJournal,
       name: name,
       mission_id: "mission-resume",
       realized_contact_id: "contact-resume",
       path_id: "path-resume",
       provider_binding_id: "provider-resume",
       base_path: dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       checkpoint_interval_ms: 60_000},
      id: id
    )

    id
  end

  defp start_consumer(journal) do
    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    id = {:consumer, System.unique_integer([:positive])}

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         name: :"resume_consumer_#{System.unique_integer([:positive])}",
         mission_id: "mission-resume",
         realized_contact_id: "contact-resume",
         path_id: "path-resume",
         provider_binding_id: "provider-resume",
         journal_name: journal,
         executor_name: executor,
         processing_max_batch_entries: 1,
         poll_interval_ms: 5},
        id: id
      )

    {consumer, id}
  end

  defp append!(journal, bytes) do
    {:ok, _entry} =
      IngressJournal.append(journal, bytes, DateTime.utc_now(), %{
        mission_id: "mission-resume",
        source_endpoint_ref: "endpoint-resume",
        protocol_family: :tm,
        ingress_metadata: %{"frame_size" => 14, "ocf_length" => 0}
      })
  end

  defp executor_loop(test_pid) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, raw_evidence, _async_context, completion}}} ->
        send(test_pid, {:processing_enqueued, raw_evidence, completion})
        executor_loop(test_pid)
    end
  end

  defp frame(count, packet_length \\ 1) do
    <<0::2, 11::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, packet_length::16, 0, 21>>
  end

  defp raw_frame(count, fhp, payload) when byte_size(payload) == 8 do
    <<0::2, 11::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, fhp::11,
      payload::binary>>
  end
end
