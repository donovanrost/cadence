defmodule Cadence.Databases do
  @moduledoc """
  Context for managing telemetry database definition sets.

  Provides functions for listing, creating, publishing, and deleting
  versioned telemetry databases for missions.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Missions.Mission
  alias Cadence.Telemetry.Database.DefinitionSet
  alias Cadence.Telemetry.Database.YamlImporter

  @doc """
  Lists all definition sets for a mission, ordered by creation date (newest first).
  """
  def list_definition_sets(%Mission{id: mission_id}) do
    list_definition_sets(mission_id)
  end

  def list_definition_sets(mission_id) when is_binary(mission_id) do
    from(ds in DefinitionSet,
      where: ds.mission_id == ^mission_id,
      order_by: [desc: ds.inserted_at],
      preload: [packet_definitions: :packet_items]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single definition set by ID.
  Raises if not found.
  """
  def get_definition_set!(id) do
    DefinitionSet
    |> Repo.get!(id)
    |> Repo.preload(packet_definitions: :packet_items)
  end

  @doc """
  Gets a definition set by ID, returns nil if not found.
  """
  def get_definition_set(id) do
    case Repo.get(DefinitionSet, id) do
      nil -> nil
      ds -> Repo.preload(ds, packet_definitions: :packet_items)
    end
  end

  @doc """
  Gets the active definition set for a mission.
  """
  def get_active_definition_set(%Mission{id: mission_id}) do
    get_active_definition_set(mission_id)
  end

  def get_active_definition_set(mission_id) when is_binary(mission_id) do
    DefinitionSet.get_active(mission_id)
  end

  @doc """
  Imports a YAML string and creates a new definition set.

  Returns `{:ok, definition_set}` or `{:error, reason}`.
  """
  def import_yaml(%Mission{} = mission, yaml_content, opts \\ []) do
    YamlImporter.import_string(mission, yaml_content, opts)
  end

  @doc """
  Imports a YAML file and creates a new definition set.

  Returns `{:ok, definition_set}` or `{:error, reason}`.
  """
  def import_yaml_file(%Mission{} = mission, file_path, opts \\ []) do
    YamlImporter.import_file(mission, file_path, opts)
  end

  @doc """
  Publishes a definition set, making it the active version.
  Supersedes any currently active version for the mission.

  Returns `{:ok, definition_set}` or `{:error, reason}`.
  """
  def publish_definition_set(%DefinitionSet{} = definition_set) do
    DefinitionSet.publish(definition_set)
  end

  @doc """
  Deletes a definition set.
  Only unpublished (never activated) versions can be deleted.

  Returns `{:ok, definition_set}` or `{:error, changeset}`.
  """
  def delete_definition_set(%DefinitionSet{published_at: nil} = definition_set) do
    Repo.delete(definition_set)
  end

  def delete_definition_set(%DefinitionSet{}) do
    {:error, :cannot_delete_published}
  end

  @doc """
  Returns stats for a definition set (packet count, item count).
  """
  def definition_set_stats(%DefinitionSet{} = definition_set) do
    definition_set = Repo.preload(definition_set, packet_definitions: :packet_items)

    packet_count = length(definition_set.packet_definitions)

    item_count =
      definition_set.packet_definitions
      |> Enum.map(fn pd -> length(pd.packet_items) end)
      |> Enum.sum()

    %{
      packet_count: packet_count,
      item_count: item_count
    }
  end

  @doc """
  Checks if a definition set is the currently active one.
  """
  def is_active?(%DefinitionSet{published_at: nil}), do: false
  def is_active?(%DefinitionSet{superseded_at: superseded}) when not is_nil(superseded), do: false
  def is_active?(%DefinitionSet{}), do: true

  @doc """
  Returns a changeset for creating a new definition set.
  Used primarily for form validation.
  """
  def change_definition_set(%DefinitionSet{} = definition_set, attrs \\ %{}) do
    DefinitionSet.changeset(definition_set, attrs)
  end
end
