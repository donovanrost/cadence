defmodule Cadence.Simulator.SendBuffer do
  @moduledoc """
  Batching buffer for network sends that decouples packet generation from I/O.

  Accumulates encoded packets and flushes them to the network in batches,
  reducing syscall overhead and preventing I/O latency from blocking generators.

  ## Batching Strategy

  Follows the CVTBatcher pattern with dual-trigger flushing:
  - **Time-based**: Arm a one-shot flush timer only when the buffer becomes non-empty
  - **Size-based**: Flush when batch reaches `batch_size_bytes` (default: 32KB)
  - Whichever comes first triggers a flush

  ## Usage

      # Start the buffer
      {:ok, pid} = SendBuffer.start_link(
        output: {:tcp, "localhost", 9999},
        batch_timeout: 10,
        batch_size: 32_768
      )

      # Send packets (non-blocking cast)
      SendBuffer.send_packet(pid, binary_packet)

      # Get stats
      SendBuffer.stats(pid)

      # Force immediate flush
      SendBuffer.flush(pid)
  """

  use GenServer
  require Logger

  alias Cadence.Time.Timer, as: TimeTimer

  @default_batch_timeout 10
  @default_batch_size 32_768
  @default_batch_size_multiplier 4

  defstruct [
    :output,
    :socket,
    :base_batch_timeout,
    :base_batch_size,
    :max_batch_size,
    :batch_timeout,
    :batch_size,
    :timer_ref,
    :mode,
    :coordinator_pid,
    :socket_owner,
    buffer: [],
    buffer_bytes: 0,
    packets_buffered: 0,
    packets_sent: 0,
    bytes_sent: 0,
    flushes: 0,
    status_version: 0
  ]

  @type output ::
          {:tcp, String.t(), non_neg_integer()} | {:udp, String.t(), non_neg_integer()} | nil

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the send buffer.

  ## Options

  - `:output` - Network output: `{:tcp, host, port}` or `{:udp, host, port}` (required)
  - `:batch_timeout` - Time-based flush interval in ms (default: 10)
  - `:batch_size` - Size-based flush threshold in bytes (default: 32768)
  - `:name` - Optional process name
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a packet to the buffer. Non-blocking cast.

  The packet will be accumulated and sent in the next batch flush.
  """
  @spec send_packet(GenServer.server(), binary()) :: :ok
  def send_packet(pid, binary) when is_binary(binary) do
    GenServer.cast(pid, {:packet, binary})
  end

  @doc """
  Sends a batch of packets to the buffer with a single cast.

  Packets must be in send order.
  """
  @spec send_packets(GenServer.server(), [binary()], non_neg_integer() | nil) :: :ok
  def send_packets(pid, binaries, total_bytes \\ nil)
      when is_list(binaries) and (is_integer(total_bytes) or is_nil(total_bytes)) do
    {packet_count, total_bytes} = batch_stats(binaries, total_bytes)

    GenServer.cast(pid, {:packets, binaries, packet_count, total_bytes})
  end

  @doc """
  Buffers a batch of packets synchronously.

  Returns the current backlog after the batch has been accepted.
  """
  @spec buffer_packets(GenServer.server(), [binary()], non_neg_integer() | nil) :: %{
          packets_buffered: non_neg_integer(),
          buffer_bytes: non_neg_integer(),
          status_version: non_neg_integer()
        }
  def buffer_packets(pid, binaries, total_bytes \\ nil)
      when is_list(binaries) and (is_integer(total_bytes) or is_nil(total_bytes)) do
    {packet_count, total_bytes} = batch_stats(binaries, total_bytes)
    GenServer.call(pid, {:buffer_packets, binaries, packet_count, total_bytes}, :infinity)
  end

  @doc """
  Attaches an externally-managed socket (listen mode).
  """
  @spec attach_socket(GenServer.server(), port()) :: :ok
  def attach_socket(pid, socket) do
    GenServer.cast(pid, {:attach_socket, socket})
  end

  @doc """
  Detaches the externally-managed socket (listen mode).
  """
  @spec detach_socket(GenServer.server()) :: :ok
  def detach_socket(pid) do
    GenServer.cast(pid, :detach_socket)
  end

  @doc """
  Forces an immediate flush of the buffer.
  """
  @spec flush(GenServer.server()) :: :ok
  def flush(pid) do
    GenServer.call(pid, :flush)
  end

  @doc """
  Gets buffer statistics.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @doc """
  Stops the buffer, flushing any remaining packets.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    output = Keyword.get(opts, :output)
    batch_timeout = Keyword.get(opts, :batch_timeout, @default_batch_timeout)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    max_batch_size =
      Keyword.get(opts, :max_batch_size, batch_size * @default_batch_size_multiplier)

    mode = Keyword.get(opts, :mode, :connect)
    coordinator_pid = Keyword.get(opts, :coordinator_pid)

    state = %__MODULE__{
      output: output,
      base_batch_timeout: batch_timeout,
      base_batch_size: batch_size,
      max_batch_size: max(max_batch_size, batch_size),
      batch_timeout: batch_timeout,
      batch_size: batch_size,
      mode: mode,
      coordinator_pid: coordinator_pid,
      socket_owner: nil
    }

    # Connect to output
    state = connect_output(state)

    Logger.debug(
      "SendBuffer started: output=#{inspect(output)}, timeout=#{batch_timeout}ms, size=#{batch_size}"
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:packet, binary}, state) do
    new_state =
      state
      |> enqueue_packets([binary], 1, byte_size(binary))
      |> maybe_publish_status(state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:packets, binaries, packet_count, total_bytes}, state) do
    new_state =
      state
      |> enqueue_packets(binaries, packet_count, total_bytes)
      |> maybe_publish_status(state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:attach_socket, socket}, state) do
    {:noreply, %{state | socket: socket, socket_owner: :external}}
  end

  @impl true
  def handle_cast(:detach_socket, state) do
    {:noreply, %{state | socket: nil, socket_owner: nil}}
  end

  @impl true
  def handle_call({:buffer_packets, binaries, packet_count, total_bytes}, _from, state) do
    new_state =
      state
      |> enqueue_packets(binaries, packet_count, total_bytes)
      |> maybe_publish_status(state)

    {:reply, buffer_status(new_state), new_state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state =
      state
      |> cancel_flush_timer()
      |> do_flush(:manual)
      |> maybe_publish_status(state)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      output: format_output(state.output),
      base_batch_timeout: state.base_batch_timeout,
      base_batch_size: state.base_batch_size,
      batch_timeout: state.batch_timeout,
      batch_size: state.batch_size,
      max_batch_size: state.max_batch_size,
      buffer_bytes: state.buffer_bytes,
      packets_buffered: state.packets_buffered,
      packets_sent: state.packets_sent,
      bytes_sent: state.bytes_sent,
      flushes: state.flushes
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:flush, state) do
    previous_state = state

    new_state =
      state
      |> clear_timer_ref()
      |> do_flush(:timer)
      |> maybe_publish_status(previous_state)

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Flush any remaining packets
    state
    |> cancel_flush_timer()
    |> do_flush(:manual)

    # Close socket
    close_socket(state)

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_flush(%{buffer: []} = state, _reason), do: state

  defp do_flush(state, flush_reason) do
    %{buffer: buffer, buffer_bytes: buffer_bytes, packets_buffered: packets_buffered} = state

    # Reverse buffer to restore send order and create iolist
    # iolist is more efficient than binary concatenation
    iolist = Enum.reverse(buffer)

    # Send as single syscall
    case do_send(state, iolist) do
      :ok ->
        %{
          state
          | buffer: [],
            buffer_bytes: 0,
            packets_buffered: 0,
            packets_sent: state.packets_sent + packets_buffered,
            bytes_sent: state.bytes_sent + buffer_bytes,
            flushes: state.flushes + 1
        }
        |> adjust_batching(flush_reason, buffer_bytes)

      {:error, reason} ->
        Logger.warning(
          "SendBuffer flush failed: #{inspect(reason)}, dropping #{packets_buffered} packets; attempting reconnect"
        )

        state
        |> reconnect_output()
        |> Map.merge(%{buffer: [], buffer_bytes: 0, packets_buffered: 0})
    end
  end

  defp do_send(%{socket: nil} = state, _iolist) do
    {:error, missing_socket_reason(state)}
  end

  defp do_send(%{output: {:tcp, _, _}, socket: socket}, iolist) do
    :gen_tcp.send(socket, iolist)
  end

  defp do_send(%{output: {:udp, host, port}, socket: socket}, iolist) do
    :gen_udp.send(socket, String.to_charlist(host), port, IO.iodata_to_binary(iolist))
  end

  defp do_send(_, _), do: {:error, :invalid_output}

  defp missing_socket_reason(%{output: nil}), do: :no_output_configured
  defp missing_socket_reason(%{mode: :listen}), do: :no_client_connected
  defp missing_socket_reason(%{output: {:tcp, _, _}}), do: :not_connected
  defp missing_socket_reason(%{output: {:udp, _, _}}), do: :not_connected
  defp missing_socket_reason(_), do: :not_connected

  defp connect_output(%{output: nil} = state), do: state

  defp connect_output(%{mode: :listen, output: {:tcp, _host, _port}} = state), do: state

  defp connect_output(%{output: {:tcp, host, port}} = state) do
    opts = [
      :binary,
      active: false,
      nodelay: true,
      sndbuf: 131_072,
      send_timeout: 5000
    ]

    case :gen_tcp.connect(String.to_charlist(host), port, opts) do
      {:ok, socket} ->
        Logger.info("SendBuffer connected to TCP #{host}:#{port}")
        %{state | socket: socket, socket_owner: :internal}

      {:error, reason} ->
        Logger.warning("SendBuffer failed to connect to TCP #{host}:#{port}: #{inspect(reason)}")
        state
    end
  end

  defp connect_output(%{output: {:udp, _host, _port}} = state) do
    case :gen_udp.open(0, [:binary, sndbuf: 131_072]) do
      {:ok, socket} ->
        Logger.debug("SendBuffer opened UDP socket")
        %{state | socket: socket, socket_owner: :internal}

      {:error, reason} ->
        Logger.warning("SendBuffer failed to open UDP socket: #{inspect(reason)}")
        state
    end
  end

  defp connect_output(state), do: state

  defp reconnect_output(%{mode: :listen} = state), do: %{state | socket: nil}
  defp reconnect_output(%{socket_owner: :external} = state), do: %{state | socket: nil}

  defp reconnect_output(%{output: {:tcp, _host, _port}} = state) do
    %{state | socket: nil} |> connect_output()
  rescue
    _ -> %{state | socket: nil}
  end

  defp reconnect_output(%{output: {:udp, _host, _port}} = state) do
    %{state | socket: nil} |> connect_output()
  rescue
    _ -> %{state | socket: nil}
  end

  defp reconnect_output(state), do: %{state | socket: nil}

  defp close_socket(%{socket: nil}), do: :ok
  defp close_socket(%{socket_owner: :external}), do: :ok
  defp close_socket(%{output: {:tcp, _, _}, socket: socket}), do: :gen_tcp.close(socket)
  defp close_socket(%{output: {:udp, _, _}, socket: socket}), do: :gen_udp.close(socket)
  defp close_socket(_), do: :ok

  defp enqueue_packets(state, [], _packet_count, _total_bytes), do: state

  defp enqueue_packets(state, packets, packet_count, total_bytes) do
    was_empty = state.buffer == []
    new_buffer = :lists.reverse(packets, state.buffer)
    new_bytes = state.buffer_bytes + total_bytes
    new_count = state.packets_buffered + packet_count

    updated_state = %{
      state
      | buffer: new_buffer,
        buffer_bytes: new_bytes,
        packets_buffered: new_count
    }

    cond do
      new_bytes >= state.batch_size ->
        updated_state
        |> cancel_flush_timer()
        |> do_flush(:size)

      was_empty ->
        schedule_flush(updated_state)

      true ->
        updated_state
    end
  end

  defp maybe_publish_status(new_state, previous_state) do
    if buffer_changed?(new_state, previous_state) do
      published_state = %{new_state | status_version: previous_state.status_version + 1}
      notify_coordinator(published_state)
      published_state
    else
      new_state
    end
  end

  defp buffer_changed?(new_state, previous_state) do
    new_state.packets_buffered != previous_state.packets_buffered or
      new_state.buffer_bytes != previous_state.buffer_bytes
  end

  defp notify_coordinator(%{coordinator_pid: pid} = state) when is_pid(pid) do
    send(
      pid,
      {:send_buffer_status, state.status_version, state.packets_buffered, state.buffer_bytes}
    )
  end

  defp notify_coordinator(_state), do: :ok

  defp buffer_status(state) do
    %{
      packets_buffered: state.packets_buffered,
      buffer_bytes: state.buffer_bytes,
      status_version: state.status_version
    }
  end

  defp batch_stats(binaries, nil) do
    Enum.reduce(binaries, {0, 0}, fn binary, {count, bytes} ->
      {count + 1, bytes + byte_size(binary)}
    end)
  end

  defp batch_stats(binaries, total_bytes), do: {length(binaries), total_bytes}

  defp adjust_batching(
         %{batch_size: batch_size, max_batch_size: max_batch_size} = state,
         :size,
         flushed_bytes
       )
       when flushed_bytes >= batch_size and batch_size < max_batch_size do
    %{state | batch_size: min(batch_size * 2, max_batch_size)}
  end

  defp adjust_batching(
         %{batch_size: batch_size, base_batch_size: base_batch_size} = state,
         :timer,
         flushed_bytes
       )
       when batch_size > base_batch_size and flushed_bytes * 4 <= batch_size do
    %{state | batch_size: max(base_batch_size, div(batch_size, 2))}
  end

  defp adjust_batching(state, _flush_reason, _flushed_bytes), do: state

  defp schedule_flush(%{timer_ref: nil} = state) do
    timer_ref = TimeTimer.send_after(self(), :flush, state.batch_timeout)
    %{state | timer_ref: timer_ref}
  end

  defp schedule_flush(state), do: state

  defp cancel_flush_timer(%{timer_ref: nil} = state), do: state

  defp cancel_flush_timer(state) do
    TimeTimer.cancel(state.timer_ref)
    %{state | timer_ref: nil}
  end

  defp clear_timer_ref(state), do: %{state | timer_ref: nil}

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)
end
