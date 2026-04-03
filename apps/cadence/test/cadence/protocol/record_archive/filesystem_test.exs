defmodule Cadence.Protocol.RecordArchive.FileSystemTest do
  use Cadence.DataCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.Schemas.ProtocolArchiveRecordEntryRow
  alias Cadence.Protocol.{PacketRecord, RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  setup do
    previous_config = Application.get_env(:cadence, :protocol_record_archive, [])

    base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_protocol_record_archive_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:cadence, :protocol_record_archive,
      module: FileSystem,
      base_path: base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    start_supervised!(
      {Cadence.Protocol.RecordArchive.FileSystem.Writer,
       Application.get_env(:cadence, :protocol_record_archive)}
    )

    on_exit(fn ->
      Application.put_env(:cadence, :protocol_record_archive, previous_config)
      File.rm_rf!(base_path)
    end)

    organization_id =
      "org-protocol-archive-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "mission-protocol-archive-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{mission_id: mission_id}
  end

  test "archives packet and frame records to segment files and fetches them by evidence, source, contact, and metadata",
       %{mission_id: mission_id} do
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
             RecordArchive.persist_records(raw_evidence, [transfer_frame_record], [packet_record])

    stats_before_flush = RecordArchive.stats(mission_id)
    assert stats_before_flush.queue_depth == 2
    assert stats_before_flush.oldest_buffered_age_ms >= 0
    assert stats_before_flush.flush_count == 0

    assert :ok = RecordArchive.flush(mission_id)

    stats_after_flush = RecordArchive.stats(mission_id)
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
               mission_id,
               Scope.new(%{evidence_ids: [raw_evidence.evidence_id]})
             )

    assert fetched_packet.packet_id == "packet-alpha"
    assert fetched_packet.packet_data == <<0, 7>>

    assert {:ok, [source_filtered_frame]} =
             RecordArchive.fetch_transfer_frame_records(
               mission_id,
               Scope.new(%{source_ref: "antenna-alpha"})
             )

    assert source_filtered_frame.frame_record_id == "frame-alpha"
    assert source_filtered_frame.frame_seq == 7

    assert {:ok, [contact_filtered_packet]} =
             RecordArchive.fetch_packet_records(
               mission_id,
               Scope.new(%{realized_contact_id: "contact-alpha"})
             )

    assert contact_filtered_packet.packet_id == "packet-alpha"

    assert {:ok, [metadata_filtered_frame]} =
             RecordArchive.fetch_transfer_frame_records(
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

    assert 2 == Repo.aggregate(ProtocolArchiveRecordEntryRow, :count, :entry_id)
  end

  test "stats and flush tolerate legacy writer state without buffer sizes", %{
    mission_id: mission_id
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

    :sys.replace_state(Cadence.Protocol.RecordArchive.FileSystem.Writer, fn state ->
      state
      |> Map.put(:buffers, %{mission_id => entries})
      |> Map.put(:buffer_started_at_ms, %{mission_id => System.monotonic_time(:millisecond)})
      |> Map.delete(:buffer_sizes)
    end)

    stats_before_flush = RecordArchive.stats(mission_id)
    assert stats_before_flush.queue_depth == 2

    assert :ok = RecordArchive.flush(mission_id)
    assert 2 == Repo.aggregate(ProtocolArchiveRecordEntryRow, :count, :entry_id)

    stats_after_flush = RecordArchive.stats(mission_id)
    assert stats_after_flush.queue_depth == 0
    assert stats_after_flush.flush_count == 1
  end
end
