defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetPolicyModel do
  @moduledoc "Authorized bounded policy administration data for a compiled Planning contribution."
  alias Cadence.Auth
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.FleetPolicyProjection, as: Projection

  def load(scope, mission_id, params) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         :ok <- scope_mission(scope, mission_id),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, query} <- query(params),
         {:ok, policy, version} <- current(scope.organization_id, mission_id),
         {:ok, active} <- active(scope.organization_id, mission_id),
         {:ok, grants} <- AutomationGrants.list_page(scope, mission_id, query.grants_page),
         permissions <- permissions(scope),
         {:ok, identities} <-
           identities(scope, mission_id, query.identities_page, permissions.grants) do
      {:ok,
       %{
         contract_version: 1,
         context: %{organization_id: scope.organization_id, mission_id: mission_id},
         query: query,
         state: if(policy, do: Atom.to_string(policy.lifecycle_state), else: "unconfigured"),
         current: Projection.version(version),
         active: Projection.version(active),
         defaults: Projection.values(nil),
         permissions: permissions,
         identities: identities,
         grants: %{grants | entries: Enum.map(grants.entries, &Projection.grant/1)}
       }}
    end
  end

  defp scope_mission(%{mission_id: scoped}, mission) when is_nil(scoped) or scoped == mission,
    do: :ok

  defp scope_mission(_, _), do: {:error, :scope_mismatch}

  def query(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ~w(grants_page identities_page))),
         {:ok, grants} <- page(Map.get(params, "grants_page", "1")),
         {:ok, identities} <- page(Map.get(params, "identities_page", "1")) do
      {:ok, %{grants_page: grants, identities_page: identities}}
    else
      _ -> {:error, :invalid_policy_query}
    end
  end

  def query(_), do: {:error, :invalid_policy_query}

  defp page(v) when is_binary(v) and byte_size(v) <= 7 do
    case Integer.parse(v) do
      {n, ""} when n in 1..1_000_000 ->
        if Integer.to_string(n) == v, do: {:ok, n}, else: {:error, :invalid_page}

      _ ->
        {:error, :invalid_page}
    end
  end

  defp page(_), do: {:error, :invalid_page}

  defp current(org, mission) do
    case FleetPlanningPolicies.fetch(org, mission) do
      {:error, :fleet_planning_policy_not_found} -> {:ok, nil, nil}
      other -> other
    end
  end

  defp active(org, mission) do
    case FleetPlanningPolicies.fetch_active(org, mission) do
      {:ok, _, version} -> {:ok, version}
      {:error, :active_fleet_planning_policy_not_found} -> {:ok, nil}
      other -> other
    end
  end

  defp permissions(scope),
    do: %{
      edit: permitted?(scope, :manage_fleet_planning_policy),
      approve: permitted?(scope, :approve_fleet_planning_policy),
      grants: permitted?(scope, :manage_automation_grants)
    }

  defp permitted?(scope, action),
    do: Policy.authorize(scope, action, %{organization_id: scope.organization_id}) == :ok

  defp identities(scope, mission, page, true),
    do: Auth.list_service_identity_choices(scope, mission, page)

  defp identities(_, _, page, false), do: {:ok, %{page: page, more: false, entries: []}}
end
