defmodule Cadence.Telemetry.Storage.IdentityStateRetentionTest do
  @moduledoc """
  #359 (a): trivial observation identity states are deleted once both the observation store's
  retention and the re-delivery window have passed; everything else is kept.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Control.IdentityStateRetention
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow
  alias Cadence.TestSupport.ObservationIdentityFixtures
  alias Ecto.Adapters.SQL.Sandbox

  @now ~U[2026-11-19 12:00:00Z]
  @hour 3_600
  # The production shape: QuestDB keeps 48 h, the journal 72 h + 24 h settlement: cutoff 96 h.
  @settings [
    now: @now,
    observation_retention_hours: 48,
    journal_retention_ms: 72 * @hour * 1_000,
    settlement_allowance_hours: 24,
    pause_ms: 0
  ]

  describe "the cutoff" do
    test "is the later of the observation retention and the re-delivery window" do
      assert IdentityStateRetention.cutoff(@now, @settings) == ago(96)

      # A store that keeps observations longer than the re-delivery window wins.
      assert IdentityStateRetention.cutoff(
               @now,
               Keyword.put(@settings, :observation_retention_hours, 240)
             ) ==
               ago(240)
    end

    test "is unset outside dev, so a deployment deletes nothing until it names its retention" do
      # config.exs sets nothing; only dev.exs names the dev stack's 48 h (lead's review).
      assert Application.get_env(:cadence, IdentityStateRetention, [])[
               :observation_retention_hours
             ] == nil

      assert IdentityStateRetention.cutoff(@now) == nil
    end

    test "is unknown without an observation retention, and then nothing is deleted" do
      settings = Keyword.put(@settings, :observation_retention_hours, nil)
      assert IdentityStateRetention.cutoff(@now, settings) == nil

      trivial = state!("unset", last_seen_hours_ago: 500)

      assert %{stopped: :no_observation_retention, matched: 0} =
               IdentityStateRetention.run([mode: :live] ++ settings)

      assert present?(trivial)
    end
  end

  describe "a live run" do
    test "deletes only a trivial state past the cutoff and keeps every other case" do
      gone = state!("trivial-old", last_seen_hours_ago: 97)
      within = state!("trivial-recent", last_seen_hours_ago: 95)

      decided = state!("decided", last_seen_hours_ago: 200)

      {:ok, _} =
        ObservationIdentityStates.apply_decision(decided, :mark_advisory,
          organization_id: "org-retention",
          mission_id: "mission-retention",
          decision_reason: "operator_review",
          refresh_latest_value?: false,
          publish_facts?: false
        )

      counted_twice = state!("canonical-twice", last_seen_hours_ago: 200, canonical_count: 2)
      conflict = state!("conflict", last_seen_hours_ago: 200, conflict_count: 1)
      duplicate = state!("duplicate", last_seen_hours_ago: 200, duplicate_count: 1)
      superseded = state!("superseded", last_seen_hours_ago: 200, superseded_count: 1)
      advisory = state!("advisory", last_seen_hours_ago: 200, advisory_count: 1)
      revised = state!("revised", last_seen_hours_ago: 200, decision_reason: "canonical_revision")
      replay = state!("replay", last_seen_hours_ago: 200, replay_run_id: "replay-run-1")

      events_before = Repo.aggregate(DecisionEventRow, :count)

      assert %{mode: :live, matched: 1, stopped: :end} =
               IdentityStateRetention.run([mode: :live] ++ @settings)

      refute present?(gone)

      for kept <- [
            within,
            decided,
            counted_twice,
            conflict,
            duplicate,
            superseded,
            advisory,
            revised,
            replay
          ] do
        assert present?(kept), "#{kept} was deleted"
      end

      assert Repo.aggregate(DecisionEventRow, :count) == events_before
    end

    test "keeps a state whose observation is still in the observation store" do
      # The store keeps 240 h here: a state last seen 200 h ago still describes a stored row.
      in_store = state!("in-store", last_seen_hours_ago: 200)
      settings = Keyword.put(@settings, :observation_retention_hours, 240)

      assert %{matched: 0} = IdentityStateRetention.run([mode: :live] ++ settings)
      assert present?(in_store)
    end

    test "walks the table in batches and resumes from its cursor" do
      ids = for n <- 1..7, do: state!("batch-#{n}", last_seen_hours_ago: 100)

      first =
        IdentityStateRetention.run([mode: :live, scan_size: 2, max_batches: 2] ++ @settings)

      assert %{scanned: 4, matched: 4, batches: 2, stopped: :batch_limit} = first

      rest =
        IdentityStateRetention.run(
          [mode: :live, scan_size: 2, max_batches: 10, cursor: first.cursor] ++ @settings
        )

      assert %{matched: 3, stopped: :end} = rest
      refute Enum.any?(ids, &present?/1)
    end
  end

  describe "a dry run" do
    test "counts what a live run would delete and deletes nothing" do
      old = state!("dry-old", last_seen_hours_ago: 120)
      _recent = state!("dry-recent", last_seen_hours_ago: 1)

      assert %{mode: :dry, matched: 1, stopped: :end} =
               IdentityStateRetention.run([mode: :dry] ++ @settings)

      assert present?(old)
    end

    test "is the default mode, and the environment switches it" do
      assert IdentityStateRetention.mode([]) == :dry

      for {value, mode} <- [{"live", :live}, {"off", :off}, {"anything", :dry}] do
        System.put_env("CADENCE_IDENTITY_STATE_RETENTION", value)
        assert IdentityStateRetention.mode([]) == mode
      end
    after
      System.delete_env("CADENCE_IDENTITY_STATE_RETENTION")
    end

    test "an off run touches nothing" do
      old = state!("off-old", last_seen_hours_ago: 120)
      assert %{stopped: :off, matched: 0} = IdentityStateRetention.run([mode: :off] ++ @settings)
      assert present?(old)
    end
  end

  describe "ticks run at a fixed rate (qa 11-20: the hour slipped by each walk's own time)" do
    @hour_ms 3_600_000

    test "the first tick is one period from start" do
      assert IdentityStateRetention.next_due(nil, 1_000, @hour_ms) == 1_000 + @hour_ms
    end

    test "the next tick is one period after the previous one was DUE, not after the walk ended" do
      due = 10 * @hour_ms
      walk_ended = due + 90_000

      assert IdentityStateRetention.next_due(due, walk_ended, @hour_ms) == due + @hour_ms
    end

    test "a walk that ran past due times skips to the first one still ahead, never bunching ticks" do
      due = 10 * @hour_ms

      assert IdentityStateRetention.next_due(due, due + @hour_ms, @hour_ms) == due + 2 * @hour_ms

      assert IdentityStateRetention.next_due(due, due + 2 * @hour_ms + 5, @hour_ms) ==
               due + 3 * @hour_ms
    end

    test "after 24 ticks of 90 s walks, the schedule hasn't moved" do
      start = 0

      due =
        Enum.reduce(1..24, IdentityStateRetention.next_due(nil, start, @hour_ms), fn _tick, due ->
          IdentityStateRetention.next_due(due, due + 90_000, @hour_ms)
        end)

      assert due == start + 25 * @hour_ms
    end
  end

  describe "every tick is logged (qa 11-20: a silent tick looked like a stopped walk)" do
    test "a tick that matched nothing still logs its summary, matched=0" do
      _recent = state!("log-recent", last_seen_hours_ago: 1)

      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :info], fn ->
          assert %{matched: 0} = [mode: :dry] |> Kernel.++(@settings) |> then(&start_and_tick/1)
        end)

      assert log =~ "identity state retention dry"
      assert log =~ "matched=0"
    end
  end

  describe "near a pass (lead, #368 review)" do
    test "a tick does nothing while a pass is near, and is logged as skipped" do
      old = state!("pass-old", last_seen_hours_ago: 120)

      # The test config logs at :warning; let the info line through for this test (async: false).
      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :info], fn ->
          assert %{stopped: :pass_cluster, matched: 0, batches: 0} =
                   [mode: :live, pass_near?: fn -> true end]
                   |> Kernel.++(@settings)
                   |> then(&start_and_tick/1)
        end)

      assert log =~ "skipped: a pass is near"
      assert present?(old)
    end

    test "a pass that comes near mid-walk stops it before the next batch; the next tick resumes" do
      ids = for n <- 1..4, do: state!("mid-#{n}", last_seen_hours_ago: 100)
      {:ok, calls} = Agent.start_link(fn -> 0 end)
      near_after_first = fn -> Agent.get_and_update(calls, &{&1 >= 1, &1 + 1}) end

      first =
        IdentityStateRetention.run(
          [mode: :live, scan_size: 2, max_batches: 10, pass_near?: near_after_first] ++ @settings
        )

      assert %{stopped: :pass_cluster, matched: 2, batches: 1} = first

      rest =
        IdentityStateRetention.run(
          [mode: :live, scan_size: 2, cursor: first.cursor, pass_near?: fn -> false end] ++
            @settings
        )

      assert %{matched: 2, stopped: :end} = rest
      refute Enum.any?(ids, &present?/1)
    end

    test "a dry tick skips too" do
      _old = state!("pass-dry", last_seen_hours_ago: 120)

      assert %{stopped: :pass_cluster, matched: 0} =
               IdentityStateRetention.run([mode: :dry, pass_near?: fn -> true end] ++ @settings)
    end
  end

  test "the supervised process runs a tick on request" do
    old = state!("process-old", last_seen_hours_ago: 120)

    pid =
      start_supervised!(
        {IdentityStateRetention,
         [name: :identity_state_retention_under_test, tick_ms: 0, mode: :live] ++ @settings}
      )

    Sandbox.allow(Repo, self(), pid)

    assert %{matched: 1} = IdentityStateRetention.run_now(:identity_state_retention_under_test)
    refute present?(old)
  end

  defp start_and_tick(opts) do
    pid =
      start_supervised!(
        {IdentityStateRetention, [name: :retention_pass_test, tick_ms: 0] ++ opts}
      )

    Sandbox.allow(Repo, self(), pid)
    IdentityStateRetention.run_now(:retention_pass_test)
  end

  # A state as the write path stored it before the first-seen rule (#157; since then a canonical
  # first sighting writes no row): the rows retention exists to delete. Aged and shaped by
  # overrides.
  defp state!(name, overrides) do
    envelope = envelope("sample-#{name}", Keyword.get(overrides, :replay_run_id))
    last_seen = ago(Keyword.fetch!(overrides, :last_seen_hours_ago))

    changes =
      overrides
      |> Keyword.take([
        :canonical_count,
        :duplicate_count,
        :conflict_count,
        :superseded_count,
        :advisory_count,
        :decision_reason
      ])
      |> Keyword.merge(first_seen_at: last_seen, last_seen_at: last_seen)

    ObservationIdentityFixtures.pre_first_seen_state!(envelope, changes)
    envelope.observation_identity_id
  end

  defp present?(id), do: Repo.get(TelemetryObservationIdentityStateRow, id) != nil

  defp ago(hours), do: DateTime.add(@now, -hours * @hour, :second)

  defp envelope(sample_id, replay_run_id) do
    realm = if replay_run_id, do: :replay, else: :flight

    {:ok, context} =
      WriteContext.new(
        organization_id: "org-retention",
        mission_id: "mission-retention",
        realm: realm,
        replay_run_id: replay_run_id,
        data_source_id: "ds-primary",
        binding_id: "binding-v1",
        source_endpoint_id: "station-a",
        recorded_at: ~U[2026-11-10 12:00:00Z],
        metadata: %{}
      )

    sample = %Sample{
      sample_id: sample_id,
      mission_id: "mission-retention",
      spacecraft_id: "sc-1",
      point_id: "HK.#{sample_id}",
      point_name: "HK.#{sample_id}",
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: 42,
      engineering_value: 42,
      quality_state: :good,
      generation_time: ~U[2026-11-10 11:59:59Z],
      receipt_time: ~U[2026-11-10 12:00:00Z],
      provenance: %{}
    }

    {:ok, envelope} = ObservationEnvelope.from_sample(context, sample, validity_state: :canonical)
    envelope
  end
end
