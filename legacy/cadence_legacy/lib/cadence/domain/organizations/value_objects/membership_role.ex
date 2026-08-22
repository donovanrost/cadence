defmodule Cadence.Domain.Organizations.ValueObjects.MembershipRole do
  @moduledoc """
  Value object representing organization membership roles.

  ## Role Values

  - `:owner` - Full control over organization, can delete and manage all settings
  - `:admin` - Can manage users, missions, and most settings (cannot delete org)
  - `:member` - Can view organization and participate in assigned missions

  ## Permission Hierarchy

  ```
  ┌─────────┐
  │  OWNER  │  ← Full control, can delete org
  └────┬────┘
       │
  ┌────┴────┐
  │  ADMIN  │  ← Manage users, missions, settings
  └────┬────┘
       │
  ┌────┴────┐
  │ MEMBER  │  ← View and participate
  └─────────┘
  ```
  """

  @type t :: :owner | :admin | :member

  @values [:owner, :admin, :member]

  # Role hierarchy levels (higher = more permissions)
  @role_levels %{
    owner: 3,
    admin: 2,
    member: 1
  }

  @doc """
  Returns all valid role values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the default role for new members.
  """
  @spec default() :: t()
  def default, do: :member

  @doc """
  Returns true if the given value is a valid role.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a role value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_role}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_role}

  @doc """
  Parses a string or atom into a role.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_role}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "owner" -> {:ok, :owner}
      "admin" -> {:ok, :admin}
      "member" -> {:ok, :member}
      _ -> {:error, :invalid_role}
    end
  end

  def parse(_), do: {:error, :invalid_role}

  @doc """
  Returns the hierarchy level for a role.
  """
  @spec level(t()) :: pos_integer()
  def level(role) when role in @values do
    Map.fetch!(@role_levels, role)
  end

  @doc """
  Returns true if the first role has higher or equal permissions than the second.
  """
  @spec at_least?(t(), t()) :: boolean()
  def at_least?(role, required_role) when role in @values and required_role in @values do
    level(role) >= level(required_role)
  end

  @doc """
  Returns true if the first role can manage (promote/demote) the second role.
  A role can only manage roles below it in the hierarchy.
  """
  @spec can_manage?(t(), t()) :: boolean()
  def can_manage?(manager_role, target_role)
      when manager_role in @values and target_role in @values do
    level(manager_role) > level(target_role)
  end

  @doc """
  Returns true if the role can perform administrative actions.
  """
  @spec admin?(t()) :: boolean()
  def admin?(:owner), do: true
  def admin?(:admin), do: true
  def admin?(_), do: false

  @doc """
  Returns true if the role is the owner role.
  """
  @spec owner?(t()) :: boolean()
  def owner?(:owner), do: true
  def owner?(_), do: false

  @doc """
  Returns the display name for a role.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:owner), do: "Owner"
  def display_name(:admin), do: "Admin"
  def display_name(:member), do: "Member"

  @doc """
  Returns a color for the role (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:owner), do: "purple"
  def color(:admin), do: "blue"
  def color(:member), do: "gray"
end
