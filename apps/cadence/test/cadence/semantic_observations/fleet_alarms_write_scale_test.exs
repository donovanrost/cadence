defmodule Cadence.SemanticObservations.FleetAlarmsWriteScaleTest do
  @moduledoc """
  What keeping the live fleet summary costs the transition transaction (#871), at 1,000 spacecraft x
  200 parameters (200,000 latest alarm rows, 3% active). Excluded by default (`--include scale`); it
  prints the cost of `SemanticObservations.persist_many/1` for a normal batch (3 transitions of one
  spacecraft) and for a mass event (EVERY parameter of one spacecraft transitions in one batch).
  Run it with and without the `Multi.run(:fleet_alarm_summaries, ...)` step to get the difference.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.{FleetAlarms, LatestAlarmStateRow}

  @moduletag timeout: 900_000

  @org "org-fleet-alarm-write"
  @mission "mission-fleet-alarm-write"
  @crafts 1_000
  @points 200

  test "the transition transaction, with the summary refresh" do
    persist_mission_scope(@org, @mission)
    now = DateTime.utc_now()
    Repo.query!("SET LOCAL session_replication_role = replica")

    rows =
      for c <- 1..@crafts, p <- 1..@points do
        active? = rem(c * 31 + p * 17, 1_000) < 30

        %{
          organization_id: @org,
          mission_id: @mission,
          spacecraft_scope_id: "sc-#{c}",
          spacecraft_id: "sc-#{c}",
          parameter_id: "P#{p}",
          policy_id: "policy-P#{p}",
          evaluation_id: "e-#{c}-#{p}",
          transition_id: "t-#{c}-#{p}",
          effective_state: if(active?, do: "critical", else: "normal"),
          generation_time: DateTime.add(now, -3_600, :second),
          receipt_time: DateTime.add(now, -3_600, :second),
          state_document: %{"value" => %{}},
          inserted_at: now,
          updated_at: now
        }
      end

    for chunk <- Enum.chunk_every(rows, 2_000), do: Repo.insert_all(LatestAlarmStateRow, chunk)
    Repo.query!("SET LOCAL session_replication_role = origin")
    FleetAlarms.refresh(Repo, @org, @mission, for(c <- 1..@crafts, do: "sc-#{c}"))
    Repo.query!("ANALYZE semantic_latest_alarm_states")
    Repo.query!("ANALYZE semantic_fleet_alarm_summaries")

    counter = :counters.new(1, [])

    batch = fn craft, parameters, state, tick ->
      for p <- parameters do
        :counters.add(counter, 1, 1)
        id = "w-#{:counters.get(counter, 1)}"
        at = DateTime.add(now, tick, :second)
        transition(@org, @mission, "sc-#{craft}", "P#{p}", {:normal, state}, at, id)
      end
    end

    run = fn label, parameters, iterations ->
      ms =
        for t <- 1..iterations do
          craft = rem(t * 37, @crafts) + 1
          state = Enum.at([:critical, :warning, :normal], rem(t, 3))
          prepared = batch.(craft, parameters, state, t)
          {us, :ok} = :timer.tc(fn -> SemanticObservations.persist_many(prepared) end)
          us / 1_000
        end

      s = Enum.sort(ms)

      IO.puts(
        "ALARM WRITE COST #{label}: p50 #{Float.round(Enum.at(s, div(length(s), 2)), 1)} ms, " <>
          "p99 #{Float.round(Enum.at(s, min(length(s) - 1, trunc(length(s) * 0.99))), 1)} ms"
      )
    end

    run.("normal batch (3 transitions of one spacecraft)", 1..3, 60)
    run.("mass event (all 200 parameters of one spacecraft)", 1..@points, 20)
  end
end
