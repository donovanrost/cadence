defmodule Cadence.MissionDatabase.DefinitionSet do
  @moduledoc """
  A versioned, immutable snapshot of command and telemetry definitions.

  The DefinitionSet is the atomic unit of the Mission Database - a complete
  set of definitions for telemetry and commands at a specific version.

  ## Versioning Model

  - Each import creates a new DefinitionSet with a version string
  - Only one DefinitionSet can be active (published) at a time per mission
  - Published DefinitionSets are **immutable** - changes require a new version
  - `published_at` marks when a version became active
  - `superseded_at` marks when it was replaced by a newer version
  - Historical playback uses the version that was active at telemetry receipt time

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

      # Import a new version
      {:ok, definition_set} = YamlImporter.import(mission, "path/to/db.yaml", "1.0.0")

      # Publish it (makes it active)
      {:ok, definition_set} = DefinitionSet.publish(definition_set)

      # Query active version
      active = DefinitionSet.get_active(mission_id)
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_formats [:xtce, :cosmos, :eds, :yaml, :csv, :json]

  schema "mdb_definition_sets" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

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

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new DefinitionSet.
  """
  def changeset(definition_set, attrs) do
    definition_set
    |> cast(attrs, [
      :organization_id,
      :mission_id,
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
    |> validate_required([:organization_id, :mission_id, :version, :source_format])
    |> validate_inclusion(:source_format, @source_formats)
    |> validate_immutability()
    |> unique_constraint([:mission_id, :version],
      name: :mdb_definition_sets_mission_version_index,
      message: "Version already exists for this mission"
    )
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

  @doc """
  Gets the currently active DefinitionSet for a mission.
  Returns nil if no version is published.
  """
  def get_active(mission_id) do
    from(ds in __MODULE__,
      where: ds.mission_id == ^mission_id,
      where: not is_nil(ds.published_at),
      where: is_nil(ds.superseded_at),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets the DefinitionSet that was active at a specific point in time.
  Useful for historical playback with correct definitions.
  """
  def get_at_time(mission_id, %DateTime{} = timestamp) do
    from(ds in __MODULE__,
      where: ds.mission_id == ^mission_id,
      where: ds.published_at <= ^timestamp,
      where: is_nil(ds.superseded_at) or ds.superseded_at > ^timestamp,
      order_by: [desc: ds.published_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a specific version of DefinitionSet for a mission.
  """
  def get_by_version(mission_id, version) do
    from(ds in __MODULE__,
      where: ds.mission_id == ^mission_id,
      where: ds.version == ^version,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all DefinitionSets for a mission, ordered by creation time.
  """
  def list_for_mission(mission_id) do
    from(ds in __MODULE__,
      where: ds.mission_id == ^mission_id,
      order_by: [desc: ds.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Publishes a DefinitionSet, making it the active version.
  Supersedes any currently active version.
  """
  def publish(%__MODULE__{} = definition_set) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      # Supersede current active version if any
      case get_active(definition_set.mission_id) do
        nil ->
          :ok

        current_active ->
          current_active
          |> change(%{superseded_at: now})
          |> Repo.update!()
      end

      # Publish this version
      definition_set
      |> change(%{published_at: now})
      |> Repo.update!()
    end)
  end

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
            :units,
            :algorithms,
            :streams,
            {:data_types, [:default_calibrator, :unit, :context_calibrators, :context_alarms]},
            {:containers, [container_entries: :parameter]},
            {:parameters, [:data_type]},
            {:meta_commands, [:arguments, :transmission_constraints, :verifiers]}
          ])

        {:ok, loaded}
    end
  end

  @doc """
  Loads the active DefinitionSet for a mission with all associations.
  """
  def load_active_complete(mission_id) do
    case get_active(mission_id) do
      nil ->
        {:error, :no_active_definition_set}

      definition_set ->
        load_complete(definition_set.id)
    end
  end

  @doc """
  Returns true if this DefinitionSet is published (active or superseded).
  """
  def published?(%__MODULE__{published_at: nil}), do: false
  def published?(%__MODULE__{published_at: _}), do: true

  @doc """
  Returns true if this DefinitionSet is currently active.
  """
  def active?(%__MODULE__{published_at: nil}), do: false
  def active?(%__MODULE__{superseded_at: ts}) when not is_nil(ts), do: false
  def active?(%__MODULE__{published_at: _}), do: true

  @doc """
  Returns the list of valid source formats.
  """
  def valid_source_formats, do: @source_formats
end
