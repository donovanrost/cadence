defmodule Cadence.Protocol.RecordArchive.PacketOriginsTest do
  @moduledoc """
  #1078 P5 slice E1a: a stored sample's origin is read back from its archived packet, for a whole
  page of packet ids in one lookup, never one per row. A packet the archive no longer holds has no
  key; one archived before origins were recorded maps to nil; another mission's packet is never
  returned.
  """
  use Cadence.ProcessDataCase, async: false
  @moduletag :tmp_dir

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Protocol.{Origin, PacketRecord, RecordArchive}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Repo

  @receipt ~U[2026-11-28 12:00:00.000000Z]

  setup context do
    policy =
      RecordArchive.policy(
        module: FileSystem,
        base_path: context.tmp_dir,
        repo: Repo,
        flush_interval_ms: 5_000,
        flush_count: 1_000
      )

    start_supervised!(RecordArchive.child_spec(policy))

    suffix = Integer.to_string(System.unique_integer([:positive]))
    org = "org-origins-" <> suffix
    mission = "mission-origins-" <> suffix
    other = "mission-origins-other-" <> suffix

    persist_mission_scope(org, mission)
    persist_mission_scope(org, other)

    %{policy: policy, mission: mission, other: other}
  end

  test "reads each packet's origin in one lookup, however many are asked for", c do
    packets = for n <- 1..30, do: packet(c.mission, "packet-#{n}", origin(n))
    archive!(c.policy, c.mission, "evidence-a", packets)

    ids = Enum.map(packets, & &1.packet_id)

    {{:ok, one}, one_queries} =
      count_queries(fn -> RecordArchive.fetch_packet_origins(c.policy, c.mission, [hd(ids)]) end)

    {{:ok, all}, all_queries} =
      count_queries(fn -> RecordArchive.fetch_packet_origins(c.policy, c.mission, ids) end)

    assert json(one) == %{"packet-1" => origin_json(1)}
    assert map_size(all) == 30
    assert json(all)["packet-17"] == origin_json(17)

    # One identity lookup finds the segments; the count doesn't follow the number of packets.
    assert all_queries == one_queries
    assert all_queries <= 2
  end

  test "a packet the archive does not hold has no key; one from before origins maps to nil", c do
    archive!(c.policy, c.mission, "evidence-b", [
      packet(c.mission, "with-origin", origin(1)),
      packet(c.mission, "before-origins", nil)
    ])

    assert {:ok, origins} =
             RecordArchive.fetch_packet_origins(c.policy, c.mission, [
               "with-origin",
               "before-origins",
               "dropped-by-retention"
             ])

    assert json(origins) == %{"with-origin" => origin_json(1), "before-origins" => nil}
    refute Map.has_key?(origins, "dropped-by-retention")
  end

  test "another mission's packet is not returned", c do
    archive!(c.policy, c.other, "evidence-c", [packet(c.other, "foreign", origin(1))])

    assert {:ok, %{}} = RecordArchive.fetch_packet_origins(c.policy, c.mission, ["foreign"])

    assert {:ok, %{"foreign" => _}} =
             RecordArchive.fetch_packet_origins(c.policy, c.other, ["foreign"])
  end

  test "the Postgres backend reads the same answers in one query", c do
    postgres = RecordArchive.policy([])

    evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-postgres",
        mission_id: c.mission,
        protocol_family: :tm,
        raw: <<1, 2>>,
        receipt_time: @receipt
      })

    Repo.insert!(RawEvidenceRow.changeset(evidence))

    for packet <- [packet(c.mission, "pg-with", origin(1)), packet(c.mission, "pg-old", nil)] do
      Repo.insert!(PacketRecordRow.changeset(%{packet | evidence_id: "evidence-postgres"}))
    end

    {{:ok, origins}, queries} =
      count_queries(fn ->
        RecordArchive.fetch_packet_origins(postgres, c.mission, ["pg-with", "pg-old", "pg-gone"])
      end)

    assert json(origins) == %{"pg-with" => origin_json(1), "pg-old" => nil}
    assert queries == 1

    assert {:ok, %{}} = RecordArchive.fetch_packet_origins(postgres, c.other, ["pg-with"])
  end

  test "an empty page reads nothing", c do
    {result, queries} =
      count_queries(fn -> RecordArchive.fetch_packet_origins(c.mission, []) end)

    assert result == {:ok, %{}}
    assert queries == 0
  end

  defp archive!(policy, mission, evidence_id, packets) do
    evidence =
      RawEvidence.new(%{
        evidence_id: evidence_id,
        mission_id: mission,
        protocol_family: :tm,
        raw: <<1, 2>>,
        receipt_time: @receipt
      })

    assert :ok = RecordArchive.persist_records(policy, evidence, [], packets)
    assert :ok = RecordArchive.flush(policy, mission)
  end

  defp packet(mission, id, origin) do
    provenance = if origin, do: %{origin: origin}, else: %{}

    %PacketRecord{
      packet_id: id,
      evidence_id: "evidence-placeholder",
      mission_id: mission,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<1, 2>>,
      receipt_time: @receipt,
      provenance: provenance
    }
  end

  defp origin(n) do
    %{
      v: 1,
      kind: :direct,
      source_endpoint_id: "endpoint-#{n}",
      scid: 11,
      vcid: 2,
      map_id: nil,
      apid: 42,
      relay: nil
    }
  end

  # The descriptor as plain JSON values: the archive hands it back as it stored it (a segment keeps
  # the terms, Postgres the JSON), and `Origin.to_json/1` makes both one form.
  defp origin_json(n), do: n |> origin() |> Origin.to_json()

  defp json(origins), do: Map.new(origins, fn {id, o} -> {id, o && Origin.to_json(o)} end)

  defp count_queries(fun) do
    owner = self()
    counter = :counters.new(1, [])
    handler = make_ref()

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == owner, do: :counters.add(counter, 1, 1)
        end,
        nil
      )

    try do
      {fun.(), :counters.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end
end
