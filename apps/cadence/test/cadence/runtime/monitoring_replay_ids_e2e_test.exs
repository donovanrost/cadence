defmodule Cadence.Runtime.MonitoringReplayIdsE2ETest do
  @moduledoc """
  DECISIONS #99, the end-to-end test (lead 11-17: required before #99's restart). A live mission
  runtime with a catalog limit takes journal-positioned TM frames; the limit fires and the alarm
  episode and event are written with replay-safe ids. Then the crash window #99 exists for: the
  effects were written but the partition's semantic commit didn't survive. The partition owner is
  killed and recovers from the store (state from before the input), and the journal replays the
  same bytes, once as the same evidence and once re-cut mid-frame (another batching). Each replay
  re-derives the same transition and finds the same ids: no new rows, no MM_REPLAY_ID_CONFLICT.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Control.MissionRuntime, as: ControlMissionRuntime
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Management.Activations
  alias Cadence.Platform.ReplayId
  alias Cadence.Runtime.{MissionCoordinator, PartitionKey, PartitionOwner, Persistence}
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  # HEALTH.mode carries catalog limits; 50 is past red_high.
  @limited_yaml """
  packets:
    - name: HEALTH
      apid: 42
      items:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_size: 8
          limits:
            yellow_high: 5
            red_high: 20
  commands: []
  """

  @frame_size 10
  @stream "e2e-replay-stream"

  setup do
    org = "org-replay-e2e-#{System.unique_integer([:positive])}"
    mid = "mission-replay-e2e-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    c = %{org: org, mission: mission, scope: scope, craft: craft, endpoint: endpoint}
    configure(c, revision.catalog_revision_id)

    limited =
      Fixtures.persist_imported_revision!(org, mid, revision_label: "Limits", yaml: @limited_yaml)

    profile = profile!(c, revision.catalog_revision_id)

    apply!(c, [
      update("spacecraft_profile", profile, "catalog_revision_id", limited.catalog_revision_id)
    ])

    readmit!(c)

    on_exit(fn -> Cadence.Runtime.stop_mission(mid) end)
    c
  end

  test "a replay after the crash window, as one batch or re-cut, finds the same alarm ids", c do
    raise_frames = frames(mode: 50, sequence: 1)
    clear_frames = frames(mode: 0, sequence: 2)
    clear_at = byte_size(raise_frames)

    log =
      capture_log(fn ->
        # The limit fires, then a later frame clears it: one episode, raised and cleared.
        assert transition?(ingest!(evidence(c, raise_frames, 0)), :critical)
        assert transition?(ingest!(evidence(c, clear_frames, clear_at)), :normal)
        first = effect_ids(c)

        assert [_episode] = first.episodes
        assert length(first.events) == 2
        assert Enum.all?(first.episodes ++ first.events, &match?({:ok, _}, ReplayId.parse(&1)))

        # The crash window, then the journal replays the first frame. Monitoring re-derives the
        # raise, and with no active episode the writer would OPEN a second one (what an Ids.new id
        # did before #99); the episode's id is already stored, so it is a replay and skipped.
        crash_window!(c)
        assert transition?(ingest!(evidence(c, raise_frames, 0)), :critical)
        assert effect_ids(c) == first
        assert [%{state: "cleared"}] = episodes(c)

        # The same replay, re-cut mid-frame: two evidences, the second starting inside a frame.
        crash_window!(c)
        cut = div(@frame_size, 2) + 1
        <<head::binary-size(^cut), tail::binary>> = raise_frames
        refute transition?(ingest!(evidence(c, head, 0)), :critical)
        assert transition?(ingest!(evidence(c, tail, cut)), :critical)
        assert effect_ids(c) == first
        assert [%{state: "cleared"}] = episodes(c)
      end)

    refute log =~ "MM_REPLAY_ID_CONFLICT"
  end

  # The window #99 covers: the alarm effects were written, the partition's monitoring state wasn't
  # kept. Drop the partition's semantic runtime rows and the latest alarm state (MonitoringSeed
  # restores monitoring from it at recovery), then kill the owner: it recovers from before the
  # input, so the replay re-derives the same transition and the writer meets the stored ids.
  defp crash_window!(c) do
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}
    {:ok, owner} = PartitionOwner.lookup(c.mission.mission_id, key)

    for table <- [
          "semantic_runtime_commits",
          "semantic_runtime_heads",
          "semantic_runtime_checkpoints"
        ] do
      Repo.delete_all(from(row in table, where: field(row, :mission_id) == ^c.mission.mission_id))
    end

    Repo.delete_all(
      from(row in "semantic_latest_alarm_states", where: row.mission_id == ^c.mission.mission_id)
    )

    Process.exit(owner, :kill)

    assert_eventually(fn ->
      match?({:ok, pid} when pid != owner, PartitionOwner.lookup(c.mission.mission_id, key))
    end)
  end

  # The partition processes; the persistence projector then writes the results. The test makes
  # the projector's own call (journal-owned evidence: semantic outputs only), synchronously.
  defp ingest!(evidence) do
    {:ok, result} = Cadence.process_telemetry_ingress(evidence)
    :ok = Persistence.persist_semantic_processing_results([result])
    result
  end

  defp transition?(%{semantic_result: %{monitoring_results: results}}, to),
    do: Enum.any?(results, &match?(%{transition: %{to: ^to}}, &1))

  defp transition?(_result, _to), do: false

  defp episodes(c),
    do: Repo.all(from(e in EpisodeRow, where: e.mission_id == ^c.mission.mission_id))

  defp effect_ids(c) do
    mission = c.mission.mission_id

    %{
      episodes:
        Repo.all(from(e in EpisodeRow, where: e.mission_id == ^mission, select: e.episode_id))
        |> Enum.sort(),
      events:
        Repo.all(from(e in EpisodeEventRow, where: e.mission_id == ^mission, select: e.event_id))
        |> Enum.sort()
    }
  end

  defp evidence(c, bytes, offset) do
    RawEvidence.new(%{
      mission_id: c.mission.mission_id,
      source_endpoint_ref: c.endpoint.source_endpoint_id,
      spacecraft_id: c.craft.spacecraft_id,
      protocol_family: :tm,
      receipt_time: ~U[2026-11-17 01:00:00.000000Z],
      receipt_times: records(offset, byte_size(bytes)),
      raw: bytes,
      metadata: %{
        "journal_stream_id" => @stream,
        "journal_start_offset" => offset,
        "journal_end_offset" => offset + byte_size(bytes),
        frame_size: @frame_size,
        ocf_length: 0
      }
    })
  end

  # The journal's records (socket reads): 2 bytes each, received 1 ms apart. A batch is whole
  # records (every offset used here is even), so each byte has the same record, and time, however
  # the replay batches them.
  defp records(offset, size) do
    for start <- offset..(offset + size - 1)//2,
        do: {start, DateTime.add(~U[2026-11-17 01:00:00.000000Z], start, :millisecond)}
  end

  defp frames(mode: mode, sequence: sequence) do
    packet = <<0::3, 0::1, 0::1, 42::11, 3::2, sequence::14, 0::16, mode::8>>

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, state} = Segmentation.init([])

    {:ok, encoded, _state} =
      Segmentation.segment_encode(sdu, %{frame_size: @frame_size, ocf_length: 0}, state, [])

    IO.iodata_to_binary(encoded)
  end

  defp readmit!(c) do
    reconciler = ControlMissionRuntime.reconciler_name(c.mission.mission_id)
    old = GenServer.whereis(reconciler)
    Process.exit(old, :kill)

    assert_eventually(fn ->
      pid = GenServer.whereis(reconciler)

      pid not in [nil, old] and
        match?(
          %{applied_generation: g, last_error: nil} when is_integer(g),
          GenServer.call(pid, :snapshot)
        )
    end)

    {:ok, spec} = MissionCoordinator.active_spec(c.mission.mission_id)
    spec
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp profile!(c, catalog) do
    id = "profile-replay-e2e-#{System.unique_integer([:positive])}"

    apply!(c, [
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: id,
        document: %{
          "display_name" => "Replay e2e profile",
          "downlink_protocol" => "tm",
          "uplink_protocol" => "tc",
          "catalog_revision_id" => catalog,
          "frame_parameters" => %{"frame_size" => @frame_size, "ocf_length" => 0}
        }
      }
    ])

    apply!(c, [
      %{
        kind: "spacecraft",
        action: :update,
        entity_id: c.craft.spacecraft_id,
        changes: [
          %{path: "spacecraft_type_id", value: id},
          %{path: "spacecraft_type_version", value: 1}
        ]
      }
    ])

    id
  end

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}

  defp apply!(c, ops) do
    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "E2E"}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
        reason: "Replay ids end-to-end test",
        expected_version: staged.version,
        acknowledged_holds: true
      })
  end

  defp configure(c, catalog) do
    current = Drafts.snapshot(c.mission, c.craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    {:ok, _} =
      Drafts.save(c.scope, c.mission.mission_id, c.craft.spacecraft_id, current.token, document)

    token = Drafts.snapshot(c.mission, c.craft).token

    {:ok, request} =
      Review.request_many(c.scope, c.mission.mission_id, %{c.craft.spacecraft_id => token})

    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
