defmodule Cadence.Reads.DerivedPointsCompositionsTest do
  @moduledoc """
  Two compositions in one mission (#451, after M): craft A runs revision X, which derives
  `bus_volts`, craft B runs revision Y, which derives `bus_amps`. The point catalog for a craft
  lists its own revision's derived points; without a craft it lists every revision in use's, a
  point once; and what a read costs does not depend on the number of spacecraft.
  """
  use Cadence.DataCase, async: false

  alias Cadence.DerivedPointFixtures, as: Fixtures
  alias Cadence.FleetRevisionFixtures
  alias Cadence.Ops.PointCatalog

  @org "org-derived-compositions"
  @amps "/vehicle/derived/bus_amps"
  @received ~U[2026-11-20 12:00:00.000000Z]

  setup do
    mission = "mission-derived-compositions-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    x = Fixtures.activate!(@org, mission)
    y = Fixtures.compile!(@org, mission, derived_name: @amps)

    FleetRevisionFixtures.assign!(
      @org,
      mission,
      2,
      assignments(["craft-a"], ["craft-b"], x, y),
      @received
    )

    %{mission: mission, x: x, y: y}
  end

  defp assignments(a, b, x, y) do
    Map.new(Enum.map(a, &{&1, x.revision_id}) ++ Enum.map(b, &{&1, y.revision_id}))
  end

  defp derived(mission, opts) do
    @org
    |> PointCatalog.list_points(mission, opts)
    |> Enum.filter(&(&1.source == :derived))
    |> Enum.map(& &1.point_id)
  end

  test "a craft's catalog lists its own revision's derived points", c do
    assert derived(c.mission, spacecraft_id: "craft-a") == [c.x.derived_id]
    assert derived(c.mission, spacecraft_id: "craft-b") == [c.y.derived_id]
  end

  test "without a craft, every revision in use's, each once, ordered by name", c do
    assert Enum.sort(derived(c.mission, [])) == Enum.sort([c.x.derived_id, c.y.derived_id])

    names =
      @org
      |> PointCatalog.list_points(c.mission)
      |> Enum.filter(&(&1.source == :derived))
      |> Enum.map(& &1.qualified_name)

    assert names == [@amps, Fixtures.derived_name()]
  end

  test "a craft moves with its composition's next generation", c do
    FleetRevisionFixtures.assign!(
      @org,
      c.mission,
      3,
      %{"craft-a" => c.y.revision_id},
      DateTime.add(@received, 1, :second)
    )

    assert derived(c.mission, spacecraft_id: "craft-a") == [c.y.derived_id]
    assert derived(c.mission, []) == [c.y.derived_id]
  end

  test "the statements per read do not depend on the number of spacecraft", c do
    counts =
      for size <- [4, 40] do
        mission = "#{c.mission}-#{size}"
        persist_mission_scope(@org, mission)
        x = Fixtures.activate!(@org, mission)
        y = Fixtures.compile!(@org, mission, derived_name: @amps)
        crafts = Enum.map(1..size, &"craft-#{&1}")
        {left, right} = Enum.split(crafts, div(size, 2))
        FleetRevisionFixtures.assign!(@org, mission, 2, assignments(left, right, x, y), @received)

        # Warm the per-revision derived points; then count a read.
        derived(mission, [])

        {size, count(fn -> derived(mission, spacecraft_id: "craft-1") end),
         count(fn -> derived(mission, []) end)}
      end

    assert [{4, per_craft, all}, {40, per_craft, all}] = counts
  end

  defp count(fun) do
    me = self()
    handler = "dp-count-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _e, _m, _meta, _ -> send(me, :q) end,
      nil
    )

    fun.()
    :telemetry.detach(handler)
    drain(0)
  end

  defp drain(n) do
    receive do
      :q -> drain(n + 1)
    after
      0 -> n
    end
  end
end
