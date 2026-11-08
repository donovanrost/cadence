defmodule Cadence.Protocol.RecordArchive.FileSystemTest do
  use Cadence.ProcessDataCase, async: false

  import Ecto.Query

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Protocol.RecordArchive.FileSystem.RecordEntryRow,
    as: ProtocolArchiveRecordEntryRow

  alias Cadence.Protocol.{PacketRecord, RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
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

    changed_bytes =
      FileSystem.build_entries(%{raw_evidence | raw: <<9, 9, 9, 9>>}, [transfer_frame_record], [])

    assert {:error, {:protocol_archive_record_identity_conflict, ["frame-idempotent"]}} =
             FileSystem.persist_segment("changed-frame-bytes", changed_bytes,
               object_key: "mission-alpha/changed-frame-bytes.bin"
             )

    [frame, packet] = entries
    changed = Map.put(packet, "packet_data_base64", Base.encode64(<<99, 99>>))

    assert {:error, {:protocol_archive_record_identity_conflict, _ids}} =
             FileSystem.persist_segment("segment-collision", [frame, changed],
               object_key: "mission-alpha/segment-collision.bin"
             )

    assert Repo.get!(ProtocolArchiveRecordEntryRow, "packet_record:packet-idempotent").object_key ==
             "mission-alpha/segment-alpha.bin"

    # Legacy writers can still populate the nullable column during a rollout,
    # but their rows are not evidence of content equality for a new writer.
    ProtocolArchiveRecordEntryRow
    |> where([row], row.record_id == "packet-idempotent")
    |> Repo.update_all(set: [content_sha256: nil])

    assert {:error, {:protocol_archive_record_identity_conflict, _ids}} =
             FileSystem.persist_segment("segment-legacy", entries,
               object_key: "mission-alpha/segment-legacy.bin"
             )
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
               ["ecto_insert_all_protocol_archive_record_entries"]
             )
  end

  @tag archive_fault: true
  test "retains buffered records and retries database exceptions without restarting", %{
    mission_id: mission_id,
    archive_policy: policy
  } do
    writer = Process.whereis(FileSystem.Writer)

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

      assert {:error, {:archive_database_error, _message}} =
               RecordArchive.flush(policy, mission_id)

      assert_receive :archive_write_failed
      # The timer retries without another enqueue or flush request.
      assert_receive :archive_write_failed, 1_000

      assert %{queue_depth: 1, backpressured?: true, flush_failure_count: count} =
               RecordArchive.stats(policy, mission_id)

      assert count >= 2
      assert Process.whereis(FileSystem.Writer) == writer
      refute Repo.get(ProtocolArchiveRecordEntryRow, "packet_record:#{packet.packet_id}")

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
      assert_receive {:archive_write_completed, {:ok, :ok}}, 2_000

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

  test "stats and flush tolerate legacy writer state without buffer sizes", %{
    mission_id: mission_id,
    archive_policy: archive_policy
  } do
    receipt_time = DateTime.from_unix!(1_700_910_000, :second)

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-protocol-legacy-state",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1, 2, 3, 4>>,
        receipt_time: receipt_time
      })

    transfer_frame_record =
      TransferFrameRecord.new(%{
        frame_record_id: "frame-legacy-state",
        evidence_id: raw_evidence.evidence_id,
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        scid: 11,
        vcid: 2,
        frame_seq: 21,
        raw_frame_offset_bytes: 0,
        raw_frame_length_bytes: 1115,
        payload_length_bytes: 1109,
        first_header_pointer: 0,
        quality: :good,
        receipt_time: receipt_time
      })

    packet_record = %PacketRecord{
      packet_id: "packet-legacy-state",
      evidence_id: raw_evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 29,
      secondary_header?: false,
      packet_data: <<2, 9>>,
      receipt_time: receipt_time,
      provenance: %{}
    }

    entries = FileSystem.build_entries(raw_evidence, [transfer_frame_record], [packet_record])

    writer = Keyword.get(archive_policy.backend_opts, :name, FileSystem.Writer)

    :sys.replace_state(writer, fn state ->
      state
      |> Map.put(:buffers, %{mission_id => entries})
      |> Map.put(:buffer_started_at_ms, %{mission_id => System.monotonic_time(:millisecond)})
      |> Map.delete(:buffer_sizes)
    end)

    stats_before_flush = RecordArchive.stats(archive_policy, mission_id)
    assert stats_before_flush.queue_depth == 2

    assert :ok = RecordArchive.flush(archive_policy, mission_id)
    assert 2 == archive_entry_count(entries)

    stats_after_flush = RecordArchive.stats(archive_policy, mission_id)
    assert stats_after_flush.queue_depth == 0
    assert stats_after_flush.flush_count == 1
  end

  defp archive_entry_count(entries) when is_list(entries) do
    record_ids = Enum.map(entries, &Map.fetch!(&1, "record_id"))

    ProtocolArchiveRecordEntryRow
    |> where([row], row.record_id in ^record_ids)
    |> Repo.aggregate(:count, :entry_id)
  end
end
