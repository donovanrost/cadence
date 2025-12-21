defmodule Cadence.Buckets.BucketMembership do
  @moduledoc """
  User membership in a bucket with access control.

  Bucket memberships define what users can do within a bucket context,
  including command authority scoping.

  ## Roles

  - `operator` - Can execute commands within scope
  - `supervisor` - Can execute commands and manage operators
  - `observer` - View-only access

  ## Command Authority

  The `can_command` field and associated scoping fields control what
  commands a user can execute:

  - `can_command` - Whether the user can execute commands at all
  - `max_hazard_level` - Maximum hazard level they can execute (0-5)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Buckets.Bucket
  alias Cadence.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ["operator", "supervisor", "observer"]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          bucket_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          role: String.t(),
          can_command: boolean(),
          max_hazard_level: integer() | nil,
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "bucket_memberships" do
    field :role, :string
    field :can_command, :boolean, default: false
    field :max_hazard_level, :integer
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :bucket, Bucket
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:bucket_id, :user_id, :role]
  @optional_fields [:can_command, :max_hazard_level, :started_at, :ended_at]

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> validate_number(:max_hazard_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> unique_constraint([:bucket_id, :user_id],
      name: :bucket_memberships_active_unique,
      message: "user already has an active membership in this bucket"
    )
    |> foreign_key_constraint(:bucket_id)
    |> foreign_key_constraint(:user_id)
  end

  def roles, do: @roles
end
