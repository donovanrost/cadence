defmodule Cadence.Runtime.ProfileAcceptor do
  @moduledoc """
  One shared TCP socket per mission and listen endpoint. Each adapter registers its stable
  delivery binding, pinned profile and SCID. The socket is handed over only after binding and
  allowlist admission and a unique SCID match within the binding.

  The acceptor monitors its registrations and lingers after the last one leaves. An own
  listener can reclaim an idle endpoint at a pass boundary. Adapters monitor the acceptor and
  can register again if it dies.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Cadence.Comms.ListenEndpoint
  alias Cadence.ProviderAdapters.InboundSocket
  alias Cadence.ProviderAdapters.InboundSocket.Authorization
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Runtime.ProfileAcceptor.Routing

  @default_linger_ms 30_000
  @max_routes 8
  @rate_window_seconds 60
  @refusal_kinds [:tls_handshake_failed, :no_registered_contact]

  @doc "The acceptors' supervisor in a runtime namespace."
  def supervisor_name(%ProcessNamespace{} = namespace \\ ProcessNamespace.default()),
    do: ProcessNamespace.via(namespace, :profile_acceptor_supervisor)

  @doc "Registers with the endpoint owner and returns the actual port and the PID to monitor."
  def register(namespace, mission_id, profile_id, listen, registration) do
    if Map.get(registration, :provider_binding_id, profile_id) == profile_id do
      registration =
        registration
        |> Map.put(:provider_binding_id, profile_id)
        |> Map.put_new(:delivery_binding_id, profile_id)

      register(namespace, mission_id, profile_id, listen, registration, 3)
    else
      {:error, :wrong_binding}
    end
  end

  defp register(namespace, mission_id, profile_id, listen, registration, attempts) do
    case register_once(namespace, mission_id, profile_id, listen, registration) do
      {:exit, reason} ->
        if acceptor_ending?(reason) and attempts > 1 do
          # A linger or cutover may release the registry name just after this attempt.
          Process.sleep(10)
          register(namespace, mission_id, profile_id, listen, registration, attempts - 1)
        else
          {:error, {:tcp_provider_listen_failed, profile_id, {:acceptor_exited, reason}}}
        end

      result ->
        result
    end
  end

  defp register_once(namespace, mission_id, profile_id, listen, registration) do
    with {:ok, pid} <- ensure_started(namespace, mission_id, profile_id, listen) do
      case GenServer.call(
             pid,
             {:register, Map.get(listen, :delivery_auth, :plaintext), registration}
           ) do
        :retired -> {:exit, :normal}
        result -> result
      end
    end
  catch
    :exit, reason -> {:exit, reason}
  end

  defp acceptor_ending?({reason, {GenServer, :call, _args}}), do: acceptor_ending?(reason)
  defp acceptor_ending?(reason) when reason in [:noproc, :normal, :shutdown], do: true
  defp acceptor_ending?({:shutdown, _detail}), do: true
  defp acceptor_ending?(_reason), do: false

  def registrations(acceptor) do
    case snapshot(acceptor) do
      %{registrations: registrations} -> registrations
      nil -> []
    end
  end

  def snapshot(acceptor) do
    GenServer.call(acceptor, :snapshot)
  catch
    :exit, _gone -> nil
  end

  def whereis(namespace, mission_id, profile_id, listen) do
    case Registry.lookup(namespace.registry, key(mission_id, profile_id, listen)) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp ensure_started(namespace, mission_id, profile_id, listen) do
    key = key(mission_id, profile_id, listen)
    name = ProcessNamespace.via(namespace, key)

    spec = %{
      id: key,
      start: {__MODULE__, :start_link, [[name: name, profile_id: profile_id, listen: listen]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(supervisor_name(namespace), spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp key(mission_id, profile_id, listen) do
    endpoint =
      case bind_endpoint(listen) do
        %{host: host, port: port} -> {host, port}
        nil -> {:ephemeral, profile_id}
      end

    {:profile_acceptor, mission_id, endpoint}
  end

  defp bind_endpoint(listen), do: ListenEndpoint.bind(listen[:host], listen[:port])

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @doc "Releases an idle shared listener before opening an own listener that overlaps it."
  def release_idle(namespace, mission_id, listen) do
    case bind_endpoint(listen) do
      nil -> :ok
      endpoint -> release_overlapping(namespace, mission_id, endpoint)
    end
  end

  defp release_overlapping(namespace, mission_id, %{port: port} = endpoint) do
    namespace.registry
    |> Registry.select([
      {{{:profile_acceptor, mission_id, {:"$1", port}}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.filter(fn {host, _pid} ->
      ListenEndpoint.overlaps?(endpoint, %{host: host, port: port})
    end)
    |> Enum.reduce_while(:ok, fn {_host, pid}, :ok ->
      case release(pid) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp release(pid) do
    GenServer.call(pid, :release_idle)
  catch
    :exit, reason ->
      if acceptor_ending?(reason), do: :ok, else: {:error, :eaddrinuse}
  end

  def close_replaced_listener(namespace, mission_id, profile_id, listen) do
    if pid = whereis(namespace, mission_id, profile_id, listen),
      do: GenServer.cast(pid, :check_mode)

    :ok
  end

  @impl true
  def init(opts) do
    listen = Keyword.fetch!(opts, :listen)
    profile_id = Keyword.fetch!(opts, :profile_id)
    mode = Map.get(listen, :delivery_auth, :plaintext)
    bind = bind_endpoint(listen)
    host = if bind, do: bind.host, else: Map.get(listen, :host)
    port = Map.fetch!(listen, :port)

    case InboundSocket.listen(host, port, mode) do
      {:ok, listener} ->
        state = %{
          listener: listener,
          mode: mode,
          port: actual_port(listener, port),
          host: host,
          plaintext_binding: nil,
          linger_ms: Map.get(listen, :linger_ms, @default_linger_ms),
          registrations: %{},
          active_routes: 0,
          accept_ref: nil,
          linger_ref: nil,
          refused: 0,
          refusal_buckets: %{}
        }

        {:ok, state |> maybe_linger() |> schedule_accept()}

      {:error, reason} ->
        {:stop, {:tcp_provider_listen_failed, profile_id, reason}}
    end
  end

  @impl true
  def handle_call({:register, mode, registration}, _from, state) do
    case registration_status(state, mode, registration) do
      :ok ->
        state = put_registration(state, registration)
        {:reply, {:ok, state.port, self()}, state}

      {:error, reason}
      when reason in [:mode_mismatch, :wrong_binding] and map_size(state.registrations) == 0 ->
        {:stop, :normal, :retired, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:release_idle, _from, %{registrations: regs} = state) when map_size(regs) == 0,
    do: {:stop, :normal, :ok, state}

  def handle_call(:release_idle, _from, state), do: {:reply, {:error, :eaddrinuse}, state}

  def handle_call(:routing, _from, state) do
    {:reply,
     %{
       registrations: Map.values(state.registrations),
       mode: state.mode,
       plaintext_binding: state.plaintext_binding
     }, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       endpoint: %{host: state.host, port: state.port},
       port: state.port,
       registrations: Map.values(state.registrations),
       refused: state.refused,
       refusals_per_minute: refusal_rates(state.refusal_buckets, now_second())
     }, state}
  end

  defp registration_status(state, mode, _registration) when mode != state.mode,
    do: {:error, :mode_mismatch}

  defp registration_status(
         %{mode: :plaintext, plaintext_binding: binding},
         :plaintext,
         registration
       ) do
    if is_nil(binding) or binding == registration.delivery_binding_id,
      do: :ok,
      else: {:error, :wrong_binding}
  end

  defp registration_status(%{mode: :mtls}, :mtls, registration) do
    case registration[:delivery_authorization] do
      %Authorization{mode: :mtls, binding_id: id} = authorization
      when id == registration.delivery_binding_id ->
        Authorization.listener_ready(authorization)

      _other ->
        {:error, :invalid_delivery_authorization}
    end
  end

  defp put_registration(state, %{adapter: adapter} = registration) do
    ref =
      case state.registrations[adapter] do
        %{monitor: existing} -> existing
        nil -> Process.monitor(adapter)
      end

    binding =
      if state.mode == :plaintext, do: registration.delivery_binding_id, else: nil

    %{
      state
      | registrations:
          Map.put(state.registrations, adapter, Map.put(registration, :monitor, ref)),
        plaintext_binding: binding,
        linger_ref: nil
    }
  end

  @impl true
  def handle_cast(:check_mode, state) do
    {retired, current} = Enum.split_with(state.registrations, &mode_replaced?/1)

    Enum.each(retired, fn {_adapter, registration} ->
      Process.demonitor(registration.monitor, [:flush])
    end)

    case {retired, current} do
      {[_ | _], []} -> {:stop, :normal, state}
      _other -> {:noreply, %{state | registrations: Map.new(current)}}
    end
  end

  defp mode_replaced?({_adapter, registration}),
    do:
      Authorization.listener_ready(registration[:delivery_authorization]) ==
        {:error, :mode_mismatch}

  @impl true
  def handle_info({:accepted, ref}, %{accept_ref: ref} = state),
    do:
      {:noreply,
       schedule_accept(%{state | accept_ref: nil, active_routes: state.active_routes + 1})}

  def handle_info(:route_finished, state),
    do: {:noreply, schedule_accept(%{state | active_routes: max(0, state.active_routes - 1)})}

  def handle_info({:accept_failed, ref, reason}, %{accept_ref: ref} = state) do
    if reason != :closed,
      do:
        Logger.warning("shared listener on port #{state.port} accept failed: #{inspect(reason)}")

    {:noreply, schedule_accept(%{state | accept_ref: nil})}
  end

  def handle_info({:refused, peer, reason, kind}, state) do
    if rem(state.refused, 100) == 0,
      do:
        Logger.warning(
          "shared listener on port #{state.port} refused #{peer}: #{inspect(reason)}"
        )

    next = %{state | refused: state.refused + 1}
    {:noreply, count_endpoint_refusal(next, kind)}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case state.registrations[pid] do
      %{monitor: ^ref} ->
        {:noreply, maybe_linger(%{state | registrations: Map.delete(state.registrations, pid)})}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:linger_expired, ref}, %{linger_ref: ref, registrations: regs} = state)
      when map_size(regs) == 0 do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    InboundSocket.close(state.listener)
    :ok
  end

  @impl true
  def format_status(status), do: Map.update!(status, :state, &Map.delete(&1, :listener))

  defp schedule_accept(%{accept_ref: ref} = state) when is_reference(ref), do: state
  defp schedule_accept(%{active_routes: count} = state) when count >= @max_routes, do: state

  defp schedule_accept(state) do
    ref = make_ref()
    parent = self()
    listener = state.listener

    Task.start(fn ->
      case InboundSocket.transport_accept(listener) do
        {:ok, socket} ->
          send(parent, {:accepted, ref})

          try do
            Routing.route(socket, parent)
          after
            send(parent, :route_finished)
          end

        {:error, reason} ->
          send(parent, {:accept_failed, ref, reason})
      end
    end)

    %{state | accept_ref: ref}
  end

  # One bounded slot per second, identified by its monotonic timestamp. Older samples expire
  # even if there are no further refusals or the listener receives no requests for its snapshot.
  defp count_endpoint_refusal(state, kind) when kind in @refusal_kinds do
    second = now_second()
    slot = Integer.mod(second, @rate_window_seconds)

    update_in(state.refusal_buckets, fn buckets ->
      case Map.get(buckets, slot) do
        {^second, counts} ->
          Map.put(buckets, slot, {second, Map.update(counts, kind, 1, &(&1 + 1))})

        _expired ->
          Map.put(buckets, slot, {second, %{kind => 1}})
      end
    end)
  end

  defp count_endpoint_refusal(state, _kind), do: state

  defp refusal_rates(buckets, now) do
    counts = for {_slot, {at, counts}} <- buckets, now - at < @rate_window_seconds, do: counts

    Map.new(@refusal_kinds, fn kind ->
      {kind, Enum.reduce(counts, 0, &(Map.get(&1, kind, 0) + &2))}
    end)
  end

  defp now_second, do: System.monotonic_time(:second)

  defp maybe_linger(%{registrations: regs} = state) when map_size(regs) == 0 do
    ref = make_ref()
    Process.send_after(self(), {:linger_expired, ref}, state.linger_ms)
    %{state | linger_ref: ref}
  end

  defp maybe_linger(state), do: state

  defp actual_port(listener, fallback) do
    case InboundSocket.port(listener) do
      {:ok, port} -> port
      _error -> fallback
    end
  end
end
