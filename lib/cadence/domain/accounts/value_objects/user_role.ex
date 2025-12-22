defmodule Cadence.Domain.Accounts.ValueObjects.UserRole do
  @moduledoc """
  Value object representing a user's role within an organization.

  Roles are hierarchical, with higher roles having all permissions of lower roles:
  - `:system_admin` - Platform-level administrator (cross-organization)
  - `:owner` - Organization owner with full control
  - `:admin` - Organization administrator
  - `:member` - Regular organization member

  ## Usage

      iex> UserRole.valid?(:admin)
      true

      iex> UserRole.at_least?(:admin, :member)
      true

      iex> UserRole.can_manage?(:admin, :member)
      true
  """

  @type t :: :system_admin | :owner | :admin | :member

  @roles [:system_admin, :owner, :admin, :member]

  # Role hierarchy (higher index = higher privilege)
  @role_hierarchy %{
    member: 0,
    admin: 1,
    owner: 2,
    system_admin: 3
  }

  @doc """
  Returns all valid roles.
  """
  @spec all() :: [t()]
  def all, do: @roles

  @doc """
  Returns roles available for assignment within an organization.

  Excludes :system_admin which is platform-level only.
  """
  @spec organization_roles() :: [t()]
  def organization_roles, do: [:owner, :admin, :member]

  @doc """
  Checks if the given value is a valid role.
  """
  @spec valid?(term()) :: boolean()
  def valid?(role) when role in @roles, do: true
  def valid?(_), do: false

  @doc """
  Validates and returns the role.
  """
  @spec validate(term()) :: {:ok, t()} | {:error, :invalid_role}
  def validate(role) when role in @roles, do: {:ok, role}
  def validate(role) when is_binary(role) do
    case parse(role) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, :invalid_role}
    end
  end
  def validate(_), do: {:error, :invalid_role}

  @doc """
  Parses a string into a role atom.
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse("system_admin"), do: {:ok, :system_admin}
  def parse("owner"), do: {:ok, :owner}
  def parse("admin"), do: {:ok, :admin}
  def parse("member"), do: {:ok, :member}
  def parse(_), do: :error

  @doc """
  Returns the default role for new users.
  """
  @spec default() :: t()
  def default, do: :member

  @doc """
  Returns the hierarchy level of a role (higher = more privilege).
  """
  @spec hierarchy_level(t()) :: non_neg_integer()
  def hierarchy_level(role) when role in @roles do
    Map.fetch!(@role_hierarchy, role)
  end

  @doc """
  Checks if the first role is at least as privileged as the second.

  ## Examples

      iex> UserRole.at_least?(:admin, :member)
      true

      iex> UserRole.at_least?(:member, :admin)
      false
  """
  @spec at_least?(t(), t()) :: boolean()
  def at_least?(role, required_role) when role in @roles and required_role in @roles do
    hierarchy_level(role) >= hierarchy_level(required_role)
  end

  @doc """
  Checks if a user with the first role can manage users with the second role.

  A role can manage roles strictly below it in the hierarchy.
  System admins can manage all roles.

  ## Examples

      iex> UserRole.can_manage?(:admin, :member)
      true

      iex> UserRole.can_manage?(:admin, :admin)
      false
  """
  @spec can_manage?(t(), t()) :: boolean()
  def can_manage?(:system_admin, _target_role), do: true
  def can_manage?(actor_role, target_role) when actor_role in @roles and target_role in @roles do
    hierarchy_level(actor_role) > hierarchy_level(target_role)
  end

  @doc """
  Checks if a role transition is valid.

  Users cannot promote themselves. Owners can promote to admin.
  System admins can make any transition.

  Returns `{:ok, new_role}` or `{:error, reason}`.
  """
  @spec validate_promotion(t(), t(), t()) :: {:ok, t()} | {:error, atom()}
  def validate_promotion(actor_role, current_role, new_role) do
    cond do
      not valid?(new_role) ->
        {:error, :invalid_role}

      actor_role == :system_admin ->
        {:ok, new_role}

      not can_manage?(actor_role, current_role) ->
        {:error, :insufficient_permissions}

      hierarchy_level(new_role) >= hierarchy_level(actor_role) ->
        {:error, :cannot_promote_to_equal_or_higher}

      true ->
        {:ok, new_role}
    end
  end

  @doc """
  Returns a human-readable display name for the role.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:system_admin), do: "System Administrator"
  def display_name(:owner), do: "Owner"
  def display_name(:admin), do: "Administrator"
  def display_name(:member), do: "Member"

  @doc """
  Checks if the role is a system-level role.
  """
  @spec system_role?(t()) :: boolean()
  def system_role?(:system_admin), do: true
  def system_role?(_), do: false

  @doc """
  Checks if the role is an organization-level role.
  """
  @spec organization_role?(t()) :: boolean()
  def organization_role?(role), do: role in organization_roles()
end
