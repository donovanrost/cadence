defmodule Cadence.Domain.Missions.Entities.MissionMembership do
  @moduledoc """
  Pure domain entity representing a user's membership in a mission.

  Mission memberships define what actions a user can perform within a specific mission.
  This is separate from bucket memberships, which control time-bounded command authority
  during shifts.

  ## Usage

      {:ok, membership} = MissionMembership.new(%{
        user_id: user_id,
        mission_id: mission_id,
        role: :operator
      })

      # Check permissions
      MissionMembership.can_command?(membership)  # => true
  """

  alias Cadence.Domain.Missions.ValueObjects.MembershipRole
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          mission_id: String.t(),
          role: MembershipRole.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :user_id,
    :mission_id,
    :role,
    :created_at,
    :updated_at
  ]

  @doc """
  Creates a new MissionMembership entity.

  ## Required Fields

  - `:user_id` - User ID
  - `:mission_id` - Mission ID
  - `:role` - Membership role (default: :viewer)
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs, [:user_id, :mission_id]),
         {:ok, role} <- parse_role(attrs[:role]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         user_id: attrs[:user_id],
         mission_id: attrs[:mission_id],
         role: role,
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates the membership role.
  """
  @spec update_role(t(), MembershipRole.t()) :: {:ok, t()} | {:error, term()}
  def update_role(%__MODULE__{} = membership, new_role) do
    case MembershipRole.parse(new_role) do
      {:ok, role} ->
        {:ok, %{membership | role: role, updated_at: CadenceTime.now()}}

      error ->
        error
    end
  end

  @doc """
  Returns true if the membership allows sending commands.
  """
  @spec can_command?(t()) :: boolean()
  def can_command?(%__MODULE__{role: role}), do: MembershipRole.can_command?(role)

  @doc """
  Returns true if the membership allows configuring the mission.
  """
  @spec can_configure?(t()) :: boolean()
  def can_configure?(%__MODULE__{role: role}), do: MembershipRole.can_configure?(role)

  @doc """
  Returns true if the membership allows managing users.
  """
  @spec can_manage_users?(t()) :: boolean()
  def can_manage_users?(%__MODULE__{role: role}), do: MembershipRole.can_manage_users?(role)

  @doc """
  Returns true if the membership has at least the given role level.
  """
  @spec has_role_at_least?(t(), MembershipRole.t()) :: boolean()
  def has_role_at_least?(%__MODULE__{role: role}, minimum_role) do
    MembershipRole.at_least?(role, minimum_role)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, fields) do
    missing = Enum.filter(fields, fn field -> is_nil(attrs[field]) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp parse_role(nil), do: {:ok, MembershipRole.default()}
  defp parse_role(role) when is_atom(role), do: MembershipRole.parse(role)
  defp parse_role(role) when is_binary(role), do: MembershipRole.parse(role)
  defp parse_role(_), do: {:error, :invalid_role}
end
