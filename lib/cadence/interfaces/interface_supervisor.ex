defmodule Cadence.Interfaces.InterfaceSupervisor do
  @moduledoc """
  DynamicSupervisor that manages all interface processes for a mission.

  When a mission starts, this supervisor:
  1. Loads all interface configurations from the database
  2. Starts the appropriate interface GenServer for each (TcpClientInterface, etc.)
  3. Monitors interface health and handles crashes

  Each interface process is registered in the MissionRegistry with the key:
  `{:interface, mission_id, interface_id}`

  ## Example

      # Started by MissionInstance supervision tree
      {:ok, pid} = InterfaceSupervisor.start_link(mission_id: mission_id)

      # Dynamically add a new interface
      InterfaceSupervisor.start_interface(mission_id, interface_id)

      # Stop an interface
      InterfaceSupervisor.stop_interface(mission_id, interface_id)
  """

  use DynamicSupervisor
  require Logger

  alias Cadence.Interfaces
  alias Cadence.Interfaces.Factory

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the InterfaceSupervisor for a mission.

  Automatically loads and starts all interfaces for the mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Starts a specific interface for a mission.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_interface(mission_id, interface_id) do
    case Interfaces.get_interface(interface_id) do
      nil ->
        {:error, :interface_not_found}

      interface ->
        if interface.mission_id != mission_id do
          {:error, :interface_not_in_mission}
        else
          child_spec = Factory.child_spec_for(interface)
          DynamicSupervisor.start_child(via_tuple(mission_id), child_spec)
        end
    end
  end

  @doc """
  Stops a specific interface for a mission.

  Returns `:ok` or `{:error, :not_found}`.
  """
  def stop_interface(mission_id, interface_id) do
    case Registry.lookup(@registry, {:interface, mission_id, interface_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(via_tuple(mission_id), pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running interface PIDs for a mission.
  """
  def list_interfaces(mission_id) do
    DynamicSupervisor.which_children(via_tuple(mission_id))
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end

  @doc """
  Restarts an interface (stop and start).
  """
  def restart_interface(mission_id, interface_id) do
    with :ok <- stop_interface(mission_id, interface_id),
         {:ok, pid} <- start_interface(mission_id, interface_id) do
      {:ok, pid}
    end
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting InterfaceSupervisor for mission #{mission_id}")

    # Start the supervisor first
    result = DynamicSupervisor.init(strategy: :one_for_one)

    # Then load and start all interfaces asynchronously
    # We do this async to avoid blocking the supervision tree startup
    Task.start(fn -> load_and_start_interfaces(mission_id) end)

    result
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:interface_supervisor, mission_id}}}
  end

  defp load_and_start_interfaces(mission_id) do
    Logger.info("Loading interfaces for mission #{mission_id}")

    interfaces = Interfaces.list_interfaces(mission_id)

    Logger.info("Found #{length(interfaces)} interface(s) for mission #{mission_id}")

    Enum.each(interfaces, fn interface ->
      case start_interface(mission_id, interface.id) do
        {:ok, pid} ->
          Logger.info(
            "Started interface #{interface.name} (#{interface.id}) for mission #{mission_id}, pid: #{inspect(pid)}"
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
