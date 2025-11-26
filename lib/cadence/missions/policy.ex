defmodule Cadence.Missions.Policy do
  @moduledoc """
  Authorization policy for mission-level actions.

  System admins have full access to all missions.

  Mission roles (via MissionMembership):
  - admin: Full control over the mission
  - engineer: Can modify mission configuration and targets
  - operator: Can view telemetry and send commands
  - viewer: Read-only access

  Organization-level permissions:
  - Organization owners/admins have full access to all missions in their org
  """

  @behaviour Bodyguard.Policy

  import Ecto.Query
  alias Cadence.Accounts.{User, Scope}
  alias Cadence.Missions.{Mission, MissionMembership}
  alias Cadence.Repo

  # System admins can do anything
  def authorize(_action, %Scope{system_admin?: true}, %Mission{}), do: :ok
  def authorize(_action, %User{system_admin: true}, %Mission{}), do: :ok

  # Check scope-based authorization
  def authorize(action, %Scope{} = scope, %Mission{} = mission) do
    if scope.user do
      authorize_user(action, scope.user, mission, scope.current_organization)
    else
      :error
    end
  end

  # Legacy User-based authorization
  def authorize(action, %User{} = user, %Mission{} = mission) do
    authorize_user(action, user, mission, nil)
  end

  # Organization owners/admins can do anything to missions in their org
  defp authorize_user(
         _action,
         user,
         %Mission{id: mission_id, organization_id: mission_org_id} = _mission,
         current_org
       ) do
    cond do
      # Check if user is org owner/admin via organization_memberships
      has_org_admin_access?(user, mission_org_id) ->
        :ok

      # Check if current organization matches and user has owner/admin role there
      current_org && current_org.id == mission_org_id &&
          has_membership_role?(user, mission_org_id, ["owner", "admin"]) ->
        :ok

      # Otherwise check mission membership
      true ->
        check_mission_membership(user.id, mission_id)
    end
  end

  defp check_mission_membership(user_id, mission_id) do
    case get_mission_role(user_id, mission_id) do
      "admin" -> :ok
      role when not is_nil(role) -> check_mission_role_permission(:view, role)
      nil -> :error
    end
  end

  defp has_org_admin_access?(%User{organization_memberships: memberships}, org_id)
       when is_list(memberships) do
    Enum.any?(memberships, fn membership ->
      membership.organization_id == org_id && membership.role in ["owner", "admin"]
    end)
  end

  defp has_org_admin_access?(_user, _org_id), do: false

  defp has_membership_role?(%User{organization_memberships: memberships}, org_id, roles)
       when is_list(memberships) do
    Enum.any?(memberships, fn membership ->
      membership.organization_id == org_id && membership.role in roles
    end)
  end

  defp has_membership_role?(_user, _org_id, _roles), do: false

  # Specific action checks based on mission role
  defp check_mission_role_permission(:view, role) when role in ["engineer", "operator", "viewer"],
    do: :ok

  defp check_mission_role_permission(:update, "engineer"), do: :ok
  defp check_mission_role_permission(:manage_targets, "engineer"), do: :ok

  defp check_mission_role_permission(:send_command, role) when role in ["engineer", "operator"],
    do: :ok

  defp check_mission_role_permission(:view_telemetry, role)
       when role in ["engineer", "operator", "viewer"],
       do: :ok

  defp check_mission_role_permission(_, _), do: :error

  defp get_mission_role(user_id, mission_id) do
    MissionMembership
    |> where([mm], mm.user_id == ^user_id and mm.mission_id == ^mission_id)
    |> select([mm], mm.role)
    |> Repo.one()
  end
end
