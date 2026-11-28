defmodule Cadence.Runtime.ProfileAcceptor do
  @moduledoc """
  One TCP listener per listen-mode provider profile (DECISIONS #87, director 11-14). Overlapping
  contacts on one profile used to each listen on the profile's fixed port, so the second failed
  with `:eaddrinuse` until the first ended.

  The acceptor owns only the listening socket. A listen-mode `tcp_socket` adapter REGISTERS with it
  (its contact, provider binding, spacecraft and SCID) instead of listening. Each accepted peer is
  checked, identified, then handed to its adapter by `controlling_process` with the bytes read to
  identify it; from there the adapter runs its connected-session path unchanged. Nothing is
  persisted.

  An acceptor belongs to one mission and one provider binding (its name), so a connection is
  attributed to that binding before anything is read (#990, DECISIONS #115):

  - each registration carries its own source allowlist (`allowed_peers`, from its contact's
    profile version). On accept, before any frame is read, the peer must be in the union of the
    lists registered NOW; a peer outside every one is refused `peer_not_allowed`;
  - then the first frame's TM SCID must match exactly one contact registered through THIS
    binding (the same truth the #38 release guard uses). The SCID only picks a contact within the
    binding's mission; it never picks the mission;
  - and the peer must be in THAT registration's own list. Two profile versions can overlap on one
    acceptor; an address only an older version allows never reaches a newer contact (or the
    reverse). Otherwise the connection is refused `peer_not_allowed` and nothing is handed over,
    so nothing is stored. Mutual TLS (#991) will replace the address as the binding's proof.

  There is no fallback: a peer whose first frame can't be read is refused.

  Anything else is refused: closed, counted, and reported to EVERY registered adapter, so each
  contact on the profile counts the profile's refusals (ux U50 words it as the shared listener's,
  never one pass's fault); rate-limited in the log. The acceptor monitors its adapters, unregisters a stopped one and
  closes the listener `linger_ms` after the last one leaves.
  """

  # Temporary: an acceptor is never restarted by its supervisor. Its adapters register again on
  # :DOWN (which starts a fresh one), so a supervisor restart only raced them for the port; a
  # restart failing :eaddrinuse repeatedly took the DynamicSupervisor past max_restarts, and
  # Runtime.Supervisor is one_for_all, so every contact's runtime with it.
  use GenServer, restart: :temporary

  import Bitwise

  require Logger

  alias Cadence.Comms.PeerAddresses
  alias Cadence.Runtime.ProcessNamespace

  @identify_timeout_ms 10_000
  @default_linger_ms 30_000
  @tcp_opts [:binary, packet: 0, active: false, reuseaddr: true, nodelay: true]

  @type registration :: %{
          required(:adapter) => pid(),
          required(:realized_contact_id) => binary(),
          required(:path_id) => binary(),
          required(:scid) => non_neg_integer() | nil,
          optional(:provider_binding_id) => binary(),
          optional(:allowed_peers) => [Cadence.Comms.PeerAddresses.range()],
          optional(:frame_size) => pos_integer() | nil
        }

  @doc "The acceptors' supervisor in a runtime namespace."
  @spec supervisor_name(ProcessNamespace.t()) :: GenServer.name()
  def supervisor_name(%ProcessNamespace{} = namespace \\ ProcessNamespace.default()),
    do: ProcessNamespace.via(namespace, :profile_acceptor_supervisor)

  @doc """
  Registers `registration` with the acceptor of `{mission_id, profile_id}` (started, and its port
  bound, on first use). `{:ok, port, acceptor}` or `{:error, {:tcp_provider_listen_failed,
  profile_id, reason}}`, as a direct listen would have reported.

  `acceptor` is the process that stored the registration (its `self()`); the caller monitors that
  pid. A pid looked up afterwards could be a newer acceptor that never heard of the registration,
  or nil if this one died in between; monitoring a dead pid delivers `:DOWN` (`:noproc`) at once,
  so the caller's re-registration covers that race.

  An acceptor can be ending as it's called: its linger fires just as the next contact on the
  profile registers, and `start_child` hands back the dying pid. The call then exits `:normal`
  (or `:noproc`, `:shutdown`); register starts a fresh acceptor and tries again (api-ops, lead:
  a contact start mustn't fail on it). Any other exit, or a third ending one, is
  `{:error, {:tcp_provider_listen_failed, profile_id, {:acceptor_exited, reason}}}`, which a
  re-registering adapter retries.
  """
  @spec register(ProcessNamespace.t(), binary(), binary(), map(), registration()) ::
          {:ok, :inet.port_number(), pid()} | {:error, term()}
  def register(namespace, mission_id, profile_id, listen, registration),
    do: register(namespace, mission_id, profile_id, listen, registration, 3)

  defp register(namespace, mission_id, profile_id, listen, registration, attempts) do
    case register_once(namespace, mission_id, profile_id, listen, registration) do
      {:exit, reason} ->
        if acceptor_ending?(reason) and attempts > 1 do
          # The ended acceptor's name is released asynchronously; give the registry a moment.
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
      GenServer.call(pid, {:register, registration})
    end
  catch
    :exit, reason -> {:exit, reason}
  end

  defp acceptor_ending?({reason, {GenServer, :call, _args}}), do: acceptor_ending?(reason)
  defp acceptor_ending?(reason) when reason in [:noproc, :normal, :shutdown], do: true
  defp acceptor_ending?({:shutdown, _detail}), do: true
  defp acceptor_ending?(_reason), do: false

  @doc """
  The registrations an acceptor holds (`[%{adapter, realized_contact_id, path_id, scid, ...}]`);
  `[]` once it has gone.
  """
  @spec registrations(pid()) :: [map()]
  def registrations(acceptor) do
    GenServer.call(acceptor, :routing).registrations
  catch
    :exit, _gone -> []
  end

  @doc "The running acceptor of `{mission_id, profile_id}`, if any (adapters monitor it)."
  @spec whereis(ProcessNamespace.t(), binary(), binary()) :: pid() | nil
  def whereis(namespace, mission_id, profile_id) do
    case Registry.lookup(namespace.registry, {:profile_acceptor, mission_id, profile_id}) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp ensure_started(namespace, mission_id, profile_id, listen) do
    name = name(namespace, mission_id, profile_id)

    spec = %{
      id: {__MODULE__, mission_id, profile_id},
      start:
        {__MODULE__, :start_link,
         [[name: name, mission_id: mission_id, profile_id: profile_id, listen: listen]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(supervisor_name(namespace), spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp name(namespace, mission_id, profile_id),
    do: ProcessNamespace.via(namespace, {:profile_acceptor, mission_id, profile_id})

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @impl true
  def init(opts) do
    listen = Keyword.fetch!(opts, :listen)
    profile_id = Keyword.fetch!(opts, :profile_id)

    case :gen_tcp.listen(Map.fetch!(listen, :port), listen_opts(Map.get(listen, :host))) do
      {:ok, listener} ->
        state = %{
          profile_id: profile_id,
          mission_id: Keyword.fetch!(opts, :mission_id),
          listener: listener,
          port: actual_port(listener, listen.port),
          linger_ms: Map.get(listen, :linger_ms, @default_linger_ms),
          registrations: %{},
          accept_ref: nil,
          linger_ref: nil,
          refused: 0
        }

        {:ok, schedule_accept(state)}

      {:error, reason} ->
        {:stop, {:tcp_provider_listen_failed, profile_id, reason}}
    end
  end

  @impl true
  def handle_call({:register, %{adapter: adapter} = registration}, _from, state) do
    ref = Process.monitor(adapter)
    state = cancel_linger(state)
    {:reply, {:ok, state.port, self()}, put_in(state.registrations[ref], registration)}
  end

  def handle_call(:routing, _from, state) do
    # Only this binding's contacts: the acceptor is the binding's (its name), so a registration
    # from any other binding would be a fault, never a candidate.
    registrations =
      state.registrations
      |> Map.values()
      |> Enum.filter(&(Map.get(&1, :provider_binding_id, state.profile_id) == state.profile_id))

    {:reply, %{registrations: registrations}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       port: state.port,
       registrations: Map.values(state.registrations),
       refused: state.refused
     }, state}
  end

  # A connection arrived: accept the next at once; its task identifies and hands this one over.
  @impl true
  def handle_info({:accepted, ref}, %{accept_ref: ref} = state),
    do: {:noreply, schedule_accept(%{state | accept_ref: nil})}

  def handle_info({:accept_failed, ref, reason}, %{accept_ref: ref} = state) do
    if reason != :closed,
      do: Logger.warning("profile acceptor #{state.profile_id} accept failed: #{inspect(reason)}")

    {:noreply, schedule_accept(%{state | accept_ref: nil})}
  end

  def handle_info({:refused, peer, reason}, state) do
    if rem(state.refused, 100) == 0,
      do:
        Logger.warning("profile acceptor #{state.profile_id} refused #{peer}: #{inspect(reason)}")

    {:noreply, %{state | refused: state.refused + 1}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {_gone, registrations} = Map.pop(state.registrations, ref)
    {:noreply, maybe_linger(%{state | registrations: registrations})}
  end

  def handle_info({:linger_expired, ref}, %{linger_ref: ref, registrations: regs} = state)
      when map_size(regs) == 0 do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = :gen_tcp.close(state.listener)
    :ok
  end

  defp schedule_accept(state) do
    ref = make_ref()
    parent = self()
    listener = state.listener
    profile_id = state.profile_id

    Task.start(fn ->
      case :gen_tcp.accept(listener) do
        {:ok, socket} ->
          send(parent, {:accepted, ref})
          route(socket, GenServer.call(parent, :routing), parent, profile_id)

        {:error, reason} ->
          send(parent, {:accept_failed, ref, reason})
      end
    end)

    %{state | accept_ref: ref}
  end

  # In the accept task (it owns the socket): identify the peer within a bound, then hand it over
  # with the bytes read to identify it, or refuse it.
  defp route(socket, %{registrations: registrations}, parent, profile_id) do
    {ip, peer} = peer_address(socket)

    case admit(socket, ip, registrations) do
      {:ok, registration, prefix} -> hand_over(socket, registration, prefix, peer, profile_id)
      {:refused, reason} -> refuse(socket, peer, reason, registrations, parent)
    end
  end

  # The union of the lists registered now, checked before reading; then the matched
  # registration's own list, checked before anything is handed over.
  defp admit(_socket, _ip, []), do: {:refused, :no_registered_contact}

  defp admit(socket, ip, registrations) do
    if Enum.any?(registrations, &peer_allowed?(&1, ip)),
      do: socket |> identify(registrations) |> own_list(ip),
      else: {:refused, :peer_not_allowed}
  end

  defp own_list({:ok, registration, _prefix} = identified, ip),
    do: if(peer_allowed?(registration, ip), do: identified, else: {:refused, :peer_not_allowed})

  defp own_list(refused, _ip), do: refused

  defp peer_allowed?(registration, ip),
    do: PeerAddresses.allowed?(Map.get(registration, :allowed_peers, []), ip)

  defp identify(socket, registrations) do
    frame_size = registrations |> Enum.map(&Map.get(&1, :frame_size)) |> Enum.find(&is_integer/1)

    case read_first_frame(socket, frame_size) do
      {:ok, frame} -> match_scid(frame, registrations)
      :unreadable -> {:refused, :unidentified}
      {:error, reason} -> {:refused, {:read_failed, reason}}
    end
  end

  defp read_first_frame(_socket, nil), do: :unreadable

  # The frame's receipt time is when it was read, not when it's handed over (api-ops review).
  defp read_first_frame(socket, frame_size) when frame_size >= 2 do
    case :gen_tcp.recv(socket, frame_size, @identify_timeout_ms) do
      {:ok, frame} -> {:ok, {frame, DateTime.utc_now()}}
      {:error, reason} -> {:error, reason}
    end
  end

  # TM transfer frame primary header: version (2 bits), spacecraft id (10 bits).
  defp match_scid({<<_version::2, scid::10, _rest::bitstring>> = frame, read_at}, registrations) do
    case Enum.filter(registrations, &(&1.scid == scid)) do
      [registration] -> {:ok, registration, {frame, read_at}}
      [] -> {:refused, {:unregistered_scid, scid}}
      _several -> {:refused, {:ambiguous_scid, scid}}
    end
  end

  defp hand_over(socket, %{adapter: adapter} = registration, {prefix, read_at}, peer, profile_id) do
    case :gen_tcp.controlling_process(socket, adapter) do
      :ok ->
        send(adapter, {:peer_accepted, socket, prefix, peer, read_at})

      {:error, reason} ->
        :gen_tcp.close(socket)

        Logger.warning(
          "profile acceptor #{profile_id} could not hand #{peer} to " <>
            "#{registration.realized_contact_id}: #{inspect(reason)}"
        )
    end
  end

  defp refuse(socket, peer, reason, registrations, parent) do
    :gen_tcp.close(socket)
    Enum.each(registrations, &send(&1.adapter, {:peer_refused, peer, reason}))
    send(parent, {:refused, peer, reason})
  end

  defp maybe_linger(%{registrations: regs} = state) when map_size(regs) == 0 do
    ref = make_ref()
    Process.send_after(self(), {:linger_expired, ref}, state.linger_ms)
    %{state | linger_ref: ref}
  end

  defp maybe_linger(state), do: state

  defp cancel_linger(state), do: %{state | linger_ref: nil}

  # The peer's address as a tuple (for the allowlist) and as text (for refusals); an IPv4-mapped
  # IPv6 address (::ffff:a.b.c.d) reads as its IPv4 address (api-ops review).
  defp peer_address(socket) do
    case :inet.peername(socket) do
      {:ok, {address, _port}} -> {address, format_address(address)}
      _unknown -> {nil, "unknown"}
    end
  end

  defp format_address({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: format_address({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})

  defp format_address(address), do: address |> :inet.ntoa() |> to_string()

  defp listen_opts(nil), do: @tcp_opts
  defp listen_opts(host) when is_binary(host), do: [{:ip, parse_ip(host)} | @tcp_opts]

  defp parse_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> ip
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp actual_port(listener, fallback) do
    case :inet.port(listener) do
      {:ok, port} -> port
      _error -> fallback
    end
  end
end
