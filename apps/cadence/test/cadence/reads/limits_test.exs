defmodule Cadence.Reads.LimitsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Limits.{Definition, Event}
  alias Cadence.Limits.LimitDefinitionLifecycleEventRow

  alias Cadence.Persistence.Schemas.{
    TelemetryLatestLimitStateRow,
    TelemetryLimitEventRow
  }

  alias Cadence.Repo

  @organization_id "org-limit-reads"
  @mission_id "mission-limit-reads"

  test "reads effective limit definition intervals from lifecycle events" do
    persist_mission_scope(@organization_id, @mission_id)

    assert {:ok, _definition} =
             Cadence.persist_limit_definition(
               limit_definition(version: 1, yellow_high: 10, red_high: 20)
             )

    assert {:ok, _definition} =
             Cadence.persist_limit_definition(
               limit_definition(version: 2, yellow_high: 15, red_high: 25)
             )

    assert [first, second] =
             Cadence.telemetry_limit_definition_intervals(
               @organization_id,
               @mission_id,
               "HK.counter",
               realm: :flight,
               limit_set_name: "ops"
             )

    assert first.limit_definition_id == "counter-limits"
    assert first.limit_definition_version == 1
    assert first.active_to == second.active_from
    assert first.thresholds["yellow_high"] == 10
    assert first.thresholds["red_high"] == 20
    assert first.complete?

    assert second.limit_definition_version == 2
    assert second.active_to == nil
    assert second.thresholds["yellow_high"] == 15
    assert second.thresholds["red_high"] == 25
    assert second.previous_limit_definition_version == 1
    assert second.metadata["definition_activation_key"] == second.definition_activation_key
    assert second.complete?
  end

  test "filters definition intervals to the requested time range" do
    persist_mission_scope(@organization_id, @mission_id <> "-range")

    assert {:ok, _definition} =
             Cadence.persist_limit_definition(
               limit_definition(mission_id: @mission_id <> "-range", version: 1, yellow_high: 10)
             )

    assert [interval] =
             Cadence.telemetry_limit_definition_intervals(
               @organization_id,
               @mission_id <> "-range",
               "HK.counter",
               from_receipt_time: DateTime.add(DateTime.utc_now(), 1, :hour)
             )

    assert interval.limit_definition_version == 1
  end

  test "reads definition intervals from canonical operational events" do
    mission_id = @mission_id <> "-operational-events"

    persist_mission_scope(@organization_id, mission_id)

    assert {:ok, _definition} =
             Cadence.persist_limit_definition(
               limit_definition(
                 mission_id: mission_id,
                 version: 1,
                 yellow_high: 10,
                 red_high: 20
               )
             )

    assert {:ok, _definition} =
             Cadence.persist_limit_definition(
               limit_definition(
                 mission_id: mission_id,
                 version: 2,
                 yellow_high: 15,
                 red_high: 25
               )
             )

    assert [_, _] =
             Cadence.OperationalEvents.list_events(
               @organization_id,
               mission_id,
               category: :limits,
               source_record_kind: :limit_definition_lifecycle_event,
               order: :asc
             )

    Repo.delete_all(LimitDefinitionLifecycleEventRow)

    assert [first, second] =
             Cadence.telemetry_limit_definition_intervals(
               @organization_id,
               mission_id,
               "HK.counter",
               limit_set_name: "ops"
             )

    assert first.limit_definition_version == 1
    assert first.active_to == second.active_from
    assert second.limit_definition_version == 2
    assert second.previous_limit_definition_version == 1
    assert second.metadata["limit_definition_lifecycle_event_id"]
  end

  test "reads replay latest limit state from replay-scoped history instead of live projection" do
    mission_id = @mission_id <> "-replay-latest"
    persist_mission_scope(@organization_id, mission_id)

    live_latest =
      limit_event("limit-live-latest", mission_id, "sample-live", 20, ~U[2026-06-17 12:10:00Z],
        provenance: storage_provenance(:flight, nil)
      )

    replay_older =
      limit_event(
        "limit-replay-older",
        mission_id,
        "sample-replay-older",
        90,
        ~U[2026-06-17 12:01:00Z],
        provenance: storage_provenance(:replay, "replay-run-1")
      )

    replay_newer =
      limit_event(
        "limit-replay-newer",
        mission_id,
        "sample-replay-newer",
        99,
        ~U[2026-06-17 12:02:00Z],
        provenance: storage_provenance(:replay, "replay-run-1")
      )

    other_replay =
      limit_event(
        "limit-other-replay",
        mission_id,
        "sample-other-replay",
        77,
        ~U[2026-06-17 12:03:00Z],
        provenance: storage_provenance(:replay, "replay-run-2")
      )

    for event <- [live_latest, replay_older, replay_newer, other_replay] do
      assert {:ok, _row} = Repo.insert(TelemetryLimitEventRow.changeset(event))
    end

    assert {:ok, _row} =
             %TelemetryLatestLimitStateRow{}
             |> TelemetryLatestLimitStateRow.changeset(live_latest)
             |> Repo.insert()

    latest_live =
      Cadence.latest_telemetry_limit_state(@organization_id, mission_id, "HK.counter", [])

    assert latest_live.limit_event_id == "limit-live-latest"
    assert latest_live.evaluated_value == 20

    latest_replay =
      Cadence.latest_telemetry_limit_state(@organization_id, mission_id, "HK.counter",
        realm: :replay,
        replay_run_id: "replay-run-1"
      )

    assert latest_replay.limit_event_id == "limit-replay-newer"
    assert latest_replay.evaluated_value == 99
    assert latest_replay.provenance["storage"]["replay_run_id"] == "replay-run-1"

    replay_history =
      Cadence.telemetry_limit_event_history(@organization_id, mission_id, "HK.counter",
        realm: :replay,
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert Enum.map(replay_history, & &1.limit_event_id) == [
             "limit-replay-older",
             "limit-replay-newer"
           ]
  end

  defp limit_definition(opts) do
    mission_id = Keyword.get(opts, :mission_id, @mission_id)

    Definition.new(%{
      mission_id: mission_id,
      limit_definition_id: "counter-limits",
      point_id: "HK.counter",
      version: Keyword.fetch!(opts, :version),
      limit_set_name: "ops",
      thresholds: %{
        "yellow_high" => Keyword.fetch!(opts, :yellow_high),
        "red_high" => Keyword.get(opts, :red_high)
      }
    })
  end

  defp limit_event(limit_event_id, mission_id, sample_id, value, receipt_time, opts) do
    %Event{
      limit_event_id: limit_event_id,
      mission_id: mission_id,
      spacecraft_id: "sc-1",
      point_id: "HK.counter",
      point_name: "HK.counter",
      source_sample_type: :telemetry_sample,
      sample_id: sample_id,
      limit_definition_id: "counter-limits",
      limit_definition_version: 1,
      limit_set_name: "ops",
      evaluated_value: value,
      limit_state: if(value >= 90, do: :yellow_high, else: :green),
      normalized_state: if(value >= 90, do: :yellow, else: :green),
      violation: value >= 90,
      generation_time: receipt_time,
      receipt_time: receipt_time,
      provenance: Keyword.get(opts, :provenance, %{})
    }
  end

  defp storage_provenance(realm, replay_run_id) do
    storage =
      %{
        "realm" => Atom.to_string(realm),
        "data_source_id" => "managed_questdb_#{realm}",
        "binding_id" => "#{realm}_telemetry"
      }
      |> maybe_put_replay_run_id(replay_run_id)

    %{"storage" => storage}
  end

  defp maybe_put_replay_run_id(storage, nil), do: storage

  defp maybe_put_replay_run_id(storage, replay_run_id) do
    Map.put(storage, "replay_run_id", replay_run_id)
  end
end
