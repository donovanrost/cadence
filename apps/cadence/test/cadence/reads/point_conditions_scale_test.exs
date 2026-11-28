defmodule Cadence.Reads.PointConditionsScaleTest do
  @moduledoc """
  A spacecraft's point conditions at 200 and 2,000 points per spacecraft, in a node whose
  current-value store also holds a 1,000-spacecraft fleet (200,000 values), as the fleet read is
  measured (#143). Excluded by default; `mix test --include scale`.
  """
  use Cadence.DataCase, async: false

  @moduletag :scale

  alias Cadence.Limits
  alias Cadence.Limits.Store.{AlarmPage, LatestStateRow, SpacecraftStates}
  alias Cadence.Ops.PointCatalog
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.{PointConditions, PointInfo}
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.{CurrentValueStore, Sample}
  alias Cadence.Telemetry.CurrentValueStore.ETS

  @org "org-pc-scale"
  @mission "mission-pc-scale"
  @fleet 1_000
  @fleet_points 200
  @definitions 200
  @limit_states [:green, :yellow_high, :red_high, :blue]

  test "one spacecraft's points at 200 and 2,000 points, beside a 1,000-spacecraft fleet" do
    persist_mission_scope(@org, @mission)
    now = ~U[2026-11-27 12:00:00.000000Z]

    for c <- 1..2 do
      {:ok, _} =
        SpacecraftStore.persist_spacecraft(
          @org,
          Spacecraft.new(%{
            spacecraft_id: "sc-#{c}",
            organization_id: @org,
            mission_id: @mission,
            display_name: "SC-#{c}",
            scid: c
          })
        )
    end

    cache = CurrentValueStore.policy(module: ETS)
    saved = Application.get_env(:cadence, :telemetry_current_value_store)
    Application.put_env(:cadence, :telemetry_current_value_store, module: ETS)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:cadence, :telemetry_current_value_store, saved),
        else: Application.delete_env(:cadence, :telemetry_current_value_store)
    end)

    start_supervised!(CurrentValueStore.child_spec(cache))

    # The rest of the fleet: 1,000 spacecraft x 200 points of current values on this node.
    for chunk <-
          Enum.chunk_every(
            for(c <- 3..@fleet, p <- 1..@fleet_points, do: sample("sc-#{c}", "HK.p#{p}", now, p)),
            5_000
          ),
        do: :ok = CurrentValueStore.record_samples(cache, chunk)

    Repo.query!("SET LOCAL session_replication_role = replica")

    definitions =
      for p <- 1..@definitions do
        review = Limits.limit_definition_review(@org, @mission, "HK.p#{p}", "FLIGHT")

        {:ok, definition} =
          Limits.append_limit_definition(
            @org,
            @mission,
            %{
              point_id: "HK.p#{p}",
              limit_set_name: "FLIGHT",
              thresholds: %{"yellow_high" => 5}
            },
            review
          )

        definition
      end

    {def_us, _} = :timer.tc(fn -> Limits.active_limit_definitions(@org, @mission) end)

    IO.puts(
      "Limits.active_limit_definitions for #{length(definitions)} definitions: " <>
        "#{Float.round(def_us / 1_000, 1)} ms"
    )

    for {craft, points} <- [{"sc-1", 200}, {"sc-2", 2_000}] do
      for chunk <-
            Enum.chunk_every(
              for(p <- 1..points, do: sample(craft, "HK.q#{p}", now, p), into: []),
              5_000
            ),
          do: :ok = CurrentValueStore.record_samples(cache, chunk)

      for chunk <- Enum.chunk_every(for(p <- 1..points, do: state_row(craft, p, now)), 1_000),
          do: Repo.insert_all(LatestStateRow, chunk)

      # ~10% of the points have a live alarm, some critical.
      for chunk <-
            Enum.chunk_every(for(p <- 1..div(points, 10), do: alarm_row(craft, p, now)), 1_000),
          do: Repo.insert_all(LatestAlarmStateRow, chunk)

      Repo.query!("ANALYZE telemetry_latest_limit_states")
      Repo.query!("ANALYZE semantic_latest_alarm_states")

      measure(craft, points, now)
    end

    assert length(@limit_states) == 4
  end

  defp measure(craft, points, now) do
    load = fn opts ->
      PointConditions.load(@org, @mission, craft, [now: now, limit: 200] ++ opts)
    end

    for _ <- 1..5, do: load.([])

    runs =
      for _ <- 1..100 do
        {micros, {:ok, result}} = :timer.tc(fn -> load.([]) end)
        assert result.counts.total >= points
        micros / 1_000
      end

    sorted = Enum.sort(runs)

    IO.puts(
      "PointConditions.load, #{points} points on the spacecraft, first page of 200, fleet of " <>
        "#{@fleet} x #{@fleet_points} values on the node: p50 #{Float.round(Enum.at(sorted, 49), 1)} ms, " <>
        "p99 #{Float.round(Enum.at(sorted, 98), 1)} ms"
    )

    for {name, fun} <- [
          {"current-value store, this spacecraft",
           fn -> CurrentValueStore.latest_values_for_mission(@mission, spacecraft_id: craft) end},
          {"ground states", fn -> SpacecraftStates.list(@org, @mission, craft) end},
          {"live states",
           fn -> SemanticObservations.list_for_spacecraft(@org, @mission, craft) end},
          {"active limit point ids", fn -> Limits.active_limit_point_ids(@org, @mission) end},
          {"point catalog", fn -> PointCatalog.list_points(@org, @mission) end},
          {"point info", fn -> PointInfo.by_id(@org, @mission) end},
          {"crossed_at, 200 rows",
           fn ->
             AlarmPage.crossed_at(
               @mission,
               for(p <- 1..200, do: {craft, "HK.q#{p}", "red"})
             )
           end}
        ] do
      times = for _ <- 1..30, do: elem(:timer.tc(fun), 0) / 1_000
      sorted = Enum.sort(times)

      IO.puts(
        "  of which #{name}: p50 #{Float.round(Enum.at(sorted, 14), 1)} ms, max #{Float.round(List.last(sorted), 1)} ms"
      )
    end

    assert Enum.at(sorted, 98) < 1_000
  end

  defp sample(craft, point, at, n) do
    %Sample{
      sample_id: "s-#{craft}-#{point}",
      mission_id: @mission,
      spacecraft_id: craft,
      point_id: point,
      point_name: point,
      packet_definition_id: "pd",
      packet_definition_version: 1,
      packet_id: "pk",
      evidence_id: "ev",
      raw_value: n,
      engineering_value: n,
      quality_state: :good,
      generation_time: at,
      receipt_time: DateTime.add(at, -rem(n * 7, 600), :second),
      provenance: %{}
    }
  end

  defp state_row(craft, p, now) do
    state = Enum.at(["green", "yellow", "red", "blue"], rem(p, 4))
    at = DateTime.add(now, -rem(p * 13, 3_000), :second)

    %{
      limit_event_id: "ev-#{craft}-#{p}",
      mission_id: @mission,
      organization_id: @org,
      spacecraft_scope_id: craft,
      spacecraft_id: craft,
      point_id: "HK.q#{p}",
      point_name: "HK.q#{p}",
      source_sample_type: "telemetry_sample",
      sample_id: "s",
      limit_definition_id: "d",
      limit_definition_version: 1,
      limit_set_name: "d",
      evaluated_value: JsonDocument.wrap_value(p),
      limit_state: if(state in ["red", "yellow"], do: "#{state}_high", else: state),
      normalized_state: state,
      violation: state in ["red", "yellow"],
      generation_time: at,
      receipt_time: at,
      provenance: %{},
      inserted_at: at,
      updated_at: at
    }
  end

  defp alarm_row(craft, p, now) do
    %{
      organization_id: @org,
      mission_id: @mission,
      spacecraft_scope_id: craft,
      spacecraft_id: craft,
      parameter_id: "HK.q#{p}",
      policy_id: "pol",
      evaluation_id: "ev-#{craft}-#{p}",
      transition_id: "tr-#{craft}-#{p}",
      effective_state: if(rem(p, 3) == 0, do: "critical", else: "warning"),
      generation_time: now,
      receipt_time: now,
      state_document: %{},
      inserted_at: now,
      updated_at: now
    }
  end
end
