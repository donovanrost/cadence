defmodule Cadence.Telemetry.Database.DefinitionSet do
  @moduledoc """
  Represents a versioned set of command and telemetry definitions.

  A DefinitionSet is the **atomic unit** of the C&T database - a snapshot containing
  both telemetry packets and command definitions at a specific version. This ensures
  commands and telemetry are always consistent and versioned together.

  ## Versioning Model

  - Each import creates a new DefinitionSet with a version string
  - Only one DefinitionSet can be active (published) at a time per mission
  - Published DefinitionSets are **immutable** - changes require a new version
  - `published_at` marks when a version became active
  - `superseded_at` marks when it was replaced by a newer version
  - Historical playback uses the version that was active at telemetry receipt time

  ## Contents

  A DefinitionSet contains:
  - **PacketDefinitions** - Telemetry packet structures and items
  - **CommandDefinitions** - Command structures and parameters

  Note: Derived items are stored separately as a mission-scoped runtime overlay
  (see `Cadence.Telemetry.Database.DerivedItem`).

  ## Example

      # Import a new version (telemetry + commands)
      {:ok, definition_set} = YamlImporter.import(mission_id, "path/to/db.yaml", "1.0.0")

      # Publish it (makes it active)
      {:ok, definition_set} = DefinitionSet.publish(definition_set)

      # Query active version
      active = DefinitionSet.get_active(mission_id)

      # Load complete set (packets + commands)
      {:ok, complete} = DefinitionSet.load_complete(definition_set.id)

      # Query version at a specific time
      historical = DefinitionSet.get_at_time(mission_id, ~U[2024-06-15 12:00:00Z])
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Missions.Mission
  alias Cadence.Telemetry.Packet.PacketDefinition
  alias Cadence.Commands.CommandDefinition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_formats ["yaml", "xtce", "cosmos", "csv"]

  schema "definition_sets" do
    belongs_to :mission, Mission

    field :version, :string
    field :description, :string

    # Source tracking
    field :source_format, :string
    field :source_filename, :string
    field :source_hash, :string

    # Lifecycle timestamps
    field :published_at, :utc_datetime
    field :superseded_at, :utc_datetime

    # Associations - unified C&T database
    has_many :packet_definitions, PacketDefinition
    has_many :command_definitions, CommandDefinition

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new DefinitionSet.
  """
  def changeset(definition_set, attrs) do
    definition_set
    |> cast(attrs, [
      :mission_id,
      :version,
      :description,
      :source_format,
      :source_filename,
      :source_hash,
      :published_at,
      :superseded_at
    ])
    |> validate_required([:mission_id, :version, :source_format])
    |> validate_inclusion(:source_format, @source_formats)
    |> validate_immutability()
    |> unique_constraint([:mission_id, :version],
      message: "Version already exists for this mission"
    )
  end

  # Validate that published DefinitionSets cannot be modified (except for lifecycle fields)
  defp validate_immutability(changeset) do
    # Only check on updates to existing records
    if changeset.data.id && changeset.data.published_at do
      # Published sets can only have lifecycle fields updated
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

  After publishing, broadcasts a notification on the mission's PubSub topic
  so that runtime components (PacketIdentifier, etc.) can reload definitions.
  """
  def publish(%__MODULE__{} = definition_set) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
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

    # Broadcast notification on success
    case result do
      {:ok, published_set} ->
        broadcast_definition_set_change(published_set)
        {:ok, published_set}

      error ->
        error
    end
  end

  @doc """
  Broadcasts a notification that the active DefinitionSet has changed.

  Runtime components can subscribe to `mission:<mission_id>:definition_set:changed`
  to receive notifications when they need to reload definitions.
  """
  def broadcast_definition_set_change(%__MODULE__{} = definition_set) do
    topic = "mission:#{definition_set.mission_id}:definition_set:changed"

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:definition_set_changed, definition_set.id, definition_set.version}
    )
  end

  @doc """
  Subscribes to DefinitionSet change notifications for a mission.
  """
  def subscribe_to_changes(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:definition_set:changed")
  end

  @doc """
  Returns the list of valid source formats.
  """
  def valid_source_formats, do: @source_formats

  @doc """
  Loads a complete DefinitionSet with all associations (packets, commands, items).

  This function atomically loads the entire C&T database for efficient runtime use.
  The result includes:

  - `packet_definitions` with nested `packet_items` and `conversions`
  - `command_definitions` with nested `command_parameters`

  ## Example

      {:ok, complete} = DefinitionSet.load_complete(definition_set_id)
      # => %DefinitionSet{
      #      packet_definitions: [%PacketDefinition{packet_items: [...]}],
      #      command_definitions: [%CommandDefinition{command_parameters: [...]}]
      #    }
  """
  def load_complete(definition_set_id) do
    case Repo.get(__MODULE__, definition_set_id) do
      nil ->
        {:error, :not_found}

      definition_set ->
        loaded =
          definition_set
          |> Repo.preload(
            packet_definitions: [packet_items: [:conversion]],
            command_definitions: [:command_parameters]
          )

        {:ok, loaded}
    end
  end

  @doc """
  Loads the active DefinitionSet for a mission with all associations.

  Combines `get_active/1` and `load_complete/1` for convenience.
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
  Returns summary statistics for a DefinitionSet.
  """
  def get_stats(definition_set_id) do
    packet_count =
      from(p in PacketDefinition, where: p.definition_set_id == ^definition_set_id, select: count())
      |> Repo.one()

    command_count =
      from(c in CommandDefinition, where: c.definition_set_id == ^definition_set_id, select: count())
      |> Repo.one()

    %{
      packet_count: packet_count || 0,
      command_count: command_count || 0,
      total_definitions: (packet_count || 0) + (command_count || 0)
    }
  end
end
