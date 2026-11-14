defmodule Cadence.Runtime.IngressJournalTimeTagsTest do
  @moduledoc """
  The 11-14 00:38:36–00:40:40Z failure, at the seam where it happened: a backlog of journal records
  (one per socket read, each stamped at the read) is merged by the consumer into one work item.
  Decoding it must give every frame its own record's receipt time, not the first record's.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Protocol.TMFrameIngress
  alias Cadence.Runtime.IngressJournalConsumer

  @frame_size 14

  # Production's batching, read from config/config.exs as prod evaluates it, so this test always
  # merges like production does. config/test.exs takes one record per batch, which is how the
  # 11-14 merge bug hid from every other test.
  @prod_config Path.expand("../../../config/config.exs", __DIR__)

  setup_all do
    batch =
      @prod_config
      |> Config.Reader.read!(env: :prod, target: :host)
      |> get_in([:cadence, :ingress_journal, :processing_max_batch_entries])

    %{prod_batch_entries: batch}
  end

  test "production merges journal records into batches", %{prod_batch_entries: batch} do
    assert is_integer(batch) and batch > 1,
           "production no longer merges journal records; revisit the time-tags tests"
  end

  @tag :tmp_dir
  test "a merged backlog keeps each frame's socket receipt time through decoding", %{
    tmp_dir: tmp_dir,
    prod_batch_entries: batch
  } do
    id = System.unique_integer([:positive])
    journal = :"time_tags_journal_#{id}"
    context = [mission_id: "mission-tt", realized_contact_id: "contact-tt", path_id: "path-tt"]

    start_supervised!(
      {IngressJournal,
       context ++
         [
           name: journal,
           provider_binding_id: "provider-tt-#{id}",
           base_path: tmp_dir,
           durability: :sync,
           max_bytes: 1_024 * 1_024,
           segment_bytes: 64 * 1_024,
           checkpoint_interval_ms: 60_000
         ]}
    )

    # A production-sized backlog of socket reads, one frame each, 1 s apart, while persistence was
    # behind (8 on 11-14).
    t0 = ~U[2026-11-14 00:38:40.869209Z]
    times = for i <- 0..(batch - 1), do: DateTime.add(t0, i, :second)

    metadata = %{
      mission_id: "mission-tt",
      protocol_family: :tm,
      ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
    }

    for {time, count} <- Enum.zip(times, 100..(99 + batch)) do
      assert {:ok, _entries} = IngressJournal.append_stream(journal, frame(count), time, metadata)
    end

    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    start_supervised!(
      {IngressJournalConsumer,
       context ++
         [
           name: :"time_tags_consumer_#{id}",
           provider_binding_id: "provider-tt-#{id}",
           journal_name: journal,
           executor_name: executor,
           processing_max_batch_entries: batch,
           poll_interval_ms: 5
         ]}
    )

    # The consumer hands the whole backlog over as one work item, as it did on 11-14.
    assert_receive {:processing_enqueued, %RawEvidence{} = evidence}, 5_000
    assert evidence.metadata["journal_record_count"] == batch
    assert evidence.receipt_time == t0

    {:ok, pipeline} = TMFrameIngress.init()

    assert {:ok, result, <<>>, _pipeline, _continuity} =
             TMFrameIngress.process(evidence, pipeline, %{}, <<>>)

    assert Enum.map(result.packet_records, & &1.receipt_time) == times
    assert Enum.map(result.packet_records, & &1.source_time) == times

    assert Enum.map(result.packet_records, & &1.sequence_count) ==
             Enum.to_list(100..(99 + batch))
  end

  defp frame(count) do
    <<0::2, 11::10, 2::3, 0::1, count::8, count::8, 0::1, 0::1, 0::1, 3::2, 0::11, 0::3, 0::1,
      0::1, 42::11, 3::2, count::14, 1::16, 0, 21>>
  end

  defp executor_loop(test_pid) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, raw_evidence, _async_context, _completion}}} ->
        send(test_pid, {:processing_enqueued, raw_evidence})
        executor_loop(test_pid)
    end
  end
end
