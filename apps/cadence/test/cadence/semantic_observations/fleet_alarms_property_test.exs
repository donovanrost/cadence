defmodule Cadence.SemanticObservations.FleetAlarmsPropertyTest do
  @moduledoc """
  The live fleet summary equals the aggregate of the latest alarm states (#871): after ANY sequence
  of transition batches through `SemanticObservations.persist_many/1` (raises, escalations, clears,
  states that change nothing (`unknown`, `disabled`), late arrivals the upsert ignores, one spacecraft
  or several per transaction), `FleetAlarms.load/2` is exactly what grouping the active rows gives:
  worst severity, how many are active, the newest receipt, the worst alarm, and no row for a
  spacecraft with none active. Random sequences from a printed seed; a failure names it.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.{FleetAlarms, FleetAlarmSummaryRow, LatestAlarmStateRow}

  @org "org-fleet-alarm-prop"
  @mission "mission-fleet-alarm-prop"
  @crafts ["sc-1", "sc-2", "sc-3", "sc-4"]
  @parameters ["P1", "P2", "P3", "P4", "P5"]
  @states [:normal, :watch, :warning, :distress, :critical, :severe, :unknown, :disabled]
  @active ~w(watch warning distress critical severe)
  @steps 40
  @sequences 8

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "any sequence of transition batches gives the summary the aggregate gives" do
    for n <- 1..@sequences do
      seed = :erlang.unique_integer([:positive])
      :rand.seed(:exsss, {seed, n, 11})
      Repo.delete_all(FleetAlarmSummaryRow)
      Repo.delete_all(LatestAlarmStateRow)
      counter = :counters.new(1, [])

      for step <- 1..@steps do
        batch = batch(counter)
        assert :ok = SemanticObservations.persist_many(batch)

        assert_equals_aggregate(
          "seed #{seed}, sequence #{n}, step #{step}, #{length(batch)} transitions"
        )
      end
    end
  end

  # One transaction: 1 to 4 transitions (a mass event of one spacecraft in the first case).
  defp batch(counter) do
    case :rand.uniform(4) do
      1 ->
        craft = Enum.random(@crafts)
        for p <- @parameters, do: one(counter, craft, p)

      _other ->
        for _ <- 1..:rand.uniform(4),
            do: one(counter, Enum.random(@crafts), Enum.random(@parameters))
    end
  end

  defp one(counter, craft, parameter) do
    :counters.add(counter, 1, 1)
    id = "prop-#{:counters.get(counter, 1)}-#{System.unique_integer([:positive])}"
    [from, to] = Enum.take_random(@states, 2)
    # Some older than what is stored (the upsert ignores those).
    at = DateTime.add(~U[2026-11-26 12:00:00.000000Z], :rand.uniform(60), :second)
    transition(@org, @mission, craft, parameter, {from, to}, at, id)
  end

  defp assert_equals_aggregate(context) do
    expected = aggregate()
    actual = FleetAlarms.load(@org, @mission)

    assert Map.keys(actual) |> Enum.sort() == Map.keys(expected) |> Enum.sort(), context

    for {craft, want} <- expected do
      got = actual[craft]
      assert got.limit_state == want.limit_state, "#{context}: #{craft} condition"
      assert got.active == want.active, "#{context}: #{craft} active"
      assert got.last_received_at == want.last_received_at, "#{context}: #{craft} last received"
      assert got.worst.parameter_id == want.parameter_id, "#{context}: #{craft} worst"
    end
  end

  # The oracle: group the rows themselves.
  defp aggregate do
    Repo.all(LatestAlarmStateRow)
    |> Enum.filter(&(&1.effective_state in @active and not is_nil(&1.spacecraft_id)))
    |> Enum.group_by(& &1.spacecraft_id)
    |> Map.new(fn {craft, rows} ->
      worst =
        Enum.min_by(rows, &{-rank(&1), -DateTime.to_unix(&1.receipt_time, :microsecond), -&1.id})

      {craft,
       %{
         limit_state: if(rank(worst) == 2, do: :critical, else: :caution),
         active: length(rows),
         last_received_at: rows |> Enum.map(& &1.receipt_time) |> Enum.max(DateTime),
         parameter_id: worst.parameter_id
       }}
    end)
  end

  defp rank(%{effective_state: state}) when state in ["distress", "critical", "severe"], do: 2
  defp rank(_row), do: 1

  test "the writer holds one advisory lock per transitioned spacecraft until its transaction ends" do
    batch = [
      transition(
        @org,
        @mission,
        "sc-1",
        "P1",
        {:normal, :critical},
        ~U[2026-11-26 12:00:01.000000Z],
        "lock-1"
      ),
      transition(
        @org,
        @mission,
        "sc-1",
        "P2",
        {:normal, :warning},
        ~U[2026-11-26 12:00:02.000000Z],
        "lock-2"
      ),
      transition(
        @org,
        @mission,
        "sc-2",
        "P1",
        {:normal, :watch},
        ~U[2026-11-26 12:00:03.000000Z],
        "lock-3"
      )
    ]

    # The test's sandbox transaction outlives persist_many's own, so the locks are still visible:
    # the two spacecraft, once each, however many of their parameters transitioned.
    assert :ok = SemanticObservations.persist_many(batch)

    assert %{rows: [[2]]} =
             Repo.query!(
               "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
             )

    # In the alarm namespace, so the ground-limit summary's locks do not serialize with these.
    for craft <- ["sc-1", "sc-2"] do
      assert %{rows: [[1]]} =
               Repo.query!(
                 """
                 SELECT count(*) FROM pg_locks
                 WHERE locktype = 'advisory' AND pid = pg_backend_pid()
                   AND ((classid::bigint << 32) | objid::bigint) = hashtextextended($1, 0)
                 """,
                 ["semantic_fleet_alarm/" <> @mission <> "/" <> craft]
               )
    end
  end
end
