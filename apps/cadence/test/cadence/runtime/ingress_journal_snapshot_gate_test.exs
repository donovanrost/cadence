defmodule Cadence.Runtime.IngressJournalSnapshotGateTest do
  @moduledoc """
  The journal's durable processing cursor follows the partitions' semantic snapshots
  (DECISIONS #94/#96, #692): processing and flow control run ahead, the durable resume point
  waits for the snapshot that covers what it releases.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Runtime.IngressJournalConsumer
  alias Cadence.Runtime.IngressJournalConsumer.SnapshotGate
  alias Cadence.Runtime.SemanticSnapshotNotifier

  describe "SnapshotGate" do
    test "with no gating partition the durable resume point is where processing finished" do
      assert SnapshotGate.limit(SnapshotGate.new(), 500, 100) == 500
      assert SnapshotGate.limit(SnapshotGate.note(SnapshotGate.new(), nil), 500, 100) == 500
    end

    test "a gating partition holds the resume point at its snapshot, and at the floor before one" do
      gate = SnapshotGate.note(SnapshotGate.new(), "p1")
      assert SnapshotGate.limit(gate, 500, 100) == 100
      assert SnapshotGate.holding?(gate, 500, 100)

      gate = SnapshotGate.snapshotted(gate, "p1", 300)
      assert SnapshotGate.limit(gate, 500, 100) == 300
      assert SnapshotGate.limit(gate, 250, 100) == 250

      gate = SnapshotGate.snapshotted(gate, "p1", 500)
      assert SnapshotGate.limit(gate, 500, 100) == 500
      refute SnapshotGate.holding?(gate, 500, 100)
    end

    test "with several partitions the lowest snapshot wins, and a snapshot never moves back" do
      gate =
        SnapshotGate.new()
        |> SnapshotGate.note("p1")
        |> SnapshotGate.note("p2")
        |> SnapshotGate.snapshotted("p1", 400)

      assert SnapshotGate.limit(gate, 500, 100) == 100

      gate = SnapshotGate.snapshotted(gate, "p2", 250)
      assert SnapshotGate.limit(gate, 500, 100) == 250

      gate = SnapshotGate.snapshotted(gate, "p1", 50)
      assert SnapshotGate.limit(gate, 500, 100) == 250
    end

    test "a partition that stopped after its final snapshot gates no longer" do
      gate =
        SnapshotGate.new()
        |> SnapshotGate.note("p1")
        |> SnapshotGate.note("p2")
        |> SnapshotGate.snapshotted("p1", 400)
        |> SnapshotGate.snapshotted("p2", 250)

      assert SnapshotGate.limit(gate, 500, 100) == 250

      gate = SnapshotGate.release(gate, "p2")
      assert SnapshotGate.limit(gate, 500, 100) == 400

      gate = SnapshotGate.release(gate, "p1")
      assert SnapshotGate.limit(gate, 500, 100) == 500

      # A restarted partition gates again from its first batch, from the floor.
      gate = SnapshotGate.note(gate, "p1")
      assert SnapshotGate.limit(gate, 500, 100) == 100
    end
  end

  @tag :tmp_dir
  test "the durable resume point follows snapshots while the read cursor runs ahead", ctx do
    %{journal: journal, consumer: consumer, entries: [a, b]} = start_stream(ctx.tmp_dir, 2)

    {raw, ref} = next_batch()
    assert %RawEvidence{} = raw
    persisted(consumer, ref, "p1")

    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")

    # Both batches are processed and acked in memory; nothing is snapshotted: the durable resume
    # point has not moved from the journal's start.
    assert %{processing: b_end} = cursors(journal)
    assert b_end == b.end_offset
    assert resume(journal) == 0

    # A snapshot covering the first batch releases the first batch only.
    snapshotted(consumer, "p1", a.stream_id, a.end_offset)
    assert resume(journal) == a.end_offset
    assert %{processing: ^b_end} = cursors(journal)

    # A snapshot of another stream changes nothing.
    snapshotted(consumer, "p1", "another-stream", b.end_offset)
    assert resume(journal) == a.end_offset

    snapshotted(consumer, "p1", a.stream_id, b.end_offset)
    assert resume(journal) == b.end_offset
  end

  @tag :tmp_dir
  test "a partition that stopped after its final snapshot stops pinning the journal", ctx do
    %{journal: journal, consumer: consumer, entries: [a, b]} = start_stream(ctx.tmp_dir, 2)

    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")
    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")
    assert resume(journal) == 0

    # Another stream's partition stopping changes nothing.
    send(consumer, {:semantic_snapshot_stopped, "p1", "another-stream"})
    _ = :sys.get_state(consumer)
    assert resume(journal) == 0

    send(consumer, {:semantic_snapshot_stopped, "p1", a.stream_id})
    _ = :sys.get_state(consumer)
    assert resume(journal) == b.end_offset
  end

  @tag :tmp_dir
  test "a partition that stopped reaches the consumer through the notifier", ctx do
    %{journal: journal, consumer: consumer, entries: [a]} = start_stream(ctx.tmp_dir, 1)
    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")
    assert resume(journal) == 0

    assert :ok = SemanticSnapshotNotifier.stopped("p1", %{a.stream_id => a.end_offset})
    _ = :sys.get_state(consumer)
    assert resume(journal) == a.end_offset
  end

  @tag :tmp_dir
  test "a partition that reports no gate does not hold the journal", ctx do
    %{journal: journal, consumer: consumer, entries: [a, b]} = start_stream(ctx.tmp_dir, 2)

    {_raw, ref} = next_batch()
    persisted(consumer, ref, nil)
    assert resume(journal) == a.end_offset

    {_raw, ref} = next_batch()
    persisted(consumer, ref, nil)
    assert resume(journal) == b.end_offset
  end

  @tag :tmp_dir
  test "quiescing waits for the end-of-pass snapshot, then drains", ctx do
    %{journal: journal, consumer: consumer, entries: [a]} = start_stream(ctx.tmp_dir, 1)

    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")

    quiesce = Task.async(fn -> IngressJournalConsumer.quiesce(consumer) end)
    assert Task.yield(quiesce, 100) == nil
    assert resume(journal) == 0

    snapshotted(consumer, "p1", a.stream_id, a.end_offset)

    assert {:ok, %{status: :quiesced, incomplete_at_end: %{journal_bytes: 0}}} =
             Task.await(quiesce)

    assert resume(journal) == a.end_offset
  end

  @tag :tmp_dir
  test "quiescing gives up on a snapshot that never comes, so the journal can still drain",
       ctx do
    %{journal: journal, consumer: consumer, entries: [a]} =
      start_stream(ctx.tmp_dir, 1, quiesce_snapshot_wait_ms: 50)

    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")

    assert {:ok, %{status: :quiesced}} = IngressJournalConsumer.quiesce(consumer)
    assert resume(journal) == a.end_offset
  end

  @tag :tmp_dir
  test "a consumer is told of snapshots through the notifier", ctx do
    %{journal: journal, consumer: consumer, entries: [a]} = start_stream(ctx.tmp_dir, 1)
    {_raw, ref} = next_batch()
    persisted(consumer, ref, "p1")
    _ = :sys.get_state(consumer)

    assert :ok = SemanticSnapshotNotifier.published("p1", %{a.stream_id => a.end_offset})
    _ = :sys.get_state(consumer)
    assert resume(journal) == a.end_offset
  end

  defp start_stream(tmp_dir, entry_count, consumer_opts \\ []) do
    suffix = System.unique_integer([:positive])
    journal = :"gate_journal_#{suffix}"

    start_supervised!(
      {IngressJournal,
       name: journal,
       mission_id: "mission-gate",
       realized_contact_id: "contact-gate",
       path_id: "path-gate",
       provider_binding_id: "provider-gate-#{suffix}",
       base_path: tmp_dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       checkpoint_interval_ms: 60_000}
    )

    entries =
      for n <- 1..entry_count do
        {:ok, entry} =
          IngressJournal.append(journal, <<n, n, n, n>>, DateTime.utc_now(), %{
            mission_id: "mission-gate",
            protocol_family: :tm
          })

        entry
      end

    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         [
           name: :"gate_consumer_#{suffix}",
           mission_id: "mission-gate",
           realized_contact_id: "contact-gate",
           path_id: "path-gate",
           provider_binding_id: "provider-gate-#{suffix}",
           journal_name: journal,
           executor_name: executor,
           poll_interval_ms: 5,
           processing_max_batch_entries: 1
         ] ++ consumer_opts}
      )

    %{journal: journal, consumer: consumer, entries: entries}
  end

  defp next_batch do
    assert_receive {:processing_enqueued, raw_evidence, {_consumer, ref}}, 5_000
    {raw_evidence, ref}
  end

  defp persisted(consumer, ref, partition) do
    send(consumer, {:provider_ingress_persisted, self(), ref, %{snapshot_partition: partition}})
    _ = :sys.get_state(consumer)
  end

  defp snapshotted(consumer, partition, stream_id, offset) do
    send(consumer, {:semantic_snapshot_durable, partition, stream_id, offset})
    _ = :sys.get_state(consumer)
  end

  defp cursors(journal) do
    {:ok, %{cursors: cursors}} = IngressJournal.snapshot(journal)
    cursors
  end

  defp resume(journal) do
    {:ok, %{resume_points: %{processing: %{resume: resume}}}} = IngressJournal.snapshot(journal)
    resume
  end

  defp executor_loop(test_pid) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, raw_evidence, _async_context, completion}}} ->
        send(test_pid, {:processing_enqueued, raw_evidence, completion})
        executor_loop(test_pid)
    end
  end
end
