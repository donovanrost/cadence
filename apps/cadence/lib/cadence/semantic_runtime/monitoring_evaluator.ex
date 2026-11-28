defmodule Cadence.SemanticRuntime.MonitoringEvaluator do
  @moduledoc "Pure monitoring policy evaluation with persistence and conformance counts."

  alias Cadence.Catalog.MissionModel.Canonical
  alias Cadence.SemanticRuntime.{MonitoringPlan, MonitoringResult, Update}

  @severity_rank %{normal: 0, watch: 1, warning: 2, distress: 3, critical: 4, severe: 5}

  @spec evaluate(MonitoringPlan.t(), Update.t(), map(), map()) :: {MonitoringResult.t(), map()}
  def evaluate(%MonitoringPlan{} = plan, %Update{} = update, latest, prior) do
    {prior, rule_changed} = apply_rule_digest(plan, prior)
    {rules, context_name} = select_rules(plan, latest)
    evaluated = evaluated_state(plan, update, rules)
    next = plan |> advance_state(evaluated, prior) |> put_rule_digest(plan)

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
      conformance_count: next.conformance_count,
      metadata: rule_changed_metadata(rule_changed)
    }

    {result, next}
  end

  # A change of the rules in force (#451 T2, contract 6): the persistence counters start again, the
  # effective state is kept (an open alarm survives a threshold edit and is judged anew by the next
  # sample), and the result says `rule_changed`. A state with no digest yet (first evaluation, or one
  # written before plans carried digests) adopts the plan's without a reset, and a plan with no
  # digest changes nothing, so legacy results, state and snapshots stay as they were. The change is
  # in `metadata`, never a struct field: partition replay verifies results by equality.
  defp apply_rule_digest(%MonitoringPlan{rule_digest: nil}, prior), do: {prior, nil}

  defp apply_rule_digest(%MonitoringPlan{rule_digest: digest}, prior) do
    case Map.get(prior, :rule_digest) do
      nil ->
        {prior, nil}

      ^digest ->
        {prior, nil}

      previous ->
        reset =
          Map.merge(prior, %{violation_count: 0, conformance_count: 0, candidate_state: nil})

        {reset, %{from: previous, to: digest}}
    end
  end

  defp put_rule_digest(next, %MonitoringPlan{rule_digest: nil}), do: next

  defp put_rule_digest(next, %MonitoringPlan{rule_digest: digest}),
    do: Map.put(next, :rule_digest, digest)

  defp rule_changed_metadata(nil), do: %{}
  defp rule_changed_metadata(change), do: %{rule_changed: change}

  @doc """
  The rule behind an update's evaluated state, for the alarm hook (flight events):
  `%{kind, id, label}`, or `nil` when no rule matched (or the policy is disabled, or the sample's
  quality is bad). `context_name` is the result's `matched_context`.

  Pure, with the same rule selection and matching as `evaluate/4`. It never feeds
  `MonitoringResult`: partition replay verifies results by equality, so any new field there would
  diverge every pre-deploy commit.

    * `kind`: `comparison | range | enumerated | boolean | string`.
    * `id`: a short content hash of the canonical rule, stable while the rule itself doesn't change
      (across catalog revisions and reorderings).
    * `label`: `"<context or default>#<index>"`, for display only.
  """
  @spec matched_rule(MonitoringPlan.t(), Update.t(), binary() | nil) :: map() | nil
  def matched_rule(%MonitoringPlan{disabled: true}, _update, _context_name), do: nil

  def matched_rule(_plan, %Update{quality: quality}, _context_name)
      when quality in [:bad, :unknown],
      do: nil

  def matched_rule(%MonitoringPlan{} = plan, %Update{} = update, context_name) do
    case rules_named(plan, context_name) do
      {:ok, rules} -> best_match(rules, update, context_name)
      :ambiguous -> nil
    end
  end

  @doc """
  The rule that matches `value` with the highest severity (the first of equals), or `nil`. Pure:
  the rule selection `evaluate/4` and `matched_rule/3` share, without a plan or a state, for a
  caller that holds a rule list (threshold limits, `ThresholdLimits`).
  """
  @spec best_rule([map()], term()) :: map() | nil
  def best_rule(rules, value) do
    rules
    |> Enum.filter(&rule_matches?(&1, value))
    |> Enum.max_by(&Map.get(@severity_rank, severity(&1), 0), fn -> nil end)
  end

  defp best_match(rules, update, context_name) do
    rules
    |> Enum.with_index()
    |> Enum.filter(fn {rule, _index} -> rule_matches?(rule, update.value) end)
    |> Enum.max_by(fn {rule, _index} -> Map.get(@severity_rank, severity(rule), 0) end, fn ->
      nil
    end)
    |> case do
      nil ->
        nil

      {rule, index} ->
        %{
          kind: rule |> value(:kind, :comparison) |> to_string(),
          id: rule_id(rule),
          label: "#{context_name || "default"}##{index}"
        }
    end
  end

  # `matched_context` is the matched context's name, `nil` for the defaults. An unnamed context
  # also records `nil`, and two contexts can share a name: then which rules applied isn't
  # knowable from the name, so say nothing (the hook falls back) rather than name a wrong rule.
  defp rules_named(plan, nil) do
    if Enum.any?(plan.contexts, &is_nil(value(&1, :name))),
      do: :ambiguous,
      else: {:ok, plan.default_rules}
  end

  defp rules_named(plan, context_name) do
    case Enum.filter(plan.contexts, &(value(&1, :name) == context_name)) do
      [context] -> {:ok, value(context, :rules, [])}
      [] -> {:ok, plan.default_rules}
      _same_name -> :ambiguous
    end
  end

  defp severity(rule), do: rule |> value(:severity, :warning) |> normalize_atom()

  # A compiled rule carries its own id, stable across edits (#451); an older rule is named by a
  # hash of its content.
  defp rule_id(rule) do
    case value(rule, :rule_id) do
      id when is_binary(id) and id != "" -> id
      _none -> "rule:" <> String.slice(Canonical.sha256(canonical(rule)), 0, 16)
    end
  end

  # Keys and atoms as strings, so atom- and string-keyed copies of a rule hash alike.
  defp canonical(%{} = map) when not is_struct(map),
    do: map |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)

  defp canonical(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp canonical(value), do: value

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
