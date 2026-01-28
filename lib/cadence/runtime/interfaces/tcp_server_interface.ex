defmodule Cadence.Runtime.Interfaces.TcpServerInterface do
  @moduledoc """
  TCP Server interface for receiving bytes from multiple clients.

  This GenServer owns socket lifecycle and byte I/O only. It emits raw bytes
  to the runtime router and does not perform protocol framing or routing.
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent
  alias Cadence.Runtime.Router
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [
      :interface,
      :listen_socket,
      :bind_address,
      :bind_port,
      :max_clients,
      :client_timeout,
      clients: %{},
      listening: false,
      total_clients_connected: 0,
      bytes_received: 0,
      bytes_sent: 0
    ]
  end

  defmodule ClientState do
    @moduledoc false
    defstruct [
      :socket,
      :remote_address,
      :remote_port,
      :connected_at,
      :client_id,
      bytes_received: 0,
      bytes_sent: 0
    ]
  end

  ## Client API

  @doc """
  Starts the TCP server interface with the given Interface entity.
  """
  def start_link(%Interface{} = interface) do
    name = {:via, Registry, {@registry, {:interface, interface.mission_id, interface.id}}}
    GenServer.start_link(__MODULE__, interface, name: name)
  end

  @doc """
  Gets server statistics including client information.
  """
  def stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  @doc """
  Lists all connected clients with their information.
  """
  def list_clients(pid) do
    GenServer.call(pid, :list_clients)
  end

  @doc """
  Sends data to all connected clients.
  """
  def broadcast(pid, data) do
    GenServer.call(pid, {:send_data, data, :all})
  end

  @doc """
  Sends data to a specific client by socket.
  """
  def send_to_client(pid, client_socket, data) do
    GenServer.call(pid, {:send_data, data, {:client, client_socket}})
  end

  ## Server Callbacks

  @impl true
  def init(%Interface{} = interface) do
    config = interface_config(interface)
    bind_address = bind_address_for_interface(interface)
    max_clients = config_value(config, "max_clients", :max_clients, 100)
    client_timeout = config_value(config, "client_timeout", :client_timeout, 300_000)

    Logger.info("""
    Starting TCP Server Interface #{interface.name}:
      mission_id: #{interface.mission_id}
      interface_id: #{interface.id}
      bind_address: #{bind_address}
      bind_port: #{interface.bind_port}
    """)

    state = %State{
      interface: interface,
      bind_address: bind_address,
      bind_port: interface.bind_port,
      max_clients: max_clients,
      client_timeout: client_timeout,
      clients: %{}
    }

    send(self(), :listen)
    {:ok, state}
  end

  @impl true
  def handle_info(:listen, state) do
    ip_tuple = parse_bind_address(state.bind_address)

    listen_opts = [
      :binary,
      active: false,
      reuseaddr: true,
      packet: :raw,
      ip: ip_tuple
    ]

    case :gen_tcp.listen(state.bind_port, listen_opts) do
      {:ok, listen_socket} ->
        Logger.info("TCP server listening on #{state.bind_address}:#{state.bind_port}")
        send(self(), :accept)
        {:noreply, %{state | listen_socket: listen_socket, listening: true}}

      {:error, reason} ->
        Logger.error("Failed to listen on port #{state.bind_port}: #{inspect(reason)}")
        {:stop, {:listen_error, reason}, state}
    end
  end

  @impl true
  def handle_info(:accept, %State{listen_socket: listen_socket} = state) do
    case :gen_tcp.accept(listen_socket, 100) do
      {:ok, client_socket} ->
        handle_client_accept(client_socket, state)

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        TimeTimer.send_after(self(), :accept, 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp, client_socket, data}, state) do
    case Map.get(state.clients, client_socket) do
      nil ->
        Logger.warning("Received data from unknown client socket")
        {:noreply, state}

      client_state ->
        handle_client_data(client_socket, data, client_state, state)
    end
  end

  @impl true
  def handle_info({:tcp_closed, client_socket}, state) do
    case Map.get(state.clients, client_socket) do
      nil ->
        {:noreply, state}

      client_state ->
        Logger.info(
          "Client #{client_state.remote_address}:#{client_state.remote_port} disconnected"
        )

        handle_client_disconnect(client_socket, state)
    end
  end

  @impl true
  def handle_info({:tcp_error, client_socket, reason}, state) do
    Logger.error("TCP error on client socket: #{inspect(reason)}")
    handle_client_disconnect(client_socket, state)
  end

  @impl true
  def handle_cast({:downlink_packets, _connection_id, _count}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      mission_id: state.interface.mission_id,
      interface_id: state.interface.id,
      listening: state.listening,
      bind_port: state.bind_port,
      connected_clients: map_size(state.clients),
      total_clients_connected: state.total_clients_connected,
      bytes_received: state.bytes_received,
      bytes_sent: state.bytes_sent
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_clients, _from, state) do
    clients =
      Enum.map(state.clients, fn {_socket, client_state} ->
        %{
          remote_address: client_state.remote_address,
          remote_port: client_state.remote_port,
          connected_at: client_state.connected_at,
          client_id: client_state.client_id,
          bytes_received: client_state.bytes_received,
          bytes_sent: client_state.bytes_sent
        }
      end)

    {:reply, clients, state}
  end

  @impl true
  def handle_call({:send_data, data}, _from, state) do
    {reply, next_state} = dispatch_uplink(state, data)
    {:reply, reply, next_state}
  end

  @impl true
  def handle_call({:send_data, data, :all}, _from, state) do
    results =
      Enum.map(state.clients, fn {socket, _client_state} ->
        :gen_tcp.send(socket, data)
      end)

    successful = Enum.count(results, fn result -> result == :ok end)
    updated = update_bytes_sent(state, data, successful)
    {:reply, {:ok, successful}, updated}
  end

  @impl true
  def handle_call({:send_data, data, {:client, socket}}, _from, state) do
    case Map.get(state.clients, socket) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      _client_state ->
        result = :gen_tcp.send(socket, data)
        updated = if result == :ok, do: update_bytes_sent(state, data, 1), else: state
        {:reply, result, updated}
    end
  end

  def handle_call(:connected?, _from, state) do
    {:reply, map_size(state.clients) > 0, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.clients, fn {socket, _client_state} ->
      :gen_tcp.close(socket)
    end)

    if state.listen_socket, do: :gen_tcp.close(state.listen_socket)

    :ok
  end

  ## Private Functions

  defp handle_client_accept(client_socket, state) do
    {:ok, {address, port}} = :inet.peername(client_socket)
    address_str = :inet.ntoa(address) |> to_string()

    Logger.info("New client connected from #{address_str}:#{port}")

    if map_size(state.clients) >= state.max_clients do
      reject_client(client_socket, state)
    else
      accept_client(client_socket, address_str, port, state)
    end
  end

  defp reject_client(client_socket, state) do
    Logger.warning("Max clients (#{state.max_clients}) reached, rejecting connection")
    :gen_tcp.close(client_socket)
    send(self(), :accept)
    {:noreply, state}
  end

  defp accept_client(client_socket, address_str, port, state) do
    client_id = state.total_clients_connected + 1

    client_state = %ClientState{
      socket: client_socket,
      remote_address: address_str,
      remote_port: port,
      connected_at: CadenceTime.now(),
      client_id: client_id
    }

    :inet.setopts(client_socket, active: true)

    new_clients = Map.put(state.clients, client_socket, client_state)
    send(self(), :accept)

    new_state = %{
      state
      | clients: new_clients,
        total_clients_connected: state.total_clients_connected + 1
    }

    if map_size(state.clients) == 0 do
      Router.interface_connected(state.interface.mission_id, state.interface.id)
      broadcast_connection_event(new_state, :disconnected, :connected, client_state)
    end

    {:noreply, new_state}
  end

  defp handle_client_data(client_socket, data, client_state, state) do
    updated_client_state = %{
      client_state
      | bytes_received: client_state.bytes_received + byte_size(data)
    }

    # Logger.debug(
    #   "[DEBUG] TCP #{state.interface.id} received #{byte_size(data)} bytes from #{client_state.remote_address}:#{client_state.remote_port}",
    #   mission_id: state.interface.mission_id
    # )

    Router.ingest(
      state.interface.mission_id,
      state.interface.id,
      data,
      downlink_metadata(state, updated_client_state)
    )

    new_clients = Map.put(state.clients, client_socket, updated_client_state)

    {:noreply,
     %{
       state
       | clients: new_clients,
         bytes_received: state.bytes_received + byte_size(data)
     }}
  end

  defp dispatch_uplink(state, data) do
    case map_size(state.clients) do
      0 ->
        {{:error, :no_clients_connected}, state}

      _count ->
        {successful, failed} = send_to_all_clients(state.clients, data)
        updated = update_bytes_sent(state, data, successful)
        reply_for_broadcast(successful, failed, updated, state)
    end
  end

  defp send_to_all_clients(clients, data) do
    Enum.reduce(clients, {0, 0}, fn {socket, client_state}, {ok, err} ->
      case :gen_tcp.send(socket, data) do
        :ok ->
          {ok + 1, err}

        {:error, reason} ->
          Logger.warning(
            "Failed to send to #{client_state.remote_address}:#{client_state.remote_port}: #{inspect(reason)}"
          )

          {ok, err + 1}
      end
    end)
  end

  defp update_bytes_sent(state, data, successful) do
    %{state | bytes_sent: state.bytes_sent + byte_size(data) * successful}
  end

  defp reply_for_broadcast(successful, _failed, new_state, _state) when successful > 0 do
    {:ok, new_state}
  end

  defp reply_for_broadcast(_successful, failed, _new_state, state) do
    {{:error, :all_sends_failed, failed}, state}
  end

  defp handle_client_disconnect(client_socket, state) do
    client_state = Map.get(state.clients, client_socket)
    :gen_tcp.close(client_socket)
    new_clients = Map.delete(state.clients, client_socket)
    new_state = %{state | clients: new_clients}

    if map_size(new_clients) == 0 and map_size(state.clients) > 0 do
      Router.interface_disconnected(state.interface.mission_id, state.interface.id)
      broadcast_connection_event(new_state, :connected, :disconnected, client_state)
    end

    {:noreply, new_state}
  end

  defp broadcast_connection_event(state, previous_state, new_state, client_state) do
    client_info =
      if client_state do
        %{
          "remote_address" => client_state.remote_address,
          "remote_port" => client_state.remote_port
        }
      end

    event =
      InterfaceConnectionEvent.new(%{
        mission_id: state.interface.mission_id,
        interface_id: state.interface.id,
        interface_name: state.interface.name,
        previous_state: previous_state,
        new_state: new_state,
        client_count: map_size(state.clients),
        client_info: client_info
      })

    Logger.info("Interface connection event: #{InterfaceConnectionEvent.describe(event)}")
    InterfaceConnectionEvent.broadcast(event)
  end

  defp interface_config(%Interface{config: config}) when is_map(config), do: config
  defp interface_config(_), do: %{}

  defp bind_address_for_interface(%Interface{bind_address: address})
       when is_binary(address) and address != "",
       do: address

  defp bind_address_for_interface(_), do: "0.0.0.0"

  defp config_value(config, string_key, atom_key, default) when is_map(config) do
    Map.get(config, string_key) || Map.get(config, atom_key) || default
  end

  defp config_value(_config, _string_key, _atom_key, default), do: default

  defp parse_bind_address(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_bind_address(address) when is_list(address) do
    case :inet.parse_address(address) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_bind_address(_), do: {0, 0, 0, 0}

  defp downlink_metadata(state, client_state) do
    %{
      mission_id: state.interface.mission_id,
      received_at: CadenceTime.now(),
      interface_id: state.interface.id,
      client_address: client_state.remote_address,
      client_port: client_state.remote_port
    }
  end
end
