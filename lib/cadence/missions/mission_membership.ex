defmodule Cadence.Missions.MissionMembership do
  @moduledoc """
  MissionMembership schema representing a user's role within a specific mission.

  Users can have different roles in different missions within the same organization:
  - viewer: Read-only access to telemetry and mission data
  - operator: Can view telemetry and send commands
  - engineer: Can modify mission configuration and definitions
  - admin: Full control over the mission including user management
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          role: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "mission_memberships" do
    field :role, :string, default: "viewer"

    # Associations
    belongs_to :user, Cadence.Accounts.User
    belongs_to :mission, Cadence.Missions.Mission

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new mission membership.
  """
  def changeset(mission_membership, attrs) do
    mission_membership
    |> cast(attrs, [:user_id, :mission_id, :role])
    |> validate_required([:user_id, :mission_id, :role])
    |> validate_inclusion(:role, ["viewer", "operator", "engineer", "admin"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:mission_id)
    |> unique_constraint([:user_id, :mission_id])
  end

  @doc """
  Changeset for updating a user's role in a mission.
  """
  def update_role_changeset(mission_membership, attrs) do
    mission_membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, ["viewer", "operator", "engineer", "admin"])
  end
end
