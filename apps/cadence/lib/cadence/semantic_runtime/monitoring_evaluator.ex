defmodule Cadence.SemanticRuntime.MonitoringEvaluator do
  @moduledoc "Pure monitoring policy evaluation with persistence and conformance counts."

  alias Cadence.SemanticRuntime.{MonitoringPlan, MonitoringResult, Update}

  @severity_rank %{normal: 0, watch: 1, warning: 2, distress: 3, critical: 4, severe: 5}

  @spec evaluate(MonitoringPlan.t(), Update.t(), map(), map()) :: {MonitoringResult.t(), map()}
  def evaluate(%MonitoringPlan{} = plan, %Update{} = update, latest, prior) do
    {rules, context_name} = select_rules(plan, latest)
    evaluated = evaluated_state(plan, update, rules)
    next = advance_state(plan, evaluated, prior)

    result = %MonitoringResult{
      policy_id: plan.policy_id,
      parameter_id: plan.parameter_id,
      update_id: update.update_id,
      evaluated_state: evaluated,
      effective_state: next.effective_state,
      previous_state: Map.get(prior, :effective_state, :normal),
      transition: transition(Map.get(prior, :effective_state, :normal), next.effective_state),
      matched_context: context_name,
      violation_count: next.violation_count,
      conformance_count: next.conformance_count
    }

    {result, next}
  end

  defp select_rules(plan, latest) do
    case Enum.find(plan.contexts, &criteria?(&1, latest)) do
      nil -> {plan.default_rules, nil}
      context -> {value(context, :rules, []), value(context, :name)}
    end
  end

  defp criteria?(context, latest) do
    case value(context, :criteria) do
      nil -> true
      criteria -> match_criteria?(criteria, latest)
    end
  end

  defp match_criteria?(criteria, latest) do
    parameter_id = value(criteria, :parameter_id)

    case Map.get(latest, parameter_id) do
      nil -> false
      update -> compare(value(criteria, :operator, :==), update.value, value(criteria, :value))
    end
  end

  defp evaluated_state(%MonitoringPlan{disabled: true}, _update, _rules), do: :disabled

  defp evaluated_state(plan, %Update{quality: quality}, _rules) when quality in [:bad, :unknown],
    do: plan.invalid_state

  defp evaluated_state(_plan, update, rules) do
    rules
    |> Enum.filter(&rule_matches?(&1, update.value))
    |> Enum.map(&(value(&1, :severity, :warning) |> normalize_atom()))
    |> Enum.max_by(&Map.get(@severity_rank, &1, 0), fn -> :normal end)
  end

  defp rule_matches?(rule, value) do
    kind = rule |> value(:kind, :comparison) |> normalize_atom()

    case kind do
      :comparison -> compare(value(rule, :operator), value, value(rule, :value))
      :range -> in_range?(value, rule)
      :enumerated -> value in value(rule, :values, [])
      :boolean -> value == value(rule, :value)
      :string -> compare(value(rule, :operator, :==), value, value(rule, :value))
    end
  end

  defp in_range?(value, rule) when is_number(value) do
    lower = value(rule, :lower)
    upper = value(rule, :upper)

    lower_ok =
      is_nil(lower) or
        compare(if(value(rule, :lower_closed, true), do: :>=, else: :>), value, lower)

    upper_ok =
      is_nil(upper) or
        compare(if(value(rule, :upper_closed, true), do: :<=, else: :<), value, upper)

    inside = lower_ok and upper_ok
    if value(rule, :outside, false), do: not inside, else: inside
  end

  defp in_range?(_value, _rule), do: false

  defp advance_state(plan, :normal, prior) do
    conformance_count = Map.get(prior, :conformance_count, 0) + 1
    previous = Map.get(prior, :effective_state, :normal)

    %{
      effective_state:
        if(conformance_count >= plan.minimum_conformance, do: :normal, else: previous),
      candidate_state: :normal,
      violation_count: 0,
      conformance_count: conformance_count
    }
  end

  defp advance_state(_plan, state, _prior) when state in [:disabled, :unknown] do
    %{effective_state: state, candidate_state: state, violation_count: 0, conformance_count: 0}
  end

  defp advance_state(plan, state, prior) do
    count =
      if Map.get(prior, :candidate_state) == state,
        do: Map.get(prior, :violation_count, 0) + 1,
        else: 1

    previous = Map.get(prior, :effective_state, :normal)

    %{
      effective_state: if(count >= plan.minimum_violations, do: state, else: previous),
      candidate_state: state,
      violation_count: count,
      conformance_count: 0
    }
  end

  defp transition(state, state), do: nil
  defp transition(from, to), do: %{from: from, to: to}

  defp compare(:==, left, right), do: left == right
  defp compare(:!=, left, right), do: left != right
  defp compare(:<, left, right), do: left < right
  defp compare(:<=, left, right), do: left <= right
  defp compare(:>, left, right), do: left > right
  defp compare(:>=, left, right), do: left >= right
  defp compare("==", left, right), do: compare(:==, left, right)
  defp compare("!=", left, right), do: compare(:!=, left, right)
  defp compare("<", left, right), do: compare(:<, left, right)
  defp compare("<=", left, right), do: compare(:<=, left, right)
  defp compare(">", left, right), do: compare(:>, left, right)
  defp compare(">=", left, right), do: compare(:>=, left, right)

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
