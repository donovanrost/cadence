defmodule Cadence.Runtime.Interfaces.InterfaceSupervisor do
  @moduledoc """
  Supervisor that manages all interface processes for a mission.

  ## Data Plane Architecture

  This supervisor loads interface domain entities ONCE at startup and injects
  them into GenServers. No database calls happen during runtime operation.

  When a mission starts, this supervisor:
  1. Loads all interface entities with protocols preloaded
  2. Starts the appropriate interface GenServer for each (TcpClientInterface, etc.)
  3. Monitors interface health and handles crashes
  4. Subscribes to config change events for hot reload

  Each interface process is registered in the MissionRegistry with the key:
  `{:interface, mission_id, interface_id}`

  ## Hot Reload

  The supervisor subscribes to `mission:{mission_id}:interface_config` and
  handles the following events:
  - `:interface_created` - Start a new interface GenServer
  - `:interface_updated` - Restart interface with new config
  - `:interface_deleted` - Stop the interface GenServer
  - `:interface_protocols_updated` - Restart interface with new protocols

  ## Example

      # Started by MissionInstance supervision tree
      {:ok, pid} = InterfaceSupervisor.start_link(mission_id: mission_id)

      # Dynamically add a new interface (with domain entity)
      InterfaceSupervisor.start_interface(mission_id, interface_entity)

      # Stop an interface
      InterfaceSupervisor.stop_interface(mission_id, interface_id)
  """

  use GenServer
  require Logger

  alias Cadence.Application.Interfaces.InterfaceQueries
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.Factory

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [:mission_id, :dynamic_sup]
  end

  ## Client API

  @doc """
  Starts the InterfaceSupervisor for a mission.

  Automatically loads and starts all interfaces for the mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Starts a specific interface using its domain entity.

  The entity should be fully loaded with protocols. No database lookups
  are performed - the entity IS the configuration.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_interface(mission_id, %Interface{} = interface) do
    GenServer.call(via_tuple(mission_id), {:start_interface, interface})
  end

  @doc """
  Starts a specific interface by ID, loading it from the database.

  This is a convenience function for cases where the entity is not
  already loaded. For hot reload scenarios, prefer `start_interface/2`
  with a pre-loaded entity.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_interface_by_id(mission_id, interface_id) do
    case InterfaceQueries.find_with_protocols(interface_id) do
      {:ok, interface} ->
        start_interface(mission_id, interface)

      {:error, :not_found} ->
        {:error, :interface_not_found}
    end
  end

  @doc """
  Stops a specific interface for a mission.

  Returns `:ok` or `{:error, :not_found}`.
  """
  def stop_interface(mission_id, interface_id) do
    GenServer.call(via_tuple(mission_id), {:stop_interface, interface_id})
  end

  @doc """
  Lists all running interface PIDs for a mission.
  """
  def list_interfaces(mission_id) do
    GenServer.call(via_tuple(mission_id), :list_interfaces)
  end

  @doc """
  Restarts an interface with a new entity (stop and start).

  Used for hot reload when configuration changes.
  """
  def restart_interface(mission_id, %Interface{} = interface) do
    GenServer.call(via_tuple(mission_id), {:restart_interface, interface})
  end

  @doc """
  Restarts an interface by ID, reloading from database.

  Convenience function for manual restarts.
  """
  def restart_interface_by_id(mission_id, interface_id) do
    case InterfaceQueries.find_with_protocols(interface_id) do
      {:ok, interface} ->
        restart_interface(mission_id, interface)

      {:error, :not_found} ->
        {:error, :interface_not_found}
    end
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting InterfaceSupervisor for mission #{mission_id}")

    # Start a DynamicSupervisor for managing interface children
    {:ok, dynamic_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    # Subscribe to interface config changes for hot reload
    topic = "mission:#{mission_id}:interface_config"
    Phoenix.PubSub.subscribe(Cadence.PubSub, topic)
    Logger.debug("Subscribed to #{topic} for interface hot reload")

    state = %State{
      mission_id: mission_id,
      dynamic_sup: dynamic_sup
    }

    # Load and start all interfaces asynchronously
    # We do this async to avoid blocking the supervision tree startup
    send(self(), :load_interfaces)

    {:ok, state}
  end

  @impl true
  def handle_call({:start_interface, %Interface{} = interface}, _from, state) do
    result = do_start_interface(interface, state)
    {:reply, result, state}
  end

  def handle_call({:stop_interface, interface_id}, _from, state) do
    result = do_stop_interface(interface_id, state)
    {:reply, result, state}
  end

  def handle_call(:list_interfaces, _from, state) do
    children =
      DynamicSupervisor.which_children(state.dynamic_sup)
      |> Enum.map(fn {_, pid, _, _} -> pid end)

    {:reply, children, state}
  end

  def handle_call({:restart_interface, %Interface{} = interface}, _from, state) do
    result = do_restart_interface(interface, state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:load_interfaces, state) do
    load_and_start_interfaces(state)
    {:noreply, state}
  end

  # Hot reload: Interface created
  def handle_info({:interface_created, %Interface{} = interface}, state) do
    Logger.info("Hot reload: Starting new interface #{interface.name} (#{interface.id})")

    case do_start_interface(interface, state) do
      {:ok, pid} ->
        Logger.info("Hot reload: Interface #{interface.name} started, pid: #{inspect(pid)}")

      {:error, reason} ->
        Logger.error(
          "Hot reload: Failed to start interface #{interface.name}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  # Hot reload: Interface updated or protocols updated
  def handle_info({event, %Interface{} = interface}, state)
      when event in [:interface_updated, :interface_protocols_updated] do
    Logger.info(
      "Hot reload: Restarting interface #{interface.name} (#{interface.id}) due to #{event}"
    )

    case do_restart_interface(interface, state) do
      {:ok, pid} ->
        Logger.info("Hot reload: Interface #{interface.name} restarted, pid: #{inspect(pid)}")

      {:error, :not_found} ->
        # Interface wasn't running, start it
        Logger.info("Hot reload: Interface #{interface.name} not running, starting it")

        case do_start_interface(interface, state) do
          {:ok, pid} ->
            Logger.info("Hot reload: Interface #{interface.name} started, pid: #{inspect(pid)}")

          {:error, reason} ->
            Logger.error(
              "Hot reload: Failed to start interface #{interface.name}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error(
          "Hot reload: Failed to restart interface #{interface.name}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  # Hot reload: Interface deleted
  def handle_info({:interface_deleted, %Interface{} = interface}, state) do
    Logger.info("Hot reload: Stopping interface #{interface.name} (#{interface.id})")

    case do_stop_interface(interface.id, state) do
      :ok ->
        Logger.info("Hot reload: Interface #{interface.name} stopped")

      {:error, :not_found} ->
        Logger.debug("Hot reload: Interface #{interface.name} was not running")
    end

    {:noreply, state}
  end

  # Ignore unhandled messages
  def handle_info(msg, state) do
    Logger.debug("InterfaceSupervisor received unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down InterfaceSupervisor for mission #{state.mission_id}")

    # DynamicSupervisor traps exits and ignores EXIT signals from non-child processes.
    # Since we started it via start_link in init (making us a linked non-child process),
    # it will NOT terminate when we die - we must explicitly stop it.
    # See: https://elixirforum.com/t/dynamicsupervisor-why-does-it-ignore-exit-signals-from-non-child-processes/73469
    if state.dynamic_sup && Process.alive?(state.dynamic_sup) do
      Supervisor.stop(state.dynamic_sup, :shutdown, 5_000)
    end

    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:interface_supervisor, mission_id}}}
  end

  defp do_start_interface(%Interface{} = interface, state) do
    if interface.mission_id != state.mission_id do
      {:error, :interface_not_in_mission}
    else
      child_spec = Factory.child_spec_for(interface)
      DynamicSupervisor.start_child(state.dynamic_sup, child_spec)
    end
  end

  defp do_stop_interface(interface_id, state) do
    case Registry.lookup(@registry, {:interface, state.mission_id, interface_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(state.dynamic_sup, pid)

      [] ->
        {:error, :not_found}
    end
  end

  defp do_restart_interface(%Interface{} = interface, state) do
    with :ok <- do_stop_interface(interface.id, state) do
      do_start_interface(interface, state)
    end
  end

  defp load_and_start_interfaces(state) do
    Logger.info("Loading interfaces for mission #{state.mission_id}")

    # Load all interfaces with protocols preloaded - this is the ONLY DB call
    interfaces = InterfaceQueries.list_for_mission(state.mission_id, preload_protocols: true)

    Logger.info("Found #{length(interfaces)} interface(s) for mission #{state.mission_id}")

    Enum.each(interfaces, fn interface ->
      # Pass the domain entity directly - no more DB lookups
      case do_start_interface(interface, state) do
        {:ok, pid} ->
          Logger.info(
            "Started interface #{interface.name} (#{interface.id}) for mission #{state.mission_id}, pid: #{inspect(pid)}"
          )

        {:error, {:already_started, pid}} ->
          Logger.debug(
            "Interface #{interface.name} (#{interface.id}) already started, pid: #{inspect(pid)}"
          )

        {:error, reason} ->
          Logger.error(
            "Failed to start interface #{interface.name} (#{interface.id}): #{inspect(reason)}"
          )
      end
    end)
  end
end
