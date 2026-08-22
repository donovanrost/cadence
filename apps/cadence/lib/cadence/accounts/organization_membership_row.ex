defmodule Cadence.Accounts.OrganizationMembershipRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Accounts.OrganizationMembership
  alias Cadence.Persistence.JsonDocument

  @primary_key {:organization_membership_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @required_fields [
    :organization_membership_id,
    :user_id,
    :organization_id,
    :role,
    :lifecycle_state,
    :metadata
  ]

  schema "organization_memberships" do
    field(:user_id, :string)
    field(:organization_id, :string)
    field(:role, :string)
    field(:lifecycle_state, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @spec changeset(OrganizationMembership.t()) :: Ecto.Changeset.t()
  def changeset(%OrganizationMembership{} = membership) do
    %__MODULE__{}
    |> cast(row_attrs(membership), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :organization_id],
      name: :organization_memberships_user_id_organization_id_index
    )
  end

  @spec update_changeset(struct(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [:role, :lifecycle_state, :metadata])
    |> validate_required([:role, :lifecycle_state, :metadata])
    |> unique_constraint([:user_id, :organization_id],
      name: :organization_memberships_user_id_organization_id_index
    )
  end

  @spec to_domain(struct()) :: OrganizationMembership.t()
  def to_domain(%__MODULE__{} = row) do
    OrganizationMembership.new(%{
      organization_membership_id: row.organization_membership_id,
      user_id: row.user_id,
      organization_id: row.organization_id,
      role: row.role,
      lifecycle_state: row.lifecycle_state,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp row_attrs(%OrganizationMembership{} = membership) do
    %{
      organization_membership_id: membership.organization_membership_id,
      user_id: membership.user_id,
      organization_id: membership.organization_id,
      role: Atom.to_string(membership.role),
      lifecycle_state: Atom.to_string(membership.lifecycle_state),
      metadata: JsonDocument.wrap_value(membership.metadata)
    }
  end

  defp all_fields do
    [:organization_membership_id, :user_id, :organization_id, :role, :lifecycle_state, :metadata]
  end
end
