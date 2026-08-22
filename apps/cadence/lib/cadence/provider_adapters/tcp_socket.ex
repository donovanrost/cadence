defmodule Cadence.ProviderAdapters.TCPSocket do
  @moduledoc """
  Path-local TCP provider adapter.

  This adapter supports:

  - outbound uplink byte delivery over one TCP connection
  - inbound fixed-size downlink message ingest for simulator-style packet or
    frame streams
  - inbound fixed-size transport-event ingest for simulator-style COP-1 CLCW
    loopback
  - both `:connect` and `:listen` socket ownership modes
  """

  use GenServer

  @behaviour Cadence.ProviderAdapters.Adapter

  require Logger

  alias Cadence.ActionRequests.ProviderRequest
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.ProviderAdapters.TCPSocket.Instrumentation

  alias Cadence.Runtime.{
    IngressArchiveConsumer,
    IngressJournalConsumer,
    IngressPersistenceProjector,
    MissionRuntime,
    ProviderIngressExecutor
  }

  @tcp_socket_buffer 1_048_576
  @tcp_opts [
    :binary,
    packet: 0,
    active: false,
    reuseaddr: true,
    nodelay: true,
    sndbuf: @tcp_socket_buffer,
    recbuf: @tcp_socket_buffer
  ]
  @executor_high_watermark 8_192
  @executor_low_watermark 2_048
  @executor_capacity_retry_ms 1_000
  @journal_capacity_retry_ms 25

  @type mode :: :connect | :listen

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def child_spec(opts) when is_list(opts) do
    %{
      id: {:tcp_socket_provider, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @impl true
  def snapshot(provider_runtime) do
    GenServer.call(provider_runtime, :snapshot)
  end

  @impl true
  def quiesce(provider_runtime) do
    GenServer.call(provider_runtime, :quiesce, :infinity)
  catch
    :exit, {:noproc, _details} -> {:error, :tcp_provider_not_running}
    :exit, {:normal, _details} -> {:error, :tcp_provider_not_running}
  end

  @impl true
  def deliver_uplink(provider_runtime, %ProviderRequest{} = provider_request) do
    GenServer.call(provider_runtime, {:deliver_uplink, provider_request})
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    path_id = Keyword.fetch!(opts, :path_id)
    provider_binding_id = Keyword.fetch!(opts, :provider_binding_id)
    source_endpoint_ref = Keyword.get(opts, :source_endpoint_ref)
    direction = Keyword.fetch!(opts, :direction)
    configuration = normalize_configuration(Keyword.fetch!(opts, :configuration))

    base_state = %{
      mission_id: mission_id,
      realized_contact_id: realized_contact_id,
      path_id: path_id,
      provider_binding_id: provider_binding_id,
      source_endpoint_ref: source_endpoint_ref,
      source_endpoint_spacecraft_id: Keyword.get(opts, :source_endpoint_spacecraft_id),
      direction: direction,
      mode: configuration.mode,
      host: configuration.host,
      configured_port: configuration.port,
      port: configuration.port,
      ingress_protocol_family: configuration.ingress_protocol_family,
      fixed_message_bytes: configuration.fixed_message_bytes,
      ingress_transport_binding_id: configuration.ingress_transport_binding_id,
      ingress_executor_name: Keyword.fetch!(opts, :ingress_executor_name),
      ingress_journal_name: Keyword.get(opts, :ingress_journal_name),
      ingress_executor_pid: nil,
      ingress_executor_monitor_ref: nil,
      socket_receiver_pid: nil,
      socket_receiver_monitor_ref: nil,
      source_ref: configuration.source_ref,
      ingress_metadata: configuration.ingress_metadata,
      listener: nil,
      socket: nil,
      uplink_bytes_sent: 0,
      uplink_payload_count: 0,
      downlink_bytes_received: 0,
      downlink_message_count: 0,
      tcp_read_count: 0,
      last_delivery_at: nil,
      last_ingress_at: nil,
      last_ingress_error: nil,
      accept_ref: nil,
      reads_paused?: false,
      lifecycle_status: :active
    }

    case ensure_ingress_dependencies(base_state) do
      {:ok, base_state} ->
        start_socket_provider(configuration, base_state, provider_binding_id)

      {:error, reason} ->
        {:stop, {:tcp_provider_missing_ingress_dependency, provider_binding_id, reason}}
    end
  end

  defp start_socket_provider(%{mode: :connect} = configuration, base_state, provider_binding_id) do
    case connect_socket(configuration.host, configuration.port) do
      {:ok, socket} ->
        state =
          base_state
          |> Map.put(:socket, socket)
          |> start_socket_receiver!(socket)

        log_provider_started(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, {:tcp_provider_connect_failed, provider_binding_id, reason}}
    end
  end

  defp start_socket_provider(%{mode: :listen} = configuration, base_state, provider_binding_id) do
    case :gen_tcp.listen(configuration.port, listen_opts(configuration.host)) do
      {:ok, listener} ->
        port = listener_port(listener, configuration.port)
        state = %{base_state | listener: listener, port: port}
        log_provider_started(state)
        {:ok, schedule_accept(state)}

      {:error, reason} ->
        {:stop, {:tcp_provider_listen_failed, provider_binding_id, reason}}
    end
  end

  @impl true
  def handle_call(:quiesce, _from, %{lifecycle_status: :quiesced} = state) do
    {:reply, {:ok, quiescence_settlement(state)}, state}
  end

  def handle_call(:quiesce, _from, state) do
    case quiesce_socket_io(state) do
      {:ok, quiesced_state} ->
        {:reply, {:ok, quiescence_settlement(quiesced_state)}, quiesced_state}

      {:error, reason, next_state} ->
        {:reply, {:error, reason}, next_state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    ingress_executor =
      case ProviderIngressExecutor.snapshot(state.ingress_executor_name) do
        {:ok, snapshot} -> snapshot
        {:error, reason} -> %{error: inspect(reason)}
      end

    ingress_persistence_projector =
      case IngressPersistenceProjector.snapshot(
             MissionRuntime.provider_persistence_projector_name(
               state.mission_id,
               state.realized_contact_id,
               state.path_id,
               state.provider_binding_id
             )
           ) do
        {:ok, snapshot} -> snapshot
        {:error, reason} -> %{error: inspect(reason)}
      end

    ingress_journal = ingress_journal_snapshot(state)
    ingress_journal_consumer = ingress_journal_consumer_snapshot(state)
    ingress_archive_consumer = ingress_archive_consumer_snapshot(state)

    {:reply,
     {:ok,
      %{
        provider_binding_id: state.provider_binding_id,
        adapter_key: :tcp_socket,
        lifecycle_status: state.lifecycle_status,
        direction: state.direction,
        source_endpoint_ref: state.source_endpoint_ref,
        source_endpoint_spacecraft_id: state.source_endpoint_spacecraft_id,
        mode: state.mode,
        host: state.host,
        configured_port: state.configured_port,
        port: state.port,
        connected?: match?({:ok, _socket}, current_socket(state)),
        ingress_protocol_family: state.ingress_protocol_family,
        fixed_message_bytes: state.fixed_message_bytes,
        ingress_transport_binding_id: state.ingress_transport_binding_id,
        source_ref: state.source_ref,
        ingress_metadata: state.ingress_metadata,
        uplink_bytes_sent: state.uplink_bytes_sent,
        uplink_payload_count: state.uplink_payload_count,
        downlink_bytes_received: state.downlink_bytes_received,
        downlink_message_count: state.downlink_message_count,
        tcp_read_count: state.tcp_read_count,
        avg_tcp_read_bytes:
          if(state.tcp_read_count > 0,
            do: state.downlink_bytes_received / state.tcp_read_count,
            else: 0.0
          ),
        last_delivery_at: state.last_delivery_at,
        last_ingress_at: state.last_ingress_at,
        last_ingress_error: state.last_ingress_error,
        reads_paused?: state.reads_paused?,
        ingress_journal: ingress_journal,
        ingress_journal_consumer: ingress_journal_consumer,
        ingress_archive_consumer: ingress_archive_consumer,
        ingress_executor: ingress_executor,
        ingress_persistence_projector: ingress_persistence_projector
      }}, state}
  end

  def handle_call(
        {:deliver_uplink, %ProviderRequest{}},
        _from,
        %{lifecycle_status: :quiesced} = state
      ) do
    {:reply, {:error, :tcp_provider_quiesced}, state}
  end

  def handle_call({:deliver_uplink, %ProviderRequest{} = provider_request}, _from, state) do
    reply =
      with {:ok, socket} <- current_socket(state),
           {:ok, payloads, total_bytes} <- decode_payloads(provider_request.payloads_base64),
           :ok <- send_payloads(socket, payloads) do
        delivery_metadata = %{
          provider_binding_id: state.provider_binding_id,
          provider_adapter_key: :tcp_socket,
          host: state.host,
          port: state.port,
          bytes_sent: total_bytes,
          payload_count: length(payloads),
          delivered_at: DateTime.utc_now()
        }

        next_state = %{
          state
          | uplink_bytes_sent: state.uplink_bytes_sent + total_bytes,
            uplink_payload_count: state.uplink_payload_count + length(payloads),
            last_delivery_at: delivery_metadata.delivered_at
        }

        {:ok, delivery_metadata, next_state}
      end

    case reply do
      {:ok, delivery_metadata, next_state} ->
        {:reply, {:ok, delivery_metadata}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    level =
      case reason do
        :normal -> :info
        :shutdown -> :info
        {:shutdown, _detail} -> :info
        _other -> :error
      end

    Logger.log(
      level,
      "TCP provider #{state.provider_binding_id} terminating: #{inspect(reason)}"
    )

    maybe_stop_socket_receiver(state)
    :ok
  end

  @impl true
  def handle_info(
        {:accept_result, accept_ref, {:ok, socket, :ok}},
        %{accept_ref: accept_ref} = state
      ) do
    case current_socket(state) do
      {:ok, _existing_socket} ->
        :gen_tcp.close(socket)
        {:noreply, schedule_accept(%{state | accept_ref: nil})}

      {:error, :tcp_provider_not_connected} ->
        {:noreply,
         state
         |> Map.put(:socket, socket)
         |> Map.put(:accept_ref, nil)
         |> start_socket_receiver!(socket)}
    end
  end

  def handle_info(
        {:accept_result, accept_ref, {:ok, _socket, {:error, reason}}},
        %{accept_ref: accept_ref} = state
      ) do
    Logger.warning(
      "TCP provider socket handoff failed for #{state.provider_binding_id}: #{inspect(reason)}"
    )

    {:noreply, schedule_accept(%{state | accept_ref: nil})}
  end

  def handle_info(
        {:accept_result, accept_ref, {:error, reason}},
        %{accept_ref: accept_ref} = state
      ) do
    Logger.warning(
      "TCP provider accept failed for #{state.provider_binding_id}: #{inspect(reason)}"
    )

    {:noreply, %{state | accept_ref: nil}}
  end

  def handle_info({:accept_result, _stale_ref, {:ok, socket, _handoff}}, state) do
    close_socket(socket)
    {:noreply, state}
  end

  def handle_info({:accept_result, _stale_ref, {:error, _reason}}, state),
    do: {:noreply, state}

  def handle_info({:tcp_receiver_batch, receiver_pid, batch_status}, state) do
    next_state =
      if receiver_matches?(state, receiver_pid) do
        apply_receiver_batch_status(state, batch_status)
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info({:tcp_receiver_reads_paused, receiver_pid, paused?}, state) do
    next_state =
      if receiver_matches?(state, receiver_pid) do
        %{state | reads_paused?: paused?}
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, executor_pid, _reason},
        %{
          lifecycle_status: :quiesced,
          ingress_executor_monitor_ref: monitor_ref,
          ingress_executor_pid: executor_pid
        } = state
      ) do
    {:noreply, %{state | ingress_executor_pid: nil, ingress_executor_monitor_ref: nil}}
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, executor_pid, reason},
        %{ingress_executor_monitor_ref: monitor_ref, ingress_executor_pid: executor_pid} = state
      ) do
    Logger.warning(
      "TCP provider ingress executor exited for #{state.provider_binding_id}: #{inspect(reason)}"
    )

    {:noreply, %{state | ingress_executor_pid: nil, ingress_executor_monitor_ref: nil}}
  end

  def handle_info({:tcp_receiver_closed, receiver_pid, reason}, state) do
    next_state =
      if receiver_matches?(state, receiver_pid) do
        Logger.log(
          socket_close_log_level(reason),
          "TCP provider socket closed for #{state.provider_binding_id}: #{inspect(reason)}"
        )

        state
        |> maybe_demonitor_socket_receiver()
        |> Map.put(:socket_receiver_pid, nil)
        |> Map.put(:socket, nil)
        |> Map.put(:last_ingress_error, inspect(reason))
        |> maybe_schedule_accept_after_disconnect()
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, receiver_pid, reason},
        %{socket_receiver_monitor_ref: monitor_ref, socket_receiver_pid: receiver_pid} = state
      ) do
    next_state =
      state
      |> Map.put(:socket_receiver_pid, nil)
      |> Map.put(:socket_receiver_monitor_ref, nil)
      |> Map.put(:socket, nil)
      |> maybe_put_receiver_down_error(reason)
      |> maybe_schedule_accept_after_disconnect()

    if reason not in [:normal, :shutdown] do
      Logger.warning(
        "TCP provider receiver exited for #{state.provider_binding_id}: #{inspect(reason)}"
      )
    end

    {:noreply, next_state}
  end

  defp normalize_configuration(configuration) when is_map(configuration) do
    mode =
      case Map.get(configuration, :mode, Map.get(configuration, "mode", :connect)) do
        :connect -> :connect
        "connect" -> :connect
        :listen -> :listen
        "listen" -> :listen
      end

    ingress_protocol_family =
      case Map.get(
             configuration,
             :ingress_protocol_family,
             Map.get(configuration, "ingress_protocol_family")
           ) do
        nil ->
          nil

        protocol_family when is_atom(protocol_family) ->
          protocol_family

        protocol_family when is_binary(protocol_family) ->
          String.to_existing_atom(protocol_family)
      end

    %{
      mode: mode,
      host: Map.get(configuration, :host, Map.get(configuration, "host", "127.0.0.1")),
      port: Map.get(configuration, :port, Map.get(configuration, "port", 0)),
      ingress_protocol_family: ingress_protocol_family,
      fixed_message_bytes:
        Map.get(
          configuration,
          :fixed_message_bytes,
          Map.get(configuration, "fixed_message_bytes")
        ) ||
          Map.get(configuration, :frame_size, Map.get(configuration, "frame_size")),
      ingress_transport_binding_id:
        Map.get(
          configuration,
          :ingress_transport_binding_id,
          Map.get(configuration, "ingress_transport_binding_id")
        ),
      source_ref: Map.get(configuration, :source_ref, Map.get(configuration, "source_ref")),
      ingress_metadata:
        Map.get(configuration, :ingress_metadata, Map.get(configuration, "ingress_metadata", %{}))
    }
  end

  defp connect_socket(host, port) when is_binary(host) and is_integer(port) do
    :gen_tcp.connect(String.to_charlist(host), port, @tcp_opts)
  end

  defp listen_opts(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> [{:ip, ip} | @tcp_opts]
      {:error, _reason} -> @tcp_opts
    end
  end

  defp listener_port(listener, fallback_port) do
    case :inet.sockname(listener) do
      {:ok, {_address, actual_port}} -> actual_port
      {:error, _reason} -> fallback_port
    end
  end

  defp schedule_accept(%{lifecycle_status: :active, listener: listener} = state)
       when not is_nil(listener) do
    accept_ref = make_ref()
    parent = self()

    Task.start(fn ->
      result =
        case :gen_tcp.accept(listener) do
          {:ok, socket} ->
            {:ok, socket, :gen_tcp.controlling_process(socket, parent)}

          {:error, reason} ->
            {:error, reason}
        end

      send(parent, {:accept_result, accept_ref, result})
    end)

    %{state | accept_ref: accept_ref}
  end

  defp schedule_accept(state), do: state

  defp current_socket(%{socket: socket}) when is_port(socket), do: {:ok, socket}
  defp current_socket(_state), do: {:error, :tcp_provider_not_connected}

  defp decode_payloads(payloads_base64) when is_list(payloads_base64) do
    Enum.reduce_while(payloads_base64, {:ok, [], 0}, fn payload_base64, {:ok, acc, total_bytes} ->
      case Base.decode64(payload_base64) do
        {:ok, payload} ->
          {:cont, {:ok, acc ++ [payload], total_bytes + byte_size(payload)}}

        :error ->
          {:halt, {:error, {:invalid_provider_payload_base64, payload_base64}}}
      end
    end)
  end

  defp send_payloads(socket, payloads) when is_list(payloads) do
    Enum.reduce_while(payloads, :ok, fn payload, :ok ->
      case :gen_tcp.send(socket, payload) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:tcp_provider_send_failed, reason}}}
      end
    end)
  end

  defp split_fixed_messages(buffer, bytes, acc) when byte_size(buffer) >= bytes do
    <<message::binary-size(^bytes), rest::binary>> = buffer
    split_fixed_messages(rest, bytes, [message | acc])
  end

  defp split_fixed_messages(buffer, _bytes, acc), do: {Enum.reverse(acc), buffer}

  defp log_provider_started(state) do
    Logger.info(
      "TCP provider #{state.provider_binding_id} started in #{state.mode} mode on #{state.host}:#{state.port}"
    )
  end

  defp start_socket_receiver!(state, socket) do
    state = maybe_stop_socket_receiver(state)
    receiver_state = socket_receiver_state(state)

    receiver_pid =
      spawn(fn ->
        receive do
          {:socket, receiver_socket} ->
            socket_receiver_loop(%{receiver_state | socket: receiver_socket})
        end
      end)

    :ok = :gen_tcp.controlling_process(socket, receiver_pid)
    send(receiver_pid, {:socket, socket})

    %{
      state
      | socket_receiver_pid: receiver_pid,
        socket_receiver_monitor_ref: Process.monitor(receiver_pid),
        reads_paused?: false
    }
  end

  defp socket_receiver_state(state) do
    %{
      provider_pid: self(),
      provider_binding_id: state.provider_binding_id,
      ingress_executor_name: state.ingress_executor_name,
      ingress_journal_name: state.ingress_journal_name,
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      path_id: state.path_id,
      source_endpoint_ref: state.source_endpoint_ref,
      source_endpoint_spacecraft_id: state.source_endpoint_spacecraft_id,
      direction: state.direction,
      ingress_protocol_family: state.ingress_protocol_family,
      fixed_message_bytes: state.fixed_message_bytes,
      ingress_transport_binding_id: state.ingress_transport_binding_id,
      source_ref: state.source_ref,
      ingress_metadata: state.ingress_metadata,
      socket: nil,
      receive_buffer: <<>>,
      message_remainder_bytes: 0,
      reads_paused?: false,
      capacity_wait_ref: nil
    }
  end

  defp socket_receiver_loop(%{ingress_journal_name: nil} = state) do
    state = maybe_wait_for_executor_capacity(state)
    receive_started_at = System.monotonic_time()

    case :gen_tcp.recv(state.socket, 0) do
      {:ok, data} ->
        Instrumentation.record_receive(state, data, elapsed_us(receive_started_at))
        receipt_time = DateTime.utc_now()
        {next_state, batch_status} = consume_socket_data(state, data, receipt_time)
        send(state.provider_pid, {:tcp_receiver_batch, self(), batch_status})
        socket_receiver_loop(next_state)

      {:error, reason} ->
        send(state.provider_pid, {:tcp_receiver_closed, self(), reason})
        :ok
    end
  end

  defp socket_receiver_loop(state) do
    receive_started_at = System.monotonic_time()

    case :gen_tcp.recv(state.socket, 0) do
      {:ok, data} ->
        Instrumentation.record_receive(state, data, elapsed_us(receive_started_at))
        receipt_time = DateTime.utc_now()
        next_state = capture_socket_data(state, data, receipt_time)
        socket_receiver_loop(next_state)

      {:error, reason} ->
        send(state.provider_pid, {:tcp_receiver_closed, self(), reason})
        :ok
    end
  end

  defp capture_socket_data(state, data, receipt_time) do
    case IngressJournal.append_stream(
           state.ingress_journal_name,
           data,
           receipt_time,
           journal_metadata(state)
         ) do
      {:ok, _entries} ->
        {message_count, message_remainder_bytes} = journal_message_count(state, data)

        if state.reads_paused? do
          send(state.provider_pid, {:tcp_receiver_reads_paused, self(), false})
        end

        send(
          state.provider_pid,
          {:tcp_receiver_batch, self(),
           %{
             bytes_received: byte_size(data),
             read_count: 1,
             message_count: message_count,
             last_ingress_at: receipt_time,
             last_ingress_error: nil
           }}
        )

        %{state | reads_paused?: false, message_remainder_bytes: message_remainder_bytes}

      {:error, :ingress_journal_full} ->
        if not state.reads_paused? do
          send(state.provider_pid, {:tcp_receiver_reads_paused, self(), true})
        end

        receive do
        after
          @journal_capacity_retry_ms ->
            capture_socket_data(%{state | reads_paused?: true}, data, receipt_time)
        end

      {:error, reason} ->
        send(
          state.provider_pid,
          {:tcp_receiver_batch, self(),
           %{
             bytes_received: byte_size(data),
             read_count: 1,
             message_count: 0,
             last_ingress_at: receipt_time,
             last_ingress_error: inspect(reason)
           }}
        )

        exit({:ingress_journal_append_failed, reason})
    end
  end

  defp journal_message_count(%{fixed_message_bytes: bytes} = state, data)
       when is_integer(bytes) and bytes > 0 do
    total_bytes = state.message_remainder_bytes + byte_size(data)
    {div(total_bytes, bytes), rem(total_bytes, bytes)}
  end

  defp journal_message_count(state, _data), do: {0, state.message_remainder_bytes}

  defp journal_metadata(state) do
    %{
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      path_id: state.path_id,
      provider_binding_id: state.provider_binding_id,
      source_endpoint_ref: state.source_endpoint_ref,
      spacecraft_id: state.source_endpoint_spacecraft_id,
      protocol_family: state.ingress_protocol_family,
      direction: state.direction,
      source_ref: state.source_ref || state.provider_binding_id,
      ingress_metadata: state.ingress_metadata || %{}
    }
  end

  defp maybe_wait_for_executor_capacity(state) do
    case ProviderIngressExecutor.snapshot(state.ingress_executor_name) do
      {:ok, snapshot} ->
        queue_depth = Map.get(snapshot, :queue_depth, 0)

        cond do
          state.reads_paused? and queue_depth >= @executor_low_watermark ->
            wait_for_executor_capacity_signal(state)

          state.reads_paused? ->
            send(state.provider_pid, {:tcp_receiver_reads_paused, self(), false})

            state
            |> cancel_capacity_waiter()
            |> Map.merge(%{reads_paused?: false, capacity_wait_ref: nil})

          queue_depth >= @executor_high_watermark ->
            state
            |> pause_socket_reads()
            |> wait_for_executor_capacity_signal()

          true ->
            state
        end

      {:error, _reason} ->
        wait_for_executor_capacity_retry(state)
    end
  end

  defp pause_socket_reads(state) do
    send(state.provider_pid, {:tcp_receiver_reads_paused, self(), true})
    %{state | reads_paused?: true}
  end

  defp wait_for_executor_capacity_signal(state) do
    {state, ref} = ensure_capacity_waiter(state)

    receive do
      {:provider_ingress_capacity_available, _executor_pid, ^ref, _queue_depth} ->
        maybe_wait_for_executor_capacity(%{state | capacity_wait_ref: nil})

      {:provider_ingress_capacity_available, _executor_pid, _stale_ref, _queue_depth} ->
        wait_for_executor_capacity_signal(state)
    after
      @executor_capacity_retry_ms ->
        maybe_wait_for_executor_capacity(state)
    end
  end

  defp ensure_capacity_waiter(%{capacity_wait_ref: ref} = state) when is_reference(ref) do
    register_capacity_waiter(state, ref)
  end

  defp ensure_capacity_waiter(state) do
    register_capacity_waiter(state, make_ref())
  end

  defp register_capacity_waiter(state, ref) do
    _ =
      ProviderIngressExecutor.notify_when_below(
        state.ingress_executor_name,
        @executor_low_watermark,
        self(),
        ref
      )

    {%{state | capacity_wait_ref: ref}, ref}
  end

  defp cancel_capacity_waiter(%{capacity_wait_ref: ref} = state) when is_reference(ref) do
    _ = ProviderIngressExecutor.cancel_notify_when_below(state.ingress_executor_name, ref)
    state
  end

  defp cancel_capacity_waiter(state), do: state

  defp wait_for_executor_capacity_retry(state) do
    receive do
      {:provider_ingress_capacity_available, _executor_pid, _ref, _queue_depth} ->
        maybe_wait_for_executor_capacity(%{state | capacity_wait_ref: nil})
    after
      @executor_capacity_retry_ms ->
        maybe_wait_for_executor_capacity(state)
    end
  end

  defp consume_socket_data(
         %{
           direction: :downlink,
           ingress_protocol_family: protocol_family,
           fixed_message_bytes: bytes
         } = state,
         data,
         receipt_time
       )
       when protocol_family in [
              :space_packet,
              :packet,
              :space_packet_stream,
              :tm,
              :tm_transfer_frame
            ] and
              is_integer(bytes) and bytes > 0 do
    buffer = state.receive_buffer <> data
    {messages, rest} = split_fixed_messages(buffer, bytes, [])

    {message_count, last_ingress_error} =
      enqueue_telemetry_messages(state, protocol_family, messages, receipt_time)

    {%{state | receive_buffer: rest},
     %{
       bytes_received: byte_size(data),
       read_count: 1,
       message_count: message_count,
       last_ingress_at: if(message_count > 0 or last_ingress_error, do: receipt_time, else: nil),
       last_ingress_error: last_ingress_error
     }}
  end

  defp consume_socket_data(
         %{ingress_protocol_family: :cop1_clcw, fixed_message_bytes: bytes} = state,
         data,
         receipt_time
       )
       when is_integer(bytes) and bytes > 0 do
    buffer = state.receive_buffer <> data
    {messages, rest} = split_fixed_messages(buffer, bytes, [])

    {message_count, last_ingress_error} =
      enqueue_transport_event_messages(state, messages, receipt_time)

    {%{state | receive_buffer: rest},
     %{
       bytes_received: byte_size(data),
       read_count: 1,
       message_count: message_count,
       last_ingress_at: if(message_count > 0 or last_ingress_error, do: receipt_time, else: nil),
       last_ingress_error: last_ingress_error
     }}
  end

  defp consume_socket_data(state, data, _receipt_time) do
    {%{state | receive_buffer: state.receive_buffer <> data},
     %{
       bytes_received: byte_size(data),
       read_count: 1,
       message_count: 0,
       last_ingress_at: nil,
       last_ingress_error: nil
     }}
  end

  defp elapsed_us(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp enqueue_telemetry_messages(_state, _protocol_family, [], _receipt_time), do: {0, nil}

  defp enqueue_telemetry_messages(state, protocol_family, messages, receipt_time) do
    raw_evidences =
      Enum.map(messages, fn message ->
        RawEvidence.new(%{
          mission_id: state.mission_id,
          source_endpoint_ref: state.source_endpoint_ref,
          spacecraft_id: state.source_endpoint_spacecraft_id,
          protocol_family: protocol_family,
          direction: :downlink,
          raw: message,
          receipt_time: receipt_time,
          source_ref: state.source_ref || state.provider_binding_id,
          metadata:
            Map.merge(state.ingress_metadata || %{}, %{
              "realized_contact_id" => state.realized_contact_id,
              "path_id" => state.path_id,
              "provider_binding_id" => state.provider_binding_id
            })
        })
      end)

    case ProviderIngressExecutor.enqueue_many_telemetry(
           state.ingress_executor_name,
           raw_evidences
         ) do
      :ok -> {length(messages), nil}
      {:error, reason} -> {0, inspect(reason)}
    end
  end

  defp enqueue_transport_event_messages(
         %{ingress_transport_binding_id: nil},
         _messages,
         _receipt_time
       ),
       do: {0, "missing_ingress_transport_binding_id"}

  defp enqueue_transport_event_messages(_state, [], _receipt_time), do: {0, nil}

  defp enqueue_transport_event_messages(state, messages, receipt_time) do
    events =
      Enum.map(messages, fn message ->
        %{kind: :cop1_clcw, clcw_binary: message}
      end)

    case ProviderIngressExecutor.enqueue_many_transport_events(
           state.ingress_executor_name,
           state.ingress_transport_binding_id,
           events,
           mission_id: state.mission_id,
           realized_contact_id: state.realized_contact_id,
           path_id: state.path_id,
           occurred_at: receipt_time
         ) do
      :ok -> {length(messages), nil}
      {:error, reason} -> {0, inspect(reason)}
    end
  end

  defp apply_receiver_batch_status(state, batch_status) do
    state
    |> Map.update!(:downlink_bytes_received, &(&1 + Map.get(batch_status, :bytes_received, 0)))
    |> Map.update!(:tcp_read_count, &(&1 + Map.get(batch_status, :read_count, 0)))
    |> Map.update!(:downlink_message_count, &(&1 + Map.get(batch_status, :message_count, 0)))
    |> maybe_put_batch_timestamp(batch_status[:last_ingress_at])
    |> maybe_put_batch_error(batch_status[:last_ingress_error])
  end

  defp maybe_put_batch_timestamp(state, nil), do: state
  defp maybe_put_batch_timestamp(state, timestamp), do: %{state | last_ingress_at: timestamp}

  defp maybe_put_batch_error(state, nil), do: %{state | last_ingress_error: nil}
  defp maybe_put_batch_error(state, error), do: %{state | last_ingress_error: error}

  defp maybe_put_receiver_down_error(state, reason) when reason in [:normal, :shutdown], do: state

  defp maybe_put_receiver_down_error(state, reason),
    do: %{state | last_ingress_error: inspect(reason)}

  defp socket_close_log_level(:closed), do: :info
  defp socket_close_log_level(_reason), do: :warning

  defp maybe_schedule_accept_after_disconnect(
         %{lifecycle_status: :active, mode: :listen} = state
       ),
       do: schedule_accept(state)

  defp maybe_schedule_accept_after_disconnect(state), do: state

  defp receiver_matches?(%{socket_receiver_pid: pid}, pid) when is_pid(pid), do: true
  defp receiver_matches?(_state, _pid), do: false

  defp maybe_stop_socket_receiver(%{socket_receiver_pid: pid} = state) when is_pid(pid) do
    Process.exit(pid, :shutdown)

    state
    |> maybe_demonitor_socket_receiver()
    |> Map.put(:socket_receiver_pid, nil)
    |> Map.put(:socket_receiver_monitor_ref, nil)
  end

  defp maybe_stop_socket_receiver(state), do: state

  defp maybe_demonitor_socket_receiver(%{socket_receiver_monitor_ref: monitor_ref} = state)
       when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    %{state | socket_receiver_monitor_ref: nil}
  end

  defp maybe_demonitor_socket_receiver(state), do: state

  defp quiesce_socket_io(state) do
    close_socket(state.listener)
    close_socket(state.socket)

    case stop_socket_receiver_and_wait(state) do
      {:ok, stopped_state} ->
        {:ok,
         %{
           stopped_state
           | lifecycle_status: :quiesced,
             listener: nil,
             socket: nil,
             accept_ref: nil,
             reads_paused?: false
         }}

      {:error, reason, stopped_state} ->
        {:error, reason, %{stopped_state | listener: nil, socket: nil, accept_ref: nil}}
    end
  end

  defp stop_socket_receiver_and_wait(%{socket_receiver_pid: pid} = state) when is_pid(pid) do
    monitor_ref = state.socket_receiver_monitor_ref || Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        {:ok,
         %{
           state
           | socket_receiver_pid: nil,
             socket_receiver_monitor_ref: nil
         }}
    after
      5_000 ->
        {:error, :tcp_provider_receiver_stop_timeout, state}
    end
  end

  defp stop_socket_receiver_and_wait(state), do: {:ok, state}

  defp close_socket(socket) when is_port(socket) do
    _ = :gen_tcp.close(socket)
    :ok
  end

  defp close_socket(_socket), do: :ok

  defp quiescence_settlement(state) do
    %{
      status: :quiesced,
      provider_binding_id: state.provider_binding_id,
      socket_closed?: is_nil(state.socket),
      listener_closed?: is_nil(state.listener),
      receiver_stopped?: is_nil(state.socket_receiver_pid)
    }
  end

  defp ingress_journal_snapshot(%{ingress_journal_name: nil}), do: nil

  defp ingress_journal_snapshot(state) do
    case IngressJournal.snapshot(state.ingress_journal_name) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp ingress_journal_consumer_snapshot(%{ingress_journal_name: nil}), do: nil

  defp ingress_journal_consumer_snapshot(state) do
    name =
      MissionRuntime.provider_ingress_journal_consumer_name(
        state.mission_id,
        state.realized_contact_id,
        state.path_id,
        state.provider_binding_id
      )

    case IngressJournalConsumer.snapshot(name) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp ingress_archive_consumer_snapshot(%{ingress_journal_name: nil}), do: nil

  defp ingress_archive_consumer_snapshot(state) do
    name =
      MissionRuntime.provider_ingress_archive_consumer_name(
        state.mission_id,
        state.realized_contact_id,
        state.path_id,
        state.provider_binding_id
      )

    case IngressArchiveConsumer.snapshot(name) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp ensure_ingress_dependencies(state) do
    with {:ok, state} <- resolve_ingress_executor(state),
         :ok <- ensure_ingress_journal(state) do
      {:ok, state}
    end
  end

  defp ensure_ingress_journal(%{ingress_journal_name: nil}), do: :ok

  defp ensure_ingress_journal(state) do
    case IngressJournal.lookup(state.ingress_journal_name) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_ingress_executor(state) do
    with {:ok, pid} <- ProviderIngressExecutor.lookup(state.ingress_executor_name) do
      next_state =
        state
        |> maybe_demonitor_ingress_executor()
        |> Map.put(:ingress_executor_pid, pid)
        |> Map.put(:ingress_executor_monitor_ref, Process.monitor(pid))

      {:ok, next_state}
    end
  end

  defp maybe_demonitor_ingress_executor(%{ingress_executor_monitor_ref: monitor_ref} = state)
       when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    %{state | ingress_executor_monitor_ref: nil}
  end

  defp maybe_demonitor_ingress_executor(state), do: state
end
