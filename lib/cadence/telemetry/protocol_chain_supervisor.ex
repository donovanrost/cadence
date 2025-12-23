defmodule Cadence.Telemetry.ProtocolChainSupervisor do
  @moduledoc """
  Supervisor that manages ProtocolChain processes for a mission.

  ## Data Plane Architecture

  Protocol chains are decoupled from interfaces for:
  1. Reusability - same chain logic works with TCP, UDP, Kafka, NATS, etc.
  2. Fault isolation - protocol crashes don't affect socket connections
  3. Testability - chains can be tested independently

  ## Hot Reload

  This supervisor subscribes to `mission:{mission_id}:interface_config` and
  handles `:interface_protocols_updated` events by updating the protocol chain
  in-place, without requiring an interface restart.

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

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Telemetry.ProtocolChain

  defmodule State do
    @moduledoc false
    defstruct [:mission_id, :dynamic_sup]
  end

  ## Client API

  @doc """
  Starts the ProtocolChainSupervisor for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Starts a ProtocolChain for an interface.

  Options:
  - `:protocols` - Required. List of InterfaceProtocol entities from the Interface.

  ## Data Plane

  Protocols MUST be provided - no database calls are made.
  Get protocols from the Interface entity's `protocols` field.
  """
  def start_chain(mission_id, interface_id, opts) do
    GenServer.call(via_tuple(mission_id), {:start_chain, interface_id, opts})
  end

  @doc """
  Stops a ProtocolChain for an interface.
  """
  def stop_chain(mission_id, interface_id) do
    GenServer.call(via_tuple(mission_id), {:stop_chain, interface_id})
  end

  @doc """
  Updates protocols for a running chain (hot reload).

  This updates the protocol chain in-place without restarting it.
  """
  def update_chain(mission_id, interface_id, protocols) do
    GenServer.call(via_tuple(mission_id), {:update_chain, interface_id, protocols})
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
    GenServer.call(via_tuple(mission_id), :list_chains)
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting ProtocolChainSupervisor for mission #{mission_id}")

    # Start a DynamicSupervisor for managing protocol chain children
    {:ok, dynamic_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    # Subscribe to interface config changes for protocol hot reload
    topic = "mission:#{mission_id}:interface_config"
    Phoenix.PubSub.subscribe(Cadence.PubSub, topic)
    Logger.debug("Subscribed to #{topic} for protocol chain hot reload")

    state = %State{
      mission_id: mission_id,
      dynamic_sup: dynamic_sup
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_chain, interface_id, opts}, _from, state) do
    result = do_start_chain(interface_id, opts, state)
    {:reply, result, state}
  end

  def handle_call({:stop_chain, interface_id}, _from, state) do
    result = do_stop_chain(interface_id, state)
    {:reply, result, state}
  end

  def handle_call({:update_chain, interface_id, protocols}, _from, state) do
    result = do_update_chain(interface_id, protocols)
    {:reply, result, state}
  end

  def handle_call(:list_chains, _from, state) do
    children =
      DynamicSupervisor.which_children(state.dynamic_sup)
      |> Enum.map(fn {_, pid, _, _} -> pid end)

    {:reply, children, state}
  end

  @impl true
  # Hot reload: Protocol chain updated for an interface
  def handle_info({:interface_protocols_updated, %Interface{} = interface}, state) do
    Logger.info(
      "Hot reload: Protocol update received for interface #{interface.name} (#{interface.id})"
    )

    case do_update_chain(interface.id, interface.protocols) do
      :ok ->
        Logger.info("Hot reload: Protocol chain updated for interface #{interface.name}")

      {:error, :not_found} ->
        # Chain not running - that's fine, it will get new protocols when started
        Logger.debug(
          "Hot reload: Protocol chain for interface #{interface.name} not running, skipping"
        )

      {:error, reason} ->
        Logger.error(
          "Hot reload: Failed to update protocol chain for #{interface.name}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  # Ignore other interface events - we only care about protocol updates
  def handle_info({event, %Interface{}}, state)
      when event in [:interface_created, :interface_updated, :interface_deleted] do
    {:noreply, state}
  end

  # Ignore unhandled messages
  def handle_info(msg, state) do
    Logger.debug("ProtocolChainSupervisor received unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down ProtocolChainSupervisor for mission #{state.mission_id}")
    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:protocol_chain_supervisor, mission_id}}}
  end

  defp do_start_chain(interface_id, opts, state) do
    # Protocols are required - get from Interface entity
    protocols = Keyword.fetch!(opts, :protocols)

    child_spec = {
      ProtocolChain,
      [
        interface_id: interface_id,
        mission_id: state.mission_id,
        protocols: protocols
      ]
    }

    DynamicSupervisor.start_child(state.dynamic_sup, child_spec)
  end

  defp do_stop_chain(interface_id, state) do
    case ProtocolChain.whereis(interface_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(state.dynamic_sup, pid)
    end
  end

  defp do_update_chain(interface_id, protocols) do
    case ProtocolChain.whereis(interface_id) do
      nil ->
        {:error, :not_found}

      _pid ->
        ProtocolChain.update_protocols(ProtocolChain.via_tuple(interface_id), protocols)
    end
  end
end
