defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetDirectory do
  @moduledoc "Scoped fleet run directory; reading this evidence never resumes a planner."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{FleetPlanningPolicies, FleetPlanningRuns}

  @states ~w(queued running completed partial failed canceled)

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ~w(page state))),
         page = Map.get(params, "page", "1"),
         true <- is_binary(page) and Regex.match?(~r/\A[1-9][0-9]{0,6}\z/, page),
         {number, ""} when number <= 1_000_000 <- Integer.parse(page),
         state = Map.get(params, "state", ""),
         true <- state in ["" | @states] do
      {:ok, %{page: number, state: if(state == "", do: nil, else: state)}}
    else
      _ -> {:error, :invalid_fleet_directory_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_fleet_directory_query}

  def load(%Scope{} = scope, mission, params) do
    context = %{organization_id: scope.organization_id, mission_id: mission.mission_id}

    with :ok <- Policy.authorize(scope, :operate_mission, context),
         {:ok, query} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, policy} <- active_policy(context),
         {:ok, runs} <-
           FleetPlanningRuns.list_page(
             context.organization_id,
             context.mission_id,
             query.page,
             query.state
           ) do
      {:ok,
       %{
         directory: %{
           contract_version: 1,
           context: context,
           query: query,
           active_policy: policy,
           runs: %{runs | entries: Enum.map(runs.entries, &run/1)}
         }
       }}
    end
  end

  defp active_policy(context) do
    case FleetPlanningPolicies.fetch_active(context.organization_id, context.mission_id) do
      {:ok, policy, version} ->
        {:ok,
         %{
           id: policy.fleet_planning_policy_id,
           version: version.version,
           content_sha256: version.content_sha256,
           max_horizon_seconds: version.horizon_document["max_horizon_seconds"]
         }}

      {:error, :active_fleet_planning_policy_not_found} ->
        {:ok, nil}

      {:error, _} = error ->
        error
    end
  end

  defp run(run) do
    %{
      id: run.fleet_planning_run_id,
      lifecycle_state: Atom.to_string(run.lifecycle_state),
      phase: Atom.to_string(run.phase),
      trigger_kind: Atom.to_string(run.trigger_kind),
      horizon_start: timestamp(run.horizon_start),
      horizon_end: timestamp(run.horizon_end),
      inserted_at: timestamp(run.inserted_at),
      policy_id: run.fleet_planning_policy_id,
      policy_version: run.fleet_planning_policy_version,
      requirement_count: run.input_document["requirement_count"],
      candidate_plan:
        if(run.candidate_contact_plan_id,
          do: %{id: run.candidate_contact_plan_id, version: run.candidate_contact_plan_version},
          else: nil
        )
    }
  end

  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
