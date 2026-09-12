defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetStart do
  @moduledoc "Authoritative policy and UTC defaults for a new manual fleet run."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{FleetPlanningPolicies, FleetStartProjection}

  def load(%Scope{} = scope, mission) do
    context = %{organization_id: scope.organization_id, mission_id: mission.mission_id}

    with :ok <- Policy.authorize(scope, :operate_mission, context),
         {:ok, policy} <- active_policy(context) do
      start = DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)
      duration = if policy, do: min(policy.max_horizon_seconds, 86_400), else: 86_400

      {:ok,
       %{
         start: %{
           contract_version: 1,
           context: context,
           policy: policy,
           defaults: %{
             horizon_start: DateTime.to_iso8601(start),
             horizon_end: start |> DateTime.add(duration, :second) |> DateTime.to_iso8601(),
             include_recurring: true
           }
         }
       }}
    end
  end

  defp active_policy(context) do
    case FleetPlanningPolicies.fetch_active(context.organization_id, context.mission_id) do
      {:ok, _, version} -> {:ok, FleetStartProjection.policy(version)}
      {:error, :active_fleet_planning_policy_not_found} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end
end
