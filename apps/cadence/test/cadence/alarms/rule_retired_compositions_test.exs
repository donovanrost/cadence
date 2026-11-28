defmodule Cadence.Alarms.RuleRetiredCompositionsTest do
  @moduledoc """
  Two compositions in one mission (#451, after M): craft A runs revision X, craft B revision Y, each
  with its own compiled monitoring plan, so a generation keeps policies PER GROUP of spacecraft. A
  policy dropped for A but kept for B retires on A only (its episode, its latest state, its fleet
  summary); a craft that runs no revision retires everything; the groups come from the revisions in
  use (`MissionModels.revisions_at/3`) with their own plans; a late batch of an older generation is
  dropped per craft; and the statements per retirement follow the number of groups, not of
  spacecraft.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Alarms.EpisodeRow
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.FleetRevisionFixtures
  alias Cadence.MonitoringPlanFixtures, as: Plans
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.{FleetAlarms, LatestAlarmStateRow}
  alias Cadence.SemanticRuntime.PlanDecoder

  @org "org-retire-compositions"
  @t0 ~U[2026-11-20 12:00:00.000000Z]
  @applied ~U[2026-11-28 13:00:00.000000Z]

  setup do
    mission = "mission-retire-compositions-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  defp prepared(mission, parameter, craft, opts \\ []) do
    @org
    |> transition(
      mission,
      craft,
      parameter,
      Keyword.get(opts, :states, {:normal, :critical}),
      DateTime.add(@t0, Keyword.get(opts, :at, 1)),
      "open-#{mission}-#{parameter}-#{craft}-#{Keyword.get(opts, :at, 1)}"
    )
    |> update_in(
      [:observation_context],
      &Map.put(&1, :generation, Keyword.get(opts, :generation, 1))
    )
  end

  defp open!(mission, parameter, craft),
    do: :ok = SemanticObservations.persist_many([prepared(mission, parameter, craft)])

  defp groups(a, b),
    do: [
      %{policies: a.policies, spacecraft: ["craft-a"]},
      %{policies: b.policies, spacecraft: ["craft-b"]}
    ]

  defp retire(mission, groups, generation \\ 2),
    do:
      SemanticObservations.retire_rules(
        @org,
        mission,
        groups,
        "activation-#{generation}",
        @applied,
        generation
      )

  defp states(mission),
    do:
      Repo.all(
        from(s in LatestAlarmStateRow,
          where: s.mission_id == ^mission,
          order_by: [s.spacecraft_id, s.policy_id],
          select: {s.spacecraft_id, s.policy_id}
        )
      )

  defp active(mission),
    do:
      Repo.all(
        from(e in EpisodeRow,
          where: e.mission_id == ^mission and e.state == "active",
          order_by: [e.spacecraft_id, e.parameter_ref],
          select: {e.spacecraft_id, e.parameter_ref}
        )
      )

  test "a policy dropped for A and kept for B retires on A only", c do
    for craft <- ["craft-a", "craft-b"],
        parameter <- ["P1", "P2"],
        do: open!(c.mission, parameter, craft)

    # X keeps P2 only; Y keeps P1 and P2.
    assert {:ok, %{episodes: 1, states: 1}} =
             retire(
               c.mission,
               groups(%{policies: ["policy-P2"]}, %{policies: ["policy-P1", "policy-P2"]})
             )

    assert states(c.mission) == [
             {"craft-a", "policy-P2"},
             {"craft-b", "policy-P1"},
             {"craft-b", "policy-P2"}
           ]

    assert active(c.mission) == [{"craft-a", "P2"}, {"craft-b", "P1"}, {"craft-b", "P2"}]
    assert %{"craft-a" => _, "craft-b" => _} = FleetAlarms.load(@org, c.mission)
  end

  test "a craft that runs no revision keeps nothing", c do
    for craft <- ["craft-a", "craft-c"], do: open!(c.mission, "P1", craft)

    assert {:ok, %{episodes: 1, states: 1}} =
             retire(c.mission, [%{policies: ["policy-P1"], spacecraft: ["craft-a"]}])

    assert states(c.mission) == [{"craft-a", "policy-P1"}]
  end

  test "a late batch of an older generation is dropped per craft", c do
    for craft <- ["craft-a", "craft-b"], do: open!(c.mission, "P1", craft)

    assert {:ok, _} =
             retire(c.mission, groups(%{policies: ["policy-P2"]}, %{policies: ["policy-P1"]}))

    late =
      for craft <- ["craft-a", "craft-b"],
          do: prepared(c.mission, "P1", craft, at: 30, states: {:critical, :normal})

    assert :ok = SemanticObservations.persist_many(late)

    # craft-a's retired state did not come back; craft-b's is the late batch's.
    assert states(c.mission) == [{"craft-b", "policy-P1"}]
  end

  test "the groups come from the revisions in use, each with its own plan", c do
    x = revision(c.mission, ["limit-a", "limit-b"])
    y = revision(c.mission, ["limit-b", "limit-c"])

    FleetRevisionFixtures.assign!(
      @org,
      c.mission,
      1,
      %{"craft-a" => x.id, "craft-b" => y.id},
      @t0
    )

    activation = %{organization_id: @org, mission_id: c.mission}

    assert {:ok, groups} =
             MissionRuntimeReconciler.live_groups(activation, %{runtime_plans: %{}}, @applied)

    by_craft = Map.new(groups, &{&1.spacecraft, Enum.sort(&1.policies)})
    assert by_craft[["craft-a"]] == Enum.sort(x.policies)
    assert by_craft[["craft-b"]] == Enum.sort(y.policies)
    assert length(x.policies) == 2 and length(y.policies) == 2
  end

  test "a plan that is not there is a doubt, and a doubt keeps everything", c do
    FleetRevisionFixtures.assign!(@org, c.mission, 1, %{"craft-a" => "no-such-revision"}, @t0)
    activation = %{organization_id: @org, mission_id: c.mission}

    assert :unknown =
             MissionRuntimeReconciler.live_groups(activation, %{runtime_plans: %{}}, @applied)
  end

  test "the statements of a retirement follow the groups, not the spacecraft", c do
    counts =
      for size <- [4, 40] do
        mission = "#{c.mission}-#{size}"
        persist_mission_scope(@org, mission)
        crafts = Enum.map(1..size, &"craft-#{&1}")
        {left, right} = Enum.split(crafts, div(size, 2))
        for craft <- crafts, do: open!(mission, "P1", craft)
        half = div(size, 2)

        groups = [
          %{policies: ["policy-P2"], spacecraft: left},
          %{policies: ["policy-P1"], spacecraft: right}
        ]

        count(fn -> assert {:ok, %{states: ^half}} = retire(mission, groups) end)
        |> then(&{size, &1})
      end

    assert [{4, statements}, {40, statements}] = counts
  end

  # A revision of `mission` whose monitoring plan has these policies (by their declaration names).
  defp revision(mission, names) do
    catalog =
      for {name, n} <- Enum.with_index(names, 1),
          do: {name, "/parameters/#{name}", [above: n]}

    plan = Plans.compile!(@org, mission, catalog).monitoring

    policies =
      %{monitoring: plan}
      |> PlanDecoder.decode()
      |> Map.fetch!(:monitoring)
      |> Enum.map(& &1.policy_id)

    %{id: plan.mission_model_revision_id, policies: policies}
  end

  defp count(fun) do
    me = self()
    handler = "retire-count-#{System.unique_integer([:positive])}"

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
