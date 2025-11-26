defmodule Cadence.Telemetry.ProtocolChainSupervisor do
  @moduledoc """
  DynamicSupervisor that manages ProtocolChain processes for a mission.

  Protocol chains are decoupled from interfaces for:
  1. Reusability - same chain logic works with TCP, UDP, Kafka, NATS, etc.
  2. Fault isolation - protocol crashes don't affect socket connections
  3. Testability - chains can be tested independently

  Each interface that needs protocol processing starts a ProtocolChain through
  this supervisor. The chain is registered by interface_id.

  ## Example

      # Started by MissionInstance supervision tree
      {:ok, pid} = ProtocolChainSupervisor.start_link(mission_id: mission_id)

      # Start a chain for an interface
      {:ok, chain_pid} = ProtocolChainSupervisor.start_chain(
        mission_id,
        interface_id,
        protocols: protocol_configs
      )

      # Stop a chain
      ProtocolChainSupervisor.stop_chain(mission_id, interface_id)
  """

  use DynamicSupervisor
  require Logger

  alias Cadence.Telemetry.ProtocolChain

  ## Client API

  @doc """
  Starts the ProtocolChainSupervisor for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Starts a ProtocolChain for an interface.

  Options:
  - `:interface_id` - Required. The interface this chain belongs to.
  - `:protocols` - Optional. List of protocol configs. If not provided,
    will be loaded from database.
  """
  def start_chain(mission_id, interface_id, opts \\ []) do
    child_spec = {
      ProtocolChain,
      [
        interface_id: interface_id,
        mission_id: mission_id
      ] ++ opts
    }

    DynamicSupervisor.start_child(via_tuple(mission_id), child_spec)
  end

  @doc """
  Stops a ProtocolChain for an interface.
  """
  def stop_chain(mission_id, interface_id) do
    case ProtocolChain.whereis(interface_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(via_tuple(mission_id), pid)
    end
  end

  @doc """
  Looks up the ProtocolChain for an interface.
  """
  def get_chain(interface_id) do
    ProtocolChain.via_tuple(interface_id)
  end

  @doc """
  Lists all running ProtocolChain PIDs for a mission.
  """
  def list_chains(mission_id) do
    DynamicSupervisor.which_children(via_tuple(mission_id))
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting ProtocolChainSupervisor for mission #{mission_id}")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:protocol_chain_supervisor, mission_id}}}
  end
end
