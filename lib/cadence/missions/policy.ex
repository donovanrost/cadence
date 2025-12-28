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

  alias Cadence.Accounts.{Scope, User}
  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Missions.Mission

  # System admins can do anything
  def authorize(_action, %Scope{system_admin?: true}, %Mission{}), do: :ok
  def authorize(_action, %Scope{system_admin?: true}, %MissionEntity{}), do: :ok
  def authorize(_action, %User{system_admin: true}, %Mission{}), do: :ok
  def authorize(_action, %User{system_admin: true}, %MissionEntity{}), do: :ok

  # Check scope-based authorization - Ecto schema
  def authorize(action, %Scope{} = scope, %Mission{} = mission) do
    if scope.user do
      authorize_user(
        action,
        scope.user,
        mission.id,
        mission.organization_id,
        scope.current_organization
      )
    else
      :error
    end
  end

  # Check scope-based authorization - Domain entity
  def authorize(action, %Scope{} = scope, %MissionEntity{} = entity) do
    if scope.user do
      authorize_user(
        action,
        scope.user,
        entity.id,
        entity.organization_id,
        scope.current_organization
      )
    else
      :error
    end
  end

  # Legacy User-based authorization - Ecto schema
  def authorize(action, %User{} = user, %Mission{} = mission) do
    authorize_user(action, user, mission.id, mission.organization_id, nil)
  end

  # Legacy User-based authorization - Domain entity
  def authorize(action, %User{} = user, %MissionEntity{} = entity) do
    authorize_user(action, user, entity.id, entity.organization_id, nil)
  end

  # Organization owners/admins can do anything to missions in their org
  defp authorize_user(_action, user, mission_id, mission_org_id, current_org) do
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
    case MissionQueries.get_user_role(user_id, mission_id) do
      {:ok, role} -> Atom.to_string(role)
      {:error, :not_found} -> nil
    end
  end
end
