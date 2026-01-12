defmodule Cadence.Runtime.Interfaces.TcpServerInterface do
  @moduledoc """
  TCP Server interface for receiving telemetry from multiple spacecraft or simulators.

  This GenServer listens on a configured port and accepts multiple simultaneous
  TCP client connections. Protocol processing is delegated to ProtocolChain processes
  managed by the ProtocolChainSupervisor.

  ## Data Plane Architecture

  This GenServer receives a domain entity at startup - no database calls are made
  during runtime. Configuration changes are handled via PubSub events.

  ## Features

  - Accepts multiple concurrent client connections
  - Per-client protocol chain instances (isolated state, fault-tolerant)
  - Automatic client disconnect handling
  - Statistics tracking per client and overall
  - Integration with Phoenix.PubSub telemetry pipeline

  ## Configuration (via Interface Entity)

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

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Downlink.Pipeline
  alias Cadence.CCSDS.Uplink.Pipeline, as: UplinkPipeline
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Telemetry.Packet
  alias Cadence.Telemetry.ProtocolChain
  alias Cadence.Telemetry.ProtocolChainSupervisor

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
      :downlink_mapping,
      :downlink_opts,
      :uplink_pipeline,
      :uplink_opts,
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
      :downlink_state,
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

    # Start the shared protocol chain for this interface with injected protocols
    # Clients will clone from this template
    start_protocol_chain(interface.mission_id, interface.id, interface.protocols)

    {downlink_mapping, downlink_opts} = init_downlink_config(interface)
    {uplink_pipeline, uplink_opts} = init_uplink_pipeline(interface)

    state = %State{
      interface: interface,
      target_ids: target_ids,
      bind_address: interface.bind_address || "0.0.0.0",
      bind_port: interface.bind_port,
      max_clients: max_clients,
      client_timeout: client_timeout,
      downlink_mapping: downlink_mapping,
      downlink_opts: downlink_opts,
      uplink_pipeline: uplink_pipeline,
      uplink_opts: uplink_opts,
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

        case encode_uplink(data, state) do
          {:ok, encoded, new_state} ->
            {successful, failed} = send_to_all_clients(new_state.clients, encoded)
            updated = update_bytes_sent(new_state, encoded, successful)
            reply_for_broadcast(successful, failed, updated, state)

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:send_data, data, :all}, _from, state) do
    case encode_uplink(data, state) do
      {:ok, encoded, new_state} ->
        results =
          Enum.map(new_state.clients, fn {socket, _client_state} ->
            :gen_tcp.send(socket, encoded)
          end)

        successful = Enum.count(results, fn result -> result == :ok end)
        {:reply, {:ok, successful}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:send_data, data, {:client, socket}}, _from, state) do
    case Map.get(state.clients, socket) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      _client_state ->
        case encode_uplink(data, state) do
          {:ok, encoded, new_state} ->
            result = :gen_tcp.send(socket, encoded)
            {:reply, result, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
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

    # Stop the protocol chain
    ProtocolChainSupervisor.stop_chain(state.interface.mission_id, state.interface.id)

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
    protocol_chain = clone_protocol_chain_for_client(state.interface.id)
    downlink_state = init_client_downlink(state)

    client_state = %ClientState{
      socket: client_socket,
      remote_address: address_str,
      remote_port: port,
      protocol_chain: protocol_chain,
      downlink_state: downlink_state,
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

    Logger.debug(
      "Accepted client #{address_str}:#{port}, total=#{map_size(new_clients)} (interface #{state.interface.id})",
      mission_id: state.interface.mission_id
    )

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

    Logger.debug(
      "TCP #{state.interface.id} received #{byte_size(data)} bytes from #{client_state.remote_address}:#{client_state.remote_port}",
      mission_id: state.interface.mission_id
    )

    case process_incoming_data(data, updated_client_state, state) do
      {:ok, packets, new_client_state} ->
        handle_incoming_pipeline_packets(
          packets,
          client_socket,
          new_client_state,
          state,
          byte_size(data)
        )

      {:ok_chain, packets_with_format, new_chain} ->
        handle_incoming_packets(
          packets_with_format,
          new_chain,
          client_socket,
          updated_client_state,
          state,
          byte_size(data)
        )

      {:stop, new_chain} ->
        updated_client_state = %{updated_client_state | protocol_chain: new_chain}
        new_clients = Map.put(state.clients, client_socket, updated_client_state)
        {:noreply, %{state | clients: new_clients}}

      {:disconnect, reason} ->
        Logger.warning(
          "Protocol error for client #{client_state.remote_address}:#{client_state.remote_port}: #{inspect(reason)} - keeping connection open"
        )

        new_clients = Map.put(state.clients, client_socket, updated_client_state)
        {:noreply, %{state | clients: new_clients}}

      {:error, reason, new_client_state} ->
        Logger.warning(
          "Downlink pipeline error for client #{client_state.remote_address}:#{client_state.remote_port}: #{inspect(reason)}"
        )

        new_clients = Map.put(state.clients, client_socket, new_client_state)
        {:noreply, %{state | clients: new_clients}}
    end
  end

  defp handle_incoming_packets(
         packets_with_format,
         new_chain,
         client_socket,
         client_state,
         state,
         data_size
       ) do
    target_id = List.first(state.target_ids) || "unknown"
    broadcast_packets(packets_with_format, client_state, state, target_id)

    updated_client_state = %{
      client_state
      | protocol_chain: new_chain,
        packets_received: client_state.packets_received + length(packets_with_format)
    }

    new_clients = Map.put(state.clients, client_socket, updated_client_state)

    {:noreply,
     %{
       state
       | clients: new_clients,
         bytes_received: state.bytes_received + data_size,
         packets_received: state.packets_received + length(packets_with_format)
     }}
  end

  defp handle_incoming_pipeline_packets(
         packets,
         client_socket,
         client_state,
         state,
         data_size
       ) do
    target_id = List.first(state.target_ids) || "unknown"
    broadcast_pipeline_packets(packets, client_state, state, target_id)

    updated_client_state = %{
      client_state
      | packets_received: client_state.packets_received + length(packets)
    }

    new_clients = Map.put(state.clients, client_socket, updated_client_state)

    {:noreply,
     %{
       state
       | clients: new_clients,
         bytes_received: state.bytes_received + data_size,
         packets_received: state.packets_received + length(packets)
     }}
  end

  defp broadcast_packets(packets_with_format, client_state, state, target_id) do
    Enum.each(packets_with_format, fn {packet_binary, format, chain_metadata} ->
      base_metadata = %{
        mission_id: state.interface.mission_id,
        stored: false,
        target_id: target_id,
        received_at: DateTime.utc_now(),
        interface_id: state.interface.id,
        client_address: client_state.remote_address,
        client_port: client_state.remote_port
      }

      metadata = Map.merge(base_metadata, chain_metadata || %{})

      case construct_packet(packet_binary, metadata, format) do
        %Packet{} = packet ->
          Phoenix.PubSub.broadcast(
            Cadence.PubSub,
            "mission:#{state.interface.mission_id}:telemetry:raw",
            {:telemetry_packet, packet, metadata}
          )

        nil ->
          :ok
      end
    end)
  end

  defp broadcast_pipeline_packets(packets, client_state, state, target_id) do
    Enum.each(packets, fn %Packet{} = packet ->
      metadata =
        %{
          mission_id: state.interface.mission_id,
          stored: false,
          target_id: target_id,
          received_at: DateTime.utc_now(),
          interface_id: state.interface.id,
          client_address: client_state.remote_address,
          client_port: client_state.remote_port
        }
        |> Map.merge(packet.source || %{})

      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "mission:#{state.interface.mission_id}:telemetry:raw",
        {:telemetry_packet, packet, metadata}
      )
    end)
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
          Logger.debug(
            "Sent #{byte_size(data)} bytes to #{client_state.remote_address}:#{client_state.remote_port}"
          )

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

  defp start_protocol_chain(mission_id, interface_id, protocols) do
    case ProtocolChainSupervisor.start_chain(mission_id, interface_id, protocols: protocols) do
      {:ok, pid} ->
        Logger.debug("Started protocol chain #{inspect(pid)} for interface #{interface_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Protocol chain already running for interface #{interface_id}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error(
          "Failed to start protocol chain for interface #{interface_id}: #{inspect(reason)}"
        )

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

  defp process_incoming_data(
         data,
         %ClientState{downlink_state: downlink_state} = client_state,
         state
       )
       when not is_nil(downlink_state) do
    ctx = %{direction: :downlink}

    case Pipeline.decode(data, ctx, state.downlink_mapping, downlink_state, state.downlink_opts) do
      {:ok, packets, updated_downlink} ->
        {:ok, packets, %{client_state | downlink_state: updated_downlink}}

      {:error, reason, updated_downlink} ->
        {:error, reason, %{client_state | downlink_state: updated_downlink}}
    end
  end

  defp process_incoming_data(data, client_state, state) do
    alias Cadence.Telemetry.ProtocolChain.Processor

    case Processor.process_read(client_state.protocol_chain, data, %{}) do
      {:ok, packets, updated_chain} ->
        format = Processor.chain_format(updated_chain)

        packets_with_format =
          Enum.map(packets, fn {packet_binary, metadata} ->
            {packet_binary, format, metadata}
          end)

        if packets_with_format == [] do
          Logger.debug(
            "Protocol chain yielded no packets for #{byte_size(data)} bytes (interface #{state.interface.id})",
            mission_id: state.interface.mission_id
          )
        end

        {:ok_chain, packets_with_format, updated_chain}

      {:stop, updated_chain} ->
        {:stop, updated_chain}

      {:disconnect, reason} ->
        {:disconnect, reason}
    end
  end

  defp init_downlink_config(interface) do
    case SDLPConfig.fetch(interface.protocols) do
      {:ok, %{mapping: mapping, opts: opts}} -> {mapping, opts}
      :error -> {nil, nil}
    end
  end

  defp init_client_downlink(%State{downlink_opts: nil}), do: nil

  defp init_client_downlink(%State{downlink_opts: opts}) do
    case Pipeline.init(opts) do
      {:ok, pipeline} -> pipeline
      {:error, _} -> nil
    end
  end

  defp init_uplink_pipeline(interface) do
    case SDLPConfig.fetch(interface.protocols) do
      {:ok, %{opts: opts}} ->
        case UplinkPipeline.init(opts) do
          {:ok, pipeline} -> {pipeline, opts}
          {:error, _} -> {nil, nil}
        end

      :error ->
        {nil, nil}
    end
  end

  defp encode_uplink(data, %State{uplink_pipeline: nil} = state) do
    {:ok, data, state}
  end

  defp encode_uplink(data, %State{} = state) do
    ctx = uplink_ctx(state.uplink_opts)

    sdu = %SDUOctets{
      profile: state.uplink_opts[:profile],
      scid: ctx[:scid],
      vcid: ctx[:vcid],
      map_id: ctx[:map_id],
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: data,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    case UplinkPipeline.encode(sdu, ctx, state.uplink_pipeline, state.uplink_opts) do
      {:ok, encoded, new_pipeline} ->
        {:ok, encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        {:error, reason, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp uplink_ctx(opts) do
    %{
      frame_size: opts[:frame_size],
      scid: opts[:uplink_scid] || opts[:scid],
      vcid: opts[:uplink_vcid] || opts[:vcid],
      map_id: opts[:uplink_map_id]
    }
  end

  defp handle_client_disconnect(client_socket, state) do
    client_state = Map.get(state.clients, client_socket)
    :gen_tcp.close(client_socket)
    new_clients = Map.delete(state.clients, client_socket)
    new_state = %{state | clients: new_clients}

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

  # Construct a Packet struct from binary data based on format
  defp construct_packet(binary, metadata, format) do
    case format do
      :ccsds ->
        build_ccsds_packet(binary, metadata)

      :raw ->
        build_ccsds_packet(binary, metadata)
    end
  end

  defp build_ccsds_packet(binary, metadata) do
    case Packet.from_ccsds(binary, metadata) do
      {:ok, packet} ->
        packet

      {:error, reason} ->
        Logger.error(
          "Failed to parse CCSDS packet for target=#{metadata.target_id}: #{inspect(reason)}"
        )

        nil
    end
  end
end
