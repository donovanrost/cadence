defmodule Cadence.Protocol.RecordArchive.QuarantineTest do
  @moduledoc """
  DECISIONS #88: one archive entry that can never be indexed is quarantined so the mission's
  storage goes on; anything not proven deterministic stays transient (api-ops' review A-F).
  """
  use Cadence.ProcessDataCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.{FileSystem, Quarantine}
  alias Cadence.Protocol.RecordArchive.FileSystem.PoisonIsolation

  setup context do
    base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_archive_quarantine_#{System.unique_integer([:positive])}"
      )

    repo =
      if context[:archive_fault] do
        start_supervised!({Cadence.ProtocolArchiveFaultRepo, owner: self()})
        Cadence.ProtocolArchiveFaultRepo
      else
        Cadence.Repo
      end

    policy =
      RecordArchive.policy(
        module: FileSystem,
        base_path: base_path,
        repo: repo,
        flush_interval_ms: 60_000,
        flush_count: 1_000
      )

    start_supervised!(RecordArchive.child_spec(policy))
    on_exit(fn -> File.rm_rf!(base_path) end)

    mission_id = "mission-quarantine-#{System.unique_integer([:positive])}"
    persist_mission_scope("org-quarantine-#{System.unique_integer([:positive])}", mission_id)
    %{mission_id: mission_id, policy: policy, base_path: base_path}
  end

  test "an identity conflict quarantines only the named entry; the rest flushes", c do
    first = evidence(c.mission_id, "run")
    archived = frame(first, c.mission_id, 1)
    assert :ok = RecordArchive.persist_records(c.policy, first, [archived], [])
    assert :ok = RecordArchive.flush(c.policy, c.mission_id)

    # A different frame at the archived frame's id (a real conflict), and two new frames.
    later = evidence(c.mission_id, "later")
    poisoned = %{frame(later, c.mission_id, 1) | scid: 99}
    fine = [frame(later, c.mission_id, 2), frame(later, c.mission_id, 3)]
    assert :ok = RecordArchive.persist_records(c.policy, later, [poisoned | fine], [])

    assert :ok = RecordArchive.flush(c.policy, c.mission_id)

    assert [%{record_id: id, error_code: "identity_conflict", realized_contact_id: "contact-q"}] =
             Quarantine.rows(c.mission_id)

    assert id == poisoned.frame_record_id
    assert %{queue_depth: 0, backpressured?: false} = RecordArchive.stats(c.policy, c.mission_id)

    # The rest is archived, and only one segment object exists per successful flush.
    assert length(segments(c)) == 2

    # (D) The mission accepts new records again.
    next = evidence(c.mission_id, "next")
    assert :ok = RecordArchive.persist_records(c.policy, next, [frame(next, c.mission_id, 4)], [])
    assert :ok = RecordArchive.flush(c.policy, c.mission_id)
  end

  test "a data error a bisect isolates to one entry is quarantined as data_rejected", c do
    good = for n <- 1..3, do: packet_batch(c.mission_id, "good-#{n}", "SC-OK")
    bad = packet_batch(c.mission_id, "bad", "SC-\u0000-BAD")

    for {evidence, packets} <- Enum.take(good, 2) ++ [bad] ++ Enum.drop(good, 2),
        do: :ok = RecordArchive.persist_records(c.policy, evidence, [], packets)

    assert :ok = RecordArchive.flush(c.policy, c.mission_id)

    {bad_evidence, [bad_packet]} = bad

    assert [%{record_id: id, error_code: "data_rejected", error: error}] =
             Quarantine.rows(c.mission_id)

    assert id == bad_packet.packet_id
    assert error =~ "0x00"
    refute bad_evidence.evidence_id == nil
  end

  test "several data-rejected entries are all quarantined in one flush (api-ops review)", c do
    batches =
      for n <- 1..12 do
        source_ref = if rem(n, 3) == 0, do: "SC-\u0000-#{n}", else: "SC-OK"
        packet_batch(c.mission_id, "many-#{n}", source_ref)
      end

    for {evidence, packets} <- batches,
        do: :ok = RecordArchive.persist_records(c.policy, evidence, [], packets)

    assert :ok = RecordArchive.flush(c.policy, c.mission_id)

    quarantined = c.mission_id |> Quarantine.rows() |> Enum.map(& &1.record_id) |> Enum.sort()
    assert quarantined == Enum.sort(for n <- [3, 6, 9, 12], do: "packet-quarantine-many-#{n}")
    assert %{queue_depth: 0, backpressured?: false} = RecordArchive.stats(c.policy, c.mission_id)
  end

  test "a later round that ends transient hands back what it quarantined, leaving no objects",
       c do
    # One frame archived, so a different frame at its id conflicts (isolated in round 2), plus a
    # data-rejected packet (round 1) and good entries.
    run = evidence(c.mission_id, "partial-run")
    :ok = RecordArchive.persist_records(c.policy, run, [frame(run, c.mission_id, 1)], [])
    :ok = RecordArchive.flush(c.policy, c.mission_id)
    before = segments(c)

    later = evidence(c.mission_id, "partial-later")
    {bad, [bad_packet]} = packet_batch(c.mission_id, "partial-bad", "SC-\u0000")

    entries =
      FileSystem.build_entries(later, [%{frame(later, c.mission_id, 1) | scid: 99}], []) ++
        FileSystem.build_entries(bad, [], [bad_packet]) ++
        FileSystem.build_entries(later, [frame(later, c.mission_id, 2)], [])

    # The quarantine accepts round 1 and refuses round 2 (as at its cap).
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    quarantine = fn _poisoned ->
      case Agent.get_and_update(calls, &{&1, &1 + 1}) do
        0 -> :ok
        _ -> {:error, :archive_quarantine_full}
      end
    end

    opts = [base_path: c.base_path, repo: Cadence.Repo]

    assert {:error, :archive_quarantine_full, [%{error_code: "data_rejected", entry: entry}]} =
             PoisonIsolation.persist(FileSystem.new_segment_id(), entries, opts, quarantine)

    assert entry["record_id"] == bad_packet.packet_id
    # Neither round's object is left behind.
    assert segments(c) == before
  end

  test "a packet whose stored bytes are not valid base64 is quarantined as data_rejected, not raised",
       c do
    {evidence, [packet]} = packet_batch(c.mission_id, "bad-base64", "SC-OK")
    {good_evidence, [good_packet]} = packet_batch(c.mission_id, "good-base64", "SC-OK")

    entries =
      Enum.map(
        FileSystem.build_entries(evidence, [], [packet]),
        &Map.put(&1, "packet_data_base64", "not base64!")
      ) ++
        FileSystem.build_entries(good_evidence, [], [good_packet])

    quarantine = fn _poisoned -> :ok end
    opts = [base_path: c.base_path, repo: Cadence.Repo]

    assert {:ok,
            %{
              quarantined: [%{error_code: "data_rejected", entry: entry, error: error}],
              indexed: 1
            }} =
             PoisonIsolation.persist(FileSystem.new_segment_id(), entries, opts, quarantine)

    assert entry["record_id"] == packet.packet_id
    assert error =~ "not valid base64"
    assert length(segments(c)) == 1
  end

  test "an error that fails every entry is environmental: nothing is quarantined", c do
    for n <- 1..2 do
      {evidence, packets} = packet_batch(c.mission_id, "all-bad-#{n}", "SC-\u0000")
      :ok = RecordArchive.persist_records(c.policy, evidence, [], packets)
    end

    assert {:error, _reason} = RecordArchive.flush(c.policy, c.mission_id)
    assert Quarantine.rows(c.mission_id) == []
    assert %{queue_depth: 2} = RecordArchive.stats(c.policy, c.mission_id)
  end

  @tag :archive_fault
  test "a transient database error never quarantines", c do
    Cadence.ProtocolArchiveFaultRepo.fail_with(%DBConnection.ConnectionError{message: "down"})
    batch = evidence(c.mission_id, "transient")
    :ok = RecordArchive.persist_records(c.policy, batch, [frame(batch, c.mission_id, 1)], [])

    assert {:error, {:archive_database_error, _}} = RecordArchive.flush(c.policy, c.mission_id)
    assert Quarantine.rows(c.mission_id) == []

    Cadence.ProtocolArchiveFaultRepo.recover()
    assert :ok = RecordArchive.flush(c.policy, c.mission_id)
    assert Quarantine.rows(c.mission_id) == []
  end

  defp segments(c), do: Path.wildcard(Path.join([c.base_path, c.mission_id, "**", "*.bin"]))

  defp evidence(mission_id, name, source_ref \\ "SC-OK") do
    RawEvidence.new(%{
      evidence_id: "evidence-quarantine-#{name}",
      mission_id: mission_id,
      protocol_family: :tm,
      direction: :downlink,
      source_ref: source_ref,
      raw: :crypto.strong_rand_bytes(8),
      receipt_time: ~U[2026-11-14 03:14:00Z],
      metadata: %{"realized_contact_id" => "contact-q"}
    })
  end

  defp frame(evidence, mission_id, seq) do
    TransferFrameRecord.new(%{
      frame_record_id: "frame-quarantine-#{seq}",
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

  defp packet_batch(mission_id, name, source_ref) do
    evidence = evidence(mission_id, name, source_ref)

    packet = %PacketRecord{
      packet_id: "packet-quarantine-#{name}",
      evidence_id: evidence.evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 100,
      sequence_count: 1,
      packet_data: <<1, 2>>,
      receipt_time: evidence.receipt_time,
      provenance: %{}
    }

    {evidence, [packet]}
  end
end
