defmodule Cadence.Protocol.RecordArchive.WriterTest do
  use Cadence.ProcessDataCase, async: false
  @moduletag :tmp_dir

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Protocol.{PacketRecord, RecordArchive}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.{IdentityRow, SegmentRow}
  alias Cadence.Repo

  setup %{tmp_dir: base_path} do
    unique = System.unique_integer([:positive])

    policy =
      RecordArchive.policy(
        module: FileSystem,
        name: Module.concat(__MODULE__, "Writer#{unique}"),
        instance_id: "record-writer-#{unique}",
        base_path: base_path,
        repo: Repo,
        flush_interval_ms: 5_000,
        flush_count: 100_000
      )

    start_supervised!(RecordArchive.child_spec(policy))
    %{policy: policy, unique: unique}
  end

  defp mission(unique, n) do
    mission_id = "mission-record-writer-#{unique}-#{n}"
    persist_mission_scope("org-record-writer-#{unique}-#{n}", mission_id)
    mission_id
  end

  defp batch(mission_id, n) do
    evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-#{mission_id}-#{n}",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1, 2>>,
        receipt_time: ~U[2026-11-25 12:00:00Z]
      })

    packet = %PacketRecord{
      packet_id: "packet-#{mission_id}-#{n}",
      evidence_id: evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      packet_data: <<1, 2>>,
      receipt_time: evidence.receipt_time,
      provenance: %{}
    }

    {evidence, [], [packet]}
  end

  defp indexed?(policy, packet_id) do
    Repo.get_by(IdentityRow,
      record_kind: "packet_record",
      record_id:
        FileSystem.entry_index_record_id(%{"record_id" => packet_id}, policy.backend_opts)
    )
  end

  test "concurrent callers on one mission share flushes, and each flush returns only once its entries are indexed",
       %{policy: policy, unique: unique} do
    mission_id = mission(unique, 1)

    results =
      1..60
      |> Task.async_stream(
        fn n ->
          {_evidence, _frames, [packet]} = batched = batch(mission_id, n)
          :ok = RecordArchive.persist_records_many(policy, [batched])
          :ok = RecordArchive.flush(policy, mission_id)
          # Durable on return: the index row and its segment exist by now.
          identity = indexed?(policy, packet.packet_id)
          segment = identity && Repo.get(SegmentRow, identity.segment_id)

          segment &&
            File.exists?(
              Path.join(Keyword.fetch!(policy.backend_opts, :base_path), segment.object_key)
            )
        end,
        max_concurrency: 60,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, durable?} -> durable? end)

    assert Enum.all?(results)

    stats = RecordArchive.stats(policy, mission_id)
    assert stats.flushed_count == 60
    assert stats.batches_flushed == 60
    assert stats.flush_count < 60
    assert stats.avg_batches_per_flush > 1.0
  end

  test "a mission's stats, flush and reset_stats work before it has a writer", %{
    policy: policy,
    unique: unique
  } do
    mission_id = mission(unique, 2)

    assert %{queue_depth: 0, flush_count: 0, backpressured?: false} =
             RecordArchive.stats(policy, mission_id)

    assert :ok = RecordArchive.flush(policy, mission_id)
    assert :ok = RecordArchive.reset_stats(policy, mission_id)
  end

  test "missions have separate writers: flushing one leaves another's buffer alone", %{
    policy: policy,
    unique: unique
  } do
    a = mission(unique, 3)
    b = mission(unique, 4)

    assert :ok = RecordArchive.persist_records_many(policy, [batch(a, 1), batch(b, 1)])
    assert :ok = RecordArchive.flush(policy, a)

    assert %{queue_depth: 0, flush_count: 1} = RecordArchive.stats(policy, a)
    assert %{queue_depth: 1, flush_count: 0} = RecordArchive.stats(policy, b)

    assert :ok = RecordArchive.flush(policy, nil)
    assert %{queue_depth: 0, flush_count: 1} = RecordArchive.stats(policy, b)
  end

  test "an idle writer goes away and the next enqueue starts a fresh one", %{
    policy: policy,
    unique: unique
  } do
    mission_id = mission(unique, 5)
    registry = Module.concat(Keyword.fetch!(policy.backend_opts, :name), Registry)

    assert :ok = RecordArchive.persist_records_many(policy, [batch(mission_id, 1)])
    assert :ok = RecordArchive.flush(policy, mission_id)
    [{pid, _}] = Registry.lookup(registry, {mission_id, nil})

    # Monitor before nudging: a writer that exits first would otherwise report :noproc.
    ref = Process.monitor(pid)
    send(pid, :idle_check)
    send(pid, :idle_check)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

    # The writer dropped its name before exiting, so no lookup can hand out the dead pid (the
    # Registry's own cleanup of a dead name is asynchronous).
    assert Registry.lookup(registry, {mission_id, nil}) == []

    assert :ok = RecordArchive.persist_records_many(policy, [batch(mission_id, 2)])
    [{fresh, _}] = Registry.lookup(registry, {mission_id, nil})
    refute fresh == pid
    assert :ok = RecordArchive.flush(policy, mission_id)
    assert indexed?(policy, "packet-#{mission_id}-2")
  end

  test "a reset answers the flush callers still waiting on the buffer it dropped", %{
    policy: policy,
    unique: unique
  } do
    mission_id = mission(unique, 6)
    registry = Module.concat(Keyword.fetch!(policy.backend_opts, :name), Registry)

    assert :ok = RecordArchive.persist_records_many(policy, [batch(mission_id, 1)])
    [{pid, _}] = Registry.lookup(registry, {mission_id, nil})

    # Suspended, the writer queues the flush and the reset in that order; it handles the flush
    # first (which parks the caller and queues :run_flush behind the reset).
    :sys.suspend(pid)
    flush = Task.async(fn -> RecordArchive.flush(policy, mission_id) end)
    wait_for_mailbox(pid, 1)
    reset = Task.async(fn -> GenServer.call(pid, :reset) end)
    wait_for_mailbox(pid, 2)
    :sys.resume(pid)

    assert :ok = Task.await(flush, 5_000)
    assert :ok = Task.await(reset, 5_000)
  end

  defp wait_for_mailbox(pid, count) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} when len >= count -> :ok
      _ -> Process.sleep(5) && wait_for_mailbox(pid, count)
    end
  end
end
