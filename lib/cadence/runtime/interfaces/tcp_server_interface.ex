defmodule Cadence.Runtime.Interfaces.TcpServerInterface do
  @moduledoc """
  TCP Server interface for receiving telemetry from multiple spacecraft or simulators.

  This GenServer listens on a configured port and accepts multiple simultaneous
  TCP client connections. Downlink processing is delegated to the DownlinkPipeline.
  Uplink encoding is delegated to the UplinkPipeline.

  ## Data Plane Architecture

  This GenServer receives a domain entity at startup - no database calls are made
  during runtime. Configuration changes are handled via PubSub events.

  ## Features

  - Accepts multiple concurrent client connections
  - Automatic client disconnect handling
  - Statistics tracking per client and overall
  - Integration with Phoenix.PubSub telemetry pipeline

  ## Configuration (via Interface Entity)

  - `bind_port` - Port to listen on (required)
  - `bind_address` - Address to bind to (default: "0.0.0.0")
  - `config.max_clients` - Maximum concurrent clients (default: 100)
  - `config.client_timeout` - Client idle timeout in ms (default: 300000)

  ## Downlink Pipeline Architecture

  Downlink processing is handled outside this GenServer to keep transport
  concerns separate from protocol decoding.
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent
  alias Cadence.Runtime.Telemetry.DownlinkPipeline
  alias Cadence.Runtime.Telemetry.UplinkPipeline

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [
      :interface,
      :target_ids,
      :listen_socket,
      :bind_address,
      :bind_port,
      :max_clients,
      :client_timeout,
      clients: %{},
      listening: false,
      total_clients_connected: 0,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0
    ]
  end

  defmodule ClientState do
    @moduledoc false
    defstruct [
      :socket,
      :remote_address,
      :remote_port,
      :connected_at,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0
    ]
  end

  ## Client API

  @doc """
  Starts the TCP server interface with the given Interface entity.

  The entity contains all configuration - no database lookups are performed.
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
    # Use target_ids from entity, or fallback to ["unknown"]
    target_ids =
      if Enum.empty?(interface.target_ids), do: ["unknown"], else: interface.target_ids

    # Extract max_clients and client_timeout from config map
    max_clients =
      get_in(interface.config, ["max_clients"]) ||
        get_in(interface.config, [:max_clients]) ||
        100

    client_timeout =
      get_in(interface.config, ["client_timeout"]) ||
        get_in(interface.config, [:client_timeout]) ||
        300_000

    Logger.info("""
    Starting TCP Server Interface #{interface.name}:
      mission_id: #{interface.mission_id}
      interface_id: #{interface.id}
      bind_address: #{interface.bind_address || "0.0.0.0"}
      bind_port: #{interface.bind_port}
      target_ids: #{inspect(target_ids)}
    """)

    state = %State{
      interface: interface,
      target_ids: target_ids,
      bind_address: interface.bind_address || "0.0.0.0",
      bind_port: interface.bind_port,
      max_clients: max_clients,
      client_timeout: client_timeout,
      clients: %{}
    }

    # Start listening asynchronously
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
        Process.send_after(self(), :accept, 1000)
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
  def handle_cast({:downlink_packets, connection_id, count}, state) do
    case Map.get(state.clients, connection_id) do
      nil ->
        {:noreply, state}

      client_state ->
        updated_client_state = %{
          client_state
          | packets_received: client_state.packets_received + count
        }

        new_clients = Map.put(state.clients, connection_id, updated_client_state)

        {:noreply,
         %{
           state
           | clients: new_clients,
             packets_received: state.packets_received + count
         }}
    end
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
      bytes_sent: state.bytes_sent,
      packets_received: state.packets_received
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
          bytes_received: client_state.bytes_received,
          bytes_sent: client_state.bytes_sent,
          packets_received: client_state.packets_received
        }
      end)

    {:reply, clients, state}
  end

  # Command dispatch from TargetDispatcher - broadcasts to all connected clients
  #
  # LIMITATION: Currently broadcasts to ALL connected clients regardless of target.
  # This works when each target has its own interface, or when only one client is connected.
  #
  # TODO: When CCSDS framing is implemented, extract the APID from the command packet
  # and route to the specific client associated with that APID. This requires:
  # 1. Add `target_id` or `apids` field to ClientState
  # 2. Build APID→socket mapping from incoming telemetry packets
  # 3. Look up the correct socket based on command APID before sending
  @impl true
  def handle_call({:send_data, data}, _from, state) do
    case map_size(state.clients) do
      0 ->
        {:reply, {:error, :no_clients_connected}, state}

      count ->
        warn_if_broadcasting(count)

        case UplinkPipeline.encode(state.interface.mission_id, state.interface.id, data) do
          {:ok, encoded} ->
            {successful, failed} = send_to_all_clients(state.clients, encoded)
            updated = update_bytes_sent(state, encoded, successful)
            reply_for_broadcast(successful, failed, updated, state)

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:send_data, data, :all}, _from, state) do
    case UplinkPipeline.encode(state.interface.mission_id, state.interface.id, data) do
      {:ok, encoded} ->
        results =
          Enum.map(state.clients, fn {socket, _client_state} ->
            :gen_tcp.send(socket, encoded)
          end)

        successful = Enum.count(results, fn result -> result == :ok end)
        {:reply, {:ok, successful}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_data, data, {:client, socket}}, _from, state) do
    case Map.get(state.clients, socket) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      _client_state ->
        case UplinkPipeline.encode(state.interface.mission_id, state.interface.id, data) do
          {:ok, encoded} ->
            result = :gen_tcp.send(socket, encoded)
            {:reply, result, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Close all client sockets
    Enum.each(state.clients, fn {socket, _client_state} ->
      :gen_tcp.close(socket)
    end)

    # Close listen socket
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
    client_state = %ClientState{
      socket: client_socket,
      remote_address: address_str,
      remote_port: port,
      connected_at: DateTime.utc_now()
    }

    :inet.setopts(client_socket, active: true)

    new_clients = Map.put(state.clients, client_socket, client_state)
    send(self(), :accept)

    new_state = %{
      state
      | clients: new_clients,
        total_clients_connected: state.total_clients_connected + 1
    }

    DownlinkPipeline.reset_connection(
      state.interface.mission_id,
      state.interface.id,
      client_socket
    )

    # Logger.debug(
    #   "Accepted client #{address_str}:#{port}, total=#{map_size(new_clients)} (interface #{state.interface.id})",
    #   mission_id: state.interface.mission_id
    # )

    maybe_broadcast_connect(state, new_state, client_state)
    {:noreply, new_state}
  end

  defp maybe_broadcast_connect(state, new_state, client_state) do
    if map_size(state.clients) == 0 do
      broadcast_connection_event(new_state, :disconnected, :connected, client_state)
    end
  end

  defp handle_client_data(client_socket, data, client_state, state) do
    updated_client_state = %{
      client_state
      | bytes_received: client_state.bytes_received + byte_size(data)
    }

    # Logger.debug(
    #   "TCP #{state.interface.id} received #{byte_size(data)} bytes from #{client_state.remote_address}:#{client_state.remote_port}",
    #   mission_id: state.interface.mission_id
    # )

    DownlinkPipeline.ingest(
      state.interface.mission_id,
      state.interface.id,
      client_socket,
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

  defp warn_if_broadcasting(count) when count > 1 do
    Logger.warning(
      "Broadcasting command to #{count} clients - target-specific routing not yet implemented"
    )
  end

  defp warn_if_broadcasting(_count), do: :ok

  defp send_to_all_clients(clients, data) do
    Enum.reduce(clients, {0, 0}, fn {socket, client_state}, {ok, err} ->
      case :gen_tcp.send(socket, data) do
        :ok ->
          # Logger.debug(
          #   "Sent #{byte_size(data)} bytes to #{client_state.remote_address}:#{client_state.remote_port}"
          # )

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
    {:reply, :ok, new_state}
  end

  defp reply_for_broadcast(_successful, failed, _new_state, state) do
    {:reply, {:error, :all_sends_failed, failed}, state}
  end

  defp handle_client_disconnect(client_socket, state) do
    client_state = Map.get(state.clients, client_socket)
    :gen_tcp.close(client_socket)
    new_clients = Map.delete(state.clients, client_socket)
    new_state = %{state | clients: new_clients}

    DownlinkPipeline.drop_connection(
      state.interface.mission_id,
      state.interface.id,
      client_socket
    )

    # Broadcast disconnection event when last client disconnects
    if map_size(new_clients) == 0 and map_size(state.clients) > 0 do
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
      stored: false,
      target_id: List.first(state.target_ids) || "unknown",
      received_at: DateTime.utc_now(),
      interface_id: state.interface.id,
      client_address: client_state.remote_address,
      client_port: client_state.remote_port
    }
  end
end
