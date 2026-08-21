defmodule Cadence.IngressArchive.FileSystemIsolationTest do
  use Cadence.ProcessDataCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.FileSystem
  alias Cadence.IngressArchive.FileSystem.EvidenceEntryRow, as: IngressArchiveEvidenceEntryRow
  alias Cadence.Repo

  @writer_a __MODULE__.WriterA
  @writer_b __MODULE__.WriterB

  setup do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "cadence_ingress_archive_isolation_#{System.unique_integer([:positive])}"
      )

    root_a = Path.join(test_root, "instance-a")
    root_b = Path.join(test_root, "instance-b")

    policy_a =
      IngressArchive.policy(
        module: FileSystem,
        name: @writer_a,
        instance_id: "instance-a",
        base_path: root_a,
        repo: Repo,
        flush_interval_ms: 60_000,
        flush_count: 100
      )

    policy_b =
      IngressArchive.policy(
        module: FileSystem,
        name: @writer_b,
        instance_id: "instance-b",
        base_path: root_b,
        repo: Repo,
        flush_interval_ms: 60_000,
        flush_count: 100
      )

    pid_a = start_supervised!(IngressArchive.child_spec(policy_a))
    pid_b = start_supervised!(IngressArchive.child_spec(policy_b))

    on_exit(fn -> File.rm_rf!(test_root) end)

    organization_id = "org-archive-isolation-#{System.unique_integer([:positive])}"
    mission_id = "mission-archive-isolation-#{System.unique_integer([:positive])}"
    persist_mission_scope(organization_id, mission_id)

    %{
      mission_id: mission_id,
      pid_a: pid_a,
      pid_b: pid_b,
      policy_a: policy_a,
      policy_b: policy_b,
      root_a: root_a,
      root_b: root_b
    }
  end

  test "identical domain IDs remain isolated through enqueue, flush, fetch, reset, and stop", %{
    mission_id: mission_id,
    pid_a: pid_a,
    pid_b: pid_b,
    policy_a: policy_a,
    policy_b: policy_b,
    root_a: root_a,
    root_b: root_b
  } do
    evidence_id = "shared-evidence-id"
    receipt_time = DateTime.from_unix!(1_701_100_000, :second)

    raw_evidence_a = raw_evidence(evidence_id, mission_id, receipt_time, <<1, 1, 1>>)
    raw_evidence_b = raw_evidence(evidence_id, mission_id, receipt_time, <<2, 2, 2>>)

    assert :ok = IngressArchive.persist_raw_evidences(policy_a, [raw_evidence_a])
    assert :ok = IngressArchive.persist_raw_evidences(policy_b, [raw_evidence_b])

    assert IngressArchive.stats(policy_a, mission_id).queue_depth == 1
    assert IngressArchive.stats(policy_b, mission_id).queue_depth == 1

    assert :ok = IngressArchive.flush(policy_a, mission_id)

    assert IngressArchive.stats(policy_a, mission_id).flush_count == 1
    assert IngressArchive.stats(policy_b, mission_id).queue_depth == 1
    assert IngressArchive.stats(policy_b, mission_id).flush_count == 0

    assert {:ok, fetched_a} = IngressArchive.fetch_raw_evidence(policy_a, mission_id, evidence_id)
    assert fetched_a.raw == raw_evidence_a.raw
    assert IngressArchive.stats(policy_b, mission_id).queue_depth == 1
    assert IngressArchive.stats(policy_b, mission_id).flush_count == 0

    assert :ok = IngressArchive.flush(policy_b, mission_id)

    assert {:ok, fetched_b} = IngressArchive.fetch_raw_evidence(policy_b, mission_id, evidence_id)
    assert fetched_b.raw == raw_evidence_b.raw

    assert length(Path.wildcard(Path.join(root_a, "**/*.bin"))) == 1
    assert length(Path.wildcard(Path.join(root_b, "**/*.bin"))) == 1
    assert Repo.aggregate(IngressArchiveEvidenceEntryRow, :count, :evidence_id) == 2

    stats_b = IngressArchive.stats(policy_b, mission_id)
    assert stats_b.queue_depth == 0
    assert stats_b.flush_count == 1
    assert stats_b.flushed_count == 1

    assert :ok = IngressArchive.reset(policy_a)

    refute File.exists?(root_a)
    assert File.exists?(root_b)
    assert IngressArchive.stats(policy_b, mission_id) == stats_b
    assert Repo.aggregate(IngressArchiveEvidenceEntryRow, :count, :evidence_id) == 1

    assert {:error, :raw_evidence_not_found} =
             IngressArchive.fetch_raw_evidence(policy_a, mission_id, evidence_id)

    assert {:ok, fetched_b_after_reset} =
             IngressArchive.fetch_raw_evidence(policy_b, mission_id, evidence_id)

    assert fetched_b_after_reset.raw == raw_evidence_b.raw
    assert IngressArchive.stats(policy_b, mission_id) == stats_b

    assert :ok = stop_supervised(@writer_a)
    refute Process.alive?(pid_a)
    assert Process.alive?(pid_b)

    assert {:ok, fetched_b_after_stop} =
             IngressArchive.fetch_raw_evidence(policy_b, mission_id, evidence_id)

    assert fetched_b_after_stop.raw == raw_evidence_b.raw
    assert IngressArchive.stats(policy_b, mission_id) == stats_b
  end

  defp raw_evidence(evidence_id, mission_id, receipt_time, raw) do
    RawEvidence.new(%{
      evidence_id: evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      direction: :downlink,
      raw: raw,
      receipt_time: receipt_time
    })
  end
end
