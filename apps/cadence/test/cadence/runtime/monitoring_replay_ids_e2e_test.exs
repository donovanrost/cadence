defmodule Cadence.Runtime.MonitoringReplayIdsE2ETest do
  @moduledoc """
  DECISIONS #99, the end-to-end test (lead 11-17: required before #99's restart). A live mission
  runtime with a catalog limit takes journal-positioned TM frames; the limit fires and the alarm
  episode and event are written with replay-safe ids. Then the crash window #99 exists for: the
  effects were written but the partition's semantic state didn't survive. The partition owner is
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

  # HEALTH.mode and HEALTH.aux carry catalog limits; 50 is past red_high.
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
        - name: aux
          data_type: uint
          bit_offset: 8
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
    raise_frames = frames(mode: 50, aux: 0, sequence: 1)
    clear_frames = frames(mode: 0, aux: 0, sequence: 2)
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

  # #161/#162: a sample's id comes from its packet (the journal position), not from the evidence
  # that carried it, so a replay cut into other batches re-derives the same sample ids, and the
  # monitoring evaluation and transition ids built over them: nothing is written twice.
  test "a re-cut replay re-derives the same sample ids, and no evaluation or transition twice",
       c do
    raise_frames = frames(mode: 50, aux: 0, sequence: 1)

    log =
      capture_log(fn ->
        first = ingest!(evidence(c, raise_frames, 0))
        assert transition?(first, :critical)
        rows = monitoring_rows(c)
        assert [_transition] = rows.transitions
        assert [_evaluation] = rows.evaluations

        crash_window!(c)
        cut = div(@frame_size, 2) + 1
        <<head::binary-size(^cut), tail::binary>> = raise_frames
        refute transition?(ingest!(evidence(c, head, 0)), :critical)
        replay = ingest!(evidence(c, tail, cut))
        assert transition?(replay, :critical)

        assert update_ids(replay) == update_ids(first)
        assert monitoring_rows(c) == rows
      end)

    refute log =~ "MM_REPLAY_ID_CONFLICT"
  end

  # #692: the reply names the partition whose snapshot gates the journal's durable ack, and a
  # stopping partition writes that snapshot, with the offset its stream is processed through.
  test "a stopping partition snapshots its semantic state and the stream offset", c do
    bytes = frames(mode: 50, aux: 0, sequence: 1)
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}

    result = ingest!(evidence(c, bytes, 0))
    assert result.semantic_snapshot_partition == PartitionKey.identifier(key)

    snapshots = fn ->
      Repo.all(
        from(s in "semantic_runtime_snapshots",
          where: s.mission_id == ^c.mission.mission_id,
          select: s.resume
        )
      )
    end

    # The stop flushes it; the cadence (60 s, or 2 s idle on a 1 s tick) has not run yet.
    {:ok, owner} = PartitionOwner.lookup(c.mission.mission_id, key)
    :ok = PartitionOwner.stop(owner)

    assert [%{@stream => offset}] = snapshots.()
    assert offset == byte_size(bytes)
  end

  # #692, the crash test for the snapshot design: a partition is killed mid-window, between two
  # snapshots. It recovers from the snapshot, the journal replays from the snapshot's offset (and,
  # to be sure, also from before it), and the state ends identical to the uninterrupted partition's,
  # with no new effect rows.
  test "a partition killed between snapshots recovers from the snapshot and the journal replay",
       c do
    raise_frames = frames(mode: 50, aux: 0, sequence: 1)
    clear_frames = frames(mode: 0, aux: 0, sequence: 2)
    clear_at = byte_size(raise_frames)
    # The journal's replay hands over the same evidence (its id derives from stream and offsets).
    raise_evidence = evidence(c, raise_frames, 0)
    clear_evidence = evidence(c, clear_frames, clear_at)

    log =
      capture_log(fn ->
        assert transition?(ingest!(raise_evidence), :critical)
        snapshot_now!(c)

        # After the snapshot, never snapshotted: the clear, and the effects it wrote.
        assert transition?(ingest!(clear_evidence), :normal)
        uninterrupted = semantic_state(c)
        effects = effect_ids(c)
        assert [%{resume: %{@stream => ^clear_at}}] = snapshot_rows(c)
        assert [_episode] = effects.episodes

        kill_partition!(c)

        # The recovered owner holds what the snapshot did: the raise, not the clear.
        recovered = semantic_state(c)
        refute recovered == uninterrupted
        assert recovered.sequence < uninterrupted.sequence

        # The journal replays from the snapshot's offset: the clear, again.
        assert transition?(ingest!(clear_evidence), :normal)
        assert semantic_state(c) == uninterrupted
        assert effect_ids(c) == effects

        # The journal replaying frames the snapshot already holds changes nothing: the state is
        # not applied to twice, and the same effects are found.
        ingest!(raise_evidence)
        assert semantic_state(c) == uninterrupted
        assert effect_ids(c) == effects
        assert [%{state: "cleared"}] = episodes(c)
      end)

    refute log =~ "MM_REPLAY_ID_CONFLICT"
  end

  # Journal off (DECISIONS #95): there is no journal to replay, and no per-batch log. A crash loses
  # the semantic memory since the last snapshot, at most 60 s of it; recovery is the snapshot. This
  # pins what is lost (latest values, algorithm memory, monitoring since the snapshot) and what is
  # not (the alarm episode, which is a projection written with the batch).
  test "with no journal to replay, a crash loses the semantic memory since the last snapshot",
       c do
    raise_frames = frames(mode: 50, aux: 0, sequence: 1)

    capture_log(fn ->
      assert transition?(ingest!(evidence(c, raise_frames, 0)), :critical)
      before = semantic_state(c)
      assert map_size(before.latest) > 0
      assert snapshot_rows(c) == []
      assert [%{state: "active"}] = episodes(c)

      kill_partition!(c)

      lost = semantic_state(c)
      assert lost.latest == %{}
      assert lost.algorithm_state == %{}
      assert lost.sequence == 0
      # The projected alarm survives; the monitoring prior is re-seeded from it.
      assert [%{state: "active"}] = episodes(c)
      assert Enum.all?(Map.values(lost.monitoring_state), &(&1.effective_state != :normal))
    end)
  end

  # #831: after a node restart the ETS current-value store is empty until each spacecraft's next
  # frame. A starting owner puts its snapshot's latest values in it, with their own times. (The
  # test runtime records into the Postgres store, so the restarted owner is started by hand, under
  # an ETS store, taking the partition over from the one that wrote the snapshot.)
  test "a starting owner seeds the ETS store from its snapshot before any new frame", c do
    alias Cadence.Telemetry.CurrentValueStore
    alias Cadence.Telemetry.CurrentValueStore.ETS

    mission = c.mission.mission_id
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}
    raised = frames(mode: 50, aux: 7, sequence: 1)

    capture_log(fn ->
      assert transition?(ingest!(evidence(c, raised, 0)), :critical)
      snapshot_now!(c)

      cache = CurrentValueStore.policy(module: ETS)
      start_supervised!(CurrentValueStore.child_spec(cache))
      assert CurrentValueStore.latest_values_for_mission(cache, mission, []) == []

      {:ok, spec} = MissionCoordinator.active_spec(mission)
      configured = Persistence.configured_policy()

      policy = %{
        configured
        | telemetry_storage: %{configured.telemetry_storage | current_value_store_policy: cache}
      }

      {:ok, owner} =
        PartitionOwner.start_link(
          mission_id: mission,
          partition_key: key,
          active_activation: spec,
          binding_set: spec.binding_set,
          persistence_policy: policy,
          register?: false
        )

      on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)

      # Before any frame: the values are there, as old as they are.
      values =
        Map.new(
          CurrentValueStore.latest_values_for_mission(cache, mission, []),
          &{&1.point_id, &1}
        )

      assert %{engineering_value: 50, receipt_time: at} = values["HEALTH.mode"]
      assert %{engineering_value: 7} = values["HEALTH.aux"]
      assert DateTime.compare(at, ~U[2026-11-17 02:00:00Z]) == :lt
      assert %{seeded_from: "semantic_snapshot"} = values["HEALTH.mode"].provenance
    end)
  end

  # A snapshot when the cadence would not take one yet (60 s, or 2 s idle): the tick says due.
  defp snapshot_now!(c) do
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}
    {:ok, owner} = PartitionOwner.lookup(c.mission.mission_id, key)

    :sys.replace_state(owner, fn state ->
      %{
        state
        | semantic_snapshot_config: Keyword.put(state.semantic_snapshot_config, :idle_ms, 0)
      }
    end)

    send(owner, :semantic_snapshot_tick)
    _ = :sys.get_state(owner)
    assert [_snapshot] = snapshot_rows(c)
  end

  defp snapshot_rows(c) do
    Repo.all(
      from(s in "semantic_runtime_snapshots",
        where: s.mission_id == ^c.mission.mission_id,
        select: %{resume: s.resume}
      )
    )
  end

  defp semantic_state(c) do
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}
    {:ok, owner} = PartitionOwner.lookup(c.mission.mission_id, key)
    :sys.get_state(owner).semantic_state
  end

  # api-ops' wedge (review 11-17). A partition that starts EMPTY (its checkpoint missing, or a
  # basis change) is seeded from the latest alarm states, which hold only NON-normal states and
  # can be later than the frame the journal replays. F1 raises mode and aux; F2 clears aux. After
  # an empty start the seed has mode critical and aux normal (the default), so replaying F1
  # re-derives only aux's raise. Numbered by transition, aux would take mode's index 0 and trip
  # MM_REPLAY_ID_CONFLICT on every retry (a wedged partition); numbered by evaluation, aux keeps
  # its own index and finds its stored episode.
  test "a replay that re-derives only some of a frame's transitions keeps each effect's id", c do
    f1 = frames(mode: 50, aux: 50, sequence: 1)
    f2 = frames(mode: 50, aux: 0, sequence: 2)

    log =
      capture_log(fn ->
        assert transition?(ingest!(evidence(c, f1, 0)), :critical)
        assert transition?(ingest!(evidence(c, f2, byte_size(f1))), :normal)
        first = effect_ids(c)
        assert length(first.episodes) == 2 and length(first.events) == 3

        # Empty start: the semantic runtime rows gone, the latest alarm states (the seed) kept.
        drop_semantic_rows!(c)
        kill_partition!(c)

        replay = ingest!(evidence(c, f1, 0))
        assert [%{update_id: aux_update}] = transitions(replay)
        assert point(replay, aux_update) == "HEALTH.aux"
        assert effect_ids(c) == first
      end)

    refute log =~ "MM_REPLAY_ID_CONFLICT"
  end

  @semantic_tables ["semantic_runtime_heads", "semantic_runtime_snapshots"]

  defp drop_semantic_rows!(c) do
    for table <- Enum.reverse(@semantic_tables) do
      Repo.query!("DELETE FROM #{table} WHERE mission_id = $1", [c.mission.mission_id])
    end
  end

  defp transitions(%{semantic_result: %{monitoring_results: results}}),
    do: Enum.filter(results, & &1.transition)

  defp update_ids(%{semantic_result: %{parameter_updates: updates}}),
    do: updates |> Enum.map(& &1.update_id) |> Enum.sort()

  defp monitoring_rows(c) do
    mission = c.mission.mission_id

    ids = fn table, column ->
      Repo.all(from(row in table, where: row.mission_id == ^mission, select: field(row, ^column)))
      |> Enum.sort()
    end

    %{
      evaluations: ids.("semantic_monitoring_evaluations", :evaluation_id),
      transitions: ids.("semantic_alarm_transitions", :transition_id)
    }
  end

  defp point(result, update_id) do
    Enum.find_value(result.semantic_result.parameter_updates, fn update ->
      update.update_id == update_id && update.qualified_name |> String.split("/") |> List.last()
    end)
    |> then(&("HEALTH." <> &1))
  end

  # The window #99 covers: the alarm effects were written, the partition's monitoring state wasn't
  # kept. Drop the partition's semantic runtime rows and the latest alarm state (MonitoringSeed
  # restores monitoring from it at recovery), then kill the owner: it recovers from before the
  # input, so the replay re-derives the same transition and the writer meets the stored ids.
  defp crash_window!(c) do
    drop_semantic_rows!(c)

    Repo.delete_all(
      from(row in "semantic_latest_alarm_states", where: row.mission_id == ^c.mission.mission_id)
    )

    kill_partition!(c)
  end

  defp kill_partition!(c) do
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}
    {:ok, owner} = PartitionOwner.lookup(c.mission.mission_id, key)
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

  defp frames(mode: mode, aux: aux, sequence: sequence) do
    packet = <<0::3, 0::1, 0::1, 42::11, 3::2, sequence::14, 1::16, mode::8, aux::8>>

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
    # DECISIONS #109: the switches live on the spacecraft row, written as a change set would; a
    # saved configuration takes them from there. Left off, the generation binds no packet.
    :ok =
      Fixtures.change_set_switches!(c.org, c.mission.mission_id, c.craft.spacecraft_id, %{
        "telemetry_enabled" => true,
        "commanding_enabled" => true
      })

    current = Drafts.snapshot(c.mission, c.craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
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
