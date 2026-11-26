defmodule Cadence.Protocol.RecordArchive.IndexTest do
  use Cadence.ProcessDataCase, async: false

  import Ecto.Query

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.{IdentityRow, Index, SegmentRow}
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  setup do
    unique = System.unique_integer([:positive])
    base_path = Path.join(System.tmp_dir!(), "cadence_archive_index_#{unique}")

    policy =
      RecordArchive.policy(
        module: FileSystem,
        name: Module.concat(__MODULE__, "Writer#{unique}"),
        base_path: base_path,
        repo: Repo,
        flush_interval_ms: 5_000,
        flush_count: 100_000
      )

    start_supervised!(RecordArchive.child_spec(policy))
    on_exit(fn -> File.rm_rf!(base_path) end)

    mission_id = "mission-archive-index-#{unique}"
    persist_mission_scope("org-archive-index-#{unique}", mission_id)
    %{policy: policy, mission_id: mission_id, base_path: base_path}
  end

  defp evidence(mission_id, id, receipt_time, opts \\ []) do
    RawEvidence.new(%{
      evidence_id: id,
      mission_id: mission_id,
      protocol_family: :tm,
      direction: :downlink,
      raw: <<1, 2>>,
      receipt_time: receipt_time,
      source_ref: Keyword.get(opts, :source_ref, "source-a"),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  defp frame(evidence, seq, spacecraft_id \\ "sc-1") do
    TransferFrameRecord.new(%{
      frame_record_id: "frame-#{evidence.mission_id}-#{seq}",
      evidence_id: evidence.evidence_id,
      mission_id: evidence.mission_id,
      spacecraft_id: spacecraft_id,
      protocol_family: :tm,
      direction: :downlink,
      scid: 11,
      vcid: 2,
      frame_seq: seq,
      raw_frame_offset_bytes: 0,
      raw_frame_length_bytes: 100,
      payload_length_bytes: 90,
      first_header_pointer: 0,
      quality: :good,
      receipt_time: evidence.receipt_time
    })
  end

  defp archive(policy, evidence, frames, packets \\ []) do
    assert :ok = RecordArchive.persist_records_many(policy, [{evidence, frames, packets}])
    assert :ok = RecordArchive.flush(policy, evidence.mission_id)
  end

  test "a segment gets one summary row and each record a narrow identity row", ctx do
    ev = evidence(ctx.mission_id, "ev-narrow", ~U[2026-11-25 10:00:00Z])

    packet = %PacketRecord{
      packet_id: "packet-narrow",
      evidence_id: ev.evidence_id,
      mission_id: ctx.mission_id,
      spacecraft_id: "sc-1",
      protocol_family: :tm,
      packet_kind: :space_packet,
      packet_data: <<1>>,
      receipt_time: ev.receipt_time,
      provenance: %{}
    }

    archive(ctx.policy, ev, [frame(ev, 1), frame(ev, 2)], [packet])

    assert [segment] = Repo.all(from(s in SegmentRow, where: s.mission_id == ^ctx.mission_id))

    assert %{
             frame_count: 2,
             packet_count: 1,
             spacecraft_ids: ["sc-1"],
             evidence_ids: ["ev-narrow"]
           } = segment

    assert segment.first_receipt_time == ~U[2026-11-25 10:00:00.000000Z]

    identities = Repo.all(from(i in IdentityRow, where: i.segment_id == ^segment.id))
    assert length(identities) == 3
    assert Enum.all?(identities, &(byte_size(&1.content_sha256) == 32))
  end

  test "a replayed frame resolves to its original and is counted once", ctx do
    first =
      evidence(ctx.mission_id, "ev-run", ~U[2026-11-25 10:00:00Z],
        metadata: %{"realized_contact_id" => "contact-1"}
      )

    archive(ctx.policy, first, [frame(first, 1), frame(first, 2)])

    # The same journal frames, grouped into other evidence after a restart, plus one new frame.
    replay =
      evidence(ctx.mission_id, "ev-replay", ~U[2026-11-25 10:05:00Z],
        metadata: %{"realized_contact_id" => "contact-1"}
      )

    archive(ctx.policy, replay, [frame(replay, 1), frame(replay, 2), frame(replay, 3)])

    assert {:ok, frames} =
             RecordArchive.fetch_transfer_frame_records(
               ctx.policy,
               ctx.mission_id,
               Scope.new(%{})
             )

    assert Enum.map(frames, & &1.frame_seq) == [1, 2, 3]
    # The replayed duplicates resolve to the original run's records.
    assert [%{evidence_id: "ev-run"}, %{evidence_id: "ev-run"}, %{evidence_id: "ev-replay"}] =
             frames

    # Three frames, not five: the replay's duplicates are not counted again.
    assert %{"contact-1" => 3} = FileSystem.received_frames(ctx.mission_id, ["contact-1"])
  end

  test "replay picks segments by scope and filters their entries", ctx do
    early = evidence(ctx.mission_id, "ev-early", ~U[2026-11-25 09:00:00Z], source_ref: "source-a")
    late = evidence(ctx.mission_id, "ev-late", ~U[2026-11-25 11:00:00Z], source_ref: "source-b")
    archive(ctx.policy, early, [frame(early, 1, "sc-1")])
    archive(ctx.policy, late, [frame(late, 2, "sc-2")])

    fetch = fn scope ->
      {:ok, frames} =
        RecordArchive.fetch_transfer_frame_records(ctx.policy, ctx.mission_id, Scope.new(scope))

      Enum.map(frames, & &1.frame_seq)
    end

    assert fetch.(%{spacecraft_id: "sc-2"}) == [2]
    assert fetch.(%{source_ref: "source-a"}) == [1]
    assert fetch.(%{evidence_ids: ["ev-late"]}) == [2]
    assert fetch.(%{from_receipt_time: ~U[2026-11-25 10:00:00Z]}) == [2]
    assert fetch.(%{to_receipt_time: ~U[2026-11-25 10:00:00Z]}) == [1]
    assert fetch.(%{limit: 1}) == [1]

    # The segment query narrows before any object is read.
    scope = Scope.new(%{spacecraft_id: "sc-2"})

    assert [%{evidence_ids: ["ev-late"]}] =
             Index.candidate_segments(
               ctx.mission_id,
               scope,
               "transfer_frame_record",
               ctx.policy.backend_opts
             )
  end

  test "indexing a segment that is already indexed leaves its object in place", ctx do
    ev = evidence(ctx.mission_id, "ev-retry", ~U[2026-11-25 10:00:00Z])
    entries = FileSystem.build_entries(ev, [frame(ev, 1)], [])
    opts = Keyword.put(ctx.policy.backend_opts, :organization_id, nil)

    assert {:ok, object_key, _size} =
             FileSystem.store_segment_object("retry-segment", entries, opts)

    opts = Keyword.put(opts, :object_key, object_key)
    assert :ok = FileSystem.persist_segment("retry-segment", entries, opts)
    assert :ok = FileSystem.persist_segment("retry-segment", entries, opts)

    assert File.regular?(Path.join(ctx.base_path, object_key))
    assert Repo.aggregate(from(s in SegmentRow, where: s.object_key == ^object_key), :count) == 1
  end

  test "the same record id carrying different bytes is an identity conflict, not a replay", ctx do
    ev = evidence(ctx.mission_id, "ev-bytes", ~U[2026-11-25 10:00:00Z])
    packet = packet(ev, "packet-same-id", <<1, 2, 3, 4>>)
    archive(ctx.policy, ev, [], [packet])

    # The same packet re-grouped into other evidence is the same record (11-14's replay).
    replay = evidence(ctx.mission_id, "ev-bytes-replay", ~U[2026-11-25 10:30:00Z])

    archive(ctx.policy, replay, [], [
      %{packet | evidence_id: replay.evidence_id, receipt_time: replay.receipt_time}
    ])

    # Other bytes under the same id: a conflict #88 quarantines, whose segment is never indexed.
    other = evidence(ctx.mission_id, "ev-bytes-other", ~U[2026-11-25 11:00:00Z])

    entries =
      FileSystem.build_entries(other, [], [packet(other, "packet-same-id", <<9, 9, 9, 9>>)])

    assert {:error, {:protocol_archive_record_identity_conflict, ["packet-same-id"]}} =
             FileSystem.persist_segment("other-bytes", entries,
               object_key: "#{ctx.mission_id}/other-bytes.bin"
             )
  end

  test "another frame's bytes under the same frame id is an identity conflict, not a replay",
       ctx do
    ev = evidence(ctx.mission_id, "ev-frame-bytes", ~U[2026-11-25 10:00:00Z])
    original = %{frame(ev, 1) | frame_sha256: :crypto.hash(:sha256, "the frame's bytes")}
    archive(ctx.policy, ev, [original])

    # The same frame re-grouped into other evidence (same bytes, so the same hash): a replay.
    replay = evidence(ctx.mission_id, "ev-frame-bytes-replay", ~U[2026-11-25 10:30:00Z])

    regrouped = %{
      original
      | evidence_id: replay.evidence_id,
        receipt_time: replay.receipt_time
    }

    archive(ctx.policy, replay, [regrouped])

    # Other bytes under the same id: a conflict, and the segment is not indexed.
    other = evidence(ctx.mission_id, "ev-frame-bytes-other", ~U[2026-11-25 11:00:00Z])
    different = %{original | frame_sha256: :crypto.hash(:sha256, "other bytes")}
    entries = FileSystem.build_entries(other, [different], [])

    assert {:error, {:protocol_archive_record_identity_conflict, [id]}} =
             FileSystem.persist_segment("other-frame", entries,
               object_key: "#{ctx.mission_id}/other-frame.bin"
             )

    assert id == original.frame_record_id
  end

  describe "digest/1 (persisted, so pinned: DECISIONS #108)" do
    @packet %{
      "record_kind" => "packet_record",
      "record_id" => "packet-golden",
      "mission_id" => "mission-golden",
      "spacecraft_id" => "sc-1",
      "protocol_family" => "tm",
      "direction" => "downlink",
      "apid" => 42,
      "packet_kind" => "space_packet",
      "packet_data_base64" => "AQIDBA==",
      "evidence_id" => "ignored"
    }

    @frame %{
      "record_kind" => "transfer_frame_record",
      "record_id" => "frame-golden",
      "mission_id" => "mission-golden",
      "spacecraft_id" => "sc-1",
      "protocol_family" => "tm",
      "direction" => "downlink",
      "scid" => 11,
      "vcid" => 2,
      "map_id" => nil,
      "frame_seq" => 7,
      "raw_frame_length_bytes" => 1115,
      "payload_length_bytes" => 1109,
      "frame_sha256" => String.duplicate("ab", 32),
      "evidence_id" => "ignored"
    }

    test "is sha256(\"archive_identity_v2\" <> JSON of the named fields <> sha256(payload))" do
      # Computed independently of the implementation (Python's hashlib and json), so a change to
      # the encoding, the field order or the version prefix fails here before it stalls a replay.
      assert hex(Index.digest(@packet)) ==
               "82c769df03cad59fd5ab68d78ce70913851679cf3ecf059eca97bd3d895f449e"

      assert hex(Index.digest(@frame)) ==
               "b539d3ec126b162b2ceaf7da55894144bbd4814cd7280dc6174315fb97a03821"
    end

    test "ignores the transport fields and covers the bytes" do
      moved =
        Map.merge(@packet, %{"evidence_id" => "other", "receipt_time" => "2026-01-01T00:00:00Z"})

      assert Index.digest(moved) == Index.digest(@packet)

      assert Index.digest(%{@packet | "packet_data_base64" => Base.encode64(<<4, 3, 2, 1>>)}) !=
               Index.digest(@packet)

      assert Index.digest(%{@packet | "apid" => 43}) != Index.digest(@packet)
      assert Index.digest(%{@frame | "frame_seq" => 8}) != Index.digest(@frame)

      # The frame's own bytes are covered (#738): another hash under the same id is another frame.
      assert Index.digest(%{@frame | "frame_sha256" => String.duplicate("cd", 32)}) !=
               Index.digest(@frame)
    end

    defp hex(binary), do: Base.encode16(binary, case: :lower)
  end

  defp packet(evidence, id, bytes) do
    %PacketRecord{
      packet_id: id,
      evidence_id: evidence.evidence_id,
      mission_id: evidence.mission_id,
      spacecraft_id: "sc-1",
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 42,
      packet_data: bytes,
      receipt_time: evidence.receipt_time,
      provenance: %{}
    }
  end
end
