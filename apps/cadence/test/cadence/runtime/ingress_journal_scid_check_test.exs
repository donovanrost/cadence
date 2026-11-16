defmodule Cadence.Runtime.IngressJournalScidCheckTest do
  @moduledoc """
  The frame-SCID cross-check through the ingress journal (DECISIONS #102): the receiver journals
  the pass's SCID with each entry, the evidence carries it, TM ingress refuses frames of another
  SCID, and the journal consumer keeps the stream's tally for the settler. The test stands in for
  the executor and decodes each evidence with the real TM ingress, as the partition does.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Protocol.TMFrameIngress
  alias Cadence.Runtime.IngressJournalConsumer

  @tag :tmp_dir
  test "a pass's frames of another SCID are refused and counted across batches", %{tmp_dir: dir} do
    name = start_journal(dir)
    append!(name, frame(11, 1) <> frame(3, 2), 11)
    append!(name, frame(3, 3) <> frame(9, 4) <> frame(11, 5), 11)
    consumer = start_consumer(name)

    {first, state} = process_next(consumer, initial_state())
    {second, _state} = process_next(consumer, state)

    assert first.evidence.metadata["spacecraft_scid"] == 11
    assert Enum.map(first.packets ++ second.packets, & &1.sequence_count) == [1, 5]

    assert {:ok, %{scid_check: check}} = IngressJournalConsumer.quiesce(consumer)

    assert check == %{
             expected_scid: 11,
             spacecraft_id: nil,
             frames: 5,
             refused: %{3 => 2, 9 => 1}
           }
  end

  @tag :tmp_dir
  test "a path with no known SCID keeps no tally and refuses nothing", %{tmp_dir: dir} do
    name = start_journal(dir)
    append!(name, frame(11, 1) <> frame(3, 2), nil)
    consumer = start_consumer(name)

    {batch, _state} = process_next(consumer, initial_state())

    refute Map.has_key?(batch.evidence.metadata, "spacecraft_scid")
    assert length(batch.packets) == 2
    assert {:ok, %{scid_check: nil}} = IngressJournalConsumer.quiesce(consumer)
  end

  defp process_next(consumer, {pipeline, continuity, remainder}) do
    receive do
      {:processing_enqueued, %RawEvidence{} = evidence, {^consumer, ref}} ->
        {:ok, result, rest, pipeline, continuity} =
          TMFrameIngress.process(evidence, pipeline, continuity, remainder)

        send(
          consumer,
          {:provider_ingress_persisted, self(), ref,
           %{
             resume_offset: result.resume_offset,
             incomplete: result.incomplete,
             scid_check: result.scid_check
           }}
        )

        # Let the ack land before the next read or the quiesce.
        _ = :sys.get_state(consumer)
        {%{evidence: evidence, packets: result.packet_records}, {pipeline, continuity, rest}}
    after
      2_000 -> flunk("no evidence enqueued")
    end
  end

  defp initial_state do
    {:ok, pipeline} = TMFrameIngress.init()
    {pipeline, %{}, <<>>}
  end

  defp start_journal(dir) do
    name = :"scid_journal_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressJournal,
       name: name,
       mission_id: "mission-scid",
       realized_contact_id: "contact-scid",
       path_id: "path-scid",
       provider_binding_id: "provider-scid",
       base_path: dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       checkpoint_interval_ms: 60_000},
      id: {:journal, name}
    )

    name
  end

  defp start_consumer(journal) do
    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    start_supervised!(
      {IngressJournalConsumer,
       name: :"scid_consumer_#{System.unique_integer([:positive])}",
       mission_id: "mission-scid",
       realized_contact_id: "contact-scid",
       path_id: "path-scid",
       provider_binding_id: "provider-scid",
       journal_name: journal,
       executor_name: executor,
       processing_max_batch_entries: 1,
       poll_interval_ms: 5},
      id: {:consumer, journal}
    )
  end

  defp append!(journal, bytes, scid) do
    {:ok, _entry} =
      IngressJournal.append(journal, bytes, DateTime.utc_now(), %{
        mission_id: "mission-scid",
        source_endpoint_ref: "endpoint-scid",
        protocol_family: :tm,
        spacecraft_scid: scid,
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

  # One 14-byte TM frame (VC 2) carrying one complete 7-byte space packet.
  defp frame(scid, count) do
    <<0::2, scid::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, 1::16, 0, 21>>
  end
end
