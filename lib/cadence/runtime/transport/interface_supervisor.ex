defmodule Cadence.Runtime.Transport.InterfaceSupervisor do
  @moduledoc """
  Dynamic supervisor for interface workers per mission.
  """

  use DynamicSupervisor

  require Logger

  alias Cadence.Runtime.Interfaces.Factory
  alias Cadence.Transports.Interface, as: TransportInterface

  @registry Cadence.MissionRegistry

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @impl true
  def init(mission_id) do
    Logger.debug("Starting InterfaceSupervisor for mission_id=#{mission_id}")
    Process.put(:mission_id, mission_id)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def terminate(reason, _state) do
    case Process.get(:mission_id) do
      nil ->
        :ok

      mission_id ->
        Logger.debug(
          "Stopping InterfaceSupervisor for mission_id=#{mission_id} reason=#{inspect(reason)}"
        )
    end

    :ok
  end

  @spec ensure_started(String.t(), String.t(), TransportInterface.t()) :: :ok | {:error, term()}
  def ensure_started(mission_id, transport_id, %TransportInterface{} = transport) do
    case lookup(mission_id, transport_id) do
      {:ok, _pid} ->
        :ok

      :error ->
        case start_child_for_config(mission_id, transport) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec ensure_stopped(String.t(), String.t()) :: :ok | {:error, :not_found}
  def ensure_stopped(mission_id, transport_id) do
    case lookup(mission_id, transport_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(via_tuple(mission_id), pid)
      :error -> {:error, :not_found}
    end
  end

  defp lookup(mission_id, transport_id) do
    case Registry.lookup(@registry, {:transport, mission_id, transport_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:interface_supervisor, mission_id}}}
  end

  defp start_child_for_config(mission_id, %TransportInterface{} = transport) do
    child_spec = Factory.child_spec_for(transport)
    DynamicSupervisor.start_child(via_tuple(mission_id), child_spec)
  rescue
    error -> {:error, error}
  end
end
