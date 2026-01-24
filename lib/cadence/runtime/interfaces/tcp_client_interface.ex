defmodule Cadence.Runtime.Interfaces.TcpClientInterface do
  @moduledoc """
  TCP Client interface for connecting to remote endpoints.

  This GenServer owns socket lifecycle and byte I/O only. It emits raw bytes
  to the runtime router and does not perform protocol framing or routing.
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Router
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

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
      bytes_sent: 0
    ]
  end

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the TCP client interface with the given Interface entity.
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
        updated = %{state | bytes_sent: state.bytes_sent + byte_size(data)}
        {:reply, :ok, updated}

      {:error, reason} = error ->
        Logger.error("Failed to send data to #{state.target_id}: #{inspect(reason)}")
        {:reply, error, handle_disconnect(state)}
    end
  end

  def handle_call(:connected?, _from, %State{} = state) do
    {:reply, state.connected, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      connected: state.connected,
      target_id: state.target_id,
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
        Logger.info(
          "TCP client connected to #{state.host}:#{state.port} for target=#{state.target_id}"
        )

        Router.interface_connected(state.interface.mission_id, state.interface.id)

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

    Router.ingest(
      state.interface.mission_id,
      state.interface.id,
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
  def handle_cast({:downlink_packets, _connection_id, _count}, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp handle_disconnect(state) do
    if state.socket, do: :gen_tcp.close(state.socket)

    Router.interface_disconnected(state.interface.mission_id, state.interface.id)

    %{
      state
      | socket: nil,
        connected: false
    }
  end

  defp schedule_reconnect(interval) do
    TimeTimer.send_after(self(), :connect, interval)
  end

  defp downlink_metadata(state) do
    %{
      mission_id: state.interface.mission_id,
      target_id: state.target_id,
      received_at: CadenceTime.now(),
      interface_id: state.interface.id
    }
  end
end
