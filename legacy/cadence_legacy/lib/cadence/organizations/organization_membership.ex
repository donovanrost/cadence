defmodule Cadence.Organizations.OrganizationMembership do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_memberships" do
    field :role, :string, default: "member"

    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Valid organization roles:
  - owner: Full control over organization, can delete, manage all settings
  - admin: Can manage users, missions, and most settings (cannot delete org)
  - member: Can view organization and participate in missions they're assigned to
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :organization_id, :role])
    |> validate_required([:user_id, :organization_id, :role])
    |> validate_inclusion(:role, ["owner", "admin", "member"])
    |> unique_constraint([:user_id, :organization_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
