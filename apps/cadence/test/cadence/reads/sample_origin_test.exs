defmodule Cadence.Reads.SampleOriginTest do
  @moduledoc """
  #1078 P5 slice E1a: a sample's origin is read back from its archived packet, never guessed. When
  there is none, the answer says why: the packet is no longer archived (the observation outlived
  it), it was archived before origins were recorded, a timer produced the value, or the archive
  could not be read.
  """
  use Cadence.ProcessDataCase, async: false
  @moduletag :tmp_dir

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{Origin, PacketRecord, RecordArchive}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Reads.SampleOrigin
  alias Cadence.Repo

  @receipt ~U[2026-11-28 12:00:00.000000Z]
  @origin %{
    v: 1,
    kind: :direct,
    source_endpoint_id: "endpoint-1",
    scid: 11,
    vcid: 2,
    map_id: nil,
    apid: 42,
    relay: nil
  }

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
    mission = "mission-sample-origin-" <> suffix
    persist_mission_scope("org-sample-origin-" <> suffix, mission)

    archive!(policy, mission, [
      packet(mission, "packet-new", @origin),
      packet(mission, "packet-old", nil)
    ])

    %{policy: policy, mission: mission}
  end

  test "a sample's origin is its archived packet's, as JSON values", c do
    assert %{origin: origin, origin_reason: nil} =
             SampleOrigin.for_sample(c.mission, container("s1", "packet-new"), archive: c.policy)

    assert origin == %{
             "v" => 1,
             "kind" => "direct",
             "source_endpoint_id" => "endpoint-1",
             "scid" => 11,
             "vcid" => 2,
             "map_id" => nil,
             "apid" => 42,
             "relay" => nil
           }
  end

  test "a packet retention has dropped reads as null with its reason, never a guess", c do
    assert %{origin: nil, origin_reason: "packet_not_archived"} =
             SampleOrigin.for_sample(c.mission, container("s2", "packet-dropped"),
               archive: c.policy
             )

    assert %{origin: nil, origin_reason: "packet_not_archived"} =
             SampleOrigin.for_sample(c.mission, container("s3", nil), archive: c.policy)
  end

  test "a packet archived before origins were recorded says so", c do
    assert %{origin: nil, origin_reason: "origin_not_recorded"} =
             SampleOrigin.for_sample(c.mission, container("s4", "packet-old"), archive: c.policy)
  end

  test "a derived sample reads its trigger's packet; a timer-triggered one has none", c do
    triggered = derived("d1", "packet-new")
    timer = derived("d2", "d2")

    answers = SampleOrigin.for_samples(c.mission, [triggered, timer], archive: c.policy)

    assert %{origin: %{"scid" => 11}, origin_reason: nil} = answers["d1"]
    assert answers["d2"] == %{origin: nil, origin_reason: "timer_triggered"}
  end

  test "a page is one archive lookup, whatever its size", c do
    page =
      for n <- 1..40,
          do: container("page-#{n}", if(rem(n, 2) == 0, do: "packet-new", else: "gone-#{n}"))

    {answers, queries} =
      count_queries(fn -> SampleOrigin.for_samples(c.mission, page, archive: c.policy) end)

    assert map_size(answers) == 40
    assert queries <= 2
    assert answers["page-2"].origin_reason == nil
    assert answers["page-1"].origin_reason == "packet_not_archived"
  end

  test "an archive that cannot be read says so instead of answering", c do
    for file <- Path.wildcard(Path.join(c.policy.backend_opts[:base_path], "**/*.bin")),
        do: File.rm!(file)

    assert %{origin: nil, origin_reason: "archive_unavailable"} =
             SampleOrigin.for_sample(c.mission, container("s5", "packet-new"), archive: c.policy)
  end

  defp container(sample_id, packet_id),
    do: %{sample_id: sample_id, packet_id: packet_id, packet_definition_id: "packet-def"}

  defp derived(sample_id, packet_id) do
    %{
      sample_id: sample_id,
      packet_id: packet_id,
      packet_definition_id: "mission_model_algorithm:algo-1"
    }
  end

  defp archive!(policy, mission, packets) do
    evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-sample-origin",
        mission_id: mission,
        protocol_family: :tm,
        raw: <<1, 2>>,
        receipt_time: @receipt
      })

    assert :ok = RecordArchive.persist_records(policy, evidence, [], packets)
    assert :ok = RecordArchive.flush(policy, mission)
  end

  defp packet(mission, id, origin) do
    %PacketRecord{
      packet_id: id,
      evidence_id: "evidence-sample-origin",
      mission_id: mission,
      protocol_family: :tm,
      packet_kind: :space_packet,
      source_endpoint_ref: origin && origin.source_endpoint_id,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<1, 2>>,
      receipt_time: @receipt,
      provenance:
        if(origin,
          do: %{origin: Origin.stored(origin), tm: %{scid: 11, vcid: 2, map_id: nil}},
          else: %{}
        )
    }
  end

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
