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
  alias Cadence.Comms.PeerAddresses
  alias Cadence.Ingress.{RawEvidence, ReceiveBackpressure}
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Platform.SnapshotCall
  alias Cadence.ProviderAdapters.TCPSocket.{Configuration, IngressDrops, Instrumentation, Session}

  alias Cadence.Runtime.{
    IngressArchiveConsumer,
    IngressJournalConsumer,
    IngressPersistenceProjector,
    MissionRuntime,
    ProcessNamespace,
    ProfileAcceptor,
    ProviderIngressExecutor,
    TransportRecords
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
  # Re-registering after the acceptor died: the first retry is quick (after a kill the old
  # listener may still be closing as we bind), later ones back off (api-ops, lead).
  @reregister_first_retry_ms 250
  @reregister_retry_ms 5_000
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
  def uplink_session(provider_runtime), do: GenServer.call(provider_runtime, :uplink_session)

  @doc "Whether a provider configuration asks for the profile's shared listener (#87)."
  defdelegate shared_listener_config?(configuration), to: Configuration

  @doc "Whether a listen-mode binding on a path of `direction` binds its OWN socket (#361)."
  defdelegate own_listener?(configuration, direction), to: Configuration

  @impl true
  def drop_unverified_peer(provider_runtime, peer, reason),
    do: GenServer.call(provider_runtime, {:drop_unverified_peer, peer, reason})

  @impl true
  def snapshot(provider_runtime) do
    # #334: a read never takes its caller (the path coordinator) down.
    SnapshotCall.call(provider_runtime, :snapshot, :provider)
  end

  @doc """
  A shared-listener adapter's refusal state (#87, ux U50), without the full snapshot:
  `{:ok, %{connected?, refusals, second_connections_refused, peers_refused}}`. `refusals` is the
  refusal window (nil until a refusal opens one).
  """
  @spec refusals(GenServer.server()) :: {:ok, map()}
  def refusals(provider_runtime), do: GenServer.call(provider_runtime, :refusals)

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
    configuration = Configuration.normalize(Keyword.fetch!(opts, :configuration))

    base_state = %{
      mission_id: mission_id,
      realized_contact_id: realized_contact_id,
      path_id: path_id,
      provider_binding_id: provider_binding_id,
      source_endpoint_ref: source_endpoint_ref,
      source_endpoint_spacecraft_id: Keyword.get(opts, :source_endpoint_spacecraft_id),
      source_endpoint_spacecraft_scid: Keyword.get(opts, :source_endpoint_spacecraft_scid),
      process_namespace: Keyword.get(opts, :process_namespace),
      acceptor?: false,
      peers_refused: 0,
      last_peer_refused: nil,
      refusals: nil,
      second_connections_refused: 0,
      connected_at: nil,
      quiet_connection_ms: configuration.quiet_connection_ms,
      allowed_peers: configuration.allowed_peers,
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

    base_state = Session.initialize(base_state, opts)

    with :ok <- validate_configuration(configuration, provider_binding_id) do
      case ensure_ingress_dependencies(base_state) do
        {:ok, base_state} ->
          start_socket_provider(configuration, base_state, provider_binding_id)

        {:error, reason} ->
          {:stop, {:tcp_provider_missing_ingress_dependency, provider_binding_id, reason}}
      end
    end
  end

  # (#990, DECISIONS #115) A listening endpoint must name the peers it accepts; one without an
  # allowlist never starts, so no unidentified peer can reach a contact.
  defp validate_configuration(%{mode: :listen, allowed_peers: []}, provider_binding_id),
    do:
      {:stop,
       {:tcp_provider_invalid_configuration, provider_binding_id, :expected_peer_addresses}}

  # (api-ops) A profile's quiet_connection_ms must be a positive integer (a numeric string is
  # coerced in normalize_configuration/1); anything else would never compare as quiet.
  defp validate_configuration(%{quiet_connection_ms: ms}, _provider_binding_id)
       when is_integer(ms) and ms > 0,
       do: :ok

  defp validate_configuration(%{quiet_connection_ms: ms}, provider_binding_id),
    do:
      {:stop,
       {:tcp_provider_invalid_configuration, provider_binding_id, {:quiet_connection_ms, ms}}}

  defp start_socket_provider(%{mode: :connect} = configuration, base_state, provider_binding_id) do
    case connect_socket(configuration.host, configuration.port) do
      {:ok, socket} ->
        state =
          base_state
          |> Map.put(:socket, socket)
          |> Session.connected()
          |> start_socket_receiver!(socket)

        log_provider_started(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, {:tcp_provider_connect_failed, provider_binding_id, reason}}
    end
  end

  # (#87) Downlink: register with the profile's acceptor instead of listening on its fixed port, so
  # overlapping contacts on one profile coexist. Uplink keeps its own listener (stage 2).
  defp start_socket_provider(
         %{mode: :listen, shared_listener?: true} = configuration,
         %{direction: :downlink} = base_state,
         provider_binding_id
       ) do
    listen = %{
      host: configuration.host,
      port: configuration.port,
      allowed_peers: configuration.allowed_peers
    }

    registration = %{
      adapter: self(),
      realized_contact_id: base_state.realized_contact_id,
      path_id: base_state.path_id,
      provider_binding_id: provider_binding_id,
      scid: base_state.source_endpoint_spacecraft_scid,
      frame_size: configuration.fixed_message_bytes
    }

    namespace = acceptor_namespace(base_state)

    case ProfileAcceptor.register(
           namespace,
           base_state.mission_id,
           provider_binding_id,
           listen,
           registration
         ) do
      {:ok, port, acceptor} ->
        # If the acceptor dies, its listener closes but our socket (if any) lives on; register
        # again so the next peer can reach us (handle_info :DOWN). We monitor the acceptor that
        # took the registration: if it already died, :DOWN (:noproc) arrives at once.
        state =
          Map.merge(base_state, %{
            acceptor?: true,
            port: port,
            acceptor_monitor_ref: Process.monitor(acceptor),
            acceptor_registration: {listen, registration},
            reregister_failures: 0
          })

        log_provider_started(state)
        {:ok, state}

      {:error, {:tcp_provider_listen_failed, _profile, _reason} = reason} ->
        {:stop, reason}

      {:error, reason} ->
        {:stop, {:tcp_provider_listen_failed, provider_binding_id, reason}}
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
  def handle_call(:uplink_session, _from, state), do: {:reply, Session.handle(state), state}

  # DECISIONS #67: qualification couldn't verify this connection's peer (a stray or unexpected
  # peer took the listener). Drop it and keep accepting, so the attested peer can connect.
  def handle_call(
        {:drop_unverified_peer, peer, reason},
        _from,
        %{socket: socket, session_peer: peer} = state
      )
      when is_port(socket) and is_binary(peer) do
    state =
      Session.warn_peer(
        state,
        :dropped,
        peer,
        "TCP provider #{state.provider_binding_id} dropped unverified peer #{peer}: " <>
          inspect(reason)
      )

    close_socket(socket)

    {:reply, :ok,
     state
     |> Session.block(:unverified_peer_connected)
     |> maybe_stop_socket_receiver()
     |> Map.put(:socket, nil)
     |> Map.put(:session_peer, nil)
     |> maybe_schedule_accept_after_disconnect()}
  end

  def handle_call({:drop_unverified_peer, _peer, _reason}, _from, state),
    do: {:reply, {:error, :peer_not_connected}, state}

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

  def handle_call(:refusals, _from, state) do
    {:reply,
     {:ok,
      %{
        connected?: match?({:ok, _socket}, current_socket(state)),
        refusals: state.refusals,
        second_connections_refused: state.second_connections_refused,
        peers_refused: state.peers_refused
      }}, state}
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
        uplink_session: Session.snapshot(state),
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
        shared_listener?: state.acceptor?,
        peers_refused: state.peers_refused,
        refusals: state.refusals,
        second_connections_refused: state.second_connections_refused,
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
           :ok <- deliver_payloads(state, provider_request, socket, payloads) do
        delivery_metadata = %{
          preparation_id: provider_request.preparation_id,
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

    Session.block(state, :provider_stopped)
    maybe_stop_socket_receiver(state)
    :ok
  end

  # (#87) The profile acceptor identified this peer as ours: the same connected path as an accept,
  # with the bytes it read to identify it handed to the receiver first.
  @impl true
  def handle_info({:peer_accepted, socket, prefix, peer, read_at}, %{acceptor?: true} = state) do
    case current_socket(state) do
      {:ok, _existing_socket} ->
        state =
          Session.warn_peer(
            state,
            :refused,
            peer,
            "TCP provider #{state.provider_binding_id} refused a second connection from " <>
              "#{peer}; #{state.session_peer} is connected"
          )

        :gen_tcp.close(socket)
        {:noreply, refuse_second_connection(state, peer)}

      {:error, :tcp_provider_not_connected} ->
        {:noreply,
         state
         |> Map.put(:socket, socket)
         |> Map.put(:connected_at, DateTime.utc_now())
         |> Session.connected()
         |> resolve_refusals()
         |> start_socket_receiver!(socket, {prefix, read_at})}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{acceptor?: true, acceptor_monitor_ref: ref} = state
      ) do
    Logger.warning(
      "TCP provider #{state.provider_binding_id} lost its profile acceptor (#{inspect(reason)}); " <>
        "registering again"
    )

    {:noreply, reregister(state)}
  end

  def handle_info({:peer_refused, peer, reason}, %{acceptor?: true} = state),
    do: {:noreply, count_refusal(state, peer, reason)}

  # (api-ops) Re-registration failed after the acceptor died: keep the live session, retry later.
  # A stale retry once registered again is ignored (no second monitor).
  def handle_info(:reregister, %{acceptor?: true, acceptor_monitor_ref: ref} = state)
      when is_reference(ref),
      do: {:noreply, state}

  def handle_info(:reregister, %{acceptor?: true} = state), do: {:noreply, reregister(state)}

  def handle_info(
        {:accept_result, accept_ref, {:ok, socket, :ok}},
        %{accept_ref: accept_ref} = state
      ) do
    if peer_allowed?(state, socket),
      do: accept_peer(socket, state),
      else: {:noreply, refuse_unallowed_peer(socket, %{state | accept_ref: nil})}
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
    # The pending accept (#67) ends with :closed when the listener is quiesced: not a fault.
    if state.lifecycle_status == :active do
      Logger.warning(
        "TCP provider accept failed for #{state.provider_binding_id}: #{inspect(reason)}"
      )
    end

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
        |> Session.block(:connection_lost)
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
      |> Session.block(:connection_lost)
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

  # An allowed peer reached our own listener: take it, or refuse it as a second connection.
  defp accept_peer(socket, state) do
    case current_socket(state) do
      {:ok, _existing_socket} ->
        # DECISIONS #67: never refuse silently; a second peer on a listener is a finding.
        state =
          Session.warn_peer(
            state,
            :refused,
            Session.peer_of(socket),
            "TCP provider #{state.provider_binding_id} refused a second connection from " <>
              "#{Session.peer_of(socket)}; #{state.session_peer} is connected"
          )

        :gen_tcp.close(socket)
        {:noreply, schedule_accept(%{state | accept_ref: nil})}

      {:error, :tcp_provider_not_connected} ->
        # Keep one accept pending while connected, so a later peer is refused (and logged)
        # rather than left in the listen backlog believing it's connected.
        {:noreply,
         state
         |> Map.put(:socket, socket)
         |> Session.connected()
         |> Map.put(:accept_ref, nil)
         |> start_socket_receiver!(socket)
         |> schedule_accept()}
    end
  end

  # (#990, DECISIONS #115) A peer outside the allowlist is closed before any byte is read,
  # counted as a refusal (ux U50), and the listener keeps accepting for the provider.
  defp refuse_unallowed_peer(socket, state) do
    peer = Session.peer_of(socket)

    state =
      Session.warn_peer(
        state,
        :refused,
        peer,
        "TCP provider #{state.provider_binding_id} refused #{peer}: not an allowed source address"
      )

    :gen_tcp.close(socket)
    state |> count_refusal(peer, :peer_not_allowed) |> schedule_accept()
  end

  defp peer_allowed?(%{allowed_peers: ranges}, socket) do
    case :inet.peername(socket) do
      {:ok, {ip, _port}} -> PeerAddresses.allowed?(ranges, ip)
      _unknown -> false
    end
  end

  # One accept at a time: a second would leave the first's result stale (and closed).
  defp schedule_accept(%{accept_ref: ref} = state) when is_reference(ref), do: state

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

  defp deliver_payloads(state, request, socket, payloads) do
    with {:ok, delivery} <- Session.begin_delivery(state, request) do
      result =
        with :ok <- TransportRecords.begin_send(state, request) do
          record_send_outcome(request, send_payloads(state, delivery, socket, payloads))
        end

      Session.finish(state, delivery, result)
    end
  end

  defp record_send_outcome(request, outcome) do
    with :ok <- TransportRecords.finish_send(request, outcome), do: outcome
  end

  defp send_payloads(state, delivery, socket, payloads) when is_list(payloads) do
    Enum.reduce_while(payloads, :ok, fn payload, :ok ->
      result = with :ok <- Session.check(state, delivery), do: :gen_tcp.send(socket, payload)

      case result do
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

  defp start_socket_receiver!(state, socket, prefix \\ <<>>) do
    state = maybe_stop_socket_receiver(state)
    receiver_state = socket_receiver_state(state)

    receiver_pid =
      spawn(fn ->
        receive do
          {:socket, receiver_socket} ->
            %{receiver_state | socket: receiver_socket}
            |> receive_prefix(prefix)
            |> socket_receiver_loop()
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

  # The refusal window behind the listener_refusal Now item (ux U50): opened by a refusal,
  # resolved 'accepted' when this contact's own peer connects; a refusal after that reopens it
  # with a fresh count. Counted live (a restart starts it again).
  # own_quiet_since (ux U50): set only for a second connection refused while our own connection
  # was quiet, the time it last showed activity.
  defp count_refusal(state, peer, reason, own_quiet_since \\ nil) do
    now = DateTime.utc_now()

    last = %{
      peer: peer,
      reason: refusal_reason(reason),
      scid: refusal_scid(reason),
      at: now,
      own_quiet_since: own_quiet_since
    }

    refusals =
      case state.refusals do
        %{resolved: nil} = open -> %{open | count: open.count + 1, last_at: now, last: last}
        _none_or_resolved -> %{count: 1, first_at: now, last_at: now, last: last, resolved: nil}
      end

    %{note_refused(state, peer, reason, now) | refusals: refusals}
  end

  defp note_refused(state, peer, reason, now) do
    %{
      state
      | peers_refused: state.peers_refused + 1,
        last_peer_refused: %{peer: peer, reason: inspect(reason), at: now}
    }
  end

  # (ux U50) A second connection identified as this contact's. While our own connection is
  # receiving it's a duplicate: counted (second_connections_refused, the pass's Technical
  # details), no refusal window. If ours has gone quiet it's likely the provider reconnecting
  # past a half-open socket while connected? still reads true: a normal refusal, so the
  # listener_refusal item opens.
  defp refuse_second_connection(state, peer) do
    now = DateTime.utc_now()
    state = %{state | second_connections_refused: state.second_connections_refused + 1}

    case quiet_since(state, now) do
      nil -> note_refused(state, peer, :second_connection, now)
      since -> count_refusal(state, peer, :second_connection, since)
    end
  end

  # When our own connection last showed activity, if that is quiet_connection_ms or longer ago;
  # nil while it's active. Only reads count, so only a downlink can be quiet (an uplink-only
  # connection has no reads); paused reads (#83 backpressure) are our silence, not the peer's.
  defp quiet_since(%{direction: direction}, _now) when direction != :downlink, do: nil
  defp quiet_since(%{reads_paused?: true}, _now), do: nil

  defp quiet_since(state, now) do
    case last_activity(state) do
      nil -> nil
      since -> if DateTime.diff(now, since, :millisecond) >= state.quiet_connection_ms, do: since
    end
  end

  defp last_activity(%{connected_at: nil, last_ingress_at: at}), do: at
  defp last_activity(%{connected_at: connected_at, last_ingress_at: nil}), do: connected_at

  defp last_activity(%{connected_at: connected_at, last_ingress_at: at}),
    do: Enum.max([connected_at, at], DateTime)

  defp resolve_refusals(%{refusals: %{resolved: nil} = open} = state),
    do: %{state | refusals: %{open | resolved: %{action: "accepted", at: DateTime.utc_now()}}}

  defp resolve_refusals(state), do: state

  defp refusal_reason({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp refusal_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp refusal_reason(_reason), do: "unknown"

  defp refusal_scid({reason, scid}) when reason in [:unregistered_scid, :ambiguous_scid],
    do: scid

  defp refusal_scid(_reason), do: nil

  defp reregister(state) do
    {listen, registration} = state.acceptor_registration
    namespace = acceptor_namespace(state)

    case ProfileAcceptor.register(
           namespace,
           state.mission_id,
           state.provider_binding_id,
           listen,
           registration
         ) do
      {:ok, _port, acceptor} ->
        %{state | acceptor_monitor_ref: Process.monitor(acceptor), reregister_failures: 0}

      {:error, error} ->
        delay_ms =
          if state.reregister_failures == 0,
            do: @reregister_first_retry_ms,
            else: @reregister_retry_ms

        Logger.warning(
          "TCP provider #{state.provider_binding_id} could not register with its profile " <>
            "acceptor (#{inspect(error)}); keeping the session, retrying in #{delay_ms} ms"
        )

        Process.send_after(self(), :reregister, delay_ms)

        %{
          state
          | acceptor_monitor_ref: nil,
            reregister_failures: state.reregister_failures + 1
        }
    end
  end

  # The bytes the profile acceptor read to identify the peer (#87) are ingested first, as if this
  # receiver had read them.
  # Stamped with the time the acceptor read them (api-ops review), and counted as a receive.
  defp receive_prefix(state, <<>>), do: state
  defp receive_prefix(state, {<<>>, _read_at}), do: state

  defp receive_prefix(%{ingress_journal_name: nil} = state, {prefix, read_at}) do
    Instrumentation.record_receive(state, prefix, 0)
    {next_state, batch_status} = consume_socket_data(state, prefix, read_at)
    send(state.provider_pid, {:tcp_receiver_batch, self(), batch_status})
    next_state
  end

  defp receive_prefix(state, {prefix, read_at}) do
    Instrumentation.record_receive(state, prefix, 0)
    capture_socket_data(state, prefix, read_at)
  end

  defp acceptor_namespace(%{process_namespace: %ProcessNamespace{} = namespace}),
    do: namespace

  defp acceptor_namespace(_state), do: ProcessNamespace.default()

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
      # The frame-SCID cross-check's expected SCID, journaled with each entry (DECISIONS #102).
      source_endpoint_spacecraft_scid: state.source_endpoint_spacecraft_scid,
      direction: state.direction,
      ingress_protocol_family: state.ingress_protocol_family,
      fixed_message_bytes: state.fixed_message_bytes,
      ingress_transport_binding_id: state.ingress_transport_binding_id,
      source_ref: state.source_ref,
      # A journal can span multiple sockets. Persist the connection boundary so
      # replay and batching cannot join bytes from different TCP byte streams.
      ingress_metadata:
        (state.ingress_metadata || %{})
        |> Map.delete(:transport_session_id)
        |> Map.put("transport_session_id", Cadence.Ids.new("tcp")),
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
        # #83: TCP pushes back (stops reading), never drops; counted when the pause begins.
        if not state.reads_paused? do
          :pause =
            ReceiveBackpressure.on_full(
              true,
              backpressure_metadata(state, :journal),
              byte_size(data)
            )

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
      # The pass's one spacecraft's SCID (nil when the path has none): the frame-SCID
      # cross-check refuses frames with another (DECISIONS #102).
      spacecraft_scid: state.source_endpoint_spacecraft_scid,
      protocol_family: state.ingress_protocol_family,
      direction: state.direction,
      source_ref: state.source_ref || state.provider_binding_id,
      ingress_metadata: state.ingress_metadata || %{}
    }
  end

  defp maybe_wait_for_executor_capacity(state) do
    # Flow control before every recv: develop's 5 s wait, exit caught (#334, fe-ops' review).
    case ProviderIngressExecutor.snapshot(state.ingress_executor_name, :flow_control) do
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
    :pause = ReceiveBackpressure.on_full(true, backpressure_metadata(state, :executor), 0)
    send(state.provider_pid, {:tcp_receiver_reads_paused, self(), true})
    %{state | reads_paused?: true}
  end

  defp backpressure_metadata(state, buffer) do
    %{
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      provider_binding_id: state.provider_binding_id,
      buffer: buffer
    }
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

  # #38: CLCWs with no gateway to go to are dropped, with a rate-limited warning.
  defp consume_socket_data(
         %{
           ingress_protocol_family: :cop1_clcw,
           fixed_message_bytes: bytes,
           ingress_transport_binding_id: nil
         } = state,
         data,
         receipt_time
       )
       when is_integer(bytes) and bytes > 0 do
    {messages, rest} = split_fixed_messages(state.receive_buffer <> data, bytes, [])
    state = IngressDrops.note(state, :clcw_unlinked, length(messages), byte_size(data))

    {%{state | receive_buffer: rest},
     %{
       bytes_received: byte_size(data),
       read_count: 1,
       message_count: 0,
       last_ingress_at: receipt_time,
       last_ingress_error: "missing_ingress_transport_binding_id"
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

  # #38: bytes the binding can't decode are dropped (not buffered without bound), with a
  # rate-limited warning.
  defp consume_socket_data(state, data, _receipt_time) do
    {IngressDrops.note(state, :undecoded, 1, byte_size(data)),
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
              "provider_binding_id" => state.provider_binding_id,
              "spacecraft_scid" => state.source_endpoint_spacecraft_scid
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

  defp maybe_schedule_accept_after_disconnect(%{acceptor?: true} = state), do: state

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
    state = Session.block(state, :quiescing)
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

    # The socket is already closed. Let an in-flight append finish instead of
    # killing the receiver between recv and durable capture.

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, :normal} ->
        {:ok,
         %{
           state
           | socket_receiver_pid: nil,
             socket_receiver_monitor_ref: nil
         }}

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, {:tcp_provider_receiver_failed, reason}, state}
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
      listener_closed?: is_nil(state.listener) and not state.acceptor?,
      peers_refused: state.peers_refused,
      last_peer_refused: state.last_peer_refused,
      refusals: state.refusals,
      second_connections_refused: state.second_connections_refused,
      shared_listener?: state.acceptor?,
      connected?: is_port(state.socket),
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
