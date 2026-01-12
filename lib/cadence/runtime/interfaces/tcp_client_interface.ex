defmodule Cadence.Runtime.Interfaces.TcpClientInterface do
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

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Downlink.Pipeline
  alias Cadence.CCSDS.Uplink.Pipeline, as: UplinkPipeline
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Telemetry.Packet
  alias Cadence.Telemetry.ProtocolChain
  alias Cadence.Telemetry.ProtocolChain.Processor
  alias Cadence.Telemetry.ProtocolChainSupervisor

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
      :downlink_pipeline,
      :downlink_mapping,
      :downlink_opts,
      :uplink_pipeline,
      :uplink_opts,
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

    {downlink_pipeline, downlink_mapping, downlink_opts} = init_downlink_pipeline(interface)
    {uplink_pipeline, uplink_opts} = init_uplink_pipeline(interface)

    state = %State{
      interface: interface,
      target_id: target_id,
      host: interface.host |> to_charlist(),
      port: interface.port,
      reconnect_interval: interface.reconnect_delay_ms || 5000,
      protocol_chain: protocol_chain,
      downlink_pipeline: downlink_pipeline,
      downlink_mapping: downlink_mapping,
      downlink_opts: downlink_opts,
      uplink_pipeline: uplink_pipeline,
      uplink_opts: uplink_opts
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
    case encode_uplink(data, state) do
      {:ok, encoded, new_state} ->
        case :gen_tcp.send(socket, encoded) do
          :ok ->
            updated = %{new_state | bytes_sent: new_state.bytes_sent + byte_size(encoded)}
            {:reply, :ok, updated}

          {:error, reason} = error ->
            Logger.error("Failed to send data to #{state.target_id}: #{inspect(reason)}")
            {:reply, error, handle_disconnect(new_state)}
        end

      {:error, reason, new_state} ->
        Logger.error("Uplink pipeline error for target=#{state.target_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, new_state}
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

        new_chain = Processor.reset_chain(state.protocol_chain)
        downlink_pipeline = reset_downlink_pipeline(state)

        {:noreply,
         %{
           state
           | socket: socket,
             connected: true,
             protocol_chain: new_chain,
             downlink_pipeline: downlink_pipeline
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

    case process_incoming_data(data, new_state) do
      {:ok, packets, updated_state} ->
        broadcast_pipeline_packets(packets, updated_state)

        {:noreply,
         %{
           updated_state
           | packets_extracted: updated_state.packets_extracted + length(packets)
         }}

      {:ok_chain, packets_with_format, updated_chain} ->
        broadcast_packets(packets_with_format, state)

        {:noreply,
         %{
           new_state
           | protocol_chain: updated_chain,
             packets_extracted: new_state.packets_extracted + length(packets_with_format)
         }}

      {:stop, updated_chain} ->
        {:noreply, %{new_state | protocol_chain: updated_chain}}

      {:error, reason, updated_state} ->
        Logger.error("Downlink pipeline error for target=#{state.target_id}: #{inspect(reason)}")
        {:noreply, updated_state}

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

  defp broadcast_packets(packets_with_format, state) do
    Enum.each(packets_with_format, fn {packet_binary, format, chain_metadata} ->
      base_metadata = %{
        mission_id: state.interface.mission_id,
        stored: false,
        target_id: state.target_id,
        received_at: DateTime.utc_now(),
        interface_id: state.interface.id
      }

      metadata = Map.merge(base_metadata, chain_metadata || %{})

      broadcast_packet(packet_binary, format, metadata, state.interface.mission_id)
    end)
  end

  defp broadcast_packet(packet_binary, format, metadata, mission_id) do
    case construct_packet(packet_binary, metadata, format) do
      %Packet{} = packet ->
        Phoenix.PubSub.broadcast(
          Cadence.PubSub,
          "mission:#{mission_id}:telemetry:raw",
          {:telemetry_packet, packet, metadata}
        )

      nil ->
        :ok
    end
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

  defp clone_protocol_chain(interface_id) do
    case ProtocolChain.clone(ProtocolChain.via_tuple(interface_id)) do
      {:ok, chain} -> chain
      {:error, _} -> []
    end
  end

  defp handle_disconnect(state) do
    if state.socket, do: :gen_tcp.close(state.socket)

    new_chain = Processor.reset_chain(state.protocol_chain)
    downlink_pipeline = reset_downlink_pipeline(state)
    uplink_pipeline = reset_uplink_pipeline(state)

    %{
      state
      | socket: nil,
        connected: false,
        protocol_chain: new_chain,
        downlink_pipeline: downlink_pipeline,
        uplink_pipeline: uplink_pipeline
    }
  end

  defp schedule_reconnect(interval) do
    Process.send_after(self(), :connect, interval)
  end

  defp process_incoming_data(data, %State{downlink_pipeline: pipeline} = state)
       when not is_nil(pipeline) do
    ctx = %{direction: :downlink}

    case Pipeline.decode(data, ctx, state.downlink_mapping, pipeline, state.downlink_opts) do
      {:ok, packets, updated_pipeline} ->
        {:ok, packets, %{state | downlink_pipeline: updated_pipeline}}

      {:error, reason, updated_pipeline} ->
        {:error, reason, %{state | downlink_pipeline: updated_pipeline}}
    end
  end

  defp process_incoming_data(data, %State{protocol_chain: []}) do
    {:ok_chain, [{data, :raw, %{}}], []}
  end

  defp process_incoming_data(data, %State{protocol_chain: chain}) do
    case Processor.process_read(chain, data, %{}) do
      {:ok, packets, updated_chain} ->
        format = Processor.chain_format(updated_chain)

        packets_with_format =
          Enum.map(packets, fn {packet_binary, metadata} ->
            {packet_binary, format, metadata}
          end)

        {:ok_chain, packets_with_format, updated_chain}

      {:stop, updated_chain} ->
        {:stop, updated_chain}

      {:disconnect, reason} ->
        {:disconnect, reason}
    end
  end

  defp init_downlink_pipeline(interface) do
    case SDLPConfig.fetch(interface.protocols) do
      {:ok, %{mapping: mapping, opts: opts}} ->
        case Pipeline.init(opts) do
          {:ok, pipeline} -> {pipeline, mapping, opts}
          {:error, _} -> {nil, nil, nil}
        end

      :error ->
        {nil, nil, nil}
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

  defp reset_downlink_pipeline(%State{downlink_opts: nil}), do: nil

  defp reset_downlink_pipeline(%State{downlink_opts: opts}) do
    case Pipeline.init(opts) do
      {:ok, pipeline} -> pipeline
      {:error, _} -> nil
    end
  end

  defp reset_uplink_pipeline(%State{uplink_opts: nil}), do: nil

  defp reset_uplink_pipeline(%State{uplink_opts: opts}) do
    case UplinkPipeline.init(opts) do
      {:ok, pipeline} -> pipeline
      {:error, _} -> nil
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

  defp broadcast_pipeline_packets(packets, state) do
    Enum.each(packets, fn %Packet{} = packet ->
      metadata =
        %{
          mission_id: state.interface.mission_id,
          interface_id: state.interface.id
        }
        |> Map.merge(packet.source || %{})

      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "mission:#{state.interface.mission_id}:telemetry:raw",
        {:telemetry_packet, packet, metadata}
      )
    end)
  end

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
