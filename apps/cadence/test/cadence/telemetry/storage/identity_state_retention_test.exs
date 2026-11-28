defmodule Cadence.Telemetry.Storage.IdentityStateRetentionTest do
  @moduledoc """
  #359 (a), on the shared sweeper (#694): trivial observation identity states are deleted once both
  the observation store's retention and the re-delivery window have passed; everything else is
  kept. The walk is chunked and never waits for a quiet moment.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Persistence.Retention
  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.Retention, as: Rule
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow
  alias Cadence.TestSupport.ObservationIdentityFixtures
  alias Cadence.TestSupport.RetentionLock

  @now ~U[2026-11-19 12:00:00Z]
  @hour 3_600

  # The production shape of the two windows: the store keeps 48 h, the journal 72 h plus 24 h of
  # settlement, so the cutoff is 96 h.
  setup do
    saved =
      for key <- [:telemetry_observation_retention, :ingress_journal, :retention],
          do: {key, Application.get_env(:cadence, key)}

    Application.put_env(:cadence, :telemetry_observation_retention, retention_days: 2)

    Application.put_env(:cadence, :ingress_journal,
      completed_stream_retention_ms: 72 * @hour * 1_000
    )

    Application.put_env(:cadence, :retention, identity_state_settlement_allowance_hours: 24)

    on_exit(fn ->
      for {key, value} <- saved do
        if value == nil,
          do: Application.delete_env(:cadence, key),
          else: Application.put_env(:cadence, key, value)
      end
    end)

    :ok
  end

  defp sweep(opts \\ []),
    do:
      Sweeper.sweep(
        Rule,
        Rule.initial_cursor(),
        Keyword.merge(
          [now: @now, pause_ms: 0, lock_key: RetentionLock.key(Rule)],
          opts
        )
      )

  describe "the cutoff" do
    test "is the later of the observation retention and the re-delivery window" do
      assert Rule.cutoff(@now) == ago(96)

      # A store that keeps observations longer than the re-delivery window wins.
      Application.put_env(:cadence, :telemetry_observation_retention, retention_days: 10)
      assert Rule.cutoff(@now) == ago(240)
    end

    test "has a default everywhere: retention is on, so a deployment names no number to enable it" do
      Application.delete_env(:cadence, :telemetry_observation_retention)
      # The platform default observation retention (30 days) is longer than the journal window.
      assert Rule.cutoff(@now) == ago(30 * 24)
      assert Retention.settings()[:enabled?] in [true, false]
    end
  end

  describe "a sweep" do
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

      assert %{rows: 1, stopped: :done} = sweep()

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
      Application.put_env(:cadence, :telemetry_observation_retention, retention_days: 10)

      assert %{rows: 0} = sweep()
      assert present?(in_store)
    end

    test "walks the table in chunks and resumes from its cursor" do
      ids = for n <- 1..7, do: state!("batch-#{n}", last_seen_hours_ago: 100)

      first = sweep(chunk_rows: 2, budget_ms: 0)

      assert %{rows: 2, chunks: 1, stopped: :budget} = first

      rest =
        Sweeper.sweep(Rule, first.cursor,
          now: @now,
          pause_ms: 0,
          lock_key: RetentionLock.key(Rule),
          chunk_rows: 2
        )

      assert %{rows: 5, stopped: :done} = rest
      refute Enum.any?(ids, &present?/1)
    end

    test "does not wait for a pass: a sweep runs whatever the contacts are doing" do
      old = state!("during-a-pass", last_seen_hours_ago: 120)

      # No pass check exists to consult: the chunk is the protection.
      assert %{rows: 1, stopped: :done} = sweep()
      refute present?(old)
    end
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
