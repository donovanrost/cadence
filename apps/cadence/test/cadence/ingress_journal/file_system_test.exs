defmodule Cadence.IngressJournal.FileSystemTest do
  use ExUnit.Case, async: true

  alias Cadence.IngressJournal.{Entry, Evidence, FileSystem}

  @context [
    mission_id: "mission-journal-test",
    realized_contact_id: "contact-journal-test",
    path_id: "path-journal-test"
  ]

  setup %{tmp_dir: tmp_dir} do
    provider_binding_id = "provider-#{System.unique_integer([:positive])}"
    name = {:via, Registry, {Cadence.Runtime.Registry, {:journal_test, provider_binding_id}}}

    opts =
      @context ++
        [
          name: name,
          provider_binding_id: provider_binding_id,
          base_path: tmp_dir,
          durability: :sync,
          max_bytes: 4_096,
          segment_bytes: 512,
          checkpoint_interval_ms: 10
        ]

    %{name: name, opts: opts}
  end

  @tag :tmp_dir
  test "captures immutable byte ranges and lets consumers read directly from segments", ctx do
    start_supervised!({FileSystem, ctx.opts})
    receipt_time = DateTime.utc_now()

    assert {:ok, first} = FileSystem.append(ctx.name, <<1, 2, 3>>, receipt_time, %{source: :tcp})
    assert {:ok, second} = FileSystem.append(ctx.name, <<4, 5>>, receipt_time, %{source: :tcp})

    assert %Entry{sequence: 0, start_offset: 0, end_offset: 3} = first
    assert %Entry{sequence: 1, start_offset: 3, end_offset: 5} = second
    assert {:ok, <<1, 2, 3>>} = Entry.read(first)
    assert {:ok, ^first} = FileSystem.next_entry(ctx.name, :processing)

    assert :ok = FileSystem.acknowledge(ctx.name, :processing, first.end_offset)
    assert {:ok, ^second} = FileSystem.next_entry(ctx.name, :processing)
    assert {:ok, ^first} = FileSystem.next_entry(ctx.name, :archive)

    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.next_offset == 5
    assert snapshot.lag_bytes.processing == 2
    assert snapshot.lag_bytes.archive == 5
  end

  @tag :tmp_dir
  test "reads bounded contiguous batches without advancing the consumer cursor", ctx do
    start_supervised!({FileSystem, ctx.opts})
    receipt_time = DateTime.utc_now()

    assert {:ok, first} = FileSystem.append(ctx.name, :binary.copy(<<1>>, 80), receipt_time)
    assert {:ok, second} = FileSystem.append(ctx.name, :binary.copy(<<2>>, 80), receipt_time)
    assert {:ok, _third} = FileSystem.append(ctx.name, :binary.copy(<<3>>, 80), receipt_time)

    assert {:ok, [^first, ^second]} = FileSystem.next_entries(ctx.name, :archive, 10, 160)
    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.cursors.archive == 0

    assert :ok = FileSystem.acknowledge(ctx.name, :archive, first.end_offset)
    assert {:ok, [^second]} = FileSystem.next_entries(ctx.name, :archive, 1, 1_024)
  end

  @tag :tmp_dir
  test "admits a stream receive as deterministic bounded logical records", ctx do
    opts = Keyword.put(ctx.opts, :capture_record_bytes, 4)
    start_supervised!({FileSystem, opts})
    receipt_time = DateTime.utc_now()

    assert {:ok, [first, second, third]} =
             FileSystem.append_stream(
               ctx.name,
               <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>,
               receipt_time,
               %{source: :tcp}
             )

    assert %Entry{sequence: 0, start_offset: 0, end_offset: 4, payload_length: 4} = first
    assert %Entry{sequence: 1, start_offset: 4, end_offset: 8, payload_length: 4} = second
    assert %Entry{sequence: 2, start_offset: 8, end_offset: 10, payload_length: 2} = third

    payload =
      [first, second, third]
      |> Enum.map(fn entry ->
        {:ok, bytes} = Entry.read(entry)
        bytes
      end)
      |> IO.iodata_to_binary()

    assert payload == <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>

    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.capture_record_bytes == 4
    assert snapshot.max_appended_entry_bytes == 4
    assert snapshot.appended_entries == 3
    assert snapshot.appended_bytes == 10
  end

  @tag :tmp_dir
  test "rejects a complete stream batch before admitting any subrecord", ctx do
    opts =
      Keyword.merge(ctx.opts,
        capture_record_bytes: 100,
        max_bytes: 300,
        segment_bytes: 1_024
      )

    start_supervised!({FileSystem, opts})

    assert {:error, :ingress_journal_full} =
             FileSystem.append_stream(
               ctx.name,
               :binary.copy(<<1>>, 200),
               DateTime.utc_now(),
               %{}
             )

    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.next_offset == 0
    assert snapshot.appended_entries == 0
    assert snapshot.retained_bytes == 0
    assert snapshot.full_count == 1
    assert :empty = FileSystem.next_entry(ctx.name, :processing)
  end

  @tag :tmp_dir
  test "recovers bounded stream records with stable range identity and provenance", ctx do
    opts = Keyword.put(ctx.opts, :capture_record_bytes, 4)
    start_supervised!({FileSystem, opts})
    metadata = %{mission_id: "mission-journal-test", protocol_family: :tm}

    assert {:ok, entries} =
             FileSystem.append_stream(
               ctx.name,
               <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>,
               DateTime.utc_now(),
               metadata
             )

    assert {:ok, original_evidence} = Evidence.from_contiguous_entries(entries)

    assert :ok =
             stop_supervised({:ingress_journal, Keyword.fetch!(ctx.opts, :provider_binding_id)})

    start_supervised!({FileSystem, opts})
    assert {:ok, recovered_entries} = FileSystem.next_entries(ctx.name, :processing, 3, 10)
    assert {:ok, recovered_evidence} = Evidence.from_contiguous_entries(recovered_entries)

    assert Enum.map(recovered_entries, &{&1.start_offset, &1.end_offset}) ==
             [{0, 4}, {4, 8}, {8, 10}]

    assert recovered_evidence.evidence_id == original_evidence.evidence_id
    assert recovered_evidence.raw == original_evidence.raw

    assert recovered_evidence.metadata["journal_capture_batch_id"] ==
             original_evidence.metadata["journal_capture_batch_id"]
  end

  @tag :tmp_dir
  test "recovers published records and truncates a torn tail", ctx do
    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, entry} = FileSystem.append(ctx.name, "captured", DateTime.utc_now(), %{})

    assert :ok =
             stop_supervised({:ingress_journal, Keyword.fetch!(ctx.opts, :provider_binding_id)})

    File.write!(entry.segment_path, <<0, 1, 2, 3, 4>>, [:append])
    start_supervised!({FileSystem, ctx.opts})

    assert {:ok, recovered} = FileSystem.next_entry(ctx.name, :processing)
    assert recovered.start_offset == entry.start_offset
    assert recovered.end_offset == entry.end_offset
    assert {:ok, "captured"} = Entry.read(recovered)
    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.recovery_truncations == 1
  end

  @tag :tmp_dir
  test "reclaims only after every required consumer cursor is checkpointed", ctx do
    opts = Keyword.merge(ctx.opts, segment_bytes: 100, checkpoint_interval_ms: 5)
    start_supervised!({FileSystem, opts})

    assert {:ok, first} =
             FileSystem.append(ctx.name, :binary.copy(<<1>>, 80), DateTime.utc_now(), %{})

    assert {:ok, second} =
             FileSystem.append(ctx.name, :binary.copy(<<2>>, 80), DateTime.utc_now(), %{})

    assert :ok = FileSystem.acknowledge(ctx.name, :processing, second.end_offset)
    Process.sleep(20)
    assert {:ok, waiting} = FileSystem.snapshot(ctx.name)
    assert waiting.segment_count == 2

    assert :ok = FileSystem.acknowledge(ctx.name, :archive, second.end_offset)

    assert_eventually(fn ->
      assert {:ok, reclaimed} = FileSystem.snapshot(ctx.name)
      assert reclaimed.segment_count == 1
      assert reclaimed.entry_count == 1
      assert reclaimed.reclaimed_segments == 1
    end)

    refute File.exists?(first.segment_path)

    assert :ok =
             stop_supervised({:ingress_journal, Keyword.fetch!(ctx.opts, :provider_binding_id)})

    start_supervised!({FileSystem, opts})
    assert {:ok, recovered} = FileSystem.snapshot(ctx.name)
    assert recovered.next_offset == second.end_offset
    assert recovered.cursors.processing == second.end_offset
    assert recovered.cursors.archive == second.end_offset

    assert {:ok, next_entry} =
             FileSystem.append(ctx.name, <<3>>, DateTime.utc_now(), %{})

    assert next_entry.start_offset == second.end_offset
  end

  @tag :tmp_dir
  test "reports append queueing and bounded checkpoint reclamation work", ctx do
    test_pid = self()
    handler_id = "journal-maintenance-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:cadence, :ingress_journal, :append],
          [:cadence, :ingress_journal, :reclaim],
          [:cadence, :ingress_journal, :maintenance]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:journal_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    opts =
      Keyword.merge(ctx.opts,
        durability: :page_cache,
        segment_bytes: 100,
        checkpoint_interval_ms: 5
      )

    start_supervised!({FileSystem, opts})

    assert {:ok, first} =
             FileSystem.append(ctx.name, :binary.copy(<<1>>, 80), DateTime.utc_now(), %{})

    assert_receive {:journal_event, [:cadence, :ingress_journal, :append], append, metadata}
    assert append.duration_us >= 0
    assert append.queue_wait_us >= 0
    assert metadata.durability == :page_cache

    assert {:ok, second} =
             FileSystem.append(ctx.name, :binary.copy(<<2>>, 80), DateTime.utc_now(), %{})

    assert {:ok, _third} =
             FileSystem.append(ctx.name, :binary.copy(<<3>>, 80), DateTime.utc_now(), %{})

    assert :ok =
             FileSystem.acknowledge(ctx.name, [:processing, :archive], second.end_offset)

    assert_receive {:journal_event, [:cadence, :ingress_journal, :reclaim], reclaimed, _metadata},
                   500

    assert reclaimed.entries == 2
    assert reclaimed.segments == 2
    assert reclaimed.bytes > 0

    assert_receive {:journal_event, [:cadence, :ingress_journal, :maintenance], maintenance,
                    metadata},
                   500

    assert maintenance.duration_us >= maintenance.checkpoint_duration_us
    assert maintenance.duration_us >= maintenance.reclaim_duration_us
    assert maintenance.queue_wait_us >= 0
    assert maintenance.queue_depth >= 0
    assert maintenance.entry_count_before == 3
    assert maintenance.entry_count_after == 1
    assert maintenance.reclaimed_entries == 2
    assert maintenance.reclaimed_segments == 2
    assert metadata.outcome == :ok
    refute File.exists?(first.segment_path)
  end

  @tag :tmp_dir
  test "keeps journal calls responsive while a cursor checkpoint is blocked", ctx do
    test_pid = self()

    checkpoint_writer = fn stream_path, cursors, next_offset, next_sequence ->
      send(test_pid, {:checkpoint_started, self()})

      receive do
        :finish_checkpoint ->
          write_checkpoint(stream_path, cursors, next_offset, next_sequence)
      after
        1_000 ->
          {:error, :checkpoint_test_timeout}
      end
    end

    opts =
      Keyword.merge(ctx.opts,
        durability: :page_cache,
        checkpoint_interval_ms: 5,
        checkpoint_writer: checkpoint_writer
      )

    start_supervised!({FileSystem, opts})

    assert {:ok, first} = FileSystem.append(ctx.name, "first", DateTime.utc_now(), %{})
    assert :ok = FileSystem.acknowledge(ctx.name, [:processing, :archive], first.end_offset)
    assert_receive {:checkpoint_started, checkpoint_pid}, 500

    assert {:ok, during_checkpoint} = FileSystem.snapshot(ctx.name)
    assert during_checkpoint.checkpoint_in_flight?
    assert during_checkpoint.durable_cursors.processing == 0

    assert {:ok, second} = FileSystem.append(ctx.name, "second", DateTime.utc_now(), %{})
    assert second.start_offset == first.end_offset
    send(checkpoint_pid, :finish_checkpoint)

    assert_eventually(fn ->
      assert {:ok, after_checkpoint} = FileSystem.snapshot(ctx.name)
      refute after_checkpoint.checkpoint_in_flight?
      assert after_checkpoint.durable_cursors.processing == first.end_offset
    end)
  end

  @tag :tmp_dir
  test "replays acknowledged entries after a crash before cursor checkpoint", ctx do
    opts = Keyword.merge(ctx.opts, checkpoint_interval_ms: 60_000)
    start_supervised!({FileSystem, opts})

    assert {:ok, entry} = FileSystem.append(ctx.name, "replay-me", DateTime.utc_now(), %{})
    assert :ok = FileSystem.acknowledge(ctx.name, [:processing, :archive], entry.end_offset)
    assert {:ok, old_pid} = FileSystem.lookup(ctx.name)

    Process.exit(old_pid, :kill)

    assert_eventually(fn ->
      assert {:ok, restarted_pid} = FileSystem.lookup(ctx.name)
      assert restarted_pid != old_pid
      assert Process.alive?(restarted_pid)
    end)

    assert {:ok, recovered} = FileSystem.snapshot(ctx.name)
    assert recovered.cursors.processing == 0
    assert recovered.cursors.archive == 0
    assert {:ok, replayed} = FileSystem.next_entry(ctx.name, :archive)
    assert replayed.start_offset == entry.start_offset
    assert replayed.end_offset == entry.end_offset
  end

  @tag :tmp_dir
  test "rejects admission before exceeding the configured bound", ctx do
    opts = Keyword.merge(ctx.opts, max_bytes: 500, segment_bytes: 1_024)
    start_supervised!({FileSystem, opts})

    assert {:ok, _entry} =
             FileSystem.append(ctx.name, :binary.copy(<<1>>, 100), DateTime.utc_now(), %{})

    assert {:error, :ingress_journal_full} =
             FileSystem.append(ctx.name, :binary.copy(<<2>>, 100), DateTime.utc_now(), %{})

    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.retained_bytes <= snapshot.max_bytes
    assert snapshot.full_count == 1
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

  defp write_checkpoint(stream_path, cursors, next_offset, next_sequence) do
    contents =
      :erlang.term_to_binary(%{
        version: 1,
        cursors: cursors,
        next_offset: next_offset,
        next_sequence: next_sequence
      })

    File.write(Path.join(stream_path, "cursors.term"), contents, [:binary])
  end
end
