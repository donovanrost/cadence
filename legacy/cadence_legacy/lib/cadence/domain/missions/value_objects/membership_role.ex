defmodule Cadence.Domain.Missions.ValueObjects.MembershipRole do
  @moduledoc """
  Value object representing a user's role within a mission.

  ## Role Values

  - `:viewer` - Read-only access to telemetry and mission data
  - `:operator` - Can view telemetry and send commands
  - `:engineer` - Can modify mission configuration and definitions
  - `:admin` - Full control over the mission including user management

  ## Permission Hierarchy

  ```
  ADMIN > ENGINEER > OPERATOR > VIEWER
  ```

  Each higher role includes all permissions of lower roles.
  """

  @type t :: :viewer | :operator | :engineer | :admin

  @values [:viewer, :operator, :engineer, :admin]

  # Permission levels for comparison (higher = more permissions)
  @levels %{
    viewer: 1,
    operator: 2,
    engineer: 3,
    admin: 4
  }

  @doc """
  Returns all valid role values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the default role for new memberships.
  """
  @spec default() :: t()
  def default, do: :viewer

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
      "viewer" -> {:ok, :viewer}
      "operator" -> {:ok, :operator}
      "engineer" -> {:ok, :engineer}
      "admin" -> {:ok, :admin}
      _ -> {:error, :invalid_role}
    end
  end

  def parse(_), do: {:error, :invalid_role}

  @doc """
  Returns the permission level for a role (higher = more permissions).
  """
  @spec level(t()) :: integer()
  def level(role) when role in @values, do: Map.fetch!(@levels, role)

  @doc """
  Returns true if role_a has at least the same permissions as role_b.
  """
  @spec at_least?(t(), t()) :: boolean()
  def at_least?(role_a, role_b) when role_a in @values and role_b in @values do
    level(role_a) >= level(role_b)
  end

  @doc """
  Returns true if the role can send commands.
  """
  @spec can_command?(t()) :: boolean()
  def can_command?(:operator), do: true
  def can_command?(:engineer), do: true
  def can_command?(:admin), do: true
  def can_command?(_), do: false

  @doc """
  Returns true if the role can modify mission configuration.
  """
  @spec can_configure?(t()) :: boolean()
  def can_configure?(:engineer), do: true
  def can_configure?(:admin), do: true
  def can_configure?(_), do: false

  @doc """
  Returns true if the role can manage mission users.
  """
  @spec can_manage_users?(t()) :: boolean()
  def can_manage_users?(:admin), do: true
  def can_manage_users?(_), do: false

  @doc """
  Returns the display name for a role.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:viewer), do: "Viewer"
  def display_name(:operator), do: "Operator"
  def display_name(:engineer), do: "Engineer"
  def display_name(:admin), do: "Admin"

  @doc """
  Returns a description of the role's permissions.
  """
  @spec description(t()) :: String.t()
  def description(:viewer), do: "Read-only access to telemetry and mission data"
  def description(:operator), do: "Can view telemetry and send commands"
  def description(:engineer), do: "Can modify mission configuration and definitions"
  def description(:admin), do: "Full control over the mission including user management"

  @doc """
  Returns a color for the role (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:viewer), do: "gray"
  def color(:operator), do: "blue"
  def color(:engineer), do: "purple"
  def color(:admin), do: "red"
end
