defmodule Cadence.Settings.Policy do
  @moduledoc """
  Authorization policy for settings management.

  Settings can be scoped to organizations or missions:
  - Organization settings: Uses organization membership roles
  - Mission settings: Uses mission membership roles with org admin fallback

  ## Roles and Permissions

  ### Organization Settings
  - System admins: Full access to all settings
  - Org owners/admins: Can view and manage org settings
  - Org members: Can view org settings (read-only)

  ### Mission Settings
  - System admins: Full access to all settings
  - Org owners/admins: Full access to mission settings in their org
  - Mission admins/engineers: Can view and manage mission settings
  - Mission operators/viewers: Can view mission settings (read-only)
  """

  @behaviour Bodyguard.Policy

  alias Cadence.Accounts.{Scope, User}
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  # System admins can do anything
  def authorize(_action, %Scope{system_admin?: true}, _resource), do: :ok
  def authorize(_action, %User{system_admin: true}, _resource), do: :ok

  # Organization settings authorization
  def authorize(action, %Scope{} = scope, %Organization{} = org) do
    if scope.user do
      authorize_org_settings(action, scope.user, org)
    else
      :error
    end
  end

  def authorize(action, %User{} = user, %Organization{} = org) do
    authorize_org_settings(action, user, org)
  end

  # Mission settings authorization
  def authorize(action, %Scope{} = scope, %Mission{} = mission) do
    if scope.user do
      authorize_mission_settings(action, scope.user, mission, scope.current_organization)
    else
      :error
    end
  end

  def authorize(action, %User{} = user, %Mission{} = mission) do
    authorize_mission_settings(action, user, mission, nil)
  end

  # Catch-all
  def authorize(_, _, _), do: :error

  # Private helpers for organization settings

  defp authorize_org_settings(action, user, org) do
    case get_org_role(user, org) do
      role when role in ["owner", "admin"] ->
        authorize_org_action(action, :admin)

      "member" ->
        authorize_org_action(action, :member)

      nil ->
        :error
    end
  end

  defp authorize_org_action(:view_settings, _role), do: :ok
  defp authorize_org_action(:manage_settings, :admin), do: :ok
  defp authorize_org_action(_, _), do: :error

  # Private helpers for mission settings

  defp authorize_mission_settings(action, user, mission, current_org) do
    cond do
      # Org admins have full access to mission settings in their org
      has_org_admin_access?(user, mission.organization_id) ->
        :ok

      # Check current org context for admin access
      current_org && current_org.id == mission.organization_id &&
          has_org_role?(user, mission.organization_id, ["owner", "admin"]) ->
        :ok

      # Fall back to mission-level role check
      true ->
        authorize_by_mission_role(action, user, mission)
    end
  end

  defp authorize_by_mission_role(action, user, mission) do
    case get_mission_role(user, mission) do
      role when role in ["admin", "engineer"] ->
        authorize_mission_action(action, :engineer)

      role when role in ["operator", "viewer"] ->
        authorize_mission_action(action, :viewer)

      nil ->
        :error
    end
  end

  defp authorize_mission_action(:view_settings, _role), do: :ok
  defp authorize_mission_action(:manage_settings, :engineer), do: :ok
  defp authorize_mission_action(_, _), do: :error

  # Role lookup helpers

  defp get_org_role(%User{organization_memberships: memberships}, %Organization{id: org_id})
       when is_list(memberships) do
    case Enum.find(memberships, &(&1.organization_id == org_id)) do
      %{role: role} -> role
      nil -> nil
    end
  end

  defp get_org_role(_user, _org), do: nil

  defp has_org_admin_access?(%User{organization_memberships: memberships}, org_id)
       when is_list(memberships) do
    Enum.any?(memberships, fn membership ->
      membership.organization_id == org_id && membership.role in ["owner", "admin"]
    end)
  end

  defp has_org_admin_access?(_user, _org_id), do: false

  defp has_org_role?(%User{organization_memberships: memberships}, org_id, roles)
       when is_list(memberships) do
    Enum.any?(memberships, fn membership ->
      membership.organization_id == org_id && membership.role in roles
    end)
  end

  defp has_org_role?(_user, _org_id, _roles), do: false

  defp get_mission_role(%User{mission_memberships: memberships}, %Mission{id: mission_id})
       when is_list(memberships) do
    case Enum.find(memberships, &(&1.mission_id == mission_id)) do
      %{role: role} -> role
      nil -> nil
    end
  end

  defp get_mission_role(user, %Mission{id: mission_id}) do
    import Ecto.Query

    alias Cadence.Missions.MissionMembership
    alias Cadence.Repo

    MissionMembership
    |> where([mm], mm.user_id == ^user.id and mm.mission_id == ^mission_id)
    |> select([mm], mm.role)
    |> Repo.one()
  end
end
