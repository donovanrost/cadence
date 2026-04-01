defmodule Cadence.MissionDatabase.Database do
  @moduledoc """
  A database is a named container for versioned command and telemetry definitions.

  Databases are mission-scoped and contain multiple versioned DefinitionSets.
  This allows different spacecraft platforms (e.g., from different vendors or
  hardware revisions) within a mission to each have their own database with
  tracked versions.

  ## Example

  A constellation mission might have:

      Mission: PWSA
      └── Databases (the "Catalog"):
          ├── "york-transport" (York Space transport layer satellites)
          │   ├── v1.0.0
          │   ├── v1.2.0
          │   └── v1.4.0
          ├── "lockheed-transport" (Lockheed transport layer)
          │   └── v2.1.0
          └── "l3harris-tracking" (L3Harris tracking layer)
              └── v1.0.0

  Each Target (spacecraft) references a specific DefinitionSet version.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.MissionDatabase.DefinitionSet
  alias Cadence.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "databases" do
    belongs_to :mission, Cadence.Missions.Mission

    field :name, :string
    field :slug, :string
    field :description, :string
    field :metadata, :map, default: %{}

    has_many :definition_sets, DefinitionSet

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a database.
  """
  def changeset(database, attrs) do
    database
    |> cast(attrs, [:mission_id, :name, :slug, :description, :metadata])
    |> validate_required([:mission_id, :name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must be lowercase alphanumeric with hyphens (e.g., 'york-transport')"
    )
    |> validate_length(:slug, min: 2, max: 100)
    |> unique_constraint([:mission_id, :slug])
    |> foreign_key_constraint(:mission_id)
  end

  @doc """
  Generates a slug from a name.
  """
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.replace(~r/^-|-$/, "")
    |> String.slice(0, 100)
  end

  @doc """
  Lists all databases for a mission.
  """
  def list_for_mission(mission_id) do
    from(d in __MODULE__,
      where: d.mission_id == ^mission_id,
      order_by: [asc: d.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a database by mission and slug.
  """
  def get_by_slug(mission_id, slug) do
    from(d in __MODULE__,
      where: d.mission_id == ^mission_id,
      where: d.slug == ^slug
    )
    |> Repo.one()
  end

  @doc """
  Gets a database by ID.
  """
  def get(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Creates a new database.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a database.
  """
  def update(%__MODULE__{} = database, attrs) do
    database
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a database and all its definition sets.
  """
  def delete(%__MODULE__{} = database) do
    Repo.delete(database)
  end

  @doc """
  Loads a database with its definition sets.
  """
  def with_definition_sets(%__MODULE__{} = database) do
    Repo.preload(database,
      definition_sets:
        from(ds in DefinitionSet,
          order_by: [desc: ds.inserted_at]
        )
    )
  end

  @doc """
  Returns the latest published definition set for a database.
  """
  def latest_published(%__MODULE__{id: id}) do
    DefinitionSet.get_latest_published(id)
  end

  @doc """
  Returns the count of definition sets for a database.
  """
  def version_count(%__MODULE__{id: id}) do
    from(ds in DefinitionSet,
      where: ds.database_id == ^id,
      select: count(ds.id)
    )
    |> Repo.one()
  end
end
