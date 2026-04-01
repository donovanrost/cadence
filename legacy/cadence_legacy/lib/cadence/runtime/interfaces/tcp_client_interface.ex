defmodule Cadence.Runtime.Interfaces.TcpClientInterface do
  @moduledoc """
  TCP Client transport for connecting to remote endpoints.

  This GenServer owns socket lifecycle and byte I/O only. It emits raw bytes
  to the runtime router and does not perform protocol framing or routing.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Router
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer
  alias Cadence.Transports.Interface, as: TransportInterface

  defmodule State do
    @moduledoc false
    defstruct [
      :transport,
      :host,
      :port,
      :socket,
      :reconnect_interval,
      connected: false,
      bytes_received: 0,
      bytes_sent: 0
    ]
  end

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the TCP client transport with the given transport interface.
  """
  def start_link(%TransportInterface{} = transport) do
    name = {:via, Registry, {@registry, {:transport, transport.mission_id, transport.id}}}
    GenServer.start_link(__MODULE__, transport, name: name)
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
  def init(%TransportInterface{} = transport) do
    endpoint = transport.endpoint || %{}

    state = %State{
      transport: transport,
      host: endpoint_value(endpoint, :host, "127.0.0.1") |> to_charlist(),
      port: endpoint_value(endpoint, :port),
      reconnect_interval: endpoint_value(endpoint, :reconnect_delay_ms, 5_000)
    }

    Logger.info(
      "Starting TCP client transport #{transport.name} host=#{endpoint_value(endpoint, :host)} port=#{endpoint_value(endpoint, :port)}"
    )

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_call({:send_data, _data}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send_data, data}, _from, %State{socket: socket} = state) do
    case send_data_over_socket(%{state | socket: socket}, data) do
      {:ok, next_state} -> {:reply, :ok, next_state}
      {:error, reason, next_state} -> {:reply, {:error, reason}, next_state}
    end
  end

  def handle_call(:connected?, _from, %State{} = state) do
    {:reply, state.connected, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      connected: state.connected,
      host: to_string(state.host),
      port: state.port,
      bytes_received: state.bytes_received,
      bytes_sent: state.bytes_sent
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case :gen_tcp.connect(state.host, state.port, [:binary, active: true, packet: :raw]) do
      {:ok, socket} ->
        Logger.info("TCP client connected to #{state.host}:#{state.port}")

        Router.transport_connected(state.transport.mission_id, state.transport.id)

        {:noreply,
         %{
           state
           | socket: socket,
             connected: true
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
    new_state = %{state | bytes_received: state.bytes_received + byte_size(data)}

    Router.ingest(state.transport.mission_id, state.transport.id, data, downlink_metadata(state))

    {:noreply, new_state}
  end

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    Logger.warning("TCP connection closed for transport=#{state.transport.id}")
    schedule_reconnect(state.reconnect_interval)
    {:noreply, handle_disconnect(state)}
  end

  def handle_info({:tcp_error, socket, reason}, %State{socket: socket} = state) do
    Logger.error("TCP error for transport=#{state.transport.id}: #{inspect(reason)}")
    schedule_reconnect(state.reconnect_interval)
    {:noreply, handle_disconnect(state)}
  end

  @impl true
  def handle_cast({:send, data, _meta}, state) when is_binary(data) do
    case send_data_over_socket(state, data) do
      {:ok, next_state} -> {:noreply, next_state}
      {:error, _reason, next_state} -> {:noreply, next_state}
    end
  end

  @impl true
  def handle_cast({:downlink_packets, _connection_id, _count}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{socket: socket} = state) when not is_nil(socket) do
    Logger.info("Closing TCP connection for transport=#{state.transport.id}")
    :gen_tcp.close(socket)
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  ## Private Functions

  defp handle_disconnect(state) do
    if state.socket, do: :gen_tcp.close(state.socket)

    Router.transport_disconnected(state.transport.mission_id, state.transport.id)

    %{
      state
      | socket: nil,
        connected: false
    }
  end

  defp send_data_over_socket(%State{connected: false} = state, _data),
    do: {:error, :not_connected, state}

  defp send_data_over_socket(%State{socket: socket} = state, data) do
    case :gen_tcp.send(socket, data) do
      :ok ->
        {:ok, %{state | bytes_sent: state.bytes_sent + byte_size(data)}}

      {:error, reason} ->
        Logger.error(
          "Failed to send data for transport=#{state.transport.id}: #{inspect(reason)}"
        )

        {:error, reason, handle_disconnect(state)}
    end
  end

  defp schedule_reconnect(interval) do
    TimeTimer.send_after(self(), :connect, interval)
  end

  defp downlink_metadata(state) do
    %{
      mission_id: state.transport.mission_id,
      received_at: CadenceTime.now(),
      transport_id: state.transport.id,
      mode: :realtime
    }
  end

  defp endpoint_value(endpoint, key, default \\ nil) when is_map(endpoint) do
    Map.get(endpoint, key) || Map.get(endpoint, Atom.to_string(key)) || default
  end
end
