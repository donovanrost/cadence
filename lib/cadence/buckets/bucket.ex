defmodule Cadence.Buckets.Bucket do
  @moduledoc """
  Polymorphic container for grouping recordings.

  Buckets represent contexts like shifts, missions, or anomaly investigations.
  Recordings can optionally reference a bucket for access control and filtering.

  ## Bucket Types

  - `mission` - The mission itself as a bucket
  - `shift` - An operator shift period
  - `anomaly` - An anomaly investigation context
  - `target_group` - A group of targets for scoping

  ## Example

      %Bucket{
        bucket_type: "shift",
        bucketable_type: "Shift",
        bucketable_id: shift_id,
        name: "Alpha Shift",
        started_at: ~U[2025-01-15 08:00:00Z],
        ended_at: ~U[2025-01-15 16:00:00Z]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @bucket_types ["organization", "mission", "target_group", "target", "shift", "anomaly"]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t() | nil,
          parent_id: Ecto.UUID.t() | nil,
          path: String.t() | nil,
          bucket_type: String.t(),
          bucketable_type: String.t(),
          bucketable_id: Ecto.UUID.t(),
          name: String.t() | nil,
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "buckets" do
    field :bucket_type, :string
    field :bucketable_type, :string
    field :bucketable_id, :binary_id
    field :name, :string
    field :path, :string
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:organization_id, :bucket_type, :bucketable_type, :bucketable_id]
  @optional_fields [:mission_id, :parent_id, :path, :name, :started_at, :ended_at, :metadata]

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:bucket_type, @bucket_types)
    |> unique_constraint([:bucketable_type, :bucketable_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:parent_id)
  end

  def bucket_types, do: @bucket_types
end
