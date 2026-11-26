defmodule Cadence.Reads.FleetStatusScaleTest do
  @moduledoc """
  `FleetStatus.load` at constellation scale (#798): 1,000 spacecraft x 200 points (200,000 latest
  limit states and 200,000 current values). Excluded by default (`--include scale`); it prints the
  figures the PR states. The budget it holds is generous (the push applies within 100 ms in the
  client, console #176); the number to read is the printed p50 and p99.
  """
  use Cadence.DataCase, async: false

  @moduletag :scale
  @moduletag timeout: 600_000

  alias Cadence.Limits.Store.LatestStateRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.FleetStatus
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.{CurrentValueStore, Sample}
  alias Cadence.Telemetry.CurrentValueStore.ETS

  @org "org-fleet-scale"
  @mission "mission-fleet-scale"
  @crafts 1_000
  @points 200
  # Their atoms, loaded for the rows' `String.to_existing_atom`.
  @limit_states [:green, :red_high]

  test "one load of the whole fleet fits the push budget, with a bounded number of queries" do
    persist_mission_scope(@org, @mission)
    now = DateTime.utc_now()

    for c <- 1..@crafts do
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

    Repo.query!("SET LOCAL session_replication_role = replica")

    rows =
      for c <- 1..@crafts, p <- 1..@points do
        id = "sc-#{c}"
        violating? = rem(c + p, 97) == 0 or rem(c + p, 41) == 0

        %{
          limit_event_id: "ev-#{c}-#{p}",
          mission_id: @mission,
          organization_id: @org,
          spacecraft_scope_id: id,
          spacecraft_id: id,
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
    Repo.query!("ANALYZE telemetry_latest_limit_states")

    cache = CurrentValueStore.policy(module: ETS)
    saved = Application.get_env(:cadence, :telemetry_current_value_store)
    Application.put_env(:cadence, :telemetry_current_value_store, module: ETS)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:cadence, :telemetry_current_value_store, saved),
        else: Application.delete_env(:cadence, :telemetry_current_value_store)
    end)

    start_supervised!(CurrentValueStore.child_spec(cache))

    for chunk <-
          Enum.chunk_every(
            for(
              c <- 1..@crafts,
              p <- 1..@points,
              do: %Sample{
                sample_id: "s-#{c}-#{p}",
                mission_id: @mission,
                spacecraft_id: "sc-#{c}",
                point_id: "HK.p#{p}",
                point_name: "HK.p#{p}",
                packet_definition_id: "pd",
                packet_definition_version: 1,
                packet_id: "pk",
                evidence_id: "ev",
                raw_value: p,
                engineering_value: p,
                quality_state: :good,
                generation_time: now,
                receipt_time: DateTime.add(now, -rem(c * 7 + p, 600), :second),
                provenance: %{}
              }
            ),
            5_000
          ),
        do: :ok = CurrentValueStore.record_samples(cache, chunk)

    queries = :counters.new(1, [])

    :telemetry.attach(
      "fleet-scale",
      [:cadence, :repo, :query],
      fn _e, _m, _meta, _ -> :counters.add(queries, 1, 1) end,
      nil
    )

    for _ <- 1..5, do: FleetStatus.load(@org, @mission, now: now)
    :counters.put(queries, 1, 0)

    runs =
      for _ <- 1..100 do
        {micros, fleet} = :timer.tc(fn -> FleetStatus.load(@org, @mission, now: now) end)
        assert fleet.counts.total == @crafts
        micros / 1_000
      end

    :telemetry.detach("fleet-scale")
    sorted = Enum.sort(runs)
    p50 = Enum.at(sorted, 49)
    p99 = Enum.at(sorted, 98)
    per_load = div(:counters.get(queries, 1), 100)

    IO.puts(
      "FleetStatus.load at #{@crafts} spacecraft x #{@points} points: p50 #{Float.round(p50, 1)} ms, " <>
        "p99 #{Float.round(p99, 1)} ms, #{per_load} queries per load"
    )

    assert length(@limit_states) == 2
    assert per_load <= 8
    assert p99 < 150
  end
end
