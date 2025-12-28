defmodule Cadence.Simulator.SendBuffer do
  @moduledoc """
  Batching buffer for network sends that decouples packet generation from I/O.

  Accumulates encoded packets and flushes them to the network in batches,
  reducing syscall overhead and preventing I/O latency from blocking generators.

  ## Batching Strategy

  Follows the CVTBatcher pattern with dual-trigger flushing:
  - **Time-based**: Flush after `batch_timeout_ms` (default: 10ms for timing fidelity)
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

  @default_batch_timeout 10
  @default_batch_size 32_768

  defstruct [
    :output,
    :socket,
    :batch_timeout,
    :batch_size,
    :timer_ref,
    buffer: [],
    buffer_bytes: 0,
    packets_buffered: 0,
    packets_sent: 0,
    bytes_sent: 0,
    flushes: 0
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

    state = %__MODULE__{
      output: output,
      batch_timeout: batch_timeout,
      batch_size: batch_size
    }

    # Connect to output
    state = connect_output(state)

    # Schedule first flush timer
    state = schedule_flush(state)

    Logger.debug(
      "SendBuffer started: output=#{inspect(output)}, timeout=#{batch_timeout}ms, size=#{batch_size}"
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:packet, binary}, state) do
    # O(1) cons onto buffer
    new_buffer = [binary | state.buffer]
    new_bytes = state.buffer_bytes + byte_size(binary)
    new_count = state.packets_buffered + 1

    state = %{state | buffer: new_buffer, buffer_bytes: new_bytes, packets_buffered: new_count}

    # Size-based flush check
    state =
      if new_bytes >= state.batch_size do
        do_flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    state = do_flush(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      output: format_output(state.output),
      batch_timeout: state.batch_timeout,
      batch_size: state.batch_size,
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
    state = do_flush(state)
    state = schedule_flush(state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Flush any remaining packets
    do_flush(state)

    # Close socket
    close_socket(state)

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_flush(%{buffer: []} = state), do: state

  defp do_flush(state) do
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

      {:error, reason} ->
        Logger.warning(
          "SendBuffer flush failed: #{inspect(reason)}, dropping #{packets_buffered} packets"
        )

        %{
          state
          | buffer: [],
            buffer_bytes: 0,
            packets_buffered: 0
        }
    end
  end

  defp do_send(%{socket: nil}, _iolist), do: :ok

  defp do_send(%{output: {:tcp, _, _}, socket: socket}, iolist) do
    :gen_tcp.send(socket, iolist)
  end

  defp do_send(%{output: {:udp, host, port}, socket: socket}, iolist) do
    # UDP needs binary, not iolist
    binary = IO.iodata_to_binary(iolist)
    :gen_udp.send(socket, String.to_charlist(host), port, binary)
  end

  defp do_send(_, _), do: :ok

  defp connect_output(%{output: nil} = state), do: state

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
        %{state | socket: socket}

      {:error, reason} ->
        Logger.warning("SendBuffer failed to connect to TCP #{host}:#{port}: #{inspect(reason)}")
        state
    end
  end

  defp connect_output(%{output: {:udp, _host, _port}} = state) do
    case :gen_udp.open(0, [:binary, sndbuf: 131_072]) do
      {:ok, socket} ->
        Logger.debug("SendBuffer opened UDP socket")
        %{state | socket: socket}

      {:error, reason} ->
        Logger.warning("SendBuffer failed to open UDP socket: #{inspect(reason)}")
        state
    end
  end

  defp connect_output(state), do: state

  defp close_socket(%{socket: nil}), do: :ok
  defp close_socket(%{output: {:tcp, _, _}, socket: socket}), do: :gen_tcp.close(socket)
  defp close_socket(%{output: {:udp, _, _}, socket: socket}), do: :gen_udp.close(socket)
  defp close_socket(_), do: :ok

  defp schedule_flush(state) do
    # Cancel existing timer if any
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    timer_ref = Process.send_after(self(), :flush, state.batch_timeout)
    %{state | timer_ref: timer_ref}
  end

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)
end
