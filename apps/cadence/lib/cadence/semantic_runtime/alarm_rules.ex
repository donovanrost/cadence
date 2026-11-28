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
    PlanDecoder,
    PlanIndex,
    Result,
    Scope
  }

  @spec for_result(map() | PlanIndex.t(), Result.t() | nil) :: %{
          optional({binary(), binary()}) => map()
        }
  def for_result(plans, %Result{monitoring_results: results} = result) when is_map(plans) do
    case Enum.filter(results, &alarming?/1) do
      [] -> %{}
      alarming -> matches(index(plans), result, alarming)
    end
  end

  def for_result(_plans, _result), do: %{}

  # The partition's own index (no decode); a plan map is decoded into one, for the callers that
  # hold the runtime plans.
  defp index(%PlanIndex{} = index), do: index

  defp index(runtime_plans),
    do:
      %{monitoring: Map.get(runtime_plans, :monitoring)}
      |> PlanDecoder.decode()
      |> PlanIndex.from_plan()

  # The policy as the update's spacecraft ran it (`MonitoringPlan.resolve/2`), by its policy id.
  defp matches(index, result, alarming) do
    updates = Map.new(result.parameter_updates, &{&1.update_id, &1})

    for monitoring <- alarming,
        update = Map.get(updates, monitoring.update_id),
        not is_nil(update),
        plan = running(index, monitoring, update),
        not is_nil(plan),
        match = MonitoringEvaluator.matched_rule(plan, update, monitoring.matched_context),
        not is_nil(match),
        into: %{},
        do: {{monitoring.policy_id, monitoring.update_id}, match}
  end

  defp running(index, monitoring, update) do
    craft = update |> Scope.from_update() |> Scope.spacecraft_id()

    index
    |> PlanIndex.monitoring_for(monitoring.parameter_id, craft)
    |> Enum.find(&(&1.policy_id == monitoring.policy_id))
  end

  defp alarming?(%{transition: %{to: to}}), do: AlarmLevel.alarming?(to)
  defp alarming?(_result), do: false
end
