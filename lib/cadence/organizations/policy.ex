defmodule Cadence.Organizations.Policy do
  @moduledoc """
  Authorization policy for organization-level actions.

  System admins have full access to all organizations.

  Organization membership roles (via organization_memberships):
  - owner: Full control over the organization
  - admin: Can manage users and organization settings
  - member: Basic access to the organization
  """

  @behaviour Bodyguard.Policy

  alias Cadence.Accounts.{User, Scope}
  alias Cadence.Organizations.Organization

  # System admins can do anything
  def authorize(_action, %Scope{system_admin?: true}, %Organization{}), do: :ok
  def authorize(_action, %User{system_admin: true}, %Organization{}), do: :ok

  # Check organization membership for regular users
  def authorize(action, %Scope{} = scope, %Organization{} = org) do
    if scope.user do
      authorize(action, scope.user, org, get_membership_role(scope.user, org))
    else
      :error
    end
  end

  # Legacy support for direct User struct (deprecated, use Scope)
  def authorize(action, %User{} = user, %Organization{} = org) do
    authorize(action, user, org, get_membership_role(user, org))
  end

  # Owners can do anything
  defp authorize(:create, _user, _org, "owner"), do: :ok
  defp authorize(:update, _user, _org, "owner"), do: :ok
  defp authorize(:delete, _user, _org, "owner"), do: :ok
  defp authorize(:manage_users, _user, _org, "owner"), do: :ok
  defp authorize(:manage_settings, _user, _org, "owner"), do: :ok
  defp authorize(:view, _user, _org, "owner"), do: :ok

  # Admins can manage users and settings
  defp authorize(:manage_users, _user, _org, "admin"), do: :ok
  defp authorize(:manage_settings, _user, _org, "admin"), do: :ok
  defp authorize(:view, _user, _org, "admin"), do: :ok

  # Members can view
  defp authorize(:view, _user, _org, "member"), do: :ok

  # Deny by default
  defp authorize(_action, _user, _org, _role), do: :error

  defp get_membership_role(%User{organization_memberships: memberships}, %Organization{id: org_id})
      when is_list(memberships) do
    case Enum.find(memberships, &(&1.organization_id == org_id)) do
      %{role: role} -> role
      nil -> nil
    end
  end

  defp get_membership_role(_user, _org), do: nil
end
