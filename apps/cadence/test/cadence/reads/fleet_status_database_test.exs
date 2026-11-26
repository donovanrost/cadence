defmodule Cadence.Reads.FleetStatusDatabaseTest do
  @moduledoc """
  The fleet read in the database (#798): the limit conditions per spacecraft are aggregated in SQL,
  the telemetry receipts come from the current-value store without reading its values, and the
  read costs the same number of queries however large the fleet is.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Limits.Store.{FleetSummary, LatestStateRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.FleetStatus
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @org "org-fleet-db"
  @mission "mission-fleet-db"
  @now ~U[2026-11-26 12:00:00.000000Z]
  # The limit states' atoms, loaded for the rows' `String.to_existing_atom`.
  @limit_states [:green, :yellow_high, :red_high, :blue]

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  defp craft(n) do
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

  defp state_row(craft, point, state, minute, opts \\ []) do
    id = if craft, do: "sc-#{craft}"
    at = DateTime.add(@now, -minute * 60, :second)

    %{
      limit_event_id: "ev-#{craft}-#{point}",
      mission_id: Keyword.get(opts, :mission, @mission),
      organization_id: Keyword.get(opts, :org, @org),
      spacecraft_scope_id: id || "__mission__",
      spacecraft_id: id,
      point_id: point,
      point_name: point,
      source_sample_type: "telemetry_sample",
      sample_id: "s",
      limit_definition_id: "d",
      limit_definition_version: 1,
      limit_set_name: "d",
      evaluated_value: JsonDocument.wrap_value(minute),
      limit_state: limit_state(state),
      normalized_state: state,
      violation: state in ["red", "yellow"],
      generation_time: at,
      receipt_time: at,
      provenance: %{},
      inserted_at: at,
      updated_at: at
    }
  end

  defp limit_state(state) when state in ["green", "blue"], do: state
  defp limit_state(state), do: "#{state}_high"

  defp seed(rows) do
    Repo.query!("SET LOCAL session_replication_role = replica")
    for chunk <- Enum.chunk_every(rows, 500), do: Repo.insert_all(LatestStateRow, chunk)
    FleetSummary.refresh(Repo, @mission, :all)
  end

  test "fixture states exist as atoms", do: assert(length(@limit_states) == 4)

  describe "FleetSummary" do
    test "per spacecraft: worst condition, violating count, newest receipt, worst violating point" do
      seed([
        state_row(1, "HK.a", "green", 30),
        state_row(1, "HK.b", "yellow", 20),
        state_row(1, "HK.c", "red", 10),
        state_row(1, "HK.d", "red", 5),
        state_row(2, "HK.a", "green", 3),
        state_row(2, "HK.b", "blue", 9),
        state_row(3, "HK.a", "yellow", 40),
        state_row(nil, "MISSION.x", "red", 1)
      ])

      summary = FleetSummary.load(@org, @mission)

      assert Map.keys(summary) |> Enum.sort() == ["sc-1", "sc-2", "sc-3"]

      assert %{limit_state: :critical, violating: 3, worst: worst, last_received_at: last} =
               summary["sc-1"]

      # Red beats yellow; of two reds, the newer.
      assert worst.point_id == "HK.d"
      assert last == DateTime.add(@now, -5 * 60, :second)

      assert %{limit_state: :nominal, violating: 0, worst: nil} = summary["sc-2"]
      assert %{limit_state: :caution, violating: 1} = summary["sc-3"]
    end

    test "only the asked mission and organization" do
      seed([
        state_row(1, "HK.a", "red", 1),
        state_row(9, "HK.a", "red", 1, mission: "other-mission", org: "other-org")
      ])

      assert Map.keys(FleetSummary.load(@org, @mission)) == ["sc-1"]
      assert FleetSummary.load("none", "none") == %{}
    end
  end

  test "load agrees with the pure builder fed the same limit states, spacecraft by spacecraft" do
    for n <- 1..6, do: craft(n)

    seed(
      for n <- 1..5,
          {point, i} <- Enum.with_index(["HK.a", "HK.b", "HK.c", "HK.d"]) do
        state =
          cond do
            rem(n + i, 5) == 0 -> "red"
            rem(n + i, 3) == 0 -> "yellow"
            true -> "green"
          end

        state_row(n, point, state, n * 3 + i)
      end
    )

    loaded = FleetStatus.load(@org, @mission, now: @now)

    built =
      FleetStatus.build(%{
        spacecraft: SpacecraftStore.list_spacecraft(@org, @mission),
        limit_states: LimitReads.latest_states_for_mission(@org, @mission, []),
        samples: [],
        now: @now,
        stale_after_s: FleetStatus.stale_after_s()
      })

    strip = fn fleet ->
      Enum.map(fleet.spacecraft, &Map.drop(&1, [:in_contact, :next_aos_at, :last_los_at]))
    end

    assert strip.(loaded) == strip.(built)
    assert loaded.counts.total == 6
    # SC-6 has no limit state at all.
    assert Enum.find(loaded.spacecraft, &(&1.id == "sc-6")).limit_state == :no_data
  end

  test "the read costs the same number of queries for a small fleet and a large one" do
    count = fn ->
      ref = make_ref()
      me = self()

      :telemetry.attach(
        {__MODULE__, ref},
        [:cadence, :repo, :query],
        fn _event, _m, meta, _ -> send(me, {ref, meta.source}) end,
        nil
      )

      FleetStatus.load(@org, @mission, now: @now)
      :telemetry.detach({__MODULE__, ref})
      drain(ref, [])
    end

    for n <- 1..3, do: craft(n)
    seed(for n <- 1..3, p <- 1..4, do: state_row(n, "HK.p#{p}", "green", p))
    small = count.()

    for n <- 4..60, do: craft(n)
    seed(for n <- 4..60, p <- 1..30, do: state_row(n, "HK.p#{p}", "yellow", p))
    large = count.()

    assert small == large
    assert length(large) <= 8
  end

  defp drain(ref, acc) do
    receive do
      {^ref, source} -> drain(ref, [source | acc])
    after
      0 -> Enum.sort(acc, &(inspect(&1) <= inspect(&2)))
    end
  end
end
