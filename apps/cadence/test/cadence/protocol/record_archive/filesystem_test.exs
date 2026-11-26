defmodule Cadence.Protocol.RecordArchive.FileSystemTest do
  use Cadence.ProcessDataCase, async: false

  import Ecto.Query

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Protocol.{PacketRecord, RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.{IdentityRow, SegmentRow}
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  setup context do
    base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_protocol_record_archive_#{System.unique_integer([:positive])}"
      )

    repo =
      if context[:archive_fault] do
        start_supervised!({Cadence.ProtocolArchiveFaultRepo, owner: self()})
        Cadence.ProtocolArchiveFaultRepo
      else
        Repo
      end

    archive_policy =
      RecordArchive.policy(
        module: FileSystem,
        base_path: base_path,
        repo: repo,
        flush_interval_ms: if(context[:archive_fault], do: 50, else: 5_000),
        flush_count: 10
      )

    start_supervised!(RecordArchive.child_spec(archive_policy))

    on_exit(fn -> File.rm_rf!(base_path) end)

    organization_id =
      "org-protocol-archive-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "mission-protocol-archive-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{mission_id: mission_id, archive_policy: archive_policy}
  end

  test "archives packet and frame records to segment files and fetches them by evidence, source, contact, and metadata",
       %{mission_id: mission_id, archive_policy: archive_policy} do
    receipt_time = DateTime.from_unix!(1_700_600_000, :second)

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-protocol-alpha",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1, 2, 3, 4>>,
        receipt_time: receipt_time,
        source_ref: "antenna-alpha",
        metadata: %{
          "realized_contact_id" => "contact-alpha",
          "antenna_id" => "ant-a",
          "path_id" => "downlink-path-alpha"
        }
      })

    transfer_frame_record =
      TransferFrameRecord.new(%{
        frame_record_id: "frame-alpha",
        evidence_id: raw_evidence.evidence_id,
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        scid: 11,
        vcid: 2,
        frame_seq: 7,
        raw_frame_offset_bytes: 0,
        raw_frame_length_bytes: 1115,
        payload_length_bytes: 1109,
        first_header_pointer: 0,
        quality: :good,
        receipt_time: receipt_time,
        metadata: %{"fhp" => 0}
      })

    packet_record = %PacketRecord{
      packet_id: "packet-alpha",
      evidence_id: raw_evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 9,
      secondary_header?: false,
      packet_data: <<0, 7>>,
      receipt_time: receipt_time,
      provenance: %{"source_ref" => "antenna-alpha"}
    }

    assert :ok =
             RecordArchive.persist_records(
               archive_policy,
               raw_evidence,
               [transfer_frame_record],
               [packet_record]
             )

    stats_before_flush = RecordArchive.stats(archive_policy, mission_id)
    assert stats_before_flush.queue_depth == 2
    assert stats_before_flush.oldest_buffered_age_ms >= 0
    assert stats_before_flush.flush_count == 0

    assert :ok = RecordArchive.flush(archive_policy, mission_id)

    stats_after_flush = RecordArchive.stats(archive_policy, mission_id)
    assert stats_after_flush.queue_depth == 0
    assert stats_after_flush.flush_count == 1
    assert stats_after_flush.flush_failure_count == 0
    assert stats_after_flush.flushed_count == 2
    assert stats_after_flush.segment_count == 1
    assert stats_after_flush.flushed_bytes_total > 0
    assert stats_after_flush.avg_flush_us >= 0.0
    assert stats_after_flush.avg_segment_bytes > 0.0

    assert {:ok, [fetched_packet]} =
             RecordArchive.fetch_packet_records(
               archive_policy,
               mission_id,
               Scope.new(%{evidence_ids: [raw_evidence.evidence_id]})
             )

    assert fetched_packet.packet_id == "packet-alpha"
    assert fetched_packet.packet_data == <<0, 7>>

    assert {:ok, [source_filtered_frame]} =
             RecordArchive.fetch_transfer_frame_records(
               archive_policy,
               mission_id,
               Scope.new(%{source_ref: "antenna-alpha"})
             )

    assert source_filtered_frame.frame_record_id == "frame-alpha"
    assert source_filtered_frame.frame_seq == 7

    assert {:ok, [contact_filtered_packet]} =
             RecordArchive.fetch_packet_records(
               archive_policy,
               mission_id,
               Scope.new(%{realized_contact_id: "contact-alpha"})
             )

    assert contact_filtered_packet.packet_id == "packet-alpha"

    assert {:ok, [metadata_filtered_frame]} =
             RecordArchive.fetch_transfer_frame_records(
               archive_policy,
               mission_id,
               Scope.new(%{metadata_match: %{"antenna_id" => "ant-a"}})
             )

    assert metadata_filtered_frame.frame_record_id == "frame-alpha"
  end

  test "treats already-indexed packet and frame entries as idempotent archive success", %{
    mission_id: mission_id
  } do
    receipt_time = DateTime.from_unix!(1_700_800_000, :second)

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-protocol-idempotent",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<5, 6, 7, 8>>,
        receipt_time: receipt_time
      })

    transfer_frame_record =
      TransferFrameRecord.new(%{
        frame_record_id: "frame-idempotent",
        evidence_id: raw_evidence.evidence_id,
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        scid: 11,
        vcid: 2,
        frame_seq: 17,
        raw_frame_offset_bytes: 0,
        raw_frame_length_bytes: 1115,
        payload_length_bytes: 1109,
        first_header_pointer: 0,
        quality: :good,
        receipt_time: receipt_time
      })

    packet_record = %PacketRecord{
      packet_id: "packet-idempotent",
      evidence_id: raw_evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 19,
      secondary_header?: false,
      packet_data: <<1, 9>>,
      receipt_time: receipt_time,
      provenance: %{}
    }

    entries = FileSystem.build_entries(raw_evidence, [transfer_frame_record], [packet_record])

    assert :ok =
             FileSystem.persist_segment("segment-alpha", entries,
               object_key: "mission-alpha/segment-alpha.bin",
               organization_id: "org-idempotent"
             )

    assert :ok =
             FileSystem.persist_segment("segment-beta", entries,
               object_key: "mission-alpha/segment-beta.bin",
               organization_id: "org-idempotent"
             )

    assert 2 == archive_entry_count(entries)

    # A frame's id is its journal position, so another frame at that id differs in what it
    # decodes to (here its frame sequence), which is a real conflict.
    other_frame =
      FileSystem.build_entries(raw_evidence, [%{transfer_frame_record | frame_seq: 18}], [])

    assert {:error, {:protocol_archive_record_identity_conflict, ["frame-idempotent"]}} =
             FileSystem.persist_segment("changed-frame-bytes", other_frame,
               object_key: "mission-alpha/changed-frame-bytes.bin"
             )

    # Likewise a packet's id hashes its bytes, so another packet at that id is another packet
    # (here another APID): a real conflict.
    [frame, packet] = entries
    changed = Map.put(packet, "apid", 99)

    assert {:error, {:protocol_archive_record_identity_conflict, _ids}} =
             FileSystem.persist_segment("segment-collision", [frame, changed],
               object_key: "mission-alpha/segment-collision.bin"
             )

    assert object_key("packet_record", "packet-idempotent") == "mission-alpha/segment-alpha.bin"
  end

  describe "a replay that groups the journal into different evidence (11-14, 008's pass)" do
    test "re-archiving the same frames is idempotent: one index row per frame", %{
      mission_id: mission_id
    } do
      # The run that archived them: one evidence over journal records 0..1.
      first =
        replay_evidence(mission_id, "0-2", ~U[2026-11-14 01:35:54.969000Z], %{"records" => 2})

      frames = for seq <- 1..3, do: replay_frame(first, mission_id, seq)
      archived = FileSystem.build_entries(first, frames, [])

      assert :ok =
               FileSystem.persist_segment("segment-run", archived,
                 object_key: "#{mission_id}/segment-run.bin"
               )

      # After the restart: the same journal records, merged with more of them into one evidence:
      # another evidence_id, evidence bytes, receipt time and batch metadata, the same frames.
      replay =
        replay_evidence(mission_id, "0-6", ~U[2026-11-14 01:44:37.000000Z], %{"records" => 6})

      replayed =
        FileSystem.build_entries(
          replay,
          Enum.map(
            frames,
            &%{&1 | evidence_id: replay.evidence_id, receipt_time: replay.receipt_time}
          ),
          []
        )

      assert :ok =
               FileSystem.persist_segment("segment-replay", replayed,
                 object_key: "#{mission_id}/segment-replay.bin"
               )

      assert 3 == archive_entry_count(replayed)

      # The index keeps the original archive's rows.
      for frame <- frames do
        assert object_key("transfer_frame_record", frame.frame_record_id) ==
                 "#{mission_id}/segment-run.bin"
      end

      # A different frame at one of those positions still conflicts.
      [frame | _rest] = frames
      wrong = FileSystem.build_entries(replay, [%{frame | scid: 99}], [])

      assert {:error, {:protocol_archive_record_identity_conflict, [id]}} =
               FileSystem.persist_segment("segment-wrong", wrong,
                 object_key: "#{mission_id}/segment-wrong.bin"
               )

      assert id == frame.frame_record_id
    end

    test "re-archiving the same packets under other evidence is idempotent too", %{
      mission_id: mission_id
    } do
      first =
        replay_evidence(mission_id, "0-2", ~U[2026-11-14 01:35:54.969000Z], %{"records" => 2})

      packets = for seq <- 1..3, do: replay_packet(first, mission_id, seq)

      assert :ok =
               FileSystem.persist_segment(
                 "segment-packets-run",
                 FileSystem.build_entries(first, [], packets),
                 object_key: "#{mission_id}/segment-packets-run.bin"
               )

      replay =
        replay_evidence(mission_id, "0-6", ~U[2026-11-14 01:44:37.000000Z], %{"records" => 6})

      replayed =
        Enum.map(
          packets,
          &%{&1 | evidence_id: replay.evidence_id, receipt_time: replay.receipt_time}
        )

      entries = FileSystem.build_entries(replay, [], replayed)

      assert :ok =
               FileSystem.persist_segment("segment-packets-replay", entries,
                 object_key: "#{mission_id}/segment-packets-replay.bin"
               )

      assert 3 == archive_entry_count(entries)

      # Another packet at one of those ids (another APID) still conflicts.
      [packet | _rest] = packets
      wrong = FileSystem.build_entries(replay, [], [%{packet | apid: 99}])

      assert {:error, {:protocol_archive_record_identity_conflict, [id]}} =
               FileSystem.persist_segment("segment-packets-wrong", wrong,
                 object_key: "#{mission_id}/segment-packets-wrong.bin"
               )

      assert id == packet.packet_id
    end

    test "the writer's buffered flush clears instead of retrying forever", %{
      mission_id: mission_id,
      archive_policy: archive_policy
    } do
      first =
        replay_evidence(mission_id, "0-2", ~U[2026-11-14 01:35:54.969000Z], %{"records" => 2})

      frames = for seq <- 1..2, do: replay_frame(first, mission_id, seq)

      assert :ok = RecordArchive.persist_records_many(archive_policy, [{first, frames, []}])
      assert :ok = RecordArchive.flush(archive_policy, mission_id)

      replay =
        replay_evidence(mission_id, "0-6", ~U[2026-11-14 01:44:37.000000Z], %{"records" => 6})

      replayed = Enum.map(frames, &%{&1 | evidence_id: replay.evidence_id})

      assert :ok = RecordArchive.persist_records_many(archive_policy, [{replay, replayed, []}])
      assert :ok = RecordArchive.flush(archive_policy, mission_id)

      # The replay's segment indexed nothing new, so its object isn't left on disk (#71 follow-up):
      # only the first run's segment remains.
      assert [_only] = segment_objects(archive_policy, mission_id)
    end
  end

  defp segment_objects(policy, mission_id) do
    [Keyword.fetch!(policy.backend_opts, :base_path), mission_id, "**", "*.bin"]
    |> Path.join()
    |> Path.wildcard()
  end

  test "segment objects cannot be overwritten with different records", %{
    mission_id: mission_id,
    archive_policy: policy
  } do
    entry = %{
      "mission_id" => mission_id,
      "receipt_time" => "2026-10-21T12:00:00Z",
      "record_id" => "immutable"
    }

    assert {:ok, key, _} = FileSystem.store_segment_object("fixed", [entry], policy.backend_opts)
    assert {:ok, ^key, _} = FileSystem.store_segment_object("fixed", [entry], policy.backend_opts)

    assert {:error, {:protocol_archive_segment_write_failed, _, {:immutable_file_collision, _}}} =
             FileSystem.store_segment_object(
               "fixed",
               [Map.put(entry, "record_id", "changed")],
               policy.backend_opts
             )

    assert {:ok, [^entry]} = FileSystem.load_segment_object(key, policy.backend_opts)
  end

  test "large archive segments stay within the database parameter limit and remain idempotent", %{
    mission_id: mission_id
  } do
    receipt_time = ~U[2026-10-19 12:00:00Z]

    evidence =
      RawEvidence.new(%{
        evidence_id: "large-segment-evidence",
        mission_id: mission_id,
        raw: <<1, 2>>,
        receipt_time: receipt_time
      })

    packets =
      Enum.map(1..4_000, fn index ->
        %PacketRecord{
          packet_id: "large-segment-packet-#{index}",
          evidence_id: evidence.evidence_id,
          mission_id: mission_id,
          protocol_family: :tm,
          packet_kind: :space_packet,
          apid: 42,
          sequence_flags: 3,
          sequence_count: index,
          secondary_header?: false,
          packet_data: <<1, 2>>,
          receipt_time: receipt_time,
          provenance: %{}
        }
      end)

    entries = FileSystem.build_entries(evidence, [], packets)
    opts = [object_key: "#{mission_id}/large-segment.bin"]

    assert :ok = FileSystem.persist_segment("large-segment", entries, opts)
    assert :ok = FileSystem.persist_segment("large-segment", entries, opts)
    assert archive_entry_count(entries) == 4_000

    assert %{rows: [[0]]} =
             Repo.query!(
               """
               SELECT count(*) FROM pg_prepared_statements
               WHERE name = $1 AND cardinality(parameter_types) >= 1000
               """,
               ["ecto_insert_all_protocol_archive_record_identities"]
             )
  end

  @tag archive_fault: true
  test "retains buffered records and retries database exceptions without restarting", %{
    mission_id: mission_id,
    archive_policy: policy
  } do
    failures = [
      %DBConnection.ConnectionError{message: "database checkout unavailable"},
      %Postgrex.Error{message: "temporary database query failure"}
    ]

    for {failure, index} <- Enum.with_index(failures, 1) do
      Cadence.ProtocolArchiveFaultRepo.fail_with(failure)

      evidence =
        RawEvidence.new(%{
          evidence_id: "retry-evidence-#{index}",
          mission_id: mission_id,
          raw: <<1, 2>>,
          receipt_time: ~U[2026-10-24 12:00:00Z]
        })

      packet = %PacketRecord{
        packet_id: "retry-packet-#{index}",
        evidence_id: evidence.evidence_id,
        mission_id: mission_id,
        protocol_family: :tm,
        packet_kind: :space_packet,
        packet_data: <<1, 2>>,
        receipt_time: evidence.receipt_time,
        provenance: %{}
      }

      assert :ok = RecordArchive.persist_records(policy, evidence, [], [packet])
      writer = mission_writer(mission_id)

      assert {:error, {:archive_database_error, _message}} =
               RecordArchive.flush(policy, mission_id)

      assert_receive :archive_write_failed
      # The timer retries without another enqueue or flush request.
      assert_receive :archive_write_failed, 1_000

      assert %{queue_depth: 1, backpressured?: true, flush_failure_count: count} =
               RecordArchive.stats(policy, mission_id)

      assert count >= 2
      assert mission_writer(mission_id) == writer
      refute object_key("packet_record", packet.packet_id)

      if index == 1 do
        assert :ok = RecordArchive.reset_stats(policy, mission_id)
        assert %{backpressured?: true} = RecordArchive.stats(policy, mission_id)
      end

      for _ <- 1..10 do
        assert {:error, {:protocol_archive_backpressured, ^mission_id}} =
                 RecordArchive.persist_records(policy, evidence, [], [packet])

        assert {:error, {:protocol_archive_backpressured, ^mission_id}} =
                 RecordArchive.persist_records_many(policy, [{evidence, [], [packet]}])
      end

      assert %{queue_depth: 1} = RecordArchive.stats(policy, mission_id)

      Cadence.ProtocolArchiveFaultRepo.recover()
      # The transaction yields the segment it indexed.
      assert_receive {:archive_write_completed, {:ok, %SegmentRow{}}}, 2_000

      assert %{queue_depth: 0, backpressured?: false, flushed_count: ^index} =
               RecordArchive.stats(policy, mission_id)

      base_path = Keyword.fetch!(policy.backend_opts, :base_path)
      assert length(Path.wildcard(Path.join(base_path, "**/*.bin"))) == index

      assert {:ok, [^packet]} =
               RecordArchive.fetch_packet_records(
                 policy,
                 mission_id,
                 Scope.new(%{evidence_ids: [evidence.evidence_id]})
               )
    end
  end

  defp mission_writer(mission_id) do
    [{pid, _value}] =
      Registry.lookup(Module.concat(FileSystem.Writer, Registry), {mission_id, nil})

    pid
  end

  defp replay_evidence(mission_id, range, receipt_time, metadata) do
    RawEvidence.new(%{
      evidence_id: "evidence-replay-" <> range,
      mission_id: mission_id,
      protocol_family: :tm,
      direction: :downlink,
      raw: :crypto.strong_rand_bytes(16),
      receipt_time: receipt_time,
      metadata: Map.put(metadata, "journal_range", range)
    })
  end

  # A frame's id is its journal position: the same for the run and the replay.
  defp replay_frame(evidence, mission_id, seq) do
    TransferFrameRecord.new(%{
      frame_record_id: "frame-stream-008-offset-#{seq * 1115}",
      evidence_id: evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      direction: :downlink,
      scid: 8,
      vcid: 0,
      frame_seq: seq,
      raw_frame_offset_bytes: seq * 1115,
      raw_frame_length_bytes: 1115,
      payload_length_bytes: 1109,
      first_header_pointer: 0,
      quality: :good,
      receipt_time: evidence.receipt_time
    })
  end

  # A journaled packet's id is its journal position and bytes: the same for the run and the replay.
  defp replay_packet(evidence, mission_id, seq) do
    %PacketRecord{
      packet_id: "packet-stream-008-frame-#{seq * 1115}",
      evidence_id: evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 100,
      sequence_count: seq,
      packet_data: <<seq>>,
      receipt_time: evidence.receipt_time,
      provenance: %{}
    }
  end

  defp archive_entry_count(entries) when is_list(entries) do
    record_ids = Enum.map(entries, &Map.fetch!(&1, "record_id"))

    IdentityRow
    |> where([row], row.record_id in ^record_ids)
    |> Repo.aggregate(:count)
  end

  defp object_key(record_kind, record_id) do
    SegmentRow
    |> join(:inner, [s], i in IdentityRow, on: i.segment_id == s.id)
    |> where([_s, i], i.record_kind == ^record_kind and i.record_id == ^record_id)
    |> select([s], s.object_key)
    |> Repo.one()
  end
end
