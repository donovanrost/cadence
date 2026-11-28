defmodule Cadence.SemanticRuntime.EffectiveRulesTest do
  @moduledoc """
  A spacecraft's effective monitoring rules from the compiled plan's rows (#451 T2): a
  spacecraft-scoped rule replaces the mission rule with its `rule_id` for that craft, adds
  otherwise, and `enabled: false` turns a mission rule off for the craft. Evaluated through the
  semantic runtime, from the plan map and from the node cache, with the stand-in plan fixture.
  """
  use Cadence.UnitCase, async: true

  import Cadence.MonitoringPlanFixtures

  alias Cadence.Runtime.{MonitoringPlanCache, ProcessNamespace}
  alias Cadence.SemanticRuntime

  alias Cadence.SemanticRuntime.{
    AlarmRules,
    EffectiveRules,
    PlanDecoder,
    PlanIndex,
    State,
    Update
  }

  @at ~U[2026-11-28 12:00:00.000000Z]

  describe "EffectiveRules.for_spacecraft/2" do
    test "mission rules apply to every craft; another craft's rows to none but it" do
      rules = [
        rule("mission:a"),
        craft_rule("mission:own", "sc-1"),
        craft_rule("mission:other", "sc-2")
      ]

      assert ids(EffectiveRules.for_spacecraft(rules, "sc-1")) == ["mission:a", "mission:own"]
      assert ids(EffectiveRules.for_spacecraft(rules, "sc-2")) == ["mission:a", "mission:other"]
      assert ids(EffectiveRules.for_spacecraft(rules, "sc-3")) == ["mission:a"]
      assert ids(EffectiveRules.for_spacecraft(rules, nil)) == ["mission:a"]
    end

    test "a craft rule with the mission rule's id replaces it, in its place, for that craft only" do
      rules = [
        rule("mission:a", above: 10),
        rule("mission:b"),
        craft_rule("mission:a", "sc-1", above: 100)
      ]

      assert [first, second] = EffectiveRules.for_spacecraft(rules, "sc-1")

      assert {first.rule_id, first.definition.value, first.scope} ==
               {"mission:a", 100, "spacecraft"}

      assert second.rule_id == "mission:b"

      assert [%{definition: %{value: 10}, scope: "mission"}, _b] =
               EffectiveRules.for_spacecraft(rules, "sc-2")
    end

    test "enabled: false on the replacing rule turns the mission rule off for that craft only" do
      rules = [rule("mission:a"), craft_rule("mission:a", "sc-1", enabled: false)]

      assert EffectiveRules.for_spacecraft(rules, "sc-1") == []
      assert ids(EffectiveRules.for_spacecraft(rules, "sc-2")) == ["mission:a"]

      # A mission rule disabled itself is off for everyone; a disabled addition adds nothing.
      assert EffectiveRules.for_spacecraft([rule("mission:x", enabled: false)], "sc-1") == []

      assert EffectiveRules.for_spacecraft([craft_rule("new", "sc-1", enabled: false)], "sc-1") ==
               []
    end

    test "string-keyed rows (as stored) resolve the same" do
      row = fn r -> Map.new(r, fn {k, v} -> {Atom.to_string(k), v} end) end
      rules = [row.(rule("mission:a")), row.(craft_rule("mission:a", "sc-1", above: 5))]

      assert [%{"definition" => %{value: 5}}] = EffectiveRules.for_spacecraft(rules, "sc-1")
    end

    test "the digest follows the rules in force: an edit for one craft changes only that craft's" do
      before = [rule("mission:a"), craft_rule("mission:a", "sc-1", above: 100)]
      edited = [rule("mission:a"), craft_rule("mission:a", "sc-1", above: 200)]

      digest = fn rules, craft ->
        rules |> EffectiveRules.for_spacecraft(craft) |> EffectiveRules.digest("settings")
      end

      assert digest.(before, "sc-1") != digest.(edited, "sc-1")
      assert digest.(before, "sc-2") == digest.(edited, "sc-2")
      assert digest.(before, "sc-1") == digest.(before, "sc-1")
      assert EffectiveRules.digest([], "settings") == "settings"
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

    defp compiled do
      plans(
        [rule("limit:p", above: 10), craft_rule("limit:p", "sc-2", above: 100)],
        [policy("p")]
      )
    end

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

    test "the alarm names the compiled rule by its id, the craft's override included" do
      plan = compiled()
      decoded = PlanDecoder.decode(plan)
      {result, _state} = run(decoded, [update(1, "sc-1", 50), update(3, "sc-2", 500)])

      matched = AlarmRules.for_result(plan, result)

      # Both craft's alarms link to the one `rule_id`, though sc-2 runs the override's body.
      assert %{{"policy:p", "u1-sc-1"} => %{id: "limit:p", kind: "comparison"}} = matched
      assert %{{"policy:p", "u3-sc-2"} => %{id: "limit:p"}} = matched
    end

    test "an edit of the rules in force says rule_changed and keeps the open alarm" do
      v1 = plans([rule("limit:p", above: 10)], [policy("p", violations: 1, conformance: 2)])
      v2 = plans([rule("limit:p", above: 100)], [policy("p", violations: 1, conformance: 2)])

      {_r1, state} = run(PlanDecoder.decode(v1), [update(1, "sc-1", 50)])

      assert state.monitoring_state |> Map.values() |> hd() |> Map.fetch!(:effective_state) ==
               :critical

      {r2, _state2} =
        SemanticRuntime.process(state, [update(2, "sc-1", 50)], PlanDecoder.decode(v2))
        |> then(fn {:ok, r, s} -> {r, s} end)

      assert [mon] = r2.monitoring_results
      assert mon.effective_state == :critical
      assert mon.transition == nil
      assert %{rule_changed: %{from: from, to: to}} = mon.metadata
      assert from != to
    end

    test "a parameter with rule rows and no policy gets a default one named for it" do
      plan = plans([rule("limit:q", parameter_id: "q")])

      assert [%{policy_id: "monitoring:q", parameter_id: "q", minimum_violations: 1}] =
               plan |> PlanDecoder.decode() |> Map.fetch!(:monitoring)

      index = plan |> PlanDecoder.decode() |> PlanIndex.from_plan()

      assert [%{default_rules: [%{rule_id: "limit:q"}]}] =
               PlanIndex.monitoring_for(index, "q", "sc-9")
    end
  end

  defp ids(rules), do: Enum.map(rules, & &1.rule_id)
end
