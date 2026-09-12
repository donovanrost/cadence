defmodule Cadence.ContactPlanning.FleetRunActions do
  @moduledoc "Explicit reviewed continuation and repair of scoped fleet runs."
  alias Cadence.ContactPlanning.{FleetPlanner, FleetRunLock, FleetRunRepairs, FleetRunReviews}

  def execute(scope, mission, action, params) do
    with {:ok, run_id, evidence, window} <- admit(action, params),
         :ok <- FleetRunReviews.authorize(scope, mission) do
      FleetRunLock.with_run(scope.organization_id, mission, run_id, fn ->
        decide(scope, mission, run_id, action, evidence, window)
      end)
    end
  end

  def validate(action, params) do
    case admit(action, params) do
      {:ok, _, _, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp admit(action, params) when is_map(params) and action in [:continue, :repair] do
    p = Map.delete(params, "mission_id")

    keys =
      if action == :repair,
        do: ~w(fleet_planning_run_id evidence repair),
        else: ~w(fleet_planning_run_id evidence)

    with true <- Enum.sort(Map.keys(p)) == Enum.sort(keys),
         id when is_binary(id) and byte_size(id) in 1..240 <- p["fleet_planning_run_id"],
         :ok <- evidence(action, p["evidence"]),
         true <- p["evidence"]["run_id"] == id,
         {:ok, window} <- window(action, p["repair"]) do
      {:ok, id, p["evidence"], window}
    else
      _ -> {:error, :fleet_run_action_invalid}
    end
  end

  defp admit(_, _), do: {:error, :fleet_run_action_invalid}
  defp evidence(:continue, e), do: FleetRunReviews.validate_evidence(e)
  defp evidence(:repair, e), do: FleetRunRepairs.validate_evidence(e)
  defp window(:continue, nil), do: {:ok, nil}

  defp window(:repair, form) when is_map(form) do
    with true <- Enum.sort(Map.keys(form)) == ~w(horizon_end horizon_start),
         {:ok, starts, 0} <- datetime(form["horizon_start"]),
         {:ok, ends, 0} <- datetime(form["horizon_end"]),
         true <- DateTime.before?(starts, ends) do
      {:ok, %{horizon_start: starts, horizon_end: ends}}
    else
      _ -> {:error, :fleet_repair_horizon_invalid}
    end
  end

  defp window(_, _), do: {:error, :fleet_repair_horizon_invalid}
  defp datetime(v) when is_binary(v) and byte_size(v) <= 40, do: DateTime.from_iso8601(v)
  defp datetime(_), do: {:error, :invalid_datetime}

  defp decide(scope, mission, run_id, :continue, evidence, _) do
    with {:ok, reviewed} <- FleetRunReviews.load(scope, mission, run_id),
         true <- reviewed.evidence === evidence,
         true <- FleetRunReviews.continuable?(reviewed.run),
         :ok <- FleetPlanner.check_current_inputs(reviewed.run),
         {:ok, result} <- FleetPlanner.run(scope, mission, run_id) do
      {:ok, receipt(result.run, evidence, "continued")}
    else
      false -> {:error, :fleet_run_review_changed}
      {:error, _} = error -> error
    end
  end

  defp decide(scope, mission, run_id, :repair, evidence, window) do
    with {:ok, run} <- FleetRunRepairs.create(scope, mission, run_id, evidence, window),
         do: {:ok, receipt(run, evidence, "repair_created")}
  end

  defp receipt(run, evidence, outcome),
    do: %{
      "contract_version" => 1,
      "organization_id" => run.organization_id,
      "mission_id" => run.mission_id,
      "fleetPlanningRunId" => run.fleet_planning_run_id,
      "lifecycleState" => Atom.to_string(run.lifecycle_state),
      "phase" => Atom.to_string(run.phase),
      "outcome" => outcome,
      "evidence" => evidence
    }
end
