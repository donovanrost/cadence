defmodule CadenceSimulator.SendBuffer do
  @moduledoc """
  Batching buffer that decouples packet generation from network I/O.
  """

  use GenServer

  require Logger

  alias CadenceSimulator.SimulatorMetrics

  @default_batch_timeout 10
  @default_batch_size 32_768
  @default_batch_size_multiplier 4
  @default_tcp_socket_buffer 1_048_576
  @default_send_timeout 30_000

  defstruct [
    :output,
    :runtime_resolver,
    :socket,
    :base_batch_timeout,
    :base_batch_size,
    :max_batch_size,
    :metrics_id,
    :metrics_sample_rate,
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

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec send_packet(GenServer.server(), binary()) :: :ok
  def send_packet(pid, binary) when is_binary(binary) do
    GenServer.cast(pid, {:packet, binary})
  end

  @spec send_packets(GenServer.server(), [binary()], non_neg_integer() | nil) :: :ok
  def send_packets(pid, binaries, total_bytes \\ nil)
      when is_list(binaries) and (is_integer(total_bytes) or is_nil(total_bytes)) do
    {packet_count, total_bytes} = batch_stats(binaries, total_bytes)
    GenServer.cast(pid, {:packets, binaries, packet_count, total_bytes})
  end

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

  @spec attach_socket(GenServer.server(), port()) :: :ok
  def attach_socket(pid, socket) do
    GenServer.cast(pid, {:attach_socket, socket})
  end

  @spec detach_socket(GenServer.server()) :: :ok
  def detach_socket(pid) do
    GenServer.cast(pid, :detach_socket)
  end

  @spec flush(GenServer.server()) :: :ok
  def flush(pid) do
    GenServer.call(pid, :flush)
  end

  @spec stats(GenServer.server()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(pid), do: GenServer.stop(pid)

  @impl true
  def init(opts) do
    output = Keyword.get(opts, :output)
    batch_timeout = Keyword.get(opts, :batch_timeout, @default_batch_timeout)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    max_batch_size =
      Keyword.get(opts, :max_batch_size, batch_size * @default_batch_size_multiplier)

    state = %__MODULE__{
      output: output,
      runtime_resolver: Keyword.get(opts, :runtime_resolver),
      base_batch_timeout: batch_timeout,
      base_batch_size: batch_size,
      max_batch_size: max(max_batch_size, batch_size),
      metrics_id: Keyword.get(opts, :metrics_id),
      metrics_sample_rate: Keyword.get(opts, :metrics_sample_rate, 100),
      batch_timeout: batch_timeout,
      batch_size: batch_size,
      mode: Keyword.get(opts, :mode, :connect),
      coordinator_pid: Keyword.get(opts, :coordinator_pid),
      socket_owner: nil
    }

    {:ok, connect_output(state)}
  end

  @impl true
  def handle_cast({:packet, binary}, state) do
    new_state =
      state
      |> enqueue_packets([binary], 1, byte_size(binary))
      |> maybe_publish_status(state)

    {:noreply, new_state}
  end

  def handle_cast({:packets, binaries, packet_count, total_bytes}, state) do
    new_state =
      state
      |> enqueue_packets(binaries, packet_count, total_bytes)
      |> maybe_publish_status(state)

    {:noreply, new_state}
  end

  def handle_cast({:attach_socket, socket}, state) do
    {:noreply, %{state | socket: socket, socket_owner: :external}}
  end

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

  def handle_call(:flush, _from, state) do
    new_state =
      state
      |> cancel_flush_timer()
      |> do_flush(:manual)
      |> maybe_publish_status(state)

    {:reply, :ok, new_state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
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
     }, state}
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
    state
    |> cancel_flush_timer()
    |> do_flush(:manual)

    close_socket(state)
    :ok
  end

  defp do_flush(%{buffer: []} = state, _reason), do: state

  defp do_flush(state, flush_reason) do
    send_sample? =
      SimulatorMetrics.sample_timing?(state.metrics_sample_rate, state.flushes + 1)

    send_start =
      if send_sample?, do: System.monotonic_time(:microsecond), else: nil

    iolist = Enum.reverse(state.buffer)

    case do_send(state, iolist) do
      :ok ->
        SimulatorMetrics.inc(state.metrics_id, :tx_packets, state.packets_buffered)
        SimulatorMetrics.inc(state.metrics_id, :tx_bytes, state.buffer_bytes)

        if send_sample? do
          SimulatorMetrics.record_timing(
            state.metrics_id,
            :sending,
            System.monotonic_time(:microsecond) - send_start
          )
        end

        %{
          state
          | buffer: [],
            buffer_bytes: 0,
            packets_buffered: 0,
            packets_sent: state.packets_sent + state.packets_buffered,
            bytes_sent: state.bytes_sent + state.buffer_bytes,
            flushes: state.flushes + 1
        }
        |> adjust_batching(flush_reason, state.buffer_bytes)

      {:error, reason} ->
        Logger.warning(
          "SendBuffer flush failed: #{inspect(reason)}, dropping #{state.packets_buffered} packets; attempting reconnect"
        )

        state
        |> reconnect_output()
        |> Map.merge(%{buffer: [], buffer_bytes: 0, packets_buffered: 0})
    end
  end

  defp do_send(%{socket: nil} = state, _iolist), do: {:error, missing_socket_reason(state)}
  defp do_send(%{output: {:tcp, _, _}, socket: socket}, iolist), do: :gen_tcp.send(socket, iolist)

  defp do_send(%{output: {:udp, host, port}, socket: socket}, iolist) do
    :gen_udp.send(socket, String.to_charlist(host), port, IO.iodata_to_binary(iolist))
  end

  defp do_send(_, _), do: {:error, :invalid_output}

  defp missing_socket_reason(%{output: nil}), do: :no_output_configured
  defp missing_socket_reason(%{mode: :listen}), do: :no_client_connected
  defp missing_socket_reason(_), do: :not_connected

  defp connect_output(state), do: do_connect_output(state, true)

  defp do_connect_output(%{output: nil} = state, _allow_refresh?), do: state
  defp do_connect_output(%{mode: :listen, output: {:tcp, _, _}} = state, _allow_refresh?), do: state

  defp do_connect_output(%{output: {:tcp, host, port}} = state, allow_refresh?) do
    opts = [
      :binary,
      active: false,
      nodelay: true,
      sndbuf: @default_tcp_socket_buffer,
      recbuf: @default_tcp_socket_buffer,
      send_timeout: @default_send_timeout
    ]

    case :gen_tcp.connect(String.to_charlist(host), port, opts) do
      {:ok, socket} ->
        %{state | socket: socket, socket_owner: :internal}

      {:error, reason} ->
        Logger.warning("SendBuffer failed to connect to TCP #{host}:#{port}: #{inspect(reason)}")

        maybe_refresh_output_and_retry(state, allow_refresh?)
    end
  end

  defp do_connect_output(%{output: {:udp, _host, _port}} = state, _allow_refresh?) do
    case :gen_udp.open(0, [:binary, sndbuf: @default_tcp_socket_buffer, recbuf: @default_tcp_socket_buffer]) do
      {:ok, socket} ->
        %{state | socket: socket, socket_owner: :internal}

      {:error, reason} ->
        Logger.warning("SendBuffer failed to open UDP socket: #{inspect(reason)}")
        state
    end
  end

  defp do_connect_output(state, _allow_refresh?), do: state

  defp reconnect_output(%{mode: :listen} = state), do: %{state | socket: nil}
  defp reconnect_output(%{socket_owner: :external} = state), do: %{state | socket: nil}

  defp reconnect_output(state) do
    close_socket(state)

    state
    |> Map.put(:socket, nil)
    |> Map.put(:socket_owner, nil)
    |> maybe_refresh_output()
    |> connect_output()
  end

  defp close_socket(%{socket: nil}), do: :ok
  defp close_socket(%{socket_owner: :external}), do: :ok
  defp close_socket(%{output: {:tcp, _, _}, socket: socket}), do: :gen_tcp.close(socket)
  defp close_socket(%{output: {:udp, _, _}, socket: socket}), do: :gen_udp.close(socket)
  defp close_socket(_), do: :ok

  defp enqueue_packets(state, [], _packet_count, _total_bytes), do: state

  defp enqueue_packets(state, packets, packet_count, total_bytes) do
    was_empty = state.buffer == []

    updated_state = %{
      state
      | buffer: :lists.reverse(packets, state.buffer),
        buffer_bytes: state.buffer_bytes + total_bytes,
        packets_buffered: state.packets_buffered + packet_count
    }

    cond do
      updated_state.buffer_bytes >= state.batch_size ->
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
      new_state.buffer_bytes != previous_state.buffer_bytes or
      new_state.packets_sent != previous_state.packets_sent or
      new_state.bytes_sent != previous_state.bytes_sent or
      new_state.flushes != previous_state.flushes
  end

  defp notify_coordinator(%{coordinator_pid: pid} = state) when is_pid(pid) do
    send(pid, {:send_buffer_status, buffer_status(state)})
  end

  defp notify_coordinator(_state), do: :ok

  defp buffer_status(state) do
    %{
      status_version: state.status_version,
      packets_buffered: state.packets_buffered,
      buffer_bytes: state.buffer_bytes,
      packets_sent: state.packets_sent,
      bytes_sent: state.bytes_sent,
      flushes: state.flushes
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
    %{state | timer_ref: Process.send_after(self(), :flush, state.batch_timeout)}
  end

  defp schedule_flush(state), do: state

  defp cancel_flush_timer(%{timer_ref: nil} = state), do: state

  defp cancel_flush_timer(state) do
    Process.cancel_timer(state.timer_ref)
    %{state | timer_ref: nil}
  end

  defp clear_timer_ref(state), do: %{state | timer_ref: nil}

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)

  defp maybe_refresh_output_and_retry(state, false), do: state

  defp maybe_refresh_output_and_retry(state, true) do
    refreshed_state = maybe_refresh_output(state)

    if refreshed_state.output != state.output do
      do_connect_output(refreshed_state, false)
    else
      refreshed_state
    end
  end

  defp maybe_refresh_output(%{runtime_resolver: nil} = state), do: state

  defp maybe_refresh_output(state) do
    case resolve_runtime_updates(state.runtime_resolver) do
      {:ok, runtime_updates} ->
        case Keyword.fetch(runtime_updates, :output) do
          {:ok, output} ->
            maybe_log_output_refresh(state.output, output)
            %{state | output: output}

          :error ->
            state
        end

      {:error, reason} ->
        Logger.warning("SendBuffer failed to refresh runtime output: #{inspect(reason)}")
        state
    end
  end

  defp maybe_log_output_refresh(output, output), do: :ok

  defp maybe_log_output_refresh(previous_output, output) do
    Logger.info(
      "SendBuffer refreshed runtime output from #{format_output(previous_output)} to #{format_output(output)}"
    )
  end

  defp resolve_runtime_updates({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, args)
  end
end
