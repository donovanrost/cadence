defmodule Cadence.Runtime.Interfaces.TcpClientInterface do
  @moduledoc """
  TCP Client interface for connecting to spacecraft simulators or ground stations.

  Downlink processing is delegated to Cadence.Runtime.Telemetry.DownlinkPipeline.
  Uplink encoding is delegated to Cadence.Runtime.Telemetry.UplinkPipeline.

  ## Data Plane Architecture

  This GenServer receives a domain entity at startup - no database calls are made
  during runtime. Configuration changes are handled via PubSub events.

  ## Configuration (via Interface Entity)

  - host: Remote hostname or IP address
  - port: Remote port number
  - target_ids: List of target identifiers for telemetry routing
  - reconnect_delay_ms: Milliseconds between reconnection attempts (default: 5000)

  ## Downlink Pipeline Architecture

  Downlink processing is handled outside this GenServer to keep transport
  concerns separate from protocol decoding.
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Telemetry.DownlinkPipeline
  alias Cadence.Runtime.Telemetry.UplinkPipeline

  defmodule State do
    @moduledoc false
    defstruct [
      :interface,
      :target_id,
      :host,
      :port,
      :socket,
      :reconnect_interval,
      connected: false,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0
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
    # TCP clients connect to a single target - use first or "unknown"
    target_id = List.first(interface.target_ids) || "unknown"

    state = %State{
      interface: interface,
      target_id: target_id,
      host: interface.host |> to_charlist(),
      port: interface.port,
      reconnect_interval: interface.reconnect_delay_ms || 5000
    }

    Logger.info(
      "Starting TCP client interface #{interface.name} for target=#{target_id}, host=#{interface.host}, port=#{interface.port}"
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
    case UplinkPipeline.encode(state.interface.mission_id, state.interface.id, data) do
      {:ok, encoded} ->
        case :gen_tcp.send(socket, encoded) do
          :ok ->
            updated = %{state | bytes_sent: state.bytes_sent + byte_size(encoded)}
            {:reply, :ok, updated}

          {:error, reason} = error ->
            Logger.error("Failed to send data to #{state.target_id}: #{inspect(reason)}")
            {:reply, error, handle_disconnect(state)}
        end

      {:error, reason} ->
        Logger.error("Uplink pipeline error for target=#{state.target_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
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

        DownlinkPipeline.reset_connection(
          state.interface.mission_id,
          state.interface.id,
          connection_id(state)
        )

        {:noreply,
         %{
           state
           | socket: socket,
             connected: true,
             packets_received: 0
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
    # Logger.debug("Received #{byte_size(data)} bytes from #{state.target_id}")

    new_state = %{state | bytes_received: state.bytes_received + byte_size(data)}

    DownlinkPipeline.ingest(
      state.interface.mission_id,
      state.interface.id,
      connection_id(state),
      data,
      downlink_metadata(state)
    )

    {:noreply, new_state}
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
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def handle_cast({:downlink_packets, connection_id, count}, state) do
    if connection_id == connection_id(state) do
      {:noreply, %{state | packets_received: state.packets_received + count}}
    else
      {:noreply, state}
    end
  end

  ## Private Functions

  defp handle_disconnect(state) do
    if state.socket, do: :gen_tcp.close(state.socket)

    DownlinkPipeline.drop_connection(
      state.interface.mission_id,
      state.interface.id,
      connection_id(state)
    )

    _ = UplinkPipeline.reset(state.interface.mission_id, state.interface.id)

    %{
      state
      | socket: nil,
        connected: false
    }
  end

  defp schedule_reconnect(interval) do
    Process.send_after(self(), :connect, interval)
  end

  defp downlink_metadata(state) do
    %{
      mission_id: state.interface.mission_id,
      stored: false,
      target_id: state.target_id,
      received_at: DateTime.utc_now(),
      interface_id: state.interface.id
    }
  end

  defp connection_id(state), do: state.interface.id
end
