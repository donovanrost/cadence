defmodule Cadence.Runtime.IngressJournalConsumerTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Runtime.IngressJournalConsumer

  @tag :tmp_dir
  test "semantic completion advances only the processing cursor", %{tmp_dir: tmp_dir} do
    provider_binding_id = "provider-processing-#{System.unique_integer([:positive])}"
    journal_name = :"processing_consumer_journal_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressJournal,
       name: journal_name,
       mission_id: "mission-processing-consumer",
       realized_contact_id: "contact-processing-consumer",
       path_id: "path-processing-consumer",
       provider_binding_id: provider_binding_id,
       base_path: tmp_dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       checkpoint_interval_ms: 60_000}
    )

    {:ok, entry} =
      IngressJournal.append(
        journal_name,
        <<1, 2, 3, 4>>,
        DateTime.utc_now(),
        %{mission_id: "mission-processing-consumer", protocol_family: :tm}
      )

    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         name: :"processing_consumer_#{System.unique_integer([:positive])}",
         mission_id: "mission-processing-consumer",
         realized_contact_id: "contact-processing-consumer",
         path_id: "path-processing-consumer",
         provider_binding_id: provider_binding_id,
         journal_name: journal_name,
         executor_name: executor,
         poll_interval_ms: 5}
      )

    assert_receive {:processing_enqueued, %RawEvidence{} = raw_evidence, {^consumer, ref}}, 5_000
    assert raw_evidence.raw == <<1, 2, 3, 4>>
    assert raw_evidence.metadata["journal_start_offset"] == entry.start_offset
    assert raw_evidence.metadata["journal_end_offset"] == entry.end_offset

    quiesce_task = Task.async(fn -> IngressJournalConsumer.quiesce(consumer) end)
    assert Task.yield(quiesce_task, 0) == nil

    send(consumer, {:provider_ingress_persisted, self(), ref})

    assert {:ok,
            %{
              status: :quiesced,
              acknowledged_batches: 1,
              acknowledged_entries: 1,
              acknowledged_bytes: 4
            }} = Task.await(quiesce_task)

    assert {:ok, snapshot} = IngressJournal.snapshot(journal_name)
    assert snapshot.cursors.processing == entry.end_offset
    assert snapshot.cursors.archive == 0
  end

  @tag :tmp_dir
  test "combines bounded contiguous records into one semantic work item", %{tmp_dir: tmp_dir} do
    provider_binding_id = "provider-processing-batch-#{System.unique_integer([:positive])}"
    journal_name = :"processing_batch_journal_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressJournal,
       name: journal_name,
       mission_id: "mission-processing-batch",
       realized_contact_id: "contact-processing-batch",
       path_id: "path-processing-batch",
       provider_binding_id: provider_binding_id,
       base_path: tmp_dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       capture_record_bytes: 4,
       checkpoint_interval_ms: 60_000}
    )

    metadata = %{mission_id: "mission-processing-batch", protocol_family: :tm}

    assert {:ok, [first, second, third]} =
             IngressJournal.append_stream(
               journal_name,
               <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>,
               DateTime.utc_now(),
               metadata
             )

    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         name: :"processing_batch_consumer_#{System.unique_integer([:positive])}",
         mission_id: "mission-processing-batch",
         realized_contact_id: "contact-processing-batch",
         path_id: "path-processing-batch",
         provider_binding_id: provider_binding_id,
         journal_name: journal_name,
         executor_name: executor,
         processing_max_batch_entries: 3,
         processing_max_batch_bytes: 10,
         poll_interval_ms: 5}
      )

    assert_receive {:processing_enqueued, %RawEvidence{} = raw_evidence, {^consumer, ref}}, 5_000
    assert raw_evidence.raw == <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
    assert raw_evidence.metadata["journal_sequence"] == first.sequence
    assert raw_evidence.metadata["journal_end_sequence"] == third.sequence
    assert raw_evidence.metadata["journal_record_count"] == 3
    assert raw_evidence.metadata["journal_start_offset"] == first.start_offset
    assert raw_evidence.metadata["journal_end_offset"] == third.end_offset

    send(consumer, {:provider_ingress_persisted, self(), ref})

    assert_eventually(fn ->
      assert {:ok, snapshot} = IngressJournal.snapshot(journal_name)
      assert snapshot.cursors.processing == third.end_offset
      assert snapshot.cursors.archive == 0

      assert {:ok, consumer_snapshot} = IngressJournalConsumer.snapshot(consumer)
      assert consumer_snapshot.acknowledged_batches == 1
      assert consumer_snapshot.acknowledged_entries == 3
      assert consumer_snapshot.acknowledged_bytes == 10
      assert consumer_snapshot.max_delivered_batch_entries == 3
      assert consumer_snapshot.max_delivered_batch_bytes == 10
    end)

    assert second.start_offset == first.end_offset
  end

  @tag :tmp_dir
  test "batches across socket capture boundaries while retaining their provenance", %{
    tmp_dir: tmp_dir
  } do
    provider_binding_id = "provider-processing-captures-#{System.unique_integer([:positive])}"
    journal_name = :"processing_capture_journal_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressJournal,
       name: journal_name,
       mission_id: "mission-processing-captures",
       realized_contact_id: "contact-processing-captures",
       path_id: "path-processing-captures",
       provider_binding_id: provider_binding_id,
       base_path: tmp_dir,
       durability: :sync,
       max_bytes: 1_024 * 1_024,
       segment_bytes: 64 * 1_024,
       capture_record_bytes: 4,
       checkpoint_interval_ms: 60_000}
    )

    metadata = %{mission_id: "mission-processing-captures", protocol_family: :tm}

    assert {:ok, first_capture} =
             IngressJournal.append_stream(
               journal_name,
               <<0, 1, 2, 3, 4, 5>>,
               DateTime.utc_now(),
               metadata
             )

    assert {:ok, second_capture} =
             IngressJournal.append_stream(
               journal_name,
               <<6, 7, 8, 9, 10, 11>>,
               DateTime.utc_now(),
               metadata
             )

    test_pid = self()
    executor = spawn(fn -> executor_loop(test_pid) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         name: :"processing_capture_consumer_#{System.unique_integer([:positive])}",
         mission_id: "mission-processing-captures",
         realized_contact_id: "contact-processing-captures",
         path_id: "path-processing-captures",
         provider_binding_id: provider_binding_id,
         journal_name: journal_name,
         executor_name: executor,
         processing_max_batch_entries: 4,
         processing_max_batch_bytes: 12,
         poll_interval_ms: 5}
      )

    assert_receive {:processing_enqueued, %RawEvidence{} = raw_evidence, {^consumer, ref}}, 5_000
    assert raw_evidence.raw == <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11>>
    assert raw_evidence.metadata["journal_record_count"] == 4
    assert raw_evidence.metadata["journal_capture_batch_count"] == 2
    assert raw_evidence.metadata["journal_capture_batch_id"] == nil

    assert raw_evidence.metadata["journal_capture_batch_ids"] == [
             capture_batch_id(first_capture),
             capture_batch_id(second_capture)
           ]

    send(consumer, {:provider_ingress_persisted, self(), ref})

    assert_eventually(fn ->
      assert {:ok, snapshot} = IngressJournalConsumer.snapshot(consumer)
      assert snapshot.acknowledged_batches == 1
      assert snapshot.acknowledged_entries == 4
      assert snapshot.acknowledged_bytes == 12
    end)
  end

  @tag :tmp_dir
  test "failures back off without rebatching, losing custody, or accepting stale completions", %{
    tmp_dir: path
  } do
    journal =
      start_supervised!(
        {IngressJournal,
         mission_id: "retry",
         realized_contact_id: "contact",
         path_id: "path",
         provider_binding_id: "provider",
         base_path: path,
         durability: :sync}
      )

    metadata = %{mission_id: "retry", protocol_family: :tm}
    {:ok, first} = IngressJournal.append(journal, <<1, 2, 3>>, DateTime.utc_now(), metadata)
    test = self()
    executor = spawn(fn -> executor_loop(test, true) end)
    on_exit(fn -> Process.exit(executor, :kill) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         mission_id: "retry",
         realized_contact_id: "contact",
         path_id: "path",
         provider_binding_id: "provider",
         journal_name: journal,
         executor_name: executor,
         poll_interval_ms: 5,
         retry_initial_ms: 100,
         retry_max_ms: 200}
      )

    assert_receive {:processing_enqueued, raw, {^consumer, ref}}, 1_000
    {:ok, last} = IngressJournal.append(journal, <<4, 5, 6>>, DateTime.utc_now(), metadata)
    failed_at = System.monotonic_time(:millisecond)
    send(consumer, {:provider_ingress_failed, executor, ref, :bad_frame})
    # Neither polling nor quiescence may bypass the backoff.
    send(consumer, :consume)
    quiesce = Task.async(fn -> IngressJournalConsumer.quiesce(consumer) end)
    assert Task.yield(quiesce, 0) == nil

    assert {:ok, %{retry_delay_ms: 100, consecutive_failures: 1}} =
             IngressJournalConsumer.snapshot(consumer)

    assert_receive {:processing_enqueued, ^raw, {^consumer, retry_ref}}, 1_000
    # Measure when the executor received the retry. A busy scheduler may resume
    # this test after the whole backoff has elapsed, making refute_receive race.
    assert_receive {:processing_enqueued_at, {^consumer, ^retry_ref}, retried_at}
    assert retried_at - failed_at >= 100
    send(consumer, {:provider_ingress_persisted, executor, ref})
    send(consumer, {:provider_ingress_failed, executor, retry_ref, :bad_frame})

    assert {:ok, %{retry_delay_ms: 200, consecutive_failures: 2}} =
             IngressJournalConsumer.snapshot(consumer)

    assert {:ok, %{cursors: %{processing: 0, archive: 0}}} = IngressJournal.snapshot(journal)
    assert_receive {:processing_enqueued, ^raw, {^consumer, final_ref}}, 1_000
    send(consumer, {:provider_ingress_failed, executor, final_ref, :bad_frame})

    assert {:ok, %{retry_delay_ms: 200, consecutive_failures: 3}} =
             IngressJournalConsumer.snapshot(consumer)

    assert_receive {:processing_enqueued, ^raw, {^consumer, capped_ref}}, 1_000
    send(consumer, {:provider_ingress_persisted, executor, capped_ref})
    assert_receive {:processing_enqueued, next, {^consumer, next_ref}}, 1_000
    assert Task.yield(quiesce, 0) == nil
    assert next.raw == <<4, 5, 6>>
    assert next.metadata["journal_start_offset"] == first.end_offset

    assert {:ok, %{consecutive_failures: 0, retry_delay_ms: 0}} =
             IngressJournalConsumer.snapshot(consumer)

    send(consumer, {:provider_ingress_persisted, executor, next_ref})
    assert {:ok, %{status: :quiesced}} = Task.await(quiesce)

    assert_eventually(fn ->
      assert {:ok, %{cursors: %{processing: offset, archive: 0}}} =
               IngressJournal.snapshot(journal)

      assert offset == last.end_offset
    end)
  end

  @tag :tmp_dir
  test "an acknowledgement failure retries custody without decoding the bytes again", %{
    tmp_dir: path
  } do
    journal =
      start_supervised!(
        {IngressJournal,
         mission_id: "ack-retry",
         realized_contact_id: "contact",
         path_id: "path",
         provider_binding_id: "provider",
         base_path: path,
         durability: :sync}
      )

    {:ok, entry} =
      IngressJournal.append(journal, <<1, 2, 3>>, DateTime.utc_now(), %{
        mission_id: "ack-retry",
        protocol_family: :tm
      })

    test = self()
    executor = spawn(fn -> executor_loop(test) end)
    proxy = spawn(fn -> journal_proxy(journal, test, true) end)
    on_exit(fn -> Enum.each([executor, proxy], &Process.exit(&1, :kill)) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         mission_id: "ack-retry",
         realized_contact_id: "contact",
         path_id: "path",
         provider_binding_id: "provider",
         journal_name: proxy,
         executor_name: executor,
         poll_interval_ms: 5,
         retry_initial_ms: 100}
      )

    assert_receive {:processing_enqueued, _, {^consumer, ref}}, 1_000
    send(consumer, {:provider_ingress_persisted, executor, ref})
    assert_receive :ack_failed, 1_000

    assert {:ok, %{phase: :acknowledge, failed_count: 1}} =
             IngressJournalConsumer.snapshot(consumer)

    assert_receive :ack_retried, 1_000

    assert_eventually(fn ->
      assert {:ok, %{cursors: %{processing: offset}}} = IngressJournal.snapshot(journal)
      assert offset == entry.end_offset
    end)

    refute_receive {:processing_enqueued, _, _}, 50
  end

  defp journal_proxy(journal, test, fail?) do
    receive do
      {:"$gen_call", from, {:acknowledge, _, _}} when fail? ->
        GenServer.reply(from, {:error, :injected_custody_failure})
        send(test, :ack_failed)
        journal_proxy(journal, test, false)

      {:"$gen_call", from, request} ->
        result = GenServer.call(journal, request)
        GenServer.reply(from, result)
        if match?({:acknowledge, _, _}, request), do: send(test, :ack_retried)
        journal_proxy(journal, test, fail?)
    end
  end

  defp executor_loop(test_pid, timestamp? \\ false) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, raw_evidence, _async_context, completion}}} ->
        if timestamp? do
          send(
            test_pid,
            {:processing_enqueued_at, completion, System.monotonic_time(:millisecond)}
          )
        end

        send(test_pid, {:processing_enqueued, raw_evidence, completion})
        executor_loop(test_pid, timestamp?)
    end
  end

  defp assert_eventually(assertion, attempts \\ 20)

  defp assert_eventually(assertion, attempts) when attempts > 1 do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
  end

  defp assert_eventually(assertion, 1), do: assertion.()

  defp capture_batch_id([entry | _rest]), do: entry.metadata.journal_capture_batch_id
end
