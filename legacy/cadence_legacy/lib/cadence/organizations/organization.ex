defmodule Cadence.Organizations.Organization do
  @moduledoc """
  Organization schema representing a tenant in the multi-tenant system.

  Each organization represents a separate customer/entity with their own missions,
  users, and isolated resources. Organizations have quotas and subscription tiers
  that control resource limits.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          slug: String.t(),
          status: String.t(),
          subscription_tier: String.t(),
          max_missions: integer(),
          max_targets_per_mission: integer(),
          max_users: integer(),
          storage_quota_gb: integer(),
          settings: map(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :subscription_tier, :string, default: "free"

    # Quotas and limits
    field :max_missions, :integer, default: 5
    field :max_targets_per_mission, :integer, default: 10
    field :max_users, :integer, default: 10
    field :storage_quota_gb, :integer, default: 10

    # Metadata
    field :settings, :map, default: %{}
    field :metadata, :map, default: %{}

    # Associations
    has_many :missions, Cadence.Missions.Mission
    has_many :organization_memberships, Cadence.Organizations.OrganizationMembership
    has_many :users, through: [:organization_memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new organization.
  """
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :name,
      :slug,
      :status,
      :subscription_tier,
      :max_missions,
      :max_targets_per_mission,
      :max_users,
      :storage_quota_gb,
      :settings,
      :metadata
    ])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
    |> validate_inclusion(:status, ["active", "suspended", "terminated"])
    |> validate_inclusion(:subscription_tier, ["free", "pro", "enterprise"])
    |> validate_number(:max_missions, greater_than: 0)
    |> validate_number(:max_targets_per_mission, greater_than: 0)
    |> validate_number(:max_users, greater_than: 0)
    |> validate_number(:storage_quota_gb, greater_than: 0)
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for updating organization settings.
  """
  def update_changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :name,
      :status,
      :subscription_tier,
      :max_missions,
      :max_targets_per_mission,
      :max_users,
      :storage_quota_gb,
      :settings,
      :metadata
    ])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["active", "suspended", "terminated"])
    |> validate_inclusion(:subscription_tier, ["free", "pro", "enterprise"])
    |> validate_number(:max_missions, greater_than: 0)
    |> validate_number(:max_targets_per_mission, greater_than: 0)
    |> validate_number(:max_users, greater_than: 0)
    |> validate_number(:storage_quota_gb, greater_than: 0)
  end
end
