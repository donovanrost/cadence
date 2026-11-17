defmodule Cadence.Runtime.ReplayConflictsPathsTest do
  # #99 follow-up: the processing path's record (journal consumer) and the sampler's buffer
  # readings and gauges.
  use Cadence.ProcessDataCase

  import ExUnit.CaptureLog

  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Runtime.IngressJournalConsumer
  alias Cadence.Runtime.ReplayConflicts.{Recorder, Row, Sampler}

  @mission "mission-replay-paths"

  defp rows, do: Repo.all(from(row in Row, order_by: [asc: row.inserted_at]))
  defp open_rows, do: Enum.filter(rows(), &is_nil(&1.resolved_at))

  @tag :tmp_dir
  test "the processing path: a failed completion opens the stream's record, its acknowledged retry resolves it",
       %{tmp_dir: path} do
    journal =
      start_supervised!(
        {IngressJournal,
         mission_id: @mission,
         realized_contact_id: "contact-1",
         path_id: "path-1",
         provider_binding_id: "binding-1",
         base_path: path,
         durability: :sync}
      )

    metadata = %{mission_id: @mission, protocol_family: :tm}
    {:ok, _entry} = IngressJournal.append(journal, <<1, 2, 3>>, DateTime.utc_now(), metadata)
    test = self()
    executor = spawn(fn -> executor_loop(test) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         mission_id: @mission,
         realized_contact_id: "contact-1",
         path_id: "path-1",
         provider_binding_id: "binding-1",
         journal_name: journal,
         executor_name: executor,
         poll_interval_ms: 5,
         retry_initial_ms: 20,
         retry_max_ms: 40}
      )

    assert_receive {:processing_enqueued, {^consumer, ref}}, 1_000
    conflict = {:semantic_runtime_failed, {:replay_id_conflict, :managed_action_request, "mar_1"}}

    capture_log(fn ->
      send(consumer, {:provider_ingress_failed, executor, ref, conflict})
      assert_receive {:processing_enqueued, {^consumer, retry_ref}}, 1_000

      assert [%Row{path: "processing", effect_kind: "managed_action_request", effect_id: "mar_1"}] =
               open_rows()

      assert {:ok, %{consecutive_failures: 1}} = IngressJournalConsumer.snapshot(consumer)
      send(consumer, {:provider_ingress_persisted, executor, retry_ref})
      assert_eventually(fn -> assert open_rows() == [] end)
    end)

    assert [%Row{resolved_at: %DateTime{}, stream_key: "contact-1:path-1:binding-1"}] = rows()
  end

  test "the sampler puts each stream's buffer on its open records and marks dropping once" do
    unit = Recorder.stream_unit(:storage, @mission, "contact-1", "path-1", "binding-1")
    other = Recorder.stream_unit(:processing, @mission, "contact-1", "path-1", "binding-1")
    timer = Recorder.partition_unit(@mission, "source_endpoint:a", "starting")

    for u <- [unit, other, timer],
        do: Recorder.track({:error, {:replay_id_conflict, :alarm_event, "aev_1"}}, u, :clear)

    reading = fn full ->
      fn _row -> {:ok, %{retained_bytes: 3_000, max_bytes: 8_000, full_count: full}} end
    end

    events = capture_events()
    t0 = ~U[2026-11-17 08:00:00.000000Z]
    assert :ok = Sampler.sample_once(reading.(2), t0)

    stream_rows = Enum.filter(open_rows(), & &1.stream_key)
    assert length(stream_rows) == 2

    assert Enum.all?(stream_rows, fn row ->
             row.buffer_retained_bytes == 3_000 and row.buffer_max_bytes == 8_000 and
               row.buffer_full_count == 2 and row.buffer_sampled_at == t0 and
               is_nil(row.dropping_since)
           end)

    assert [%Row{buffer_sampled_at: nil, partition_stopped: true}] =
             Enum.reject(open_rows(), & &1.stream_key)

    # One stream counted once, however many records it has.
    assert_received {:event, [:cadence, :replay_id, :tripped_streams],
                     %{streams: 1, stream_headroom_bytes: 5_000}, _}

    assert_received {:event, [:cadence, :replay_id, :tripped], %{units: 1}, %{path: "timer"}}

    t1 = DateTime.add(t0, 10, :second)
    assert :ok = Sampler.sample_once(reading.(3), t1)
    assert Enum.all?(Enum.filter(open_rows(), & &1.stream_key), &(&1.dropping_since == t1))

    assert :ok = Sampler.sample_once(reading.(4), DateTime.add(t1, 10, :second))
    assert Enum.all?(Enum.filter(open_rows(), & &1.stream_key), &(&1.dropping_since == t1))
    :telemetry.detach(events)
  end

  test "a stream whose journal isn't running keeps its last reading" do
    unit = Recorder.stream_unit(:storage, @mission, "contact-2", "path-1", "binding-1")
    Recorder.track({:error, {:replay_id_conflict, :alarm_event, "aev_2"}}, unit, :clear)

    assert :ok = Sampler.sample_once(fn _row -> :not_running end, DateTime.utc_now())
    assert [%Row{buffer_sampled_at: nil}] = open_rows()
  end

  defp capture_events do
    test = self()
    handler = "replay-paths-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler,
      [[:cadence, :replay_id, :tripped], [:cadence, :replay_id, :tripped_streams]],
      fn event, measurements, meta, _ -> send(test, {:event, event, measurements, meta}) end,
      nil
    )

    handler
  end

  defp executor_loop(test_pid) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, _raw_evidence, _async_context, completion}}} ->
        send(test_pid, {:processing_enqueued, completion})
        executor_loop(test_pid)
    end
  end

  defp assert_eventually(assertion, attempts \\ 50) do
    assertion.()
  rescue
    error in [ExUnit.AssertionError, MatchError] ->
      if attempts > 1 do
        Process.sleep(20)
        assert_eventually(assertion, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
