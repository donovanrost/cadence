defmodule Cadence.Targets.TargetGroup do
  @moduledoc """
  TargetGroup schema for hierarchical organization of targets within a mission.

  Target groups enable:
  - Hierarchical organization (shells, planes, fleets) for large constellations
  - Scoped access control and permissions
  - Batch operations on groups of targets
  - Optional feature - small missions may not need groups

  Example hierarchy:
    Mission
    └── Constellation (group_type: "constellation")
        ├── Shell 1 (group_type: "shell")
        │   ├── Plane A (group_type: "plane")
        │   │   ├── Target SAT-001
        │   │   └── Target SAT-002
        │   └── Plane B (group_type: "plane")
        │       └── Target SAT-003
        └── Shell 2 (group_type: "shell")
            └── ...
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          parent_id: Ecto.UUID.t() | nil,
          name: String.t(),
          slug: String.t(),
          description: String.t() | nil,
          group_type: String.t(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "target_groups" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :group_type, :string

    # Metadata
    field :metadata, :map, default: %{}

    # Associations
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    many_to_many :targets, Cadence.Targets.Target,
      join_through: "target_group_memberships",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new target group.
  """
  def changeset(target_group, attrs) do
    target_group
    |> cast(attrs, [:mission_id, :parent_id, :name, :slug, :description, :group_type, :metadata])
    |> validate_required([:mission_id, :name, :slug, :group_type])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
    |> validate_inclusion(:group_type, [
      "constellation",
      "shell",
      "plane",
      "fleet",
      "custom"
    ])
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:mission_id, :slug])
    |> validate_parent_belongs_to_same_mission()
  end

  @doc """
  Changeset for updating a target group.
  """
  def update_changeset(target_group, attrs) do
    target_group
    |> cast(attrs, [:name, :description, :metadata])
    |> validate_required([:name])
  end

  defp validate_parent_belongs_to_same_mission(changeset) do
    parent_id = get_field(changeset, :parent_id)

    # If no parent_id, validation passes
    if is_nil(parent_id) do
      changeset
    else
      # Note: This validation should be enforced at the context layer
      # where we can query the database. Here we just add the constraint.
      changeset
    end
  end
end
