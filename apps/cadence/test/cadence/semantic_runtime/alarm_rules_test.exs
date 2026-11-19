defmodule Cadence.SemanticRuntime.AlarmRulesTest do
  @moduledoc "Flight events: which rule opened an alarm, kept outside the replayed Result."
  use ExUnit.Case, async: true

  alias Cadence.SemanticRuntime.{
    AlarmRules,
    MonitoringEvaluator,
    MonitoringPlan,
    MonitoringResult,
    Result,
    Update
  }

  @at ~U[2026-11-11 12:00:00.000000Z]

  # evaluate/4 of the plan and update in golden_inputs/0, encoded by the code before
  # matched_rule/3 existed. Partition replay compares decoded commits with fresh results by
  # equality (docs/apogee/domain/semantic-runtime-replay.md), so this must keep decoding equal.
  @golden "g2gCdAAAAAx3Cl9fc3RydWN0X193L0VsaXhpci5DYWRlbmNlLlNlbWFudGljUnVudGltZS5Nb25pdG9yaW5nUmVzdWx0dxFjb25mb3JtYW5jZV9jb3VudGEAdw9lZmZlY3RpdmVfc3RhdGV3CGNyaXRpY2Fsdw9ldmFsdWF0ZWRfc3RhdGV3CGNyaXRpY2Fsdw9tYXRjaGVkX2NvbnRleHR3A25pbHcIbWV0YWRhdGF0AAAAAHcMcGFyYW1ldGVyX2lkbQAAAA5wYXJhbWV0ZXI6bW9kZXcJcG9saWN5X2lkbQAAAAtwb2xpY3k6bW9kZXcOcHJldmlvdXNfc3RhdGV3Bm5vcm1hbHcKdHJhbnNpdGlvbnQAAAACdwRmcm9tdwZub3JtYWx3AnRvdwhjcml0aWNhbHcJdXBkYXRlX2lkbQAAAA11cGRhdGU6bW9kZToxdw92aW9sYXRpb25fY291bnRhAXQAAAAEdw9jYW5kaWRhdGVfc3RhdGV3CGNyaXRpY2FsdxFjb25mb3JtYW5jZV9jb3VudGEAdw9lZmZlY3RpdmVfc3RhdGV3CGNyaXRpY2Fsdw92aW9sYXRpb25fY291bnRhAQ=="

  describe "replay safety" do
    test "a pre-change evaluation still equals a fresh one" do
      {plan, update} = golden_inputs()

      assert :erlang.binary_to_term(Base.decode64!(@golden)) ==
               MonitoringEvaluator.evaluate(plan, update, %{}, %{})
    end

    test "Result and MonitoringResult keep exactly their fields" do
      assert Map.keys(%Result{}) |> Enum.sort() ==
               ~w(__struct__ alarm_transitions diagnostics monitoring_results parameter_updates)a

      assert Map.keys(
               MonitoringResult.__struct__(
                 policy_id: nil,
                 parameter_id: nil,
                 update_id: nil,
                 evaluated_state: nil,
                 effective_state: nil
               )
             )
             |> Enum.sort() ==
               ~w(__struct__ conformance_count effective_state evaluated_state matched_context
                  metadata parameter_id policy_id previous_state transition update_id
                  violation_count)a
    end
  end

  describe "matched_rule/3" do
    for {kind, rule, value, severity} <- [
          {"enumerated", %{kind: :enumerated, values: ["SAFE"], severity: :critical}, "SAFE",
           :critical},
          {"boolean", %{kind: :boolean, value: true, severity: :warning}, true, :warning},
          {"string", %{kind: :string, operator: :==, value: "FAULT", severity: :distress},
           "FAULT", :distress},
          {"comparison", %{kind: :comparison, operator: :>, value: 100, severity: :critical}, 120,
           :critical},
          {"range", %{kind: :range, lower: 0, upper: 10, outside: true, severity: :watch}, 42,
           :watch}
        ] do
      test "agrees with the evaluator for a #{kind} rule" do
        plan = plan([unquote(Macro.escape(rule))])
        update = update(unquote(Macro.escape(value)))
        {result, _state} = MonitoringEvaluator.evaluate(plan, update, %{}, %{})

        assert result.evaluated_state == unquote(severity)

        assert %{kind: unquote(kind), id: "rule:" <> _, label: "default#0"} =
                 MonitoringEvaluator.matched_rule(plan, update, result.matched_context)
      end
    end

    test "nothing matched, bad quality or a disabled policy: nil" do
      plan = plan([%{kind: :enumerated, values: ["SAFE"], severity: :critical}])

      assert MonitoringEvaluator.matched_rule(plan, update("NOMINAL"), nil) == nil
      assert MonitoringEvaluator.matched_rule(plan, %{update("SAFE") | quality: :bad}, nil) == nil

      assert MonitoringEvaluator.matched_rule(%{plan | disabled: true}, update("SAFE"), nil) ==
               nil
    end

    test "the highest severity wins, as in the evaluator; the id follows the rule, not its place" do
      safe = %{kind: :enumerated, values: ["SAFE"], severity: :critical}
      any = %{kind: :string, operator: :!=, value: "", severity: :watch}

      first = MonitoringEvaluator.matched_rule(plan([safe, any]), update("SAFE"), nil)
      reordered = MonitoringEvaluator.matched_rule(plan([any, safe]), update("SAFE"), nil)
      string_keyed = %{"kind" => "enumerated", "values" => ["SAFE"], "severity" => "critical"}
      as_strings = MonitoringEvaluator.matched_rule(plan([string_keyed]), update("SAFE"), nil)

      assert %{kind: "enumerated", label: "default#0"} = first
      assert %{label: "default#1"} = reordered
      assert first.id == reordered.id
      assert first.id == as_strings.id
    end
  end

  describe "matched_rule/3 with contexts" do
    test "a named context's rules, labelled by the context" do
      plan = context_plan([%{name: "eclipse", criteria: nil, rules: [safe_rule()]}])
      {result, _state} = MonitoringEvaluator.evaluate(plan, update("SAFE"), %{}, %{})

      assert result.matched_context == "eclipse"

      assert %{kind: "enumerated", label: "eclipse#0"} =
               MonitoringEvaluator.matched_rule(plan, update("SAFE"), result.matched_context)
    end

    test "an unnamed matching context can't be told from the defaults: no rule (fallback)" do
      plan = context_plan([%{criteria: nil, rules: [safe_rule()]}])
      {result, _state} = MonitoringEvaluator.evaluate(plan, update("SAFE"), %{}, %{})

      assert result.evaluated_state == :critical
      assert result.matched_context == nil
      assert MonitoringEvaluator.matched_rule(plan, update("SAFE"), result.matched_context) == nil
    end

    test "two contexts with the matched name: no rule" do
      plan =
        context_plan([
          %{name: "eclipse", criteria: nil, rules: [safe_rule()]},
          %{name: "eclipse", criteria: nil, rules: []}
        ])

      assert MonitoringEvaluator.matched_rule(plan, update("SAFE"), "eclipse") == nil
    end

    test "a rule whose value is a struct still gets an id" do
      rule = %{kind: :enumerated, values: [Decimal.new("3")], severity: :warning}
      plan = plan([rule])

      assert %{kind: "enumerated", id: "rule:" <> _} =
               MonitoringEvaluator.matched_rule(plan, update(Decimal.new("3")), nil)
    end
  end

  describe "for_result/2" do
    test "only alarm transitions get a rule, keyed by policy and update" do
      {plan, update} = golden_inputs()
      {raised, _state} = MonitoringEvaluator.evaluate(plan, update, %{}, %{})
      cleared = %{raised | update_id: "other", transition: %{from: :critical, to: :normal}}
      runtime_plans = %{monitoring: runtime_plan([policy_attrs(plan)])}

      result = %Result{parameter_updates: [update], monitoring_results: [raised, cleared]}

      assert %{{"policy:mode", "update:mode:1"} => %{kind: "enumerated"}} =
               rules = AlarmRules.for_result(runtime_plans, result)

      assert map_size(rules) == 1
    end

    test "a plan without the policy (another generation) gives no rule" do
      {plan, update} = golden_inputs()
      {raised, _state} = MonitoringEvaluator.evaluate(plan, update, %{}, %{})
      result = %Result{parameter_updates: [update], monitoring_results: [raised]}

      assert AlarmRules.for_result(%{monitoring: runtime_plan([])}, result) == %{}
      assert AlarmRules.for_result(%{}, result) == %{}
    end
  end

  defp golden_inputs do
    plan =
      MonitoringPlan.new(%{
        policy_id: "policy:mode",
        parameter_id: "parameter:mode",
        default_rules: [%{kind: :enumerated, values: ["SAFE"], severity: :critical}]
      })

    update =
      Update.new(%{
        update_id: "update:mode:1",
        parameter_id: "parameter:mode",
        qualified_name: "/ADCS/MODE",
        value: "SAFE",
        raw_value: 3,
        quality: :good,
        generation_time: @at,
        receipt_time: @at,
        producer_kind: :container,
        producer_id: "container:hk",
        metadata: %{spacecraft_id: "sc-1"}
      })

    {plan, update}
  end

  defp safe_rule, do: %{kind: :enumerated, values: ["SAFE"], severity: :critical}

  defp context_plan(contexts),
    do:
      MonitoringPlan.new(%{
        policy_id: "p",
        parameter_id: "parameter:mode",
        contexts: contexts,
        default_rules: [%{kind: :enumerated, values: ["SAFE"], severity: :watch}]
      })

  defp plan(rules),
    do:
      MonitoringPlan.new(%{policy_id: "p", parameter_id: "parameter:mode", default_rules: rules})

  defp update(value) do
    {_plan, update} = golden_inputs()
    %{update | value: value}
  end

  defp policy_attrs(plan),
    do: %{
      "policy_id" => plan.policy_id,
      "parameter_id" => plan.parameter_id,
      "default_rules" => plan.default_rules
    }

  defp runtime_plan(policies) do
    %Cadence.Catalog.MissionModel.RuntimePlan{
      plan_id: "plan-monitoring",
      target: :monitoring,
      target_contract_version: "1",
      mission_model_revision_id: "revision-1",
      mission_model_content_sha256: "sha",
      layer_ids: [],
      compiler_version: "test",
      status: :ready,
      content_sha256: "sha",
      plan: %{"policies" => policies}
    }
  end
end
