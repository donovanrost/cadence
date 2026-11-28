defmodule Cadence.SemanticRuntime.EffectivePoliciesTest do
  @moduledoc """
  A spacecraft's monitoring policies from the compiled plan's entries (#451 T2, the 12-01 shape):
  per `rule_id`, the craft's spacecraft entry when there is one, else the mission entry; other
  craft's entries are dropped; a craft-only policy is that craft's own; `disabled` on an override
  turns the policy off for that craft. Evaluated through the semantic runtime, from the plan map
  and from the node cache (which reads the mission entries and the craft's own, never another
  craft's), with the stand-in plan fixture.
  """
  use Cadence.UnitCase, async: true

  import Cadence.MonitoringPlanFixtures

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

  @at ~U[2026-11-28 12:00:00.000000Z]

  defp resolve(entries, craft) do
    entries |> Enum.map(&MonitoringPlan.new/1) |> MonitoringPlan.resolve(craft)
  end

  defp declared(plans), do: Enum.map(plans, & &1.declaration_id)

  describe "MonitoringPlan.resolve/2" do
    test "mission entries apply to every craft; another craft's entries to none but it" do
      entries = [
        entry("a"),
        craft_only("own", "sc-1"),
        craft_only("other", "sc-2")
      ]

      assert declared(resolve(entries, "sc-1")) == ["a", "own"]
      assert declared(resolve(entries, "sc-2")) == ["a", "other"]
      assert declared(resolve(entries, "sc-3")) == ["a"]
      assert declared(resolve(entries, nil)) == ["a"]
    end

    test "an override replaces the mission entry with its rule_id, in its place, for that craft only" do
      entries = [
        entry("a", above: 10),
        entry("b"),
        override("a", "a-for-sc-1", "sc-1", above: 100)
      ]

      assert [first, second] = resolve(entries, "sc-1")

      assert {first.rule_id, first.declaration_id, first.scope} ==
               {"policy:a", "a-for-sc-1", :spacecraft}

      assert hd(first.default_rules)["value"] == 100
      assert second.declaration_id == "b"

      assert [%{scope: :mission} = mission, _b] = resolve(entries, "sc-2")
      assert hd(mission.default_rules)["value"] == 10
    end

    test "the override keeps the policy_id: the craft's state and episode continue across it" do
      entries = [entry("a"), override("a", "a-for-sc-1", "sc-1")]
      assert ["a"] = entries |> resolve("sc-1") |> Enum.map(& &1.policy_id)
      assert ["a"] = entries |> resolve("sc-2") |> Enum.map(& &1.policy_id)
    end

    test "disabled on the override turns the policy off for that craft only" do
      entries = [entry("a"), override("a", "a-off-sc-1", "sc-1", disabled: true)]

      assert [%{disabled: true}] = resolve(entries, "sc-1")
      assert [%{disabled: false}] = resolve(entries, "sc-2")
    end

    test "an entry from before P3 (no rule_id, no scope) is always kept" do
      legacy = %{"policy_id" => "old", "parameter_id" => "p", "default_rules" => []}

      assert declared(resolve([legacy, entry("a")], "sc-1")) == [nil, "a"]
      assert length(resolve([legacy, override("a", "x", "sc-9")], "sc-1")) == 1
    end

    test "the digest follows each entry: an edit for one craft changes only that entry's" do
      before = [entry("a"), override("a", "x", "sc-1", above: 100)]
      edited = [entry("a"), override("a", "x", "sc-1", above: 200)]

      digests = fn entries, craft -> entries |> resolve(craft) |> Enum.map(& &1.rule_digest) end

      assert digests.(before, "sc-1") != digests.(edited, "sc-1")
      assert digests.(before, "sc-2") == digests.(edited, "sc-2")
      assert [<<"monitoring_rule:v1:", _::binary>>] = digests.(before, "sc-2")
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

    defp update(n, craft, value) do
      Update.new(%{
        update_id: "u#{n}-#{craft}",
        parameter_id: "p",
        qualified_name: "/p",
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

    defp run(plan, updates) do
      {:ok, result, state} = SemanticRuntime.process(%State{}, updates, plan)
      {result, state}
    end

    defp transitions(result) do
      for r <- result.monitoring_results,
          do: {r.update_id, r.transition && {r.transition.from, r.transition.to}}
    end

    defp compiled,
      do: plans([entry("limit", above: 10), override("limit", "limit-sc-2", "sc-2", above: 100)])

    test "two spacecraft on one plan: the same value alarms one and not the other", %{
      cache: cache
    } do
      updates = [update(1, "sc-1", 50), update(2, "sc-2", 50), update(3, "sc-2", 500)]
      plan = compiled()

      expected = [
        {"u1-sc-1", {:normal, :critical}},
        {"u2-sc-2", nil},
        {"u3-sc-2", {:normal, :critical}}
      ]

      from_map = plan |> PlanDecoder.decode() |> run(updates)
      {:ok, index} = MonitoringPlanCache.acquire(cache, plan)
      from_cache = run(index, updates)

      assert transitions(elem(from_map, 0)) == expected
      # The cache and the decoded map answer the same, results and state.
      assert from_cache == from_map
    end

    test "an update reads the mission entries and its own craft's, never another craft's", %{
      cache: cache
    } do
      plan =
        plans([entry("limit"), override("limit", "x1", "sc-1"), override("limit", "x2", "sc-2")])

      {:ok, index} = MonitoringPlanCache.acquire(cache, plan)

      table = MonitoringPlanCache.table(cache)
      keys = table |> :ets.tab2list() |> Enum.map(&elem(&1, 0))

      # One key per parameter per scope.
      assert {index.plan_id, :monitoring, "p", :mission} in keys
      assert {index.plan_id, :monitoring, "p", "sc-1"} in keys
      assert {index.plan_id, :monitoring, "p", "sc-2"} in keys

      assert ["x1"] = index |> PlanIndex.monitoring_for("p", "sc-1") |> declared()
      assert ["x2"] = index |> PlanIndex.monitoring_for("p", "sc-2") |> declared()
      assert ["limit"] = index |> PlanIndex.monitoring_for("p", "sc-9") |> declared()
      assert ["limit"] = index |> PlanIndex.monitoring_for("p") |> declared()
    end

    test "the alarm names the policy by its rule_id, the craft's override included" do
      plan = compiled()

      {result, _state} =
        run(PlanDecoder.decode(plan), [update(1, "sc-1", 50), update(3, "sc-2", 500)])

      matched = AlarmRules.for_result(plan, result)

      # Both craft's alarms link to the one `rule_id`, though sc-2 runs the override's body.
      assert %{{"limit", "u1-sc-1"} => %{id: "policy:limit", kind: "comparison"}} = matched
      assert %{{"limit", "u3-sc-2"} => %{id: "policy:limit"}} = matched

      # The partition's own index gives the same names.
      index = plan |> PlanDecoder.decode() |> PlanIndex.from_plan()
      assert AlarmRules.for_result(index, result) == matched
    end

    test "an edit of the policy in force says rule_changed and keeps the open alarm" do
      v1 = plans([entry("limit", above: 10, violations: 1, conformance: 2)])
      v2 = plans([entry("limit", above: 100, violations: 1, conformance: 2)])

      {_r1, state} = run(PlanDecoder.decode(v1), [update(1, "sc-1", 50)])

      assert state.monitoring_state |> Map.values() |> hd() |> Map.fetch!(:effective_state) ==
               :critical

      {:ok, r2, _state2} =
        SemanticRuntime.process(state, [update(2, "sc-1", 50)], PlanDecoder.decode(v2))

      assert [mon] = r2.monitoring_results
      assert mon.effective_state == :critical
      assert mon.transition == nil
      assert %{rule_changed: %{from: from, to: to}} = mon.metadata
      assert from != to
    end

    test "moving a craft from the mission entry to its override resets its counters, not its alarm" do
      mission_only = plans([entry("limit", above: 10, violations: 1, conformance: 2)])

      with_override =
        plans([
          entry("limit", above: 10, violations: 1, conformance: 2),
          override("limit", "limit-sc-1", "sc-1", above: 100, violations: 1, conformance: 2)
        ])

      {_r, state} = run(PlanDecoder.decode(mission_only), [update(1, "sc-1", 50)])

      {:ok, result, _state} =
        SemanticRuntime.process(state, [update(2, "sc-1", 50)], PlanDecoder.decode(with_override))

      # Same policy_id: the state continued (still critical, one conformance counted), the digest
      # changed, so the evaluator said so.
      assert [%{effective_state: :critical, conformance_count: 1, metadata: %{rule_changed: _}}] =
               result.monitoring_results
    end
  end
end
