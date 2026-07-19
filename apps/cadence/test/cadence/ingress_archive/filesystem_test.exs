defmodule Cadence.IngressArchive.FileSystemTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.FileSystem
  alias Cadence.IngressArchive.FileSystem.EvidenceEntryRow, as: IngressArchiveEvidenceEntryRow
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  setup do
    previous_config = Application.get_env(:cadence, :ingress_archive, [])

    base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_ingress_archive_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:cadence, :ingress_archive,
      module: FileSystem,
      base_path: base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    start_supervised!(
      {Cadence.IngressArchive.FileSystem.Writer, Application.get_env(:cadence, :ingress_archive)}
    )

    on_exit(fn ->
      Application.put_env(:cadence, :ingress_archive, previous_config)
      File.rm_rf!(base_path)
    end)

    organization_id = "org-archive-" <> Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-archive-" <> Integer.to_string(System.unique_integer([:positive]))
    persist_mission_scope(organization_id, mission_id)

    %{mission_id: mission_id}
  end

  test "archives raw evidence to segment files and replays by evidence, source, contact, and metadata",
       %{
         mission_id: mission_id
       } do
    first_receipt_time = DateTime.from_unix!(1_700_500_000, :second)
    second_receipt_time = DateTime.add(first_receipt_time, 10, :second)

    raw_evidence_alpha =
      RawEvidence.new(%{
        evidence_id: "evidence-alpha",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1, 2, 3>>,
        receipt_time: first_receipt_time,
        source_ref: "antenna-alpha",
        metadata: %{
          "realized_contact_id" => "contact-alpha",
          "antenna_id" => "ant-a"
        }
      })

    raw_evidence_beta =
      RawEvidence.new(%{
        evidence_id: "evidence-beta",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<4, 5, 6>>,
        receipt_time: second_receipt_time,
        source_ref: "antenna-beta",
        metadata: %{
          "realized_contact_id" => "contact-beta",
          "antenna_id" => "ant-b"
        }
      })

    assert :ok = IngressArchive.persist_raw_evidence(raw_evidence_alpha)
    assert :ok = IngressArchive.persist_raw_evidence(raw_evidence_beta)

    stats_before_flush = IngressArchive.stats(mission_id)
    assert stats_before_flush.queue_depth == 2
    assert stats_before_flush.oldest_buffered_age_ms >= 0
    assert stats_before_flush.flush_count == 0

    assert :ok = IngressArchive.flush(mission_id)

    stats_after_flush = IngressArchive.stats(mission_id)
    assert stats_after_flush.queue_depth == 0
    assert stats_after_flush.flush_count == 1
    assert stats_after_flush.flush_failure_count == 0
    assert stats_after_flush.flushed_count == 2
    assert stats_after_flush.segment_count == 1
    assert stats_after_flush.flushed_bytes_total > 0
    assert stats_after_flush.avg_flush_us >= 0.0
    assert stats_after_flush.avg_segment_bytes > 0.0

    assert {:ok, [fetched_alpha]} =
             IngressArchive.fetch_raw_evidences(
               mission_id,
               Scope.new(%{evidence_ids: ["evidence-alpha"]})
             )

    assert fetched_alpha.evidence_id == "evidence-alpha"
    assert fetched_alpha.raw == <<1, 2, 3>>

    assert {:ok, [source_filtered]} =
             IngressArchive.fetch_raw_evidences(
               mission_id,
               Scope.new(%{source_ref: "antenna-beta"})
             )

    assert source_filtered.evidence_id == "evidence-beta"

    assert {:ok, [contact_filtered]} =
             IngressArchive.fetch_raw_evidences(
               mission_id,
               Scope.new(%{realized_contact_id: "contact-alpha"})
             )

    assert contact_filtered.evidence_id == "evidence-alpha"

    assert {:ok, [metadata_filtered]} =
             IngressArchive.fetch_raw_evidences(
               mission_id,
               Scope.new(%{metadata_match: %{"antenna_id" => "ant-b"}})
             )

    assert metadata_filtered.evidence_id == "evidence-beta"
  end

  test "treats already-indexed evidence entries as idempotent archive success", %{
    mission_id: mission_id
  } do
    receipt_time = DateTime.from_unix!(1_700_700_000, :second)

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-idempotent",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1, 2, 3>>,
        receipt_time: receipt_time
      })

    assert :ok =
             FileSystem.persist_segment("segment-alpha", [raw_evidence],
               object_key: "mission-alpha/segment-alpha.bin",
               organization_id: "org-idempotent"
             )

    assert :ok =
             FileSystem.persist_segment("segment-beta", [raw_evidence],
               object_key: "mission-alpha/segment-beta.bin",
               organization_id: "org-idempotent"
             )

    assert 1 == Repo.aggregate(IngressArchiveEvidenceEntryRow, :count, :evidence_id)
  end

  test "stats and flush tolerate legacy writer state without buffer sizes", %{
    mission_id: mission_id
  } do
    receipt_time = DateTime.from_unix!(1_700_900_000, :second)

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-legacy-state",
        mission_id: mission_id,
        protocol_family: :tm,
        direction: :downlink,
        raw: <<7, 8, 9>>,
        receipt_time: receipt_time
      })

    :sys.replace_state(Cadence.IngressArchive.FileSystem.Writer, fn state ->
      state
      |> Map.put(:buffers, %{mission_id => [raw_evidence]})
      |> Map.put(:buffer_started_at_ms, %{mission_id => System.monotonic_time(:millisecond)})
      |> Map.delete(:buffer_sizes)
    end)

    stats_before_flush = IngressArchive.stats(mission_id)
    assert stats_before_flush.queue_depth == 1

    assert :ok = IngressArchive.flush(mission_id)
    assert 1 == Repo.aggregate(IngressArchiveEvidenceEntryRow, :count, :evidence_id)

    stats_after_flush = IngressArchive.stats(mission_id)
    assert stats_after_flush.queue_depth == 0
    assert stats_after_flush.flush_count == 1
  end
end
