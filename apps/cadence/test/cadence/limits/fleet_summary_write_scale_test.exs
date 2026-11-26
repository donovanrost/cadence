defmodule Cadence.Limits.FleetSummaryWriteScaleTest do
  @moduledoc """
  What keeping the fleet summary costs the latest-limit-state writer (#849), at 1,000 spacecraft x
  200 points (200,000 states). Excluded by default (`--include scale`); it prints the figures the PR
  states and asserts only that a refresh stays far under a millisecond-scale budget per spacecraft.
  """
  use Cadence.DataCase, async: false

  @moduletag :scale
  @moduletag timeout: 900_000

  alias Cadence.Limits.{Event, Store}
  alias Cadence.Limits.Store.{FleetSummary, LatestStateRow}
  alias Cadence.Persistence.JsonDocument

  @org "org-summary-write"
  @mission "mission-summary-write"
  @crafts 1_000
  @points 200

  test "a refresh is cheap per spacecraft, and the writer's batch pays it once" do
    persist_mission_scope(@org, @mission)
    now = DateTime.utc_now()
    Repo.query!("SET LOCAL session_replication_role = replica")

    rows =
      for c <- 1..@crafts, p <- 1..@points do
        violating? = rem(c + p, 97) == 0 or rem(c + p, 41) == 0

        %{
          limit_event_id: "ev-#{c}-#{p}",
          mission_id: @mission,
          organization_id: @org,
          spacecraft_scope_id: "sc-#{c}",
          spacecraft_id: "sc-#{c}",
          point_id: "HK.p#{p}",
          point_name: "HK.p#{p}",
          source_sample_type: "telemetry_sample",
          sample_id: "s",
          limit_definition_id: "d",
          limit_definition_version: 1,
          limit_set_name: "d",
          evaluated_value: JsonDocument.wrap_value(c),
          limit_state: if(violating?, do: "red_high", else: "green"),
          normalized_state: if(violating?, do: "red", else: "green"),
          violation: violating?,
          generation_time: now,
          receipt_time: DateTime.add(now, -rem(c * 7 + p, 600), :second),
          provenance: %{},
          inserted_at: now,
          updated_at: now
        }
      end

    for chunk <- Enum.chunk_every(rows, 2_000), do: Repo.insert_all(LatestStateRow, chunk)
    Repo.query!("SET LOCAL session_replication_role = origin")
    {full_ms, :ok} = timed(fn -> FleetSummary.refresh(Repo, @mission, :all) end)
    IO.puts("WRITE COST full rebuild of 1,000 summaries from 200,000 states: #{full_ms} ms")
    Repo.query!("ANALYZE telemetry_latest_limit_states")
    Repo.query!("ANALYZE telemetry_fleet_limit_summaries")

    one =
      for t <- 1..200,
          do:
            elem(
              timed(fn ->
                FleetSummary.refresh(Repo, @mission, ["sc-#{rem(t * 37, @crafts) + 1}"])
              end),
              0
            )

    report("refresh of one spacecraft (200 states)", one)

    batch = fn c, t, n ->
      for p <- 1..n do
        flip? = rem(p + t, 23) == 0
        state = if flip?, do: :red_high, else: :green

        %Event{
          limit_event_id: "ev2-#{c}-#{p}-#{t}",
          mission_id: @mission,
          spacecraft_id: "sc-#{c}",
          point_id: "HK.p#{p}",
          point_name: "HK.p#{p}",
          source_sample_type: :telemetry_sample,
          sample_id: "s2",
          limit_definition_id: "d",
          limit_definition_version: 1,
          limit_set_name: "d",
          evaluated_value: t,
          limit_state: state,
          normalized_state: if(flip?, do: :red, else: :green),
          violation: flip?,
          generation_time: DateTime.add(now, t, :second),
          receipt_time: DateTime.add(now, t, :second),
          provenance: %{}
        }
      end
    end

    full =
      for t <- 1..40,
          do:
            elem(
              timed(fn ->
                {:ok, _} =
                  Store.persist_latest_states(Repo, batch.(rem(t * 37, @crafts) + 1, t, @points))
              end),
              0
            )

    report("persist_latest_states, 200 events of one spacecraft, summary included", full)

    single =
      for t <- 41..440,
          do:
            elem(
              timed(fn ->
                {:ok, _} =
                  Store.persist_latest_states(Repo, batch.(rem(t * 37, @crafts) + 1, t, 1))
              end),
              0
            )

    report("persist_latest_states, ONE event, summary included", single)

    assert Enum.max(one) < 20
  end

  defp timed(fun) do
    {us, result} = :timer.tc(fun)
    {Float.round(us / 1_000, 2), result}
  end

  defp report(label, ms) do
    s = Enum.sort(ms)
    p50 = Enum.at(s, div(length(s), 2))
    p99 = Enum.at(s, min(length(s) - 1, trunc(length(s) * 0.99)))
    IO.puts("WRITE COST #{label}: p50 #{p50} ms, p99 #{p99} ms")
  end
end
