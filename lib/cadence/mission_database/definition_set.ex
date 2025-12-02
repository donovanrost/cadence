defmodule Cadence.MissionDatabase.DefinitionSet do
  @moduledoc """
  A versioned, immutable snapshot of command and telemetry definitions.

  The DefinitionSet is the atomic unit of the Mission Database - a complete
  set of definitions for telemetry and commands at a specific version.

  ## Database Catalog Model

  DefinitionSets belong to a Database (catalog entry) within a Mission.
  Different spacecraft platforms can have their own databases, and targets
  (spacecraft) reference specific DefinitionSet versions.

  Example for a constellation mission:

      Mission: PWSA
      └── Databases (Catalog):
          ├── "york-transport"
          │   ├── v1.0.0 → DefinitionSet
          │   └── v1.4.0 → DefinitionSet
          └── "lockheed-transport"
              └── v2.1.0 → DefinitionSet

      Targets:
          ├── YORK-001 → references york-transport v1.4.0
          ├── YORK-002 → references york-transport v1.4.0
          └── LM-001   → references lockheed-transport v2.1.0

  ## Versioning Model

  - Each import creates a new DefinitionSet with a version string
  - Published DefinitionSets are **immutable** - changes require a new version
  - `published_at` marks when a version became available for use
  - `superseded_at` can mark when a version was deprecated

  ## Contents

  A DefinitionSet contains:
  - **DataTypes** - Shared type definitions
  - **Units** - Unit of measure definitions
  - **Algorithms** - Calibrators and conversions
  - **Containers** - Telemetry packet structures
  - **Parameters** - Telemetry parameters
  - **MetaCommands** - Command definitions
  - **Streams** - Framing/protocol definitions

  ## Example

      # Import a new version to a database
      {:ok, definition_set} = YamlImporter.import(database, "path/to/db.yaml", "1.0.0")

      # Publish it (makes it available for targets to use)
      {:ok, definition_set} = DefinitionSet.publish(definition_set)

      # Assign to a target
      Target.assign_definition_set(target, definition_set)
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.MissionDatabase.Database

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_formats [:xtce, :cosmos, :eds, :yaml, :csv, :json]

  schema "mdb_definition_sets" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :database, Database

    field :name, :string
    field :version, :string
    field :description, :string

    # Source tracking
    field :source_format, Ecto.Enum, values: @source_formats
    field :source_filename, :string
    field :source_hash, :string

    # Lifecycle
    field :published_at, :utc_datetime
    field :superseded_at, :utc_datetime

    # Extensions
    field :extensions, :map, default: %{}

    # Associations
    has_many :data_types, Cadence.MissionDatabase.DataType
    has_many :units, Cadence.MissionDatabase.Unit
    has_many :algorithms, Cadence.MissionDatabase.Algorithm
    has_many :containers, Cadence.MissionDatabase.Container
    has_many :parameters, Cadence.MissionDatabase.Parameter
    has_many :meta_commands, Cadence.MissionDatabase.MetaCommand
    has_many :streams, Cadence.MissionDatabase.Stream

    # Targets using this definition set
    has_many :targets, Cadence.Targets.Target

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new DefinitionSet.
  """
  def changeset(definition_set, attrs) do
    definition_set
    |> cast(attrs, [
      :organization_id,
      :database_id,
      :name,
      :version,
      :description,
      :source_format,
      :source_filename,
      :source_hash,
      :published_at,
      :superseded_at,
      :extensions
    ])
    |> validate_required([:organization_id, :database_id, :version, :source_format])
    |> validate_inclusion(:source_format, @source_formats)
    |> validate_immutability()
    |> unique_constraint([:database_id, :version],
      name: :mdb_definition_sets_database_version_index,
      message: "Version already exists for this database"
    )
    |> foreign_key_constraint(:database_id)
    |> foreign_key_constraint(:organization_id)
  end

  # Validate that published DefinitionSets cannot be modified (except for lifecycle fields)
  defp validate_immutability(changeset) do
    if changeset.data.id && changeset.data.published_at do
      allowed_changes = [:published_at, :superseded_at]
      actual_changes = Map.keys(changeset.changes)
      forbidden_changes = actual_changes -- allowed_changes

      if Enum.empty?(forbidden_changes) do
        changeset
      else
        add_error(
          changeset,
          :base,
          "Published DefinitionSets are immutable. Create a new version instead."
        )
      end
    else
      changeset
    end
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Gets a DefinitionSet by ID.
  """
  def get(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets the latest published DefinitionSet for a database.
  Returns nil if no version is published.
  """
  def get_latest_published(database_id) do
    from(ds in __MODULE__,
      where: ds.database_id == ^database_id,
      where: not is_nil(ds.published_at),
      where: is_nil(ds.superseded_at),
      order_by: [desc: ds.published_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a specific version of DefinitionSet for a database.
  """
  def get_by_version(database_id, version) do
    from(ds in __MODULE__,
      where: ds.database_id == ^database_id,
      where: ds.version == ^version,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all DefinitionSets for a database, ordered by creation time.
  """
  def list_for_database(database_id) do
    from(ds in __MODULE__,
      where: ds.database_id == ^database_id,
      order_by: [desc: ds.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all published DefinitionSets for a database.
  """
  def list_published_for_database(database_id) do
    from(ds in __MODULE__,
      where: ds.database_id == ^database_id,
      where: not is_nil(ds.published_at),
      order_by: [desc: ds.published_at]
    )
    |> Repo.all()
  end

  # ===========================================================================
  # Publishing
  # ===========================================================================

  @doc """
  Publishes a DefinitionSet, making it available for targets to use.

  Multiple versions can be published simultaneously within a database.
  Targets explicitly choose which version to use.
  """
  def publish(%__MODULE__{} = definition_set) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    definition_set
    |> change(%{published_at: now})
    |> Repo.update()
  end

  @doc """
  Marks a DefinitionSet as deprecated.
  Deprecated versions can still be used by targets but shouldn't be assigned to new ones.
  """
  def deprecate(%__MODULE__{} = definition_set) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    definition_set
    |> change(%{superseded_at: now})
    |> Repo.update()
  end

  # ===========================================================================
  # Loading
  # ===========================================================================

  @doc """
  Loads a complete DefinitionSet with all associations.
  """
  def load_complete(definition_set_id) do
    case Repo.get(__MODULE__, definition_set_id) do
      nil ->
        {:error, :not_found}

      definition_set ->
        loaded =
          definition_set
          |> Repo.preload([
            :database,
            :units,
            :algorithms,
            :streams,
            {:data_types, [:default_calibrator, :unit, :context_calibrators, :context_alarms]},
            {:containers, [container_entries: [parameter: [data_type: :unit]]]},
            {:parameters, [data_type: :unit]},
            {:meta_commands, [:arguments, :transmission_constraints, :verifiers]}
          ])

        {:ok, loaded}
    end
  end

  # ===========================================================================
  # Predicates
  # ===========================================================================

  @doc """
  Returns true if this DefinitionSet is published (active or superseded).
  """
  def published?(%__MODULE__{published_at: nil}), do: false
  def published?(%__MODULE__{published_at: _}), do: true

  @doc """
  Returns true if this DefinitionSet is deprecated.
  """
  def deprecated?(%__MODULE__{superseded_at: nil}), do: false
  def deprecated?(%__MODULE__{superseded_at: _}), do: true

  @doc """
  Returns true if this DefinitionSet is currently active (published but not deprecated).
  """
  def active?(%__MODULE__{published_at: nil}), do: false
  def active?(%__MODULE__{superseded_at: ts}) when not is_nil(ts), do: false
  def active?(%__MODULE__{published_at: _}), do: true

  @doc """
  Returns the list of valid source formats.
  """
  def valid_source_formats, do: @source_formats
end
