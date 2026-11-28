defmodule Cadence.Reads.MonitoredParametersTest do
  @moduledoc """
  What the active monitoring plan evaluates, per spacecraft (#451 T3a), from plans compiled through
  the real compiler (`MonitoringPlanFixtures`): the mission's entries apply to every craft, a
  craft's own entry adds a parameter (a craft-only policy) or turns one off (a disabled override)
  for that craft only, another craft's entries never reach it. The summary of a revision is built
  once and kept; a revision with no plan monitors nothing.
  """
  use Cadence.DataCase, async: false

  alias Cadence.MonitoringPlanFixtures, as: Fixtures
  alias Cadence.Reads.MonitoredParameters
  alias Cadence.SemanticRuntime.{MonitoringPlan, PlanDecoder}

  @org "org-monitored-parameters"
  @temp "/parameters/temperature"
  @volts "/parameters/volts"
  @mode "/parameters/mode"

  setup do
    mission = "mission-monitored-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  # The plan's parameter ids are semantic ids, so a parameter is named by the threshold its mission
  # entry carries (each test gives its parameters different ones).
  defp compile(mission, catalog, authored \\ []) do
    plan = Fixtures.compile!(@org, mission, catalog, authored).monitoring
    entries = PlanDecoder.decode(%{monitoring: plan}).monitoring

    ids =
      for %MonitoringPlan{scope: :mission, default_rules: [rule | _]} = entry <- entries,
          into: %{},
          do: {rule["value"] || rule[:value], entry.parameter_id}

    {[revision_id: plan.mission_model_revision_id], ids}
  end

  defp on(mission, craft, opts) do
    assert {:ok, parameters} = MonitoredParameters.for_spacecraft(@org, mission, craft, opts)
    parameters |> MapSet.to_list() |> Enum.sort()
  end

  defp sorted(ids, thresholds), do: thresholds |> Enum.map(&Map.fetch!(ids, &1)) |> Enum.sort()

  test "the mission's entries apply to every spacecraft", c do
    {opts, ids} = compile(c.mission, [{"temp", @temp, above: 10}, {"volts", @volts, above: 5}])

    assert on(c.mission, "sc-1", opts) == sorted(ids, [10, 5])
    assert on(c.mission, "sc-2", opts) == sorted(ids, [10, 5])
    assert MonitoredParameters.configured?(@org, c.mission, opts)
  end

  test "a craft-only policy adds a parameter for that craft alone", c do
    # The mission's policy on the parameter is disabled; the craft's own is enabled.
    {opts, ids} =
      compile(
        c.mission,
        [{"temp", @temp, above: 10}, {"mode", @mode, above: 100, disabled: true}],
        [{:craft_only, "mode-own", @mode, ["sc-1"], above: 1}]
      )

    assert on(c.mission, "sc-1", opts) == sorted(ids, [10, 100])
    assert on(c.mission, "sc-2", opts) == sorted(ids, [10])
  end

  test "a disabled override turns a parameter off for that craft alone", c do
    {opts, ids} =
      compile(c.mission, [{"temp", @temp, above: 10}, {"volts", @volts, above: 5}], [
        {:override, "temp", "temp-sc-1", ["sc-1"], disabled: true}
      ])

    assert on(c.mission, "sc-1", opts) == sorted(ids, [5])
    assert on(c.mission, "sc-2", opts) == sorted(ids, [10, 5])
  end

  test "an enabled override keeps the parameter, and another craft's entry never reaches it", c do
    {opts, ids} =
      compile(
        c.mission,
        [{"temp", @temp, above: 10}, {"mode", @mode, above: 100, disabled: true}],
        [
          {:override, "temp", "temp-sc-1", ["sc-1"], above: 15},
          {:craft_only, "mode-own", @mode, ["sc-2"], above: 1}
        ]
      )

    assert on(c.mission, "sc-1", opts) == sorted(ids, [10])
    assert on(c.mission, "sc-2", opts) == sorted(ids, [10, 100])
    assert on(c.mission, "sc-3", opts) == sorted(ids, [10])
  end

  test "a plan whose only enabled entry is one craft's is configured, and monitors nothing elsewhere",
       c do
    {opts, ids} =
      compile(c.mission, [{"mode", @mode, above: 100, disabled: true}], [
        {:craft_only, "mode-own", @mode, ["sc-1"], above: 1}
      ])

    assert MonitoredParameters.configured?(@org, c.mission, opts)
    assert on(c.mission, "sc-1", opts) == sorted(ids, [100])
    assert on(c.mission, "sc-2", opts) == []
  end

  test "no revision, or a plan with every policy disabled, is not configured", c do
    assert MonitoredParameters.for_spacecraft(@org, c.mission, "sc-1", revision_id: nil) == :none
    refute MonitoredParameters.configured?(@org, c.mission, revision_id: nil)

    {opts, _ids} = compile(c.mission, [{"temp", @temp, above: 10, disabled: true}])
    refute MonitoredParameters.configured?(@org, c.mission, opts)
    assert on(c.mission, "sc-1", opts) == []
  end

  test "a revision's summary is built once and kept for the next read", c do
    {opts, ids} = compile(c.mission, [{"temp", @temp, above: 10}])
    key = {c.mission, opts[:revision_id]}

    assert on(c.mission, "sc-1", opts) == sorted(ids, [10])
    # The cache writes asynchronously; this call returns after the cast was handled.
    :sys.get_state(MonitoredParameters)
    assert [{^key, _at, %{mission: mission}}] = :ets.lookup(MonitoredParameters, key)
    assert MapSet.to_list(mission) == sorted(ids, [10])

    assert on(c.mission, "sc-2", opts) == sorted(ids, [10])
  end

  test "only the newest revisions are kept", c do
    for n <- 1..20 do
      {opts, _ids} = compile(c.mission, [{"p#{n}", "/parameters/p#{n}", above: n}])
      assert MonitoredParameters.configured?(@org, c.mission, opts)
      :sys.get_state(MonitoredParameters)
    end

    assert :ets.info(MonitoredParameters, :size) <= 16
  end
end

defmodule Cadence.Reads.MonitoredParametersCompositionsTest do
  @moduledoc """
  Two compositions in one mission (#451, after M): craft A runs revision X, craft B revision Y, each
  with its own compiled plan. A craft's monitored parameters are its own revision's; `configured?`
  and `anywhere` cover every revision in use; the count of statements does not move with the
  number of spacecraft.
  """
  use Cadence.DataCase, async: false

  alias Cadence.FleetRevisionFixtures
  alias Cadence.MonitoringPlanFixtures, as: Fixtures
  alias Cadence.Reads.MonitoredParameters

  @org "org-monitored-compositions"
  @received ~U[2026-11-20 12:00:00.000000Z]

  setup do
    mission = "mission-compositions-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  # A revision whose plan monitors the given parameters (semantic ids = the names).
  defp revision(mission, parameters, opts \\ []) do
    catalog =
      for {name, n} <- Enum.with_index(parameters, 1) do
        {"limit-#{name}", "/parameters/#{name}", [above: n, parameter_id: name] ++ opts}
      end

    Fixtures.compile!(@org, mission, catalog).monitoring.mission_model_revision_id
  end

  defp on(mission, craft), do: mission |> monitored(craft) |> Enum.sort()

  defp monitored(mission, craft) do
    assert {:ok, parameters} = MonitoredParameters.for_spacecraft(@org, mission, craft)
    parameters
  end

  test "each craft's monitored parameters are its own revision's", c do
    x = revision(c.mission, ["p1", "p2"])
    y = revision(c.mission, ["p2", "p3"])

    FleetRevisionFixtures.assign!(
      @org,
      c.mission,
      1,
      %{"craft-a" => x, "craft-b" => y},
      @received
    )

    assert on(c.mission, "craft-a") == ["p1", "p2"]
    assert on(c.mission, "craft-b") == ["p2", "p3"]
    assert MonitoredParameters.for_spacecraft(@org, c.mission, "craft-c") == :none

    assert MonitoredParameters.anywhere(@org, c.mission) |> Enum.sort() == ["p1", "p2", "p3"]
    assert MonitoredParameters.configured?(@org, c.mission)
  end

  test "configured? covers every revision in use: one monitoring is enough, none is not", c do
    off = revision(c.mission, ["p1"], disabled: true)
    on = revision(c.mission, ["p2"])

    FleetRevisionFixtures.assign!(@org, c.mission, 1, %{"craft-a" => off}, @received)
    refute MonitoredParameters.configured?(@org, c.mission)
    assert MonitoredParameters.anywhere(@org, c.mission) == MapSet.new()

    FleetRevisionFixtures.assign!(
      @org,
      c.mission,
      2,
      %{"craft-a" => off, "craft-b" => on},
      DateTime.add(@received, 1, :second)
    )

    assert MonitoredParameters.configured?(@org, c.mission)
    assert on(c.mission, "craft-a") == []
    assert on(c.mission, "craft-b") == ["p2"]
  end

  test "a craft moves with its composition's next generation", c do
    x = revision(c.mission, ["p1"])
    y = revision(c.mission, ["p9"])
    FleetRevisionFixtures.assign!(@org, c.mission, 1, %{"craft-a" => x}, @received)
    assert on(c.mission, "craft-a") == ["p1"]

    FleetRevisionFixtures.assign!(
      @org,
      c.mission,
      2,
      %{"craft-a" => y},
      DateTime.add(@received, 1, :second)
    )

    assert on(c.mission, "craft-a") == ["p9"]
  end

  test "the statements per read do not depend on the number of spacecraft", c do
    x = revision(c.mission, ["p1", "p2"])
    y = revision(c.mission, ["p2", "p3"])

    counts =
      for size <- [4, 40] do
        mission = "#{c.mission}-#{size}"
        persist_mission_scope(@org, mission)
        x = revision(mission, ["p1", "p2"])
        y = revision(mission, ["p2", "p3"])

        assignments =
          Map.new(1..size, fn i -> {"craft-#{i}", if(rem(i, 2) == 0, do: x, else: y)} end)

        FleetRevisionFixtures.assign!(@org, mission, 1, assignments, @received)

        # Warm the per-revision summaries, then count what a read costs.
        MonitoredParameters.for_spacecraft(@org, mission, "craft-1")
        MonitoredParameters.anywhere(@org, mission)

        {size, count(fn -> MonitoredParameters.for_spacecraft(@org, mission, "craft-2") end),
         count(fn -> MonitoredParameters.configured?(@org, mission) end),
         count(fn -> MonitoredParameters.anywhere(@org, mission) end)}
      end

    assert [{4, a, b, d}, {40, a, b, d}] = counts
    assert a <= 2 and b <= 2 and d <= 2
    _ = {x, y}
  end

  defp count(fun) do
    me = self()
    handler = "mp-count-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _e, _m, _meta, _ -> send(me, :query) end,
      nil
    )

    fun.()
    :telemetry.detach(handler)
    drain(0)
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end
end
