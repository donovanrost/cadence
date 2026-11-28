defmodule Cadence.Reads.FleetStatusLiveAlarmsTest do
  @moduledoc """
  The fleet's condition combines the LIVE catalog monitoring alarms with the ground limits, and the
  worst wins (#871, DECISIONS #17). A live critical alarm shows on Fleet with no ground-limit job
  ever having run, a ground limit is labelled with when it was evaluated, and the read stays a
  fixed number of statements.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Limits.{Event, Store}
  alias Cadence.Reads.FleetStatus
  alias Cadence.SemanticObservations.{FleetAlarms, LatestAlarmStateRow}
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @org "org-fleet-live"
  @mission "mission-fleet-live"
  @now ~U[2026-11-26 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, "mission-fleet-live-other")

    for n <- 1..4 do
      {:ok, _} =
        SpacecraftStore.persist_spacecraft(
          @org,
          Spacecraft.new(%{
            spacecraft_id: "sc-#{n}",
            organization_id: @org,
            mission_id: @mission,
            display_name: "SC-#{n}",
            scid: n
          })
        )
    end

    :ok
  end

  defp alarm(craft, parameter, state, minute, mission \\ @mission) do
    at = DateTime.add(@now, -minute * 60, :second)

    LatestAlarmStateRow.changeset(%{
      organization_id: @org,
      mission_id: mission,
      spacecraft_id: craft,
      parameter_id: parameter,
      policy_id: "policy-#{parameter}",
      evaluation_id: "eval-#{craft}-#{parameter}-#{System.unique_integer([:positive])}",
      transition_id: "tr-#{System.unique_integer([:positive])}",
      effective_state: state,
      generation_time: at,
      receipt_time: at
    })
    |> Repo.insert!()

    # A fixture is a writer: it keeps the summary as `SemanticObservations.persist_many/1` does.
    FleetAlarms.refresh(Repo, @org, mission, [craft])
  end

  defp ground(craft, point, state, minute) do
    at = DateTime.add(@now, -minute * 60, :second)

    event = %Event{
      limit_event_id: "ev-#{craft}-#{point}",
      mission_id: @mission,
      spacecraft_id: craft,
      point_id: point,
      point_name: point,
      source_sample_type: :telemetry_sample,
      sample_id: "s",
      limit_definition_id: "d",
      limit_definition_version: 1,
      limit_set_name: "d",
      evaluated_value: 3.5,
      limit_state: state,
      normalized_state: if(state in [:red_high, :red_low], do: :red, else: :yellow),
      violation: true,
      generation_time: at,
      receipt_time: at,
      provenance: %{}
    }

    {:ok, _} = Store.persist_latest_states(Repo, [event])
  end

  defp row(id), do: Enum.find(fleet().spacecraft, &(&1.id == id))
  defp fleet, do: FleetStatus.load(@org, @mission, now: @now)

  test "a live critical alarm shows on Fleet with no ground-limit job ever run" do
    alarm("sc-1", "HEALTH.mode", "critical", 2)

    assert %{state: :critical, limit_state: :critical, violating_points: 1} = row("sc-1")

    assert %{
             source: :catalog_monitoring,
             point_id: "HEALTH.mode",
             limit_state: :critical,
             value: nil,
             raw_limit_state: nil,
             evaluated_at: nil,
             received_at: received
           } = row("sc-1").worst_point

    assert received == DateTime.add(@now, -120, :second)
    # It is heard: the alarm's receipt is a receipt.
    assert row("sc-1").last_received_at == received
    assert fleet().counts.critical == 1
    assert %{state: :never_heard, limit_state: :no_data} = row("sc-2")
  end

  test "watch and warning are caution; distress and severe are critical; the rest change nothing" do
    alarm("sc-1", "A", "watch", 5)
    alarm("sc-2", "A", "warning", 5)
    alarm("sc-3", "A", "severe", 5)
    alarm("sc-4", "A", "normal", 5)
    alarm("sc-4", "B", "unknown", 5)
    alarm("sc-4", "C", "disabled", 5)

    assert %{limit_state: :caution} = row("sc-1")
    assert %{limit_state: :caution} = row("sc-2")
    assert %{limit_state: :critical} = row("sc-3")
    assert %{limit_state: :no_data, violating_points: 0, worst_point: nil} = row("sc-4")
  end

  test "the worst of the two sources wins, the live alarm on a tie, and violating counts both" do
    # Live critical over ground caution.
    alarm("sc-1", "L", "critical", 1)
    ground("sc-1", "G", :yellow_high, 10)
    # Ground critical over live caution.
    alarm("sc-2", "L", "warning", 1)
    ground("sc-2", "G", :red_high, 10)
    # A tie at critical.
    alarm("sc-3", "L", "severe", 1)
    ground("sc-3", "G", :red_low, 10)
    # Ground only.
    ground("sc-4", "G", :yellow_low, 10)

    assert %{
             limit_state: :critical,
             violating_points: 2,
             worst_point: %{source: :catalog_monitoring}
           } =
             row("sc-1")

    assert %{
             limit_state: :critical,
             violating_points: 2,
             worst_point: %{source: :ground_limit, point_id: "G", raw_limit_state: "red_high"}
           } = row("sc-2")

    assert %{limit_state: :critical, worst_point: %{source: :catalog_monitoring}} = row("sc-3")

    assert %{limit_state: :caution, violating_points: 1, worst_point: %{source: :ground_limit}} =
             row("sc-4")
  end

  test "a ground limit says when its evaluation ran, not when its sample arrived" do
    ground("sc-1", "G", :red_high, 600)

    assert %{source: :ground_limit, received_at: received, evaluated_at: evaluated} =
             row("sc-1").worst_point

    assert received == DateTime.add(@now, -600 * 60, :second)
    # Written just now by the evaluation, long after its sample.
    assert DateTime.diff(DateTime.utc_now(), evaluated) < 60
  end

  test "FleetAlarms: the worst active alarm, the count and the newest receipt per spacecraft" do
    alarm("sc-1", "A", "watch", 30)
    alarm("sc-1", "B", "critical", 20)
    alarm("sc-1", "C", "distress", 10)
    alarm("sc-1", "D", "normal", 1)
    alarm("sc-2", "A", "warning", 4)
    alarm("sc-9", "A", "critical", 1, "mission-fleet-live-other")

    alarms = FleetAlarms.load(@org, @mission)
    assert Map.keys(alarms) |> Enum.sort() == ["sc-1", "sc-2"]

    # Critical beats watch; of two criticals the newer (C, ten minutes ago).
    assert %{limit_state: :critical, active: 3, worst: %{parameter_id: "C"}} = alarms["sc-1"]
    assert alarms["sc-1"].last_received_at == DateTime.add(@now, -10 * 60, :second)
    assert %{limit_state: :caution, active: 1} = alarms["sc-2"]
    assert FleetAlarms.load("none", "none") == %{}
  end

  test "the read still costs a fixed number of statements, with live alarms" do
    me = self()

    :telemetry.attach(
      "fleet-live-queries",
      [:cadence, :repo, :query],
      fn _e, _m, meta, _ -> send(me, {:query, meta.source}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("fleet-live-queries") end)

    count = fn ->
      drain(0)
      fleet()
      drain(0)
    end

    alarm("sc-1", "A", "critical", 1)
    few = count.()
    for n <- 5..40, do: alarm("sc-#{n}", "A", "warning", n)
    many = count.()

    assert few == many
    assert many <= 9
  end

  defp drain(n) do
    receive do
      {:query, _source} -> drain(n + 1)
    after
      0 -> n
    end
  end
end
