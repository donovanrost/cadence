defmodule Cadence.Runtime.Commands.MetaCommandCache do
  @moduledoc """
  ETS-based cache for MetaCommand definitions.

  Part of the Data Plane - provides O(1) command lookup during dispatch.
  Scoped by definition_set_id to support constellation missions with
  multiple spacecraft platforms.

  ## Cache Structure

  - Key: `{definition_set_id, command_name}` or `{definition_set_id, :opcode, opcode}`
  - Value: MetaCommand struct with arguments, verifiers, and constraints preloaded

  ## Lifecycle

  1. Started as child of MissionInstance
  2. Loads all commands for all definition_sets used by mission targets
  3. Subscribes to PubSub for definition_set changes
  4. Hot-reloads on `:definition_set_changed` events
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Cadence.Config.VersionRegistry
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Repo

  @table_prefix :meta_command_cache

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :table_name,
      commands_loaded: 0,
      definition_sets_loaded: [],
      # Track version per definition_set for cache invalidation
      definition_set_versions: %{}
    ]
  end

  ## Client API

  @doc """
  Starts the MetaCommand cache for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Looks up a command by name for a given definition_set.
  Returns {:ok, command} or {:error, :not_found}.
  O(1) ETS lookup - no database call.

  If the ETS table doesn't exist (e.g., MissionInstance not running), returns
  {:error, :cache_not_available} to signal the caller should fall back to DB.
  """
  @spec get_by_name(String.t(), String.t(), String.t()) ::
          {:ok, MetaCommand.t()} | {:error, :not_found | :cache_not_available}
  def get_by_name(mission_id, definition_set_id, command_name) do
    table = table_name(mission_id)

    if :ets.whereis(table) == :undefined do
      {:error, :cache_not_available}
    else
      case :ets.lookup(table, {definition_set_id, command_name}) do
        [{_, command}] -> {:ok, command}
        [] -> {:error, :not_found}
      end
    end
  end

  @doc """
  Looks up a command by opcode for a given definition_set.

  If the ETS table doesn't exist (e.g., MissionInstance not running), returns
  {:error, :cache_not_available} to signal the caller should fall back to DB.
  """
  @spec get_by_opcode(String.t(), String.t(), integer()) ::
          {:ok, MetaCommand.t()} | {:error, :not_found | :cache_not_available}
  def get_by_opcode(mission_id, definition_set_id, opcode) do
    table = table_name(mission_id)

    if :ets.whereis(table) == :undefined do
      {:error, :cache_not_available}
    else
      case :ets.lookup(table, {definition_set_id, :opcode, opcode}) do
        [{_, command}] -> {:ok, command}
        [] -> {:error, :not_found}
      end
    end
  end

  @doc """
  Lists all commands for a definition_set.
  """
  @spec list_for_definition_set(String.t(), String.t()) :: [MetaCommand.t()]
  def list_for_definition_set(mission_id, definition_set_id) do
    table = table_name(mission_id)

    # Use match spec to find all commands for this definition_set (by name key only)
    :ets.match_object(table, {{definition_set_id, :_}, :_})
    |> Enum.reject(fn {{ds_id, key}, _} ->
      # Exclude opcode entries (they have tuple keys like {:opcode, n})
      ds_id == definition_set_id and is_tuple(key)
    end)
    |> Enum.map(fn {_key, command} -> command end)
  end

  @doc """
  Reloads commands from the database.
  """
  def reload(mission_id) do
    GenServer.call(via_tuple(mission_id), :reload)
  end

  @doc """
  Returns statistics about loaded commands.
  """
  def stats(mission_id) do
    GenServer.call(via_tuple(mission_id), :stats)
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    table_name = table_name(mission_id)

    Logger.info("Creating MetaCommand cache table: #{table_name} for mission_id=#{mission_id}")

    # Create ETS table for fast lookups
    _table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true
      ])

    # Subscribe to definition_set and target changes
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:definition_set")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:targets")

    state = %State{
      mission_id: mission_id,
      table_name: table_name
    }

    # Load commands for all definition_sets used by mission targets
    state = load_all_definition_sets(state)

    # Subscribe to version invalidation for each loaded definition_set
    Enum.each(state.definition_sets_loaded, fn ds_id ->
      Phoenix.PubSub.subscribe(
        Cadence.PubSub,
        VersionRegistry.topic_for(:definition_set, ds_id)
      )
    end)

    {:ok, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    new_state = load_all_definition_sets(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      commands_loaded: state.commands_loaded,
      definition_sets_loaded: length(state.definition_sets_loaded),
      table_size: :ets.info(state.table_name, :size)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:definition_set_changed, definition_set_id, version}, state) do
    Logger.info(
      "DefinitionSet changed to #{version} (#{definition_set_id}) for mission_id=#{state.mission_id}, " <>
        "reloading MetaCommand cache"
    )

    new_state = load_all_definition_sets(state)
    {:noreply, new_state}
  end

  def handle_info({:target_definition_set_changed, target_id, definition_set_id}, state) do
    Logger.info(
      "Target #{target_id} changed to definition_set #{definition_set_id}, " <>
        "ensuring commands are cached"
    )

    # Only load this specific definition_set if not already loaded
    if definition_set_id in state.definition_sets_loaded do
      {:noreply, state}
    else
      count = load_for_definition_set(state.table_name, definition_set_id)

      Logger.info("Loaded #{count} commands for new definition_set=#{definition_set_id}")

      new_state = %{
        state
        | commands_loaded: state.commands_loaded + count,
          definition_sets_loaded: [definition_set_id | state.definition_sets_loaded]
      }

      {:noreply, new_state}
    end
  end

  def handle_info({:target_created, target}, state) do
    # New target added - ensure its definition_set is loaded
    if target.definition_set_id do
      if target.definition_set_id in state.definition_sets_loaded do
        {:noreply, state}
      else
        Logger.debug("Target created with new definition_set, loading commands")
        count = load_for_definition_set(state.table_name, target.definition_set_id)

        new_state = %{
          state
          | commands_loaded: state.commands_loaded + count,
            definition_sets_loaded: [target.definition_set_id | state.definition_sets_loaded]
        }

        {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  # Handle generic target update events
  def handle_info({:target_updated, _target}, state) do
    {:noreply, state}
  end

  def handle_info({:target_deleted, _target}, state) do
    {:noreply, state}
  end

  # Handle version invalidation from VersionRegistry
  def handle_info({:config_invalidated, :definition_set, definition_set_id, new_version}, state) do
    current_version = Map.get(state.definition_set_versions, definition_set_id, 0)

    if new_version > current_version do
      Logger.info(
        "Config version changed for definition_set=#{definition_set_id} " <>
          "(#{current_version} -> #{new_version}), reloading MetaCommandCache"
      )

      # Reload just this definition_set
      count = load_for_definition_set(state.table_name, definition_set_id)

      new_versions = Map.put(state.definition_set_versions, definition_set_id, new_version)

      Logger.info("Reloaded #{count} commands for definition_set=#{definition_set_id}")

      {:noreply, %{state | definition_set_versions: new_versions}}
    else
      {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.warning("MetaCommandCache received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Terminating MetaCommand cache table: #{state.table_name}")
    :ets.delete(state.table_name)
    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :meta_command_cache}}}
  end

  defp table_name(mission_id) when is_binary(mission_id) do
    String.to_atom("#{@table_prefix}_#{mission_id}")
  end

  # Load commands for all definition_sets used by mission targets
  defp load_all_definition_sets(state) do
    # Clear existing entries
    :ets.delete_all_objects(state.table_name)

    # Get all unique definition_set_ids used by targets in this mission
    definition_set_ids = get_mission_definition_set_ids(state.mission_id)

    Logger.info(
      "Loading MetaCommands for #{length(definition_set_ids)} definition_sets " <>
        "in mission_id=#{state.mission_id}"
    )

    # Load commands for each definition_set and track versions
    {total_commands, versions} =
      Enum.reduce(definition_set_ids, {0, %{}}, fn definition_set_id, {acc, vers} ->
        count = load_for_definition_set(state.table_name, definition_set_id)
        version = VersionRegistry.get_version(:definition_set, definition_set_id)
        {acc + count, Map.put(vers, definition_set_id, version)}
      end)

    Logger.info(
      "MetaCommandCache loaded #{total_commands} commands from " <>
        "#{length(definition_set_ids)} definition_sets for mission_id=#{state.mission_id}"
    )

    %{
      state
      | commands_loaded: total_commands,
        definition_sets_loaded: definition_set_ids,
        definition_set_versions: versions
    }
  end

  # Gets all unique definition_set_ids used by targets in this mission
  defp get_mission_definition_set_ids(mission_id) do
    Cadence.Targets.Target
    |> where([t], t.mission_id == ^mission_id)
    |> where([t], not is_nil(t.definition_set_id))
    |> select([t], t.definition_set_id)
    |> distinct(true)
    |> Repo.all()
  end

  # Load commands for a specific definition_set with all associations preloaded
  defp load_for_definition_set(table_name, definition_set_id) do
    commands =
      MetaCommand
      |> where([mc], mc.definition_set_id == ^definition_set_id)
      |> where([mc], mc.abstract == false or is_nil(mc.abstract))
      |> preload([:arguments, :verifiers, :transmission_constraints, :command_container])
      |> Repo.all()

    Enum.each(commands, fn cmd ->
      # Index by name
      :ets.insert(table_name, {{definition_set_id, cmd.name}, cmd})

      # Also index by opcode for binary protocol lookup
      if cmd.opcode do
        :ets.insert(table_name, {{definition_set_id, :opcode, cmd.opcode}, cmd})
      end
    end)

    Logger.debug("Loaded #{length(commands)} commands for definition_set=#{definition_set_id}")

    length(commands)
  end
end
