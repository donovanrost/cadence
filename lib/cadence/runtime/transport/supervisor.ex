defmodule Cadence.Runtime.Transport.Supervisor do
  @moduledoc """
  Mission-scoped dynamic supervisor for transport interfaces.

  Interfaces are ephemeral and own only socket lifecycle and byte I/O.
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

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @spec start_interface(String.t(), Interface.t()) :: {:ok, pid()} | {:error, term()}
  def start_interface(mission_id, %Interface{} = interface) do
    GenServer.call(via_tuple(mission_id), {:start_interface, interface})
  end

  @spec stop_interface(String.t(), String.t()) :: :ok | {:error, :not_found}
  def stop_interface(mission_id, interface_id) do
    GenServer.call(via_tuple(mission_id), {:stop_interface, interface_id})
  end

  @spec list_interfaces(String.t()) :: [pid()]
  def list_interfaces(mission_id) do
    GenServer.call(via_tuple(mission_id), :list_interfaces)
  end

  @impl true
  def init(mission_id) do
    {:ok, dynamic_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{mission_id: mission_id, dynamic_sup: dynamic_sup}
    send(self(), :load_interfaces)
    {:ok, state}
  end

  @impl true
  def handle_info(:load_interfaces, state) do
    interfaces = InterfaceQueries.list_for_mission(state.mission_id)

    Enum.each(interfaces, fn interface ->
      case do_start_interface(interface, state) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to start interface #{interface.name} (#{interface.id}): #{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:start_interface, %Interface{} = interface}, _from, state) do
    {:reply, do_start_interface(interface, state), state}
  end

  def handle_call({:stop_interface, interface_id}, _from, state) do
    {:reply, do_stop_interface(interface_id, state), state}
  end

  def handle_call(:list_interfaces, _from, state) do
    children =
      DynamicSupervisor.which_children(state.dynamic_sup)
      |> Enum.map(fn {_, pid, _, _} -> pid end)

    {:reply, children, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.dynamic_sup && Process.alive?(state.dynamic_sup) do
      Supervisor.stop(state.dynamic_sup, :shutdown, 5_000)
    end

    :ok
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:transport_supervisor, mission_id}}}
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
end
