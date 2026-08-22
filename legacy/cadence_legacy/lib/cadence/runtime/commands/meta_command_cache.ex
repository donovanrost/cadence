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

  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Runtime.Telemetry.ConfigBundle

  @table_name :meta_command_cache

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :table_name,
      commands_loaded: 0,
      definition_sets_loaded: []
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
    table = table_name()

    if :ets.whereis(table) == :undefined do
      {:error, :cache_not_available}
    else
      case :ets.lookup(table, {mission_id, definition_set_id, command_name}) do
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
    table = table_name()

    if :ets.whereis(table) == :undefined do
      {:error, :cache_not_available}
    else
      case :ets.lookup(table, {mission_id, definition_set_id, :opcode, opcode}) do
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
    table = table_name()

    # Use match spec to find all commands for this definition_set (by name key only)
    :ets.match_object(table, {{mission_id, definition_set_id, :_}, :_})
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
    table_name = table_name()

    Logger.debug("Starting MetaCommandCache for mission_id=#{mission_id}")

    if :ets.whereis(table_name) == :undefined do
      Logger.info("Creating MetaCommand cache table: #{table_name}")

      # Create ETS table for fast lookups
      _table =
        :ets.new(table_name, [
          :set,
          :named_table,
          :public,
          read_concurrency: true
        ])
    end

    # Subscribe to config updates and target changes
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:config")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:targets")

    state = %State{
      mission_id: mission_id,
      table_name: table_name
    }

    # Load commands for all definition_sets provided by config bundle
    state = load_all_definition_sets(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    new_state = load_all_definition_sets(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    table_entries = mission_entry_count(state.table_name, state.mission_id)

    stats = %{
      mission_id: state.mission_id,
      commands_loaded: state.commands_loaded,
      definition_sets_loaded: length(state.definition_sets_loaded),
      table_size: table_entries
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:config_updated, _version}, state) do
    Logger.debug("Config updated for mission_id=#{state.mission_id}, reloading MetaCommand cache")
    {:noreply, load_all_definition_sets(state)}
  end

  def handle_info({:target_created, target}, state) do
    # New target added - ensure its definition_set is loaded
    if target.definition_set_id do
      if target.definition_set_id in state.definition_sets_loaded do
        {:noreply, state}
      else
        Logger.debug("Target created with new definition_set, loading commands")

        {:noreply, load_all_definition_sets(state)}
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

  def handle_info(msg, state) do
    Logger.warning("MetaCommandCache received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("Stopping MetaCommandCache for mission_id=#{state.mission_id}")
    Logger.info("Terminating MetaCommand cache table: #{state.table_name}")
    :ets.delete(state.table_name)
    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :meta_command_cache}}}
  end

  defp table_name, do: @table_name

  # Load commands for all definition_sets provided by config bundle
  defp load_all_definition_sets(state) do
    case ConfigBundle.fetch(state.mission_id) do
      {:ok, bundle} ->
        delete_mission_entries(state.table_name, state.mission_id)

        command_defs = Map.get(bundle, :command_defs, %{})
        definition_set_ids = Map.keys(command_defs)

        Logger.info(
          "Loading MetaCommands for #{length(definition_set_ids)} definition_sets " <>
            "in mission_id=#{state.mission_id}"
        )

        total_commands =
          Enum.reduce(definition_set_ids, 0, fn definition_set_id, acc ->
            commands = Map.get(command_defs, definition_set_id, [])

            count =
              load_for_definition_set(
                state.table_name,
                state.mission_id,
                definition_set_id,
                commands
              )

            acc + count
          end)

        Logger.info(
          "MetaCommandCache loaded #{total_commands} commands from " <>
            "#{length(definition_set_ids)} definition_sets for mission_id=#{state.mission_id}"
        )

        %{
          state
          | commands_loaded: total_commands,
            definition_sets_loaded: definition_set_ids
        }

      {:error, _} ->
        state
    end
  end

  # Load commands for a specific definition_set with all associations preloaded
  defp load_for_definition_set(table_name, mission_id, definition_set_id, commands)
       when is_list(commands) do
    delete_definition_set_entries(table_name, mission_id, definition_set_id)

    Enum.each(commands, fn cmd ->
      # Index by name
      :ets.insert(table_name, {{mission_id, definition_set_id, cmd.name}, cmd})

      # Also index by opcode for binary protocol lookup
      if cmd.opcode do
        :ets.insert(table_name, {{mission_id, definition_set_id, :opcode, cmd.opcode}, cmd})
      end
    end)

    Logger.debug("Loaded #{length(commands)} commands for definition_set=#{definition_set_id}")

    length(commands)
  end

  defp delete_mission_entries(table_name, mission_id) do
    :ets.match_delete(table_name, {{mission_id, :_, :_}, :_})
    :ets.match_delete(table_name, {{mission_id, :_, :_, :_}, :_})
  end

  defp delete_definition_set_entries(table_name, mission_id, definition_set_id) do
    :ets.match_delete(table_name, {{mission_id, definition_set_id, :_}, :_})
    :ets.match_delete(table_name, {{mission_id, definition_set_id, :_, :_}, :_})
  end

  defp mission_entry_count(table_name, mission_id) do
    :ets.select_count(table_name, [
      {{{mission_id, :_, :_}, :_}, [], [true]},
      {{{mission_id, :_, :_, :_}, :_}, [], [true]}
    ])
  end
end
