defmodule Cadence.Limits.FleetSummaryPropertyTest do
  @moduledoc """
  The fleet summary equals the aggregate of the per-point latest states (#849): after ANY sequence
  of the writers' operations (upserts of newer and older states, flips between conditions, events
  without a spacecraft, whole-mission and one-spacecraft rebuilds), `FleetSummary.load/2` is exactly
  what grouping the rows themselves gives: worst condition, violating count, newest receipt, worst
  violating point, and no row for a spacecraft without states. Random sequences from a printed
  seed; a failure names it.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Limits.{Event, Store}
  alias Cadence.Limits.Store.{FleetSummary, LatestStateRow}
  alias Cadence.SemanticRuntime.ThresholdLimits

  @org "org-summary-prop"
  @mission "mission-summary-prop"
  @other_mission "mission-summary-prop-other"
  @crafts ["sc-1", "sc-2", "sc-3", "sc-4", nil]
  @points for n <- 1..6, do: "HK.p#{n}"
  @states [:green, :blue, :yellow_high, :yellow_low, :red_high, :red_low]
  @steps 60
  @sequences 12

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, @other_mission)
    :ok
  end

  test "any sequence of writes gives the summary the aggregate gives" do
    for n <- 1..@sequences do
      seed = :erlang.unique_integer([:positive])
      :rand.seed(:exsss, {seed, n, 7})
      Repo.delete_all(LatestStateRow)
      Repo.delete_all(Cadence.Limits.Store.FleetSummaryRow)
      counter = :counters.new(1, [])

      for step <- 1..@steps do
        operation = apply_random_operation(counter)
        assert_equals_aggregate("seed #{seed}, sequence #{n}, step #{step}, #{operation}")
      end
    end
  end

  test "a writer holds one advisory lock per touched spacecraft, in the ground-limit namespace" do
    counter = :counters.new(1, [])

    events =
      for craft <- ["sc-1", "sc-1", "sc-2"] do
        %{event(counter, @mission) | spacecraft_id: craft}
      end

    # The test's sandbox transaction outlives the writer's own, so its locks are still visible.
    assert {:ok, _rows} = Store.persist_latest_states(Repo, events)
    assert advisory_locks() == 2

    for craft <- ["sc-1", "sc-2"] do
      assert advisory_locks("telemetry_fleet_limit/" <> @mission <> "/" <> craft) == 1
    end

    # A one-spacecraft rebuild locks that spacecraft (already held here), a mission rebuild the
    # summarized ones and its new events' spacecraft.
    sc3 = [%{event(counter, @mission) | spacecraft_id: "sc-3"}]
    assert :ok = Store.replace_latest_states(@mission, sc3)
    assert advisory_locks("telemetry_fleet_limit/" <> @mission <> "/sc-3") == 1
    assert advisory_locks() == 3
  end

  defp advisory_locks do
    %{rows: [[n]]} =
      Repo.query!(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
      )

    n
  end

  defp advisory_locks(key) do
    %{rows: [[n]]} =
      Repo.query!(
        """
        SELECT count(*) FROM pg_locks
        WHERE locktype = 'advisory' AND pid = pg_backend_pid()
          AND ((classid::bigint << 32) | objid::bigint) = hashtextextended($1, 0)
        """,
        [key]
      )

    n
  end

  defp apply_random_operation(counter) do
    case :rand.uniform(10) do
      n when n <= 7 ->
        events = for _ <- 1..:rand.uniform(6), do: event(counter, @mission)
        {:ok, _rows} = Store.persist_latest_states(Repo, events)
        "persist #{length(events)}"

      8 ->
        # Another mission's rows must never reach this mission's summaries.
        {:ok, _rows} = Store.persist_latest_states(Repo, [event(counter, @other_mission)])
        "persist other mission"

      9 ->
        events = unique(for _ <- 1..:rand.uniform(8), do: event(counter, @mission))
        :ok = Store.replace_latest_states(@mission, events)
        "replace mission with #{length(events)}"

      10 ->
        craft = Enum.random(Enum.reject(@crafts, &is_nil/1))

        events =
          unique(
            for _ <- 1..:rand.uniform(4), do: %{event(counter, @mission) | spacecraft_id: craft}
          )

        :ok = Store.replace_latest_states(@mission, events, spacecraft_id: craft)
        "replace #{craft} with #{length(events)}"
    end
  end

  # A rebuild writes one state per (spacecraft, point), as the projection does.
  defp unique(events), do: Enum.uniq_by(events, &{&1.spacecraft_id, &1.point_id})

  defp event(counter, mission) do
    :counters.add(counter, 1, 1)
    id = :counters.get(counter, 1)
    state = Enum.random(@states)

    %Event{
      limit_event_id: "ev-#{System.unique_integer([:positive])}-#{id}",
      mission_id: mission,
      spacecraft_id: Enum.random(@crafts),
      point_id: Enum.random(@points),
      point_name: "name",
      source_sample_type: :telemetry_sample,
      sample_id: "s-#{id}",
      limit_definition_id: "d",
      limit_definition_version: 1,
      limit_set_name: "d",
      evaluated_value: id,
      limit_state: state,
      normalized_state: ThresholdLimits.normalize_state(state),
      violation: ThresholdLimits.violation?(state),
      generation_time: nil,
      # Some older than what is stored (an upsert ignores those), some equal, some newer.
      receipt_time: DateTime.add(~U[2026-11-26 12:00:00.000000Z], :rand.uniform(50), :second),
      provenance: %{}
    }
  end

  defp assert_equals_aggregate(context) do
    expected = aggregate()
    actual = FleetSummary.load(@org, @mission)

    assert Map.keys(actual) |> Enum.sort() == Map.keys(expected) |> Enum.sort(), context

    for {craft, want} <- expected do
      got = actual[craft]
      assert got.limit_state == want.limit_state, "#{context}: #{craft} condition"
      assert got.violating == want.violating, "#{context}: #{craft} violating"
      assert got.last_received_at == want.last_received_at, "#{context}: #{craft} last received"

      assert worst_id(got.worst) == want.worst_event_id, "#{context}: #{craft} worst"
    end

    # Nothing of the other mission leaked in.
    assert FleetSummary.load(@org, @other_mission) |> Map.keys() |> Enum.sort() ==
             other_mission_crafts(),
           context
  end

  defp worst_id(nil), do: nil
  defp worst_id(event), do: event.limit_event_id

  # The oracle: group the rows themselves.
  defp aggregate do
    Repo.all(LatestStateRow)
    |> Enum.filter(&(&1.mission_id == @mission and not is_nil(&1.spacecraft_id)))
    |> Enum.group_by(& &1.spacecraft_id)
    |> Map.new(fn {craft, rows} ->
      violators = Enum.filter(rows, & &1.violation)

      worst =
        violators |> Enum.sort_by(&{-rank(&1), neg(&1.receipt_time), -&1.id}) |> List.first()

      {craft,
       %{
         limit_state: condition(rows |> Enum.map(&rank/1) |> Enum.max()),
         violating: length(violators),
         last_received_at: rows |> Enum.map(& &1.receipt_time) |> Enum.max(DateTime),
         worst_event_id: worst && worst.limit_event_id
       }}
    end)
  end

  defp other_mission_crafts do
    Repo.all(LatestStateRow)
    |> Enum.filter(&(&1.mission_id == @other_mission and not is_nil(&1.spacecraft_id)))
    |> Enum.map(& &1.spacecraft_id)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp rank(%{normalized_state: "red"}), do: 2
  defp rank(%{normalized_state: "yellow"}), do: 1
  defp rank(_row), do: 0

  defp neg(time), do: -DateTime.to_unix(time, :microsecond)

  defp condition(2), do: :critical
  defp condition(1), do: :caution
  defp condition(0), do: :nominal
end
