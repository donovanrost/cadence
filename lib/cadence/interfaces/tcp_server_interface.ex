defmodule Cadence.Interfaces.TcpServerInterface do
  @moduledoc """
  TCP Server interface for receiving telemetry from multiple spacecraft or simulators.

  This GenServer listens on a configured port and accepts multiple simultaneous
  TCP client connections. Protocol processing is delegated to ProtocolChain processes
  managed by the ProtocolChainSupervisor.

  ## Features

  - Accepts multiple concurrent client connections
  - Per-client protocol chain instances (isolated state, fault-tolerant)
  - Automatic client disconnect handling
  - Statistics tracking per client and overall
  - Integration with Phoenix.PubSub telemetry pipeline

  ## Configuration

  The interface is configured via the database with:
  - `bind_port` - Port to listen on (required)
  - `bind_address` - Address to bind to (default: "0.0.0.0")
  - `config.max_clients` - Maximum concurrent clients (default: 100)
  - `config.client_timeout` - Client idle timeout in ms (default: 300000)

  ## Protocol Chain Architecture

  Protocol chains are managed separately from this interface by the ProtocolChainSupervisor.
  This provides:
  1. Fault isolation - protocol crashes don't affect TCP connections
  2. Reusability - same protocol chain logic for TCP, UDP, Kafka, etc.
  3. Testability - chains can be tested independently
  """

  use GenServer
  require Logger

  alias Cadence.Telemetry.Packet
  alias Cadence.Telemetry.ProtocolChain
  alias Cadence.Telemetry.ProtocolChainSupervisor

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :target_ids,
      :interface_id,
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
      :protocol_chain,
      :connected_at,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0
    ]
  end

  ## Client API

  @doc """
  Starts the TCP server interface.

  ## Options

  - `:mission_id` - Mission UUID (required)
  - `:interface_id` - Interface UUID (required)
  - `:name` - Interface name (required)
  - `:config` - Configuration map (required)
    - `:bind_port` - Port to listen on
    - `:bind_address` - Address to bind to (default: "0.0.0.0")
    - `:target_ids` - List of target identifiers (default: ["unknown"])
    - `:max_clients` - Max concurrent clients (default: 100)
    - `:client_timeout` - Client timeout in ms (default: 300000)
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)
    config = Keyword.fetch!(opts, :config)

    name = {:via, Registry, {@registry, {:interface, mission_id, interface_id}}}
    GenServer.start_link(__MODULE__, {mission_id, interface_id, config}, name: name)
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
  def init({mission_id, interface_id, config}) do
    target_ids = Map.get(config, :target_ids, ["unknown"])

    Logger.info("""
    Starting TCP Server Interface:
      mission_id: #{mission_id}
      interface_id: #{interface_id}
      bind_address: #{Map.get(config, :bind_address, "0.0.0.0")}
      bind_port: #{Map.fetch!(config, :bind_port)}
      target_ids: #{inspect(target_ids)}
    """)

    # Start the shared protocol chain for this interface
    # Clients will clone from this template
    start_protocol_chain(mission_id, interface_id)

    state = %State{
      mission_id: mission_id,
      target_ids: target_ids,
      interface_id: interface_id,
      bind_address: Map.get(config, :bind_address, "0.0.0.0"),
      bind_port: Map.fetch!(config, :bind_port),
      max_clients: Map.get(config, :max_clients, 100),
      client_timeout: Map.get(config, :client_timeout, 300_000),
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
        {:ok, {address, port}} = :inet.peername(client_socket)
        address_str = :inet.ntoa(address) |> to_string()

        Logger.info("New client connected from #{address_str}:#{port}")

        if map_size(state.clients) >= state.max_clients do
          Logger.warning("Max clients (#{state.max_clients}) reached, rejecting connection")
          :gen_tcp.close(client_socket)
          send(self(), :accept)
          {:noreply, state}
        else
          # Clone the protocol chain for this client
          protocol_chain = clone_protocol_chain_for_client(state.interface_id)

          client_state = %ClientState{
            socket: client_socket,
            remote_address: address_str,
            remote_port: port,
            protocol_chain: protocol_chain,
            connected_at: DateTime.utc_now()
          }

          :inet.setopts(client_socket, active: true)

          new_clients = Map.put(state.clients, client_socket, client_state)
          send(self(), :accept)

          {:noreply,
           %{
             state
             | clients: new_clients,
               total_clients_connected: state.total_clients_connected + 1
           }}
        end

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
        updated_client_state = %{
          client_state
          | bytes_received: client_state.bytes_received + byte_size(data)
        }

        # Process through the client's protocol chain
        case process_incoming_data(data, updated_client_state, state) do
          {:ok, packets_with_format, new_chain} ->
            # Publish packets to PubSub for Broadway to process
            Enum.each(packets_with_format, fn {packet_binary, format, _chain_metadata} ->
              target_id = List.first(state.target_ids) || "unknown"

              metadata = %{
                mission_id: state.mission_id,
                stored: false,
                target_id: target_id,
                received_at: DateTime.utc_now(),
                interface_id: state.interface_id,
                client_address: client_state.remote_address,
                client_port: client_state.remote_port
              }

              # Construct Packet struct based on format from protocol chain
              packet = construct_packet(packet_binary, metadata, format)

              Phoenix.PubSub.broadcast(
                Cadence.PubSub,
                "mission:#{state.mission_id}:telemetry:raw",
                {:telemetry_packet, packet, metadata}
              )
            end)

            updated_client_state = %{
              updated_client_state
              | protocol_chain: new_chain,
                packets_received: client_state.packets_received + length(packets_with_format)
            }

            new_clients = Map.put(state.clients, client_socket, updated_client_state)

            {:noreply,
             %{
               state
               | clients: new_clients,
                 bytes_received: state.bytes_received + byte_size(data),
                 packets_received: state.packets_received + length(packets_with_format)
             }}

          {:stop, new_chain} ->
            updated_client_state = %{updated_client_state | protocol_chain: new_chain}
            new_clients = Map.put(state.clients, client_socket, updated_client_state)
            {:noreply, %{state | clients: new_clients}}

          {:disconnect, reason} ->
            Logger.warning(
              "Protocol error for client #{client_state.remote_address}:#{client_state.remote_port}: #{reason}"
            )

            handle_client_disconnect(client_socket, state)
        end
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
  def handle_call(:get_stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      interface_id: state.interface_id,
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

  @impl true
  def handle_call({:send_data, data, :all}, _from, state) do
    results =
      Enum.map(state.clients, fn {socket, _client_state} ->
        :gen_tcp.send(socket, data)
      end)

    successful = Enum.count(results, fn result -> result == :ok end)
    {:reply, {:ok, successful}, state}
  end

  @impl true
  def handle_call({:send_data, data, {:client, socket}}, _from, state) do
    case Map.get(state.clients, socket) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      _client_state ->
        result = :gen_tcp.send(socket, data)
        {:reply, result, state}
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

    # Stop the protocol chain
    ProtocolChainSupervisor.stop_chain(state.mission_id, state.interface_id)

    :ok
  end

  ## Private Functions

  defp start_protocol_chain(mission_id, interface_id) do
    case ProtocolChainSupervisor.start_chain(mission_id, interface_id) do
      {:ok, pid} ->
        Logger.debug("Started protocol chain #{inspect(pid)} for interface #{interface_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Protocol chain already running for interface #{interface_id}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start protocol chain for interface #{interface_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp clone_protocol_chain_for_client(interface_id) do
    # Clone the protocol chain from the template
    case ProtocolChain.clone(ProtocolChain.via_tuple(interface_id)) do
      {:ok, chain} -> chain
      {:error, _} -> []
    end
  end

  defp process_incoming_data(data, client_state, _state) do
    # Use the Processor module directly for client-specific chains
    alias Cadence.Telemetry.ProtocolChain.Processor

    case Processor.process_read(client_state.protocol_chain, data) do
      {:ok, packets, updated_chain} ->
        # Get format from the chain
        format = Processor.chain_format(updated_chain)

        # Wrap each packet with format
        packets_with_format =
          Enum.map(packets, fn packet_binary ->
            {packet_binary, format, %{}}
          end)

        {:ok, packets_with_format, updated_chain}

      {:stop, updated_chain} ->
        {:stop, updated_chain}

      {:disconnect, reason} ->
        {:disconnect, reason}
    end
  end

  defp handle_client_disconnect(client_socket, state) do
    :gen_tcp.close(client_socket)
    new_clients = Map.delete(state.clients, client_socket)
    {:noreply, %{state | clients: new_clients}}
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

  # Construct a Packet struct from binary data based on format
  defp construct_packet(binary, metadata, format) do
    case format do
      :ccsds ->
        case Packet.from_ccsds(binary, metadata) do
          {:ok, packet} ->
            packet

          {:error, reason} ->
            Logger.error(
              "Failed to parse CCSDS packet for target=#{metadata.target_id}: #{inspect(reason)}"
            )

            # Fallback to simulator format on parse error
            Packet.from_simulator(binary, metadata)
        end

      :simulator ->
        Packet.from_simulator(binary, metadata)

      _raw ->
        # For raw format, create a generic packet
        Packet.from_simulator(binary, metadata)
    end
  end
end
