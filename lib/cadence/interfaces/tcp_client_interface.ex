defmodule Cadence.Interfaces.TcpClientInterface do
  @moduledoc """
  TCP Client interface for connecting to spacecraft simulators or ground stations.

  Protocol processing is delegated to ProtocolChain processes managed by the
  ProtocolChainSupervisor, providing fault isolation and reusability.

  ## Data Plane Architecture

  This GenServer receives a domain entity at startup - no database calls are made
  during runtime. Configuration changes are handled via PubSub events.

  ## Configuration (via Interface Entity)

  - host: Remote hostname or IP address
  - port: Remote port number
  - target_ids: List of target identifiers for telemetry routing
  - reconnect_delay_ms: Milliseconds between reconnection attempts (default: 5000)

  ## Protocol Chain Architecture

  Protocol chains are managed separately from this interface by the ProtocolChainSupervisor.
  This provides:
  1. Fault isolation - protocol crashes don't affect TCP connections
  2. Reusability - same protocol chain logic for TCP, UDP, Kafka, etc.
  3. Testability - chains can be tested independently
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Telemetry.{Pipeline, Packet}
  alias Cadence.Telemetry.ProtocolChain
  alias Cadence.Telemetry.ProtocolChainSupervisor
  alias Cadence.Telemetry.ProtocolChain.Processor

  defmodule State do
    @moduledoc false
    defstruct [
      :interface,
      :target_id,
      :host,
      :port,
      :socket,
      :reconnect_interval,
      :protocol_chain,
      connected: false,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0,
      packets_extracted: 0
    ]
  end

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the TCP client interface with the given Interface entity.

  The entity contains all configuration - no database lookups are performed.
  """
  def start_link(%Interface{} = interface) do
    name = {:via, Registry, {@registry, {:interface, interface.mission_id, interface.id}}}
    GenServer.start_link(__MODULE__, interface, name: name)
  end

  @doc """
  Sends data to the remote endpoint.
  """
  def send_data(pid, data) when is_binary(data) do
    GenServer.call(pid, {:send_data, data})
  end

  @doc """
  Returns current interface statistics.
  """
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(%Interface{} = interface) do
    # Start the protocol chain for this interface with injected protocols
    start_protocol_chain(interface.mission_id, interface.id, interface.protocols)

    # Clone the chain for this client
    protocol_chain = clone_protocol_chain(interface.id)

    # TCP clients connect to a single target - use first or "unknown"
    target_id = List.first(interface.target_ids) || "unknown"

    state = %State{
      interface: interface,
      target_id: target_id,
      host: interface.host |> to_charlist(),
      port: interface.port,
      reconnect_interval: interface.reconnect_delay_ms || 5000,
      protocol_chain: protocol_chain
    }

    protocol_info =
      if Enum.empty?(protocol_chain) do
        "none"
      else
        names = Enum.map(protocol_chain, fn {mod, _} -> inspect(mod) end)
        "[#{Enum.join(names, ", ")}]"
      end

    Logger.info(
      "Starting TCP client interface #{interface.name} for target=#{target_id}, host=#{interface.host}, port=#{interface.port}, protocols=#{protocol_info}"
    )

    # Attempt initial connection asynchronously
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_call({:send_data, _data}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send_data, data}, _from, %State{socket: socket} = state) do
    case :gen_tcp.send(socket, data) do
      :ok ->
        new_state = %{state | bytes_sent: state.bytes_sent + byte_size(data)}
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to send data to #{state.target_id}: #{inspect(reason)}")
        {:reply, error, handle_disconnect(state)}
    end
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      connected: state.connected,
      target_id: state.target_id,
      host: to_string(state.host),
      port: state.port,
      bytes_received: state.bytes_received,
      bytes_sent: state.bytes_sent,
      packets_received: state.packets_received
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case :gen_tcp.connect(state.host, state.port, [:binary, active: true, packet: :raw]) do
      {:ok, socket} ->
        Logger.info(
          "TCP client connected to #{state.host}:#{state.port} for target=#{state.target_id}"
        )

        # Reset protocol chain on connection
        new_chain = Processor.reset_chain(state.protocol_chain)

        {:noreply,
         %{
           state
           | socket: socket,
             connected: true,
             protocol_chain: new_chain
         }}

      {:error, reason} ->
        Logger.warning(
          "Failed to connect to #{state.host}:#{state.port}: #{inspect(reason)}, retrying in #{state.reconnect_interval}ms"
        )

        schedule_reconnect(state.reconnect_interval)
        {:noreply, state}
    end
  end

  def handle_info({:tcp, socket, data}, %State{socket: socket} = state) do
    Logger.debug("Received #{byte_size(data)} bytes from #{state.target_id}")

    new_state = %{state | bytes_received: state.bytes_received + byte_size(data)}

    # Process data through protocol chain
    case process_incoming_data(data, new_state) do
      {:ok, packets_with_format, updated_chain} ->
        # Forward extracted packets to pipeline
        Enum.each(packets_with_format, fn {packet_binary, format, _chain_metadata} ->
          metadata = %{
            mission_id: state.interface.mission_id,
            stored: false,
            target_id: state.target_id,
            received_at: DateTime.utc_now(),
            interface_id: state.interface.id
          }

          # Construct Packet struct based on format
          packet = construct_packet(packet_binary, metadata, format)

          # Send to pipeline
          Pipeline.process_packet(state.interface.mission_id, packet, metadata)
        end)

        {:noreply,
         %{
           new_state
           | protocol_chain: updated_chain,
             packets_extracted: new_state.packets_extracted + length(packets_with_format)
         }}

      {:stop, updated_chain} ->
        # Protocol is buffering, waiting for more data
        {:noreply, %{new_state | protocol_chain: updated_chain}}

      {:disconnect, reason} ->
        Logger.error("Protocol error for target=#{state.target_id}: #{reason}, disconnecting")

        schedule_reconnect(state.reconnect_interval)
        {:noreply, handle_disconnect(new_state)}
    end
  end

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    Logger.warning("TCP connection closed for target=#{state.target_id}")
    schedule_reconnect(state.reconnect_interval)
    {:noreply, handle_disconnect(state)}
  end

  def handle_info({:tcp_error, socket, reason}, %State{socket: socket} = state) do
    Logger.error("TCP error for target=#{state.target_id}: #{inspect(reason)}")
    schedule_reconnect(state.reconnect_interval)
    {:noreply, handle_disconnect(state)}
  end

  @impl true
  def terminate(_reason, %State{socket: socket} = state) when not is_nil(socket) do
    Logger.info("Closing TCP connection for target=#{state.target_id}")
    :gen_tcp.close(socket)
    ProtocolChainSupervisor.stop_chain(state.interface.mission_id, state.interface.id)
    :ok
  end

  def terminate(_reason, state) do
    ProtocolChainSupervisor.stop_chain(state.interface.mission_id, state.interface.id)
    :ok
  end

  ## Private Functions

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

  defp clone_protocol_chain(interface_id) do
    case ProtocolChain.clone(ProtocolChain.via_tuple(interface_id)) do
      {:ok, chain} -> chain
      {:error, _} -> []
    end
  end

  defp handle_disconnect(state) do
    if state.socket, do: :gen_tcp.close(state.socket)

    # Reset protocol chain on disconnect
    new_chain = Processor.reset_chain(state.protocol_chain)

    %{
      state
      | socket: nil,
        connected: false,
        protocol_chain: new_chain
    }
  end

  defp schedule_reconnect(interval) do
    Process.send_after(self(), :connect, interval)
  end

  defp process_incoming_data(data, %State{protocol_chain: []}) do
    # No protocols - return data as single packet with simulator format
    {:ok, [{data, :simulator, %{}}], []}
  end

  defp process_incoming_data(data, %State{protocol_chain: chain}) do
    case Processor.process_read(chain, data) do
      {:ok, packets, updated_chain} ->
        format = Processor.chain_format(updated_chain)

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

            Packet.from_simulator(binary, metadata)
        end

      :simulator ->
        Packet.from_simulator(binary, metadata)

      _raw ->
        Packet.from_simulator(binary, metadata)
    end
  end
end
