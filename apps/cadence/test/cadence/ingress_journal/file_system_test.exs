defmodule Cadence.IngressJournal.FileSystemTest do
  use ExUnit.Case, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.{Entry, Evidence, FileSystem, Identity}

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
          # Production's durability (fsync per append). config/test.exs uses :page_cache for the
          # runtime, so these tests are where seal, torn-tail recovery and crash-before-checkpoint
          # replay run under :sync (director's follow-up 4, 11-14; docs/apogee/plans/ingress-time-tags.md).
          durability: :sync,
          max_bytes: 4_096,
          segment_bytes: 512,
          checkpoint_interval_ms: 10
        ]

    %{name: name, opts: opts}
  end

  @tag :tmp_dir
  test "sealing requires both consumers, persists their positions, and closes admission", ctx do
    start_supervised!({FileSystem, Keyword.put(ctx.opts, :checkpoint_interval_ms, 60_000)})
    assert {:ok, entry} = FileSystem.append(ctx.name, "captured", DateTime.utc_now())
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, entry.end_offset)
    assert {:error, {:journal_not_drained, _, _}} = FileSystem.seal(ctx.name)
    assert :ok = FileSystem.acknowledge(ctx.name, :archive, entry.end_offset)
    assert {:ok, %{tail: tail, cursors: cursors}} = FileSystem.seal(ctx.name)
    assert tail == 8
    assert cursors == %{processing: 8, archive: 8}
    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)

    checkpoint =
      snapshot.stream_path
      |> Path.join("cursors.term")
      |> File.read!()
      |> :erlang.binary_to_term([:safe])

    assert checkpoint.cursors == cursors
    assert checkpoint.next_offset == tail

    assert {:error, :ingress_journal_sealed} =
             FileSystem.append_stream(ctx.name, "later", DateTime.utc_now())
  end

  describe "stored streams: drained on disk, and reclaim (#71 follow-up)" do
    @describetag :tmp_dir

    test "a sealed stream is drained on disk and its directory can be reclaimed", ctx do
      %{directory: directory, stream_id: stream_id} = stored!(ctx, [:processing, :archive])

      assert {:drained, bytes} = FileSystem.stored_stream_drain(directory, stream_id)
      assert bytes > 0
      assert :ok = FileSystem.reclaim_stored_stream(ctx.tmp_dir, directory)
      refute File.exists?(directory)
      assert FileSystem.stored_stream_directories(ctx.tmp_dir) == []
    end

    test "an archive or processing cursor behind the tail is not drained", ctx do
      for acked <- [[:processing], [:archive]] do
        %{directory: directory, stream_id: stream_id} = stored!(ctx, acked)

        assert {:not_drained, {:cursors_behind, [{_consumer, 0}], tail}, _bytes} =
                 FileSystem.stored_stream_drain(directory, stream_id)

        assert tail > 0
        File.rm_rf!(directory)
      end
    end

    test "a torn tail is not drained, and checking it leaves the bytes alone", ctx do
      %{directory: directory, stream_id: stream_id} = stored!(ctx, [:processing, :archive])
      [segment] = Path.wildcard(Path.join(directory, "segment-*.cij"))
      File.write!(segment, "torn", [:append])
      size = File.stat!(segment).size

      assert {:not_drained, {:torn_tail, _path}, _bytes} =
               FileSystem.stored_stream_drain(directory, stream_id)

      assert File.stat!(segment).size == size
    end

    test "an unreadable stream.term isn't listed; a path outside the base is never removed",
         ctx do
      %{directory: directory} = stored!(ctx, [:processing, :archive])
      File.write!(Path.join(directory, "stream.term"), "not a term")
      assert FileSystem.stored_stream_directories(ctx.tmp_dir) == []

      outside =
        Path.join(System.tmp_dir!(), "cadence-reclaim-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)

      for target <- [outside, Path.join(directory, "nested"), Path.join(ctx.tmp_dir, "..")] do
        assert {:error, {:reclaim_outside_base_path, _}} =
                 FileSystem.reclaim_stored_stream(ctx.tmp_dir, target)
      end

      assert File.dir?(outside)
      File.rm_rf!(outside)
    end
  end

  # A stream with one record, its given consumers acknowledged, stopped (terminate checkpoints).
  defp stored!(ctx, acked) do
    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, entry} = FileSystem.append(ctx.name, "captured", DateTime.utc_now())
    for consumer <- acked, do: :ok = FileSystem.acknowledge(ctx.name, consumer, entry.end_offset)
    :ok = stop_supervised({:ingress_journal, ctx.opts[:provider_binding_id]})
    [stream] = FileSystem.stored_stream_directories(ctx.tmp_dir)
    stream
  end

  @tag :tmp_dir
  test "a runtime stop checkpoints the acknowledged cursors (#71 follow-up)", ctx do
    start_supervised!({FileSystem, Keyword.put(ctx.opts, :checkpoint_interval_ms, 60_000)})
    assert {:ok, entry} = FileSystem.append(ctx.name, "captured", DateTime.utc_now())
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, entry.end_offset)
    assert {:ok, %{stream_path: stream_path}} = FileSystem.snapshot(ctx.name)

    # No periodic checkpoint yet; the supervisor's shutdown must write it.
    :ok = stop_supervised({:ingress_journal, ctx.opts[:provider_binding_id]})

    checkpoint =
      stream_path
      |> Path.join("cursors.term")
      |> File.read!()
      |> :erlang.binary_to_term([:safe])

    assert checkpoint.cursors.processing == entry.end_offset
    assert checkpoint.cursors.archive == 0
  end

  @tag :tmp_dir
  test "a periodic checkpoint still in flight at a stop can't overwrite the final one", ctx do
    test_pid = self()

    # The periodic writer stalls, then would write the cursors it was given (older than the
    # final ones) if it were ever released (api-ops' ordering check).
    stalling_writer = fn stream_path, cursors, next_offset, next_sequence ->
      send(test_pid, {:checkpoint_in_flight, self()})

      receive do
        :release ->
          File.write!(
            Path.join(stream_path, "cursors.term"),
            :erlang.term_to_binary(%{
              version: 1,
              cursors: cursors,
              next_offset: next_offset,
              next_sequence: next_sequence
            })
          )
      end
    end

    opts = Keyword.merge(ctx.opts, checkpoint_interval_ms: 10, checkpoint_writer: stalling_writer)
    start_supervised!({FileSystem, opts})
    assert {:ok, first} = FileSystem.append(ctx.name, "first", DateTime.utc_now())
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, first.end_offset)
    assert_receive {:checkpoint_in_flight, writer}

    assert {:ok, second} = FileSystem.append(ctx.name, "second", DateTime.utc_now())
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, second.end_offset)
    assert {:ok, %{stream_path: stream_path}} = FileSystem.snapshot(ctx.name)

    :ok = stop_supervised({:ingress_journal, ctx.opts[:provider_binding_id]})
    refute Process.alive?(writer)
    send(writer, :release)

    checkpoint =
      stream_path
      |> Path.join("cursors.term")
      |> File.read!()
      |> :erlang.binary_to_term([:safe])

    assert checkpoint.cursors.processing == second.end_offset
  end

  @tag :tmp_dir
  test "a linked process's crash still stops the journal; a normal exit doesn't", ctx do
    journal = start_supervised!({FileSystem, ctx.opts}, restart: :temporary)
    ref = Process.monitor(journal)

    # No timing windows (flaky under load in the hook runs): each linked process is monitored,
    # and the journal is synced with a call after the linked process is gone.
    linked = fn reason ->
      {pid, linked_ref} =
        spawn_monitor(fn ->
          Process.link(journal)
          exit(reason)
        end)

      assert_receive {:DOWN, ^linked_ref, :process, ^pid, ^reason}, 5_000
    end

    linked.(:normal)
    # The exit signal reached the journal before this call (it was sent before the DOWN above),
    # so a reply means the journal handled it and kept running.
    assert {:ok, _snapshot} = FileSystem.snapshot(ctx.name)
    assert Process.alive?(journal)
    refute_received {:DOWN, ^ref, :process, ^journal, _reason}

    linked.(:writer_crashed)
    assert_receive {:DOWN, ^ref, :process, ^journal, :writer_crashed}, 5_000
  end

  @tag :tmp_dir
  test "failed final checkpoint is not a successful drain", ctx do
    opts =
      Keyword.merge(ctx.opts,
        checkpoint_interval_ms: 60_000,
        checkpoint_writer: fn _, _, _, _ -> {:error, :enospc} end
      )

    start_supervised!({FileSystem, opts})
    assert {:error, {:journal_seal_failed, :enospc}} = FileSystem.seal(ctx.name)

    assert {:error, :ingress_journal_sealed} =
             FileSystem.append(ctx.name, "later", DateTime.utc_now())
  end

  @tag :tmp_dir
  test "fresh storage never reuses identities for the same contact and byte positions", ctx do
    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, original} = FileSystem.append(ctx.name, "first", DateTime.utc_now())
    child_id = {:ingress_journal, Keyword.fetch!(ctx.opts, :provider_binding_id)}
    assert :ok = stop_supervised(child_id)

    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, replay} = FileSystem.next_entry(ctx.name, :processing)
    assert Identity.evidence_id(replay) == Identity.evidence_id(original)
    assert {:ok, next} = FileSystem.append(ctx.name, "later", DateTime.utc_now())
    assert next.start_offset == original.end_offset
    assert next.stream_id == original.stream_id
    assert :ok = stop_supervised(child_id)

    fresh_opts = Keyword.update!(ctx.opts, :base_path, &Path.join(&1, "replacement"))
    start_supervised!({FileSystem, fresh_opts})
    assert {:ok, replacement} = FileSystem.append(ctx.name, "other", DateTime.utc_now())
    assert replacement.start_offset == original.start_offset
    refute replacement.stream_id == original.stream_id
    refute Identity.evidence_id(replacement) == Identity.evidence_id(original)

    refute Identity.frame_record_id(replacement.stream_id, 0, 5) ==
             Identity.frame_record_id(original.stream_id, 0, 5)
  end

  @tag :tmp_dir
  test "legacy journal metadata retains its replay identity", ctx do
    context =
      Map.new(
        Keyword.take(ctx.opts, [:mission_id, :realized_contact_id, :path_id, :provider_binding_id])
      )

    digest =
      [
        context.mission_id,
        context.realized_contact_id,
        context.path_id,
        context.provider_binding_id
      ]
      |> Enum.join("\0")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    stream_id = "stream-" <> digest
    path = Path.join(Keyword.fetch!(ctx.opts, :base_path), stream_id)
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "stream.term"),
      :erlang.term_to_binary(%{version: 1, stream_id: stream_id, context: context})
    )

    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, entry} = FileSystem.append(ctx.name, "legacy", DateTime.utc_now())
    assert entry.stream_id == stream_id
  end

  @tag :tmp_dir
  test "missing identity metadata cannot silently relabel existing bytes", ctx do
    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, entry} = FileSystem.append(ctx.name, "captured", DateTime.utc_now())

    assert :ok =
             stop_supervised({:ingress_journal, Keyword.fetch!(ctx.opts, :provider_binding_id)})

    File.rm!(Path.join(Path.dirname(entry.segment_path), "stream.term"))
    Process.flag(:trap_exit, true)
    assert {:error, :ingress_journal_stream_metadata_missing} = FileSystem.start_link(ctx.opts)
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

    metadata = %{
      mission_id: "mission-journal-test",
      protocol_family: :tm,
      ingress_metadata: %{"transport_session_id" => "socket-before-restart"}
    }

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
    assert recovered_evidence.metadata["transport_session_id"] == "socket-before-restart"

    assert {:ok, [next_entry]} =
             FileSystem.append_stream(
               ctx.name,
               <<10, 11>>,
               DateTime.utc_now(),
               %{metadata | ingress_metadata: %{"transport_session_id" => "socket-after-restart"}}
             )

    refute Evidence.compatible_entries?(List.last(recovered_entries), next_entry)

    assert {:error, :non_contiguous_ingress_journal_evidence_batch} =
             Evidence.from_contiguous_entries(recovered_entries ++ [next_entry])

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

  # DECISIONS #71: an ended contact's unstored telemetry is named by `unpersisted_journal`;
  # nothing past the processing cursor is ever reclaimed, however far the archive got.
  @tag :tmp_dir
  test "never reclaims entries the processing consumer hasn't passed, and reports them", ctx do
    opts = Keyword.merge(ctx.opts, segment_bytes: 100, checkpoint_interval_ms: 5)
    start_supervised!({FileSystem, opts})

    entries =
      for byte <- 1..3 do
        assert {:ok, entry} =
                 FileSystem.append(ctx.name, :binary.copy(<<byte>>, 80), DateTime.utc_now(), %{})

        entry
      end

    tail = List.last(entries).end_offset
    assert :ok = FileSystem.acknowledge(ctx.name, :archive, tail)
    Process.sleep(50)

    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.reclaimed_segments == 0
    assert snapshot.segment_count == 3
    assert Enum.all?(entries, &File.exists?(&1.segment_path))

    assert snapshot.processing_backlog == %{
             from_offset: 0,
             to_offset: tail,
             bytes: tail,
             entries: 3
           }

    # The backlog survives a restart; processing one entry shrinks it from the front.
    assert :ok =
             stop_supervised({:ingress_journal, Keyword.fetch!(ctx.opts, :provider_binding_id)})

    start_supervised!({FileSystem, opts})
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, hd(entries).end_offset)

    assert_eventually(fn ->
      assert {:ok, recovered} = FileSystem.snapshot(ctx.name)
      assert recovered.durable_cursors.processing == hd(entries).end_offset
      assert recovered.processing_backlog.entries == 2
      assert recovered.processing_backlog.bytes == tail - hd(entries).end_offset
    end)

    assert Enum.all?(tl(entries), &File.exists?(&1.segment_path))
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
        fn event, measurements, metadata, provider_binding_id ->
          if metadata.provider_binding_id == provider_binding_id do
            send(test_pid, {:journal_event, event, measurements, metadata})
          end
        end,
        Keyword.fetch!(ctx.opts, :provider_binding_id)
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

  # Identity v2 needs no cutover because nothing re-reads persisted entries: a consumer cursor
  # only moves forward (docs/apogee/plans/ingress-time-tags.md).
  @tag :tmp_dir
  test "a consumer cursor never moves backwards", ctx do
    start_supervised!({FileSystem, ctx.opts})
    receipt_time = DateTime.utc_now()

    assert {:ok, first} = FileSystem.append(ctx.name, <<1, 2, 3>>, receipt_time, %{})
    assert {:ok, second} = FileSystem.append(ctx.name, <<4, 5>>, receipt_time, %{})
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, second.end_offset)

    assert {:error, {:ingress_journal_cursor_regression, [:processing], end_offset}} =
             FileSystem.acknowledge(ctx.name, :processing, first.end_offset)

    assert end_offset == first.end_offset
    assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    assert snapshot.lag_bytes.processing == 0
  end

  @tag :tmp_dir
  test "evidence merged from several records keeps each record's receipt time", ctx do
    start_supervised!({FileSystem, ctx.opts})
    t0 = ~U[2026-11-14 00:38:40.000000Z]
    metadata = %{protocol_family: :tm, mission_id: "mission-journal-test"}

    entries =
      for i <- 0..2 do
        {:ok, entry} =
          FileSystem.append(
            ctx.name,
            :binary.copy(<<i>>, 14),
            DateTime.add(t0, i, :second),
            metadata
          )

        entry
      end

    assert {:ok, evidence} = Evidence.from_contiguous_entries(entries)
    assert evidence.receipt_time == t0

    assert evidence.receipt_times == [
             {0, t0},
             {14, DateTime.add(t0, 1, :second)},
             {28, DateTime.add(t0, 2, :second)}
           ]

    assert RawEvidence.receipt_time_at(evidence, 0) == t0
    assert RawEvidence.receipt_time_at(evidence, 20) == DateTime.add(t0, 1, :second)
    assert RawEvidence.receipt_time_at(evidence, 41) == DateTime.add(t0, 2, :second)

    # Read back from the ingress archive (which keeps metadata, not the struct field).
    archived = %{evidence | receipt_times: []}
    assert RawEvidence.receipt_time_at(archived, 30) == DateTime.add(t0, 2, :second)
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
