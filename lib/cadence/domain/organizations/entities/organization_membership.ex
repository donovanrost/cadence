defmodule Cadence.Domain.Organizations.Entities.OrganizationMembership do
  @moduledoc """
  Pure domain entity representing a user's membership in an organization.

  Memberships define the relationship between users and organizations,
  including the role which determines permissions within that organization.

  ## Usage

      {:ok, membership} = OrganizationMembership.new(%{
        user_id: "user-uuid",
        organization_id: "org-uuid",
        role: :member
      })

      # Promote to admin
      {:ok, membership} = OrganizationMembership.change_role(membership, :admin)
  """

  alias Cadence.Domain.Organizations.ValueObjects.MembershipRole

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          organization_id: String.t(),
          role: MembershipRole.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :user_id,
    :organization_id,
    :role,
    :created_at,
    :updated_at
  ]

  @doc """
  Creates a new OrganizationMembership entity.

  ## Required Fields

  - `:user_id` - ID of the user
  - `:organization_id` - ID of the organization

  ## Optional Fields

  - `:role` - Membership role (default: :member)
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs, [:user_id, :organization_id]),
         {:ok, role} <- parse_role(attrs[:role]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         user_id: attrs[:user_id],
         organization_id: attrs[:organization_id],
         role: role,
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Changes the membership role.
  """
  @spec change_role(t(), MembershipRole.t()) :: {:ok, t()} | {:error, term()}
  def change_role(%__MODULE__{} = membership, new_role) do
    with {:ok, role} <- parse_role(new_role) do
      {:ok, %{membership | role: role, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Promotes the membership to a higher role.
  """
  @spec promote(t(), MembershipRole.t()) :: {:ok, t()} | {:error, term()}
  def promote(%__MODULE__{role: current} = membership, new_role) do
    with {:ok, role} <- parse_role(new_role) do
      if MembershipRole.level(role) > MembershipRole.level(current) do
        {:ok, %{membership | role: role, updated_at: DateTime.utc_now()}}
      else
        {:error, :cannot_promote_to_lower_role}
      end
    end
  end

  @doc """
  Demotes the membership to a lower role.
  """
  @spec demote(t(), MembershipRole.t()) :: {:ok, t()} | {:error, term()}
  def demote(%__MODULE__{role: current} = membership, new_role) do
    with {:ok, role} <- parse_role(new_role) do
      if MembershipRole.level(role) < MembershipRole.level(current) do
        {:ok, %{membership | role: role, updated_at: DateTime.utc_now()}}
      else
        {:error, :cannot_demote_to_higher_role}
      end
    end
  end

  @doc """
  Returns true if the membership has at least the specified role level.
  """
  @spec has_role?(t(), MembershipRole.t()) :: boolean()
  def has_role?(%__MODULE__{role: role}, required_role) do
    MembershipRole.at_least?(role, required_role)
  end

  @doc """
  Returns true if the membership is an owner.
  """
  @spec owner?(t()) :: boolean()
  def owner?(%__MODULE__{role: role}), do: MembershipRole.owner?(role)

  @doc """
  Returns true if the membership has admin privileges.
  """
  @spec admin?(t()) :: boolean()
  def admin?(%__MODULE__{role: role}), do: MembershipRole.admin?(role)

  @doc """
  Returns true if the first membership can manage the second.
  A membership can only manage memberships with lower roles.
  """
  @spec can_manage?(t(), t()) :: boolean()
  def can_manage?(%__MODULE__{role: manager_role}, %__MODULE__{role: target_role}) do
    MembershipRole.can_manage?(manager_role, target_role)
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

  defp parse_role(role) when is_atom(role) do
    if MembershipRole.valid?(role) do
      {:ok, role}
    else
      {:error, :invalid_role}
    end
  end

  defp parse_role(role) when is_binary(role), do: MembershipRole.parse(role)
  defp parse_role(_), do: {:error, :invalid_role}
end
