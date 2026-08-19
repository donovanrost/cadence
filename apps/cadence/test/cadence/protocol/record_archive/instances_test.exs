defmodule Cadence.Protocol.RecordArchive.InstancesTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Protocol.RecordArchive.FileSystem.RecordEntryRow,
    as: ProtocolArchiveRecordEntryRow

  alias Cadence.Protocol.{PacketRecord, RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  @writer_a Cadence.Protocol.RecordArchive.InstancesTest.WriterA
  @writer_b Cadence.Protocol.RecordArchive.InstancesTest.WriterB

  setup do
    unique = System.unique_integer([:positive])
    base_path_a = Path.join(System.tmp_dir!(), "cadence_protocol_archive_a_#{unique}")
    base_path_b = Path.join(System.tmp_dir!(), "cadence_protocol_archive_b_#{unique}")

    policy_a =
      archive_policy(@writer_a, "protocol-archive-instance-a", base_path_a)

    policy_b =
      archive_policy(@writer_b, "protocol-archive-instance-b", base_path_b)

    start_supervised!(RecordArchive.child_spec(policy_a))
    start_supervised!(RecordArchive.child_spec(policy_b))

    on_exit(fn ->
      File.rm_rf!(base_path_a)
      File.rm_rf!(base_path_b)
    end)

    organization_id = "org-protocol-archive-instances-#{unique}"
    mission_id = "mission-protocol-archive-instances-#{unique}"
    persist_mission_scope(organization_id, mission_id)

    %{
      base_path_a: base_path_a,
      base_path_b: base_path_b,
      mission_id: mission_id,
      policy_a: policy_a,
      policy_b: policy_b
    }
  end

  test "filesystem instances isolate calls, index rows, lifecycle, and reset scope", context do
    %{
      base_path_a: base_path_a,
      base_path_b: base_path_b,
      mission_id: mission_id,
      policy_a: policy_a,
      policy_b: policy_b
    } = context

    {raw_evidence, transfer_frame_record, packet_record} = records(mission_id)

    assert :ok =
             RecordArchive.persist_records(
               policy_a,
               raw_evidence,
               [transfer_frame_record],
               [packet_record]
             )

    assert %{queue_depth: 2} = RecordArchive.stats(policy_a, mission_id)
    assert %{queue_depth: 0, flush_count: 0} = RecordArchive.stats(policy_b, mission_id)

    assert :ok =
             RecordArchive.persist_records_many(
               policy_b,
               [{raw_evidence, [transfer_frame_record], [packet_record]}]
             )

    assert %{queue_depth: 2, flush_count: 0} = RecordArchive.stats(policy_b, mission_id)

    scope = Scope.new(%{evidence_ids: [raw_evidence.evidence_id]})

    assert {:ok, [%PacketRecord{packet_id: "shared-packet-id"}]} =
             RecordArchive.fetch_packet_records(policy_a, mission_id, scope)

    assert {:ok, [%TransferFrameRecord{frame_record_id: "shared-frame-id"}]} =
             RecordArchive.fetch_transfer_frame_records(policy_a, mission_id, scope)

    assert %{queue_depth: 0, flush_count: 1, flushed_count: 2} =
             RecordArchive.stats(policy_a, mission_id)

    assert %{queue_depth: 2, flush_count: 0, flushed_count: 0} =
             RecordArchive.stats(policy_b, mission_id)

    assert :ok = RecordArchive.flush(policy_b, mission_id)

    assert {:ok, [%PacketRecord{packet_id: "shared-packet-id"}]} =
             RecordArchive.fetch_packet_records(policy_b, mission_id, scope)

    assert {:ok, [%TransferFrameRecord{frame_record_id: "shared-frame-id"}]} =
             RecordArchive.fetch_transfer_frame_records(policy_b, mission_id, scope)

    archive_backend_a = FileSystem.archive_backend(policy_a.backend_opts)
    archive_backend_b = FileSystem.archive_backend(policy_b.backend_opts)

    assert archive_backend_a != archive_backend_b
    assert 2 == archive_entry_count(archive_backend_a)
    assert 2 == archive_entry_count(archive_backend_b)
    assert [_segment_a] = segment_files(base_path_a)
    assert [_segment_b] = segment_files(base_path_b)

    stats_b = RecordArchive.stats(policy_b, mission_id)
    assert stats_b.queue_depth == 0
    assert stats_b.flush_count == 1
    assert stats_b.flushed_count == 2

    assert :ok = RecordArchive.reset_stats(policy_a, mission_id)
    assert ^stats_b = RecordArchive.stats(policy_b, mission_id)

    assert :ok = RecordArchive.reset(policy_a)
    refute File.exists?(base_path_a)
    assert File.exists?(base_path_b)
    assert 0 == archive_entry_count(archive_backend_a)
    assert 2 == archive_entry_count(archive_backend_b)

    assert {:error, {:evidence_not_found, ["shared-evidence-id"]}} =
             RecordArchive.fetch_packet_records(policy_a, mission_id, scope)

    assert {:ok, [%PacketRecord{packet_id: "shared-packet-id"}]} =
             RecordArchive.fetch_packet_records(policy_b, mission_id, scope)

    assert {:ok, [%TransferFrameRecord{frame_record_id: "shared-frame-id"}]} =
             RecordArchive.fetch_transfer_frame_records(policy_b, mission_id, scope)

    assert ^stats_b = RecordArchive.stats(policy_b, mission_id)

    assert :ok = stop_supervised(@writer_a)
    refute Process.whereis(@writer_a)
    assert is_pid(Process.whereis(@writer_b))

    assert {:ok, [%PacketRecord{packet_id: "shared-packet-id"}]} =
             RecordArchive.fetch_packet_records(policy_b, mission_id, scope)

    assert {:ok, [%TransferFrameRecord{frame_record_id: "shared-frame-id"}]} =
             RecordArchive.fetch_transfer_frame_records(policy_b, mission_id, scope)

    assert ^stats_b = RecordArchive.stats(policy_b, mission_id)
  end

  defp archive_policy(name, instance_id, base_path) do
    RecordArchive.policy(
      module: FileSystem,
      name: name,
      instance_id: instance_id,
      base_path: base_path,
      repo: Repo,
      flush_interval_ms: 5_000,
      flush_count: 10
    )
  end

  defp records(mission_id) do
    receipt_time = DateTime.from_unix!(1_700_900_000, :second)

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "shared-evidence-id",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1, 2, 3, 4>>,
        receipt_time: receipt_time,
        source_ref: "shared-source"
      })

    transfer_frame_record =
      TransferFrameRecord.new(%{
        frame_record_id: "shared-frame-id",
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
        receipt_time: receipt_time
      })

    packet_record = %PacketRecord{
      packet_id: "shared-packet-id",
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
      provenance: %{}
    }

    {raw_evidence, transfer_frame_record, packet_record}
  end

  defp archive_entry_count(archive_backend) do
    ProtocolArchiveRecordEntryRow
    |> where([row], row.archive_backend == ^archive_backend)
    |> Repo.aggregate(:count, :entry_id)
  end

  defp segment_files(base_path) do
    Path.wildcard(Path.join([base_path, "**", "*.bin"]))
  end
end
