defmodule Cadence.SemanticRuntime.AlarmRules do
  @moduledoc """
  Which monitoring rule opened or escalated each alarm transition of a semantic `Result`, for
  flight events (docs/apogee/domain/flight-events.md): `%{{policy_id, update_id} => %{kind, id,
  label}}` (`MonitoringEvaluator.matched_rule/3`).

  Built by the partition owner, which holds the generation's monitoring plan, on every path that
  prepares observations (ingress, timer firings, re-projection of timer commits on recovery). It
  travels on the prepared map next to `observation_context`, never in the `Result`, the commit
  or anything hashed: partition replay verifies results by equality
  (docs/apogee/domain/semantic-runtime-replay.md).

  The plan must be the one that produced the result. Callers pass the activation the result was
  evaluated or replayed under; recovered commits are scoped to its `runtime_basis_sha256`.
  """

  alias Cadence.SemanticRuntime.{
    AlarmLevel,
    MonitoringEvaluator,
    MonitoringPlan,
    PlanDecoder,
    Result,
    Scope
  }

  @spec for_result(map(), Result.t() | nil) :: %{optional({binary(), binary()}) => map()}
  def for_result(runtime_plans, %Result{monitoring_results: results} = result)
      when is_map(runtime_plans) do
    case Enum.filter(results, &alarming?/1) do
      [] -> %{}
      alarming -> matches(monitoring(runtime_plans), result, alarming)
    end
  end

  def for_result(_runtime_plans, _result), do: %{}

  defp matches(policies, result, alarming) do
    plans = Map.new(policies, &{&1.policy_id, &1})
    updates = Map.new(result.parameter_updates, &{&1.update_id, &1})

    for monitoring <- alarming,
        plan = Map.get(plans, monitoring.policy_id),
        update = Map.get(updates, monitoring.update_id),
        not is_nil(plan) and not is_nil(update),
        match =
          MonitoringEvaluator.matched_rule(
            running(plan, update),
            update,
            monitoring.matched_context
          ),
        not is_nil(match),
        into: %{},
        do: {{monitoring.policy_id, monitoring.update_id}, match}
  end

  # The plan as the update's spacecraft ran it (its effective compiled rules, #451 T2).
  defp running(plan, update) do
    MonitoringPlan.effective(plan, update |> Scope.from_update() |> Scope.spacecraft_id())
  end

  # Only the monitoring plan: the algorithms aren't needed to name a rule.
  defp monitoring(runtime_plans),
    do: PlanDecoder.decode(%{monitoring: Map.get(runtime_plans, :monitoring)}).monitoring

  defp alarming?(%{transition: %{to: to}}), do: AlarmLevel.alarming?(to)
  defp alarming?(_result), do: false
end
