defmodule Cadence.SemanticRuntime.EffectivePoliciesTest do
  @moduledoc """
  A spacecraft's monitoring policies from the compiled plan's entries (#451 T2, the 12-01 shape),
  compiled through the real compiler (`MonitoringPlanFixtures`): per `rule_id`, the craft's
  spacecraft entry when there is one, else the mission entry; other craft's entries are dropped; a
  craft-only policy is that craft's own; `disabled` on an override turns the policy off for that
  craft. Evaluated through the semantic runtime, from the plan map and from the node cache (which
  reads the mission entries and the craft's own, never another craft's).
  """
  use Cadence.DataCase, async: false

  alias Cadence.MonitoringPlanFixtures, as: Fixtures
  alias Cadence.Runtime.{MonitoringPlanCache, ProcessNamespace}
  alias Cadence.SemanticRuntime

  alias Cadence.SemanticRuntime.{
    AlarmRules,
    MonitoringPlan,
    PlanDecoder,
    PlanIndex,
    State,
    Update
  }

  @org "org-effective-policies"
  @parameter "/parameters/temperature"
  @at ~U[2026-11-28 12:00:00.000000Z]

  setup do
    mission = "mission-effective-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  # {entries of the parameter as decoded, the parameter's id}
  defp compile(mission, catalog, authored \\ []) do
    plans = Fixtures.compile!(@org, mission, catalog, authored)
    entries = PlanDecoder.decode(plans).monitoring
    {plans, entries, hd(entries).parameter_id}
  end

  defp threshold(%MonitoringPlan{default_rules: [rule | _]}), do: rule["value"] || rule[:value]
  defp resolve(entries, craft), do: MonitoringPlan.resolve(entries, craft)
  defp seen(entries), do: Enum.map(entries, &{&1.scope, &1.spacecraft_id, threshold(&1)})

  describe "MonitoringPlan.resolve/2 over compiled entries" do
    test "mission entries apply to every craft; another craft's entries to none but it", c do
      {_plans, entries, _p} =
        compile(c.mission, [{"limit", @parameter, above: 10}], [
          {:craft_only, "own", @parameter, ["sc-1"], above: 21},
          {:craft_only, "other", @parameter, ["sc-2"], above: 22}
        ])

      assert [{:mission, nil, 10}, {:spacecraft, "sc-1", 21}] = seen(resolve(entries, "sc-1"))
      assert [{:mission, nil, 10}, {:spacecraft, "sc-2", 22}] = seen(resolve(entries, "sc-2"))
      assert [{:mission, nil, 10}] = seen(resolve(entries, "sc-3"))
      assert [{:mission, nil, 10}] = seen(resolve(entries, nil))
    end

    test "an override replaces the mission entry with its rule_id, for that craft only", c do
      {_plans, entries, _p} =
        compile(c.mission, [{"limit", @parameter, above: 10}], [
          {:override, "limit", "limit_sc_1", ["sc-1"], above: 100}
        ])

      assert [{:spacecraft, "sc-1", 100}] = seen(resolve(entries, "sc-1"))
      assert [{:mission, nil, 10}] = seen(resolve(entries, "sc-2"))
    end

    test "the override keeps the policy_id and rule_id: the craft's state and episode continue",
         c do
      {_plans, entries, _p} =
        compile(c.mission, [{"limit", @parameter, above: 10}], [
          {:override, "limit", "limit_sc_1", ["sc-1"], above: 100}
        ])

      [mission] = resolve(entries, "sc-2")
      [override] = resolve(entries, "sc-1")

      assert override.policy_id == mission.policy_id
      assert override.rule_id == mission.rule_id
      assert "policy:" <> _ = override.rule_id
      assert override.rule_digest != mission.rule_digest
      refute override.declaration_id == mission.declaration_id
    end

    test "disabled on the override turns the policy off for that craft only", c do
      {_plans, entries, _p} =
        compile(c.mission, [{"limit", @parameter, above: 10}], [
          {:override, "limit", "limit_off", ["sc-1"], above: 10, disabled: true}
        ])

      assert [%{disabled: true}] = resolve(entries, "sc-1")
      assert [%{disabled: false}] = resolve(entries, "sc-2")
    end

    test "a mission-layer replace keeps the rule_id and moves the digest", c do
      {_before, [original], _p} = compile(c.mission, [{"limit", @parameter, above: 10}])

      {_after, [replaced], _p} =
        compile(c.mission, [{"limit", @parameter, above: 10}], [{:replace, "limit", above: 12}])

      assert replaced.rule_id == original.rule_id
      assert replaced.rule_digest != original.rule_digest
      assert {original.origin, replaced.origin} == {:catalog, :mission_layer}
    end

    test "an entry from before P3 (no rule_id, no scope) is always kept" do
      legacy = MonitoringPlan.new(%{policy_id: "old", parameter_id: "p", default_rules: []})

      mission =
        MonitoringPlan.new(%{
          policy_id: "a",
          parameter_id: "p",
          rule_id: "policy:a",
          scope: "mission"
        })

      other =
        MonitoringPlan.new(%{
          policy_id: "a",
          parameter_id: "p",
          rule_id: "policy:a",
          scope: "spacecraft",
          spacecraft_id: "sc-9"
        })

      assert [^legacy, ^mission] = resolve([legacy, mission], "sc-1")
      assert [^legacy, ^mission] = resolve([legacy, mission, other], "sc-1")
      assert [^legacy, ^other] = resolve([legacy, mission, other], "sc-9")
    end
  end

  describe "through the semantic runtime" do
    setup do
      base = Module.concat(__MODULE__, "Ns#{System.unique_integer([:positive])}")

      namespace =
        ProcessNamespace.new!(
          root_supervisor: Module.concat(base, Root),
          registry: Module.concat(base, Registry),
          mission_supervisor: Module.concat(base, Missions),
          capability_registry: Module.concat(base, Capabilities)
        )

      start_supervised!({Registry, keys: :unique, name: namespace.registry})
      start_supervised!({MonitoringPlanCache, process_namespace: namespace})
      %{cache: MonitoringPlanCache.name(namespace)}
    end

    defp update(parameter, n, craft, value) do
      Update.new(%{
        update_id: "u#{n}-#{craft}",
        parameter_id: parameter,
        qualified_name: @parameter,
        value: value,
        raw_value: value,
        quality: :good,
        receipt_time: DateTime.add(@at, n),
        generation_time: DateTime.add(@at, n),
        producer_kind: :container,
        producer_id: "c",
        metadata: %{mission_id: "m", spacecraft_id: craft}
      })
    end

    defp run(plan, updates, state \\ %State{}) do
      {:ok, result, next} = SemanticRuntime.process(state, updates, plan)
      {result, next}
    end

    defp transitions(result) do
      for r <- result.monitoring_results,
          do: {r.update_id, r.transition && {r.transition.from, r.transition.to}}
    end

    defp overridden(c) do
      compile(c.mission, [{"limit", @parameter, above: 10}], [
        {:override, "limit", "limit_sc_2", ["sc-2"], above: 100}
      ])
    end

    test "two spacecraft on one plan: the same value alarms one and not the other", c do
      {plans, _entries, p} = overridden(c)
      updates = [update(p, 1, "sc-1", 50), update(p, 2, "sc-2", 50), update(p, 3, "sc-2", 500)]

      expected = [
        {"u1-sc-1", {:normal, :critical}},
        {"u2-sc-2", nil},
        {"u3-sc-2", {:normal, :critical}}
      ]

      from_map = plans |> PlanDecoder.decode() |> run(updates)
      {:ok, index} = MonitoringPlanCache.acquire(c.cache, plans)
      from_cache = run(index, updates)

      assert transitions(elem(from_map, 0)) == expected
      # The cache and the decoded map answer the same, results and state.
      assert from_cache == from_map
    end

    test "an update reads the mission entries and its own craft's, never another craft's", c do
      {plans, _entries, p} =
        compile(c.mission, [{"limit", @parameter, above: 10}], [
          {:override, "limit", "x1", ["sc-1"], above: 11},
          {:override, "limit", "x2", ["sc-2"], above: 12}
        ])

      {:ok, index} = MonitoringPlanCache.acquire(c.cache, plans)
      keys = c.cache |> MonitoringPlanCache.table() |> :ets.tab2list() |> Enum.map(&elem(&1, 0))

      # One key per parameter per scope.
      assert {index.plan_id, :monitoring, p, :mission} in keys
      assert {index.plan_id, :monitoring, p, "sc-1"} in keys
      assert {index.plan_id, :monitoring, p, "sc-2"} in keys

      assert [{:spacecraft, "sc-1", 11}] = index |> PlanIndex.monitoring_for(p, "sc-1") |> seen()
      assert [{:spacecraft, "sc-2", 12}] = index |> PlanIndex.monitoring_for(p, "sc-2") |> seen()
      assert [{:mission, nil, 10}] = index |> PlanIndex.monitoring_for(p, "sc-9") |> seen()
      assert [{:mission, nil, 10}] = index |> PlanIndex.monitoring_for(p) |> seen()
    end

    test "the alarm names the policy by its rule_id, the craft's override included", c do
      {plans, entries, p} = overridden(c)
      [%{rule_id: rule_id, policy_id: policy_id}] = resolve(entries, "sc-1")

      {result, _state} =
        plans
        |> PlanDecoder.decode()
        |> run([update(p, 1, "sc-1", 50), update(p, 3, "sc-2", 500)])

      matched = AlarmRules.for_result(plans, result)

      # Both craft's alarms link to the one `rule_id`, though sc-2 runs the override's body.
      assert %{{^policy_id, "u1-sc-1"} => %{id: ^rule_id, kind: "comparison"}} = matched
      assert %{{^policy_id, "u3-sc-2"} => %{id: ^rule_id}} = matched

      # The partition's own index gives the same names.
      index = plans |> PlanDecoder.decode() |> PlanIndex.from_plan()
      assert AlarmRules.for_result(index, result) == matched
    end

    test "an edit of the policy in force says rule_changed with its rule_id and keeps the alarm",
         c do
      {v1, [entry], p} =
        compile(c.mission, [{"limit", @parameter, above: 10, conformance: 2}])

      {v2, _entries, _p} =
        compile(c.mission, [{"limit", @parameter, above: 10, conformance: 2}], [
          {:replace, "limit", above: 100, conformance: 2}
        ])

      {_r1, state} = run(PlanDecoder.decode(v1), [update(p, 1, "sc-1", 50)])

      assert state.monitoring_state |> Map.values() |> hd() |> Map.fetch!(:effective_state) ==
               :critical

      {r2, _state2} = run(PlanDecoder.decode(v2), [update(p, 2, "sc-1", 50)], state)

      assert [mon] = r2.monitoring_results
      assert mon.effective_state == :critical
      assert mon.transition == nil
      assert %{rule_changed: %{from: from, to: to}} = mon.metadata
      assert from == entry.rule_digest
      assert from != to
    end

    test "moving a craft from the mission entry to its override resets its counters, not its alarm",
         c do
      {mission_only, _entries, p} =
        compile(c.mission, [{"limit", @parameter, above: 10, conformance: 2}])

      {with_override, _entries, _p} =
        compile(c.mission, [{"limit", @parameter, above: 10, conformance: 2}], [
          {:override, "limit", "limit_sc_1", ["sc-1"], above: 100, conformance: 2}
        ])

      {_r, state} = run(PlanDecoder.decode(mission_only), [update(p, 1, "sc-1", 50)])
      {result, _state} = run(PlanDecoder.decode(with_override), [update(p, 2, "sc-1", 50)], state)

      # Same policy_id: the state continued (still critical, one conformance counted under the new
      # threshold), the digest changed, so the evaluator said so.
      assert [%{effective_state: :critical, conformance_count: 1, metadata: %{rule_changed: _}}] =
               result.monitoring_results
    end
  end
end
