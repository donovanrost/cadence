defmodule Cadence.IngressJournal.IngestTelemetryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.IngressJournal.IngestTelemetry
  alias Cadence.Runtime.IngressJournalConsumer
  alias Cadence.Telemetry.Sample

  test "counts a processing result's frames, packets and samples (not other outputs)" do
    result = %{
      transfer_frame_records: [:frame, :frame],
      packet_records: [:packet, :packet, :packet],
      outputs: [struct(Sample), struct(Sample), %{kind: :not_a_sample}]
    }

    assert IngestTelemetry.counts(result) == %{frames: 2, packets: 3, samples: 2}
    assert IngestTelemetry.counts(%{}) == %{frames: 0, packets: 0, samples: 0}
  end

  @tag :tmp_dir
  test "an acknowledged batch emits batch.stop with its counts, lag and path", %{tmp_dir: tmp_dir} do
    ids = ids("batch")
    attach(IngestTelemetry.batch_stop_event(), ids.provider_binding_id)
    start_journal!(ids, tmp_dir, 60_000)

    receipt_time = DateTime.add(DateTime.utc_now(), -2, :second)

    assert {:ok, _entry} =
             IngressJournal.append(ids.journal, <<1, 2, 3, 4>>, receipt_time, %{
               mission_id: ids.mission_id,
               protocol_family: :tm
             })

    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)
    consumer = start_consumer!(ids, executor)

    assert_receive {:processing_enqueued, {^consumer, ref}}, 5_000
    counts = %{frames: 1, packets: 2, samples: 29}
    send(consumer, {:provider_ingress_persisted, self(), ref, %{counts: counts}})

    assert_receive {:ingest_event, measurements, metadata}, 2_000
    assert %{entries: 1, bytes: 4, frames: 1, packets: 2, samples: 29} = measurements
    assert measurements.journal_lag_ms >= 2_000
    assert measurements.duration_us >= 0

    assert metadata == %{
             mission_id: ids.mission_id,
             path_id: ids.path_id,
             provider_binding_id: ids.provider_binding_id,
             realized_contact_id: ids.realized_contact_id
           }
  end

  @tag :tmp_dir
  test "the journal reports its processing backlog, and nothing once it is acknowledged",
       %{tmp_dir: tmp_dir} do
    ids = ids("backlog")
    attach(IngestTelemetry.journal_backlog_event(), ids.provider_binding_id)
    start_journal!(ids, tmp_dir, 5)

    receipt_time = DateTime.add(DateTime.utc_now(), -3, :second)

    assert {:ok, entry} =
             IngressJournal.append(ids.journal, <<1, 2, 3, 4, 5, 6>>, receipt_time, %{
               mission_id: ids.mission_id,
               protocol_family: :tm
             })

    assert_receive {:ingest_event, %{bytes: bytes, oldest_unacked_age_ms: age}, metadata}, 2_000
    assert bytes == entry.end_offset
    assert age >= 3_000
    assert metadata.path_id == ids.path_id

    assert :ok =
             IngressJournal.acknowledge(ids.journal, [:processing, :archive], entry.end_offset)

    # Reported at most once a second: the next report shows the backlog gone.
    assert_receive {:ingest_event, %{bytes: 0, oldest_unacked_age_ms: 0}, _metadata}, 3_000
  end

  defp ids(name) do
    unique = System.unique_integer([:positive])

    %{
      journal: :"ingest_telemetry_#{name}_journal_#{unique}",
      mission_id: "mission-ingest-telemetry-#{name}",
      realized_contact_id: "contact-ingest-telemetry-#{name}",
      path_id: "path-ingest-telemetry-#{name}-#{unique}",
      provider_binding_id: "provider-ingest-telemetry-#{name}-#{unique}"
    }
  end

  # Forwards only this test's events: async tests share the global :telemetry handlers.
  defp attach(event, provider_binding_id) do
    test_pid = self()
    handler_id = "ingest-telemetry-test-#{provider_binding_id}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, measurements, metadata, _config ->
          if metadata.provider_binding_id == provider_binding_id,
            do: send(test_pid, {:ingest_event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp start_journal!(ids, tmp_dir, checkpoint_interval_ms) do
    start_supervised!(
      {IngressJournal,
       name: ids.journal,
       mission_id: ids.mission_id,
       realized_contact_id: ids.realized_contact_id,
       path_id: ids.path_id,
       provider_binding_id: ids.provider_binding_id,
       base_path: tmp_dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       capture_record_bytes: 1_024,
       checkpoint_interval_ms: checkpoint_interval_ms}
    )
  end

  defp start_consumer!(ids, executor) do
    start_supervised!(
      {IngressJournalConsumer,
       name: :"ingest_telemetry_consumer_#{System.unique_integer([:positive])}",
       mission_id: ids.mission_id,
       realized_contact_id: ids.realized_contact_id,
       path_id: ids.path_id,
       provider_binding_id: ids.provider_binding_id,
       journal_name: ids.journal,
       executor_name: executor,
       poll_interval_ms: 5}
    )
  end

  defp executor_loop(test_pid) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, _raw_evidence, _async_context, completion}}} ->
        send(test_pid, {:processing_enqueued, completion})
        executor_loop(test_pid)
    end
  end
end
