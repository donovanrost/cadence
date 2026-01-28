defmodule Cadence.Runtime.Transport.InterfaceSupervisor do
  @moduledoc """
  Dynamic supervisor for interface workers per mission.
  """

  use DynamicSupervisor

  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface, as: InterfaceEntity
  alias Cadence.Runtime.Interfaces.Factory
  alias Cadence.Runtime.Transport.InterfaceWorker
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

  @spec ensure_started(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def ensure_started(mission_id, interface_id, config \\ %{}) do
    case lookup(mission_id, interface_id) do
      {:ok, _pid} ->
        :ok

      :error ->
        case start_child_for_config(mission_id, interface_id, config) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec ensure_stopped(String.t(), String.t()) :: :ok | {:error, :not_found}
  def ensure_stopped(mission_id, interface_id) do
    case lookup(mission_id, interface_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(via_tuple(mission_id), pid)
      :error -> {:error, :not_found}
    end
  end

  defp lookup(mission_id, interface_id) do
    case Registry.lookup(@registry, {:transport_interface, mission_id, interface_id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case Registry.lookup(@registry, {:interface, mission_id, interface_id}) do
          [{pid, _}] -> {:ok, pid}
          [] -> :error
        end
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:interface_supervisor, mission_id}}}
  end

  defp start_child_for_config(mission_id, _interface_id, %TransportInterface{} = transport) do
    case build_entity(transport) do
      {:ok, %InterfaceEntity{} = entity} ->
        child_spec = Factory.child_spec_for(entity)
        DynamicSupervisor.start_child(via_tuple(mission_id), child_spec)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_child_for_config(mission_id, interface_id, config) do
    organization_id = Map.get(config, :organization_id) || Map.get(config, "organization_id")

    child_spec =
      {InterfaceWorker,
       mission_id: mission_id,
       organization_id: organization_id,
       interface_id: interface_id,
       config: config}

    DynamicSupervisor.start_child(via_tuple(mission_id), child_spec)
  end

  defp build_entity(%TransportInterface{} = transport) do
    endpoint = transport.endpoint || %{}
    mode = endpoint_value(endpoint, :mode)

    with {:ok, connection_type} <- connection_type_for(transport.type, mode) do
      {:ok,
       %InterfaceEntity{
         id: transport.id,
         mission_id: transport.mission_id,
         name: transport.name,
         connection_type: connection_type,
         host: endpoint_value(endpoint, :host),
         port: endpoint_value(endpoint, :port),
         bind_address: bind_address_for(connection_type, endpoint),
         bind_port: bind_port_for(connection_type, endpoint),
         auto_reconnect: true,
         reconnect_delay_ms: 5_000,
         config: %{},
         metadata: %{
           "transport_type" => to_string(transport.type),
           "tags" => transport.tags || []
         },
         target_ids: []
       }}
    end
  end

  defp connection_type_for(:tcp, "server"), do: {:ok, :tcp_server}
  defp connection_type_for(:tcp, "client"), do: {:ok, :tcp_client}
  defp connection_type_for(:tcp, nil), do: {:ok, :tcp_client}
  defp connection_type_for(:udp, _mode), do: {:error, :udp_not_implemented}
  defp connection_type_for(:serial, _mode), do: {:error, :serial_not_implemented}
  defp connection_type_for(:file, _mode), do: {:error, :file_not_implemented}
  defp connection_type_for(:s3, _mode), do: {:error, :s3_not_implemented}
  defp connection_type_for(:replay, _mode), do: {:error, :replay_not_implemented}
  defp connection_type_for(type, _mode), do: {:error, {:unsupported_transport_type, type}}

  defp bind_address_for(:tcp_server, endpoint), do: endpoint_value(endpoint, :host)
  defp bind_address_for(_type, _endpoint), do: nil

  defp bind_port_for(:tcp_server, endpoint), do: endpoint_value(endpoint, :port)
  defp bind_port_for(_type, _endpoint), do: nil

  defp endpoint_value(endpoint, key) do
    Map.get(endpoint, key) || Map.get(endpoint, Atom.to_string(key))
  end
end
