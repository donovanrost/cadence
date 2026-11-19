defmodule Cadence.Reads.OrganizationAudit.PolicyEvents do
  @moduledoc """
  A mission's fleet planning policy changes for the organization audit (`kind: "contacts"`):
  each saved version ("Proposed planning policy v4", the saver's `reason`, lead 11-14) and each
  decision on one ("Approved planning policy v4", the decision's reason). Target `{kind:
  "planning_policy", id, label: "Planning policy"}`; actors are users (names filled later).
  """

  alias Cadence.ContactPlanning.FleetPlanningPolicies

  @spec list(binary(), binary()) :: [map()]
  def list(organization_id, mission_id) do
    case FleetPlanningPolicies.fetch(organization_id, mission_id) do
      {:ok, policy, _current} ->
        id = policy.fleet_planning_policy_id

        Enum.map(
          FleetPlanningPolicies.list_versions(organization_id, mission_id, id),
          &proposed(&1, id)
        ) ++
          Enum.map(
            FleetPlanningPolicies.list_approvals(organization_id, mission_id, id),
            &decided(&1, id)
          )

      {:error, _none} ->
        []
    end
  end

  defp proposed(version, id) do
    event(
      id,
      "proposed:#{version.version}",
      version.created_at,
      version.created_by,
      "Proposed planning policy v#{version.version}",
      version.reason
    )
  end

  defp decided(approval, id) do
    verb = if approval.decision in [:approved, "approved"], do: "Approved", else: "Rejected"

    event(
      id,
      "#{approval.decision}:#{approval.fleet_planning_policy_version}",
      approval.decided_at,
      approval.actor_user_id,
      "#{verb} planning policy v#{approval.fleet_planning_policy_version}",
      approval.reason
    )
  end

  defp event(policy_id, key, at, actor_id, action, reason) do
    %{
      id: "contacts:planning_policy:#{policy_id}:#{key}",
      at: at,
      actor: if(is_binary(actor_id), do: %{kind: "user", id: actor_id, name: nil}),
      kind: "contacts",
      action: action,
      target: %{kind: "planning_policy", id: policy_id, label: "Planning policy"},
      mission: nil,
      reason: reason
    }
  end
end
