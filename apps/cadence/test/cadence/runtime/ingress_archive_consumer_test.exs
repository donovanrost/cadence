defmodule Cadence.Runtime.IngressArchiveConsumerTest do
  use Cadence.UnitCase, async: false

  alias Cadence.ControllableIngressArchive
  alias Cadence.IngressArchive.Batch
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Runtime.IngressArchiveConsumer

  @context [
    mission_id: "mission-archive-consumer",
    realized_contact_id: "contact-archive-consumer",
    path_id: "path-archive-consumer"
  ]

  setup %{tmp_dir: tmp_dir} do
    start_supervised!(ControllableIngressArchive)
    provider_binding_id = "provider-archive-#{System.unique_integer([:positive])}"
    journal_name = :"archive_consumer_journal_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressJournal,
       @context ++
         [
           name: journal_name,
           provider_binding_id: provider_binding_id,
           base_path: tmp_dir,
           durability: :sync,
           max_bytes: 1_024 * 1_024,
           segment_bytes: 64 * 1_024,
           checkpoint_interval_ms: 60_000
         ]}
    )

    %{
      journal_name: journal_name,
      provider_binding_id: provider_binding_id
    }
  end

  @tag :tmp_dir
  test "archives a contiguous batch and advances only the archive cursor", ctx do
    first = append!(ctx.journal_name, :binary.copy(<<1>>, 64))
    second = append!(ctx.journal_name, :binary.copy(<<2>>, 96))
    consumer = start_consumer!(ctx)

    assert_eventually(fn ->
      assert {:ok, journal} = IngressJournal.snapshot(ctx.journal_name)
      assert journal.cursors.archive == second.end_offset
      assert journal.cursors.processing == 0
    end)

    assert {:ok, snapshot} = IngressArchiveConsumer.snapshot(consumer)
    assert snapshot.batch_count == 1
    assert snapshot.archived_entries == 2
    assert snapshot.archived_bytes == 160
    assert snapshot.failed_count == 0
    assert snapshot.pending_batch == nil

    assert [%Batch{} = batch] = ControllableIngressArchive.calls()
    assert batch.start_offset == first.start_offset
    assert batch.end_offset == second.end_offset
    assert batch.item_count == 2
  end

  @tag :tmp_dir
  test "coalesces journal entries that arrive during the bounded dwell", ctx do
    first = append!(ctx.journal_name, :binary.copy(<<5>>, 64))
    consumer = start_consumer!(ctx, max_dwell_ms: 100)

    assert_eventually(fn ->
      assert {:ok, snapshot} = IngressArchiveConsumer.snapshot(consumer)
      assert snapshot.dwell_age_ms > 0
      assert ControllableIngressArchive.calls() == []
    end)

    second = append!(ctx.journal_name, :binary.copy(<<6>>, 96))

    assert_eventually(fn ->
      assert {:ok, journal} = IngressJournal.snapshot(ctx.journal_name)
      assert journal.cursors.archive == second.end_offset
    end)

    assert [%Batch{} = batch] = ControllableIngressArchive.calls()
    assert batch.start_offset == first.start_offset
    assert batch.end_offset == second.end_offset
    assert batch.item_count == 2
  end

  @tag :tmp_dir
  test "retries the same deterministic batch after an archive effect failure", ctx do
    :ok = ControllableIngressArchive.reset(failures_remaining: 1)
    entry = append!(ctx.journal_name, :binary.copy(<<3>>, 128))
    consumer = start_consumer!(ctx)

    assert_eventually(fn ->
      assert {:ok, journal} = IngressJournal.snapshot(ctx.journal_name)
      assert journal.cursors.archive == entry.end_offset
    end)

    assert {:ok, snapshot} = IngressArchiveConsumer.snapshot(consumer)
    assert snapshot.failed_count == 1
    assert snapshot.retry_count == 1
    assert snapshot.batch_count == 1
    assert snapshot.last_recovered_at != nil

    assert [%Batch{} = first_attempt, %Batch{} = retry] = ControllableIngressArchive.calls()
    assert first_attempt.batch_id == retry.batch_id
    assert first_attempt.start_offset == retry.start_offset
    assert first_attempt.end_offset == retry.end_offset
  end

  @tag :tmp_dir
  test "does not advance a durable cursor for an accepted-only receipt", ctx do
    :ok = ControllableIngressArchive.reset(completion: :accepted)
    entry = append!(ctx.journal_name, :binary.copy(<<4>>, 80))
    consumer = start_consumer!(ctx, required_completion: :durable, retry_initial_ms: 50)

    assert_eventually(fn ->
      assert {:ok, snapshot} = IngressArchiveConsumer.snapshot(consumer)
      assert snapshot.failed_count >= 1
      assert snapshot.pending_batch != nil
    end)

    assert {:ok, waiting} = IngressJournal.snapshot(ctx.journal_name)
    assert waiting.cursors.archive == 0
    assert waiting.lag_bytes.archive == entry.end_offset

    :ok = ControllableIngressArchive.set_completion(:durable)

    assert_eventually(fn ->
      assert {:ok, archived} = IngressJournal.snapshot(ctx.journal_name)
      assert archived.cursors.archive == entry.end_offset
    end)
  end

  defp start_consumer!(ctx, opts \\ []) do
    name = :"archive_consumer_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressArchiveConsumer,
       @context ++
         [
           name: name,
           provider_binding_id: ctx.provider_binding_id,
           journal_name: ctx.journal_name,
           archive_module: ControllableIngressArchive,
           required_completion: Keyword.get(opts, :required_completion, :durable),
           max_batch_entries: 10,
           max_batch_bytes: 1_024,
           max_dwell_ms: Keyword.get(opts, :max_dwell_ms, 5),
           poll_interval_ms: 5,
           retry_initial_ms: Keyword.get(opts, :retry_initial_ms, 5),
           retry_max_ms: 50
         ]}
    )

    name
  end

  defp append!(journal_name, payload) do
    metadata = %{
      mission_id: "mission-archive-consumer",
      protocol_family: :tm,
      ingress_metadata: %{}
    }

    {:ok, entry} = IngressJournal.append(journal_name, payload, DateTime.utc_now(), metadata)
    entry
  end

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 1 do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
  end

  defp assert_eventually(assertion, 1), do: assertion.()
end
