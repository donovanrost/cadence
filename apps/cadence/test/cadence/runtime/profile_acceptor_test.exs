defmodule Cadence.Runtime.ProfileAcceptorTest do
  @moduledoc """
  DECISIONS #87 (A): one listener per listen-mode provider profile. Overlapping contacts on one
  profile each get their own peer, identified by the first frame's SCID; anything unidentified is
  refused. DECISIONS #115 (#990): the acceptor is one provider binding's, a peer outside its source
  allowlist is refused before any frame is read, the SCID only picks among that binding's
  contacts, and there is no fallback.
  """
  use ExUnit.Case, async: false

  alias Cadence.Comms.PeerAddresses
  alias Cadence.ProviderAdapters.TCPSocket
  alias Cadence.Runtime.{ProcessNamespace, ProfileAcceptor}

  @frame_size 14
  @loopback PeerAddresses.ranges(["127.0.0.1/32", "::1/128"])

  setup do
    %{
      namespace: ProcessNamespace.default(),
      mission: "mission-acceptor-#{System.unique_integer([:positive])}",
      profile: "profile-acceptor-#{System.unique_integer([:positive])}"
    }
  end

  test "two overlapping contacts on one profile each get their own peer, by SCID", c do
    {a, port} = register!(c, "contact-a", 1)
    {b, ^port} = register!(c, "contact-b", 2)

    sent_at = DateTime.utc_now()
    peer_b = connect!(port, frame(2))
    peer_a = connect!(port, frame(1))

    assert_receive {^a, {:peer_accepted, socket_a, prefix_a, _peer, read_a}}, 2_000
    assert_receive {^b, {:peer_accepted, socket_b, prefix_b, _peer, _read_b}}, 2_000
    assert <<_::2, 1::10, _::bitstring>> = prefix_a
    # The first frame's receipt time is when the acceptor read it (api-ops review).
    assert %DateTime{} = read_a
    assert DateTime.compare(read_a, sent_at) != :lt
    assert DateTime.compare(read_a, DateTime.utc_now()) != :gt
    assert <<_::2, 2::10, _::bitstring>> = prefix_b

    # Each adapter now owns its peer's socket and reads what follows.
    :ok = :gen_tcp.send(peer_a, "after-a")
    assert {:ok, "after-a"} = recv_as(a, socket_a)
    :ok = :gen_tcp.send(peer_b, "after-b")
    assert {:ok, "after-b"} = recv_as(b, socket_b)
  end

  test "a contained pass comes and goes; the other contact's session is untouched", c do
    {a, port} = register!(c, "contact-a", 1)
    peer_a = connect!(port, frame(1))
    assert_receive {^a, {:peer_accepted, socket_a, _prefix, _peer, _read_at}}, 2_000

    {b, ^port} = register!(c, "contact-b", 2)
    _peer_b = connect!(port, frame(2))
    assert_receive {^b, {:peer_accepted, _socket_b, _prefix, _peer, _read_at}}, 2_000
    stop_adapter(b)

    :ok = :gen_tcp.send(peer_a, "still-here")
    assert {:ok, "still-here"} = recv_as(a, socket_a)
  end

  test "a frame for no registered spacecraft is refused, and every adapter hears of it", c do
    {a, port} = register!(c, "contact-a", 1)
    peer = connect!(port, frame(99))

    assert_receive {^a, {:peer_refused, _peer, {:unregistered_scid, 99}}}, 2_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
    refute_received {^a, {:peer_accepted, _, _, _, _}}
  end

  test "no fallback: with one registration, a peer whose first frame can't be read is refused",
       c do
    {a, port} = register!(c, "contact-a", nil, frame_size: nil)
    peer = connect!(port, "")
    assert_receive {^a, {:peer_refused, _, :unidentified}}, 2_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
    refute_received {^a, {:peer_accepted, _, _, _, _}}
  end

  test "an IPv4-mapped allowlist entry allows its IPv4 peer", c do
    {a, port} = register!(c, "contact-a", 1, allowed: ["::ffff:127.0.0.1"])
    _peer = connect!(port, frame(1))
    assert_receive {^a, {:peer_accepted, _socket, _prefix, "127.0.0.1", _read_at}}, 2_000
  end

  test "a peer outside the allowlist is refused before any frame is read", c do
    {a, port} = register!(c, "contact-a", 1, allowed: ["10.9.9.0/24"])

    # The peer sends nothing: a refusal well inside the identify timeout (10 s) proves the
    # acceptor never waited to read a frame.
    {:ok, peer} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    assert_receive {^a, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 1_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
  end

  test "an empty allowlist refuses every peer", c do
    {a, port} = register!(c, "contact-a", 1, allowed: [])
    _peer = connect!(port, frame(1))
    assert_receive {^a, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 1_000
  end

  # The #130 case: mission A's provider stream is misdirected to mission B's port (another
  # organization), and B has a contact with the same SCID. B's binding allows only B's provider
  # (here 10.0.0.0/8); A's stream arrives from elsewhere, so it is refused on accept and never
  # handed to B's contact. (One provider serving both missions shares an egress range, which the
  # allowlist can't tell apart; mutual TLS, #991, closes that.)
  test "a misdirected stream with a colliding SCID is refused, never stored as the other mission's",
       c do
    mission_b = %{c | mission: c.mission <> "-org-b", profile: c.profile <> "-binding-b"}
    {b, port_b} = register!(mission_b, "contact-b", 7, allowed: ["10.0.0.0/8"])

    misdirected = connect!(port_b, frame(7))
    assert_receive {^b, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 1_000
    assert {:error, :closed} = :gen_tcp.recv(misdirected, 0, 2_000)
    refute_received {^b, {:peer_accepted, _, _, _, _}}
  end

  # Platform-eng on #993: two profile versions overlap on one acceptor with different lists. The
  # accept-time check is the union; the routed registration's own list decides.
  test "a peer allowed only by A's list sending B's SCID is refused, nothing handed over", c do
    {a, port} = register!(c, "contact-a", 1, allowed: ["127.0.0.1/32"])
    {b, ^port} = register!(c, "contact-b", 2, allowed: ["10.0.0.0/8"])

    peer = connect!(port, frame(2))
    assert_receive {^b, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 2_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
    refute_received {^b, {:peer_accepted, _, _, _, _}}
    refute_received {^a, {:peer_accepted, _, _, _, _}}
  end

  test "a peer allowed by B's own list reaches B", c do
    {_a, port} = register!(c, "contact-a", 1, allowed: ["10.0.0.0/8"])
    {b, ^port} = register!(c, "contact-b", 2, allowed: ["127.0.0.1/32"])

    _peer = connect!(port, frame(2))
    assert_receive {^b, {:peer_accepted, _socket, _prefix, "127.0.0.1", _read_at}}, 2_000
  end

  test "unregistering A takes A's addresses out of the accept-time union", c do
    {a, port} = register!(c, "contact-a", 1, allowed: ["127.0.0.1/32"])
    {b, ^port} = register!(c, "contact-b", 2, allowed: ["10.0.0.0/8"])
    stop_adapter(a)
    acceptor = ProfileAcceptor.whereis(c.namespace, c.mission, c.profile)
    assert eventually(fn -> length(ProfileAcceptor.registrations(acceptor)) == 1 end)

    # Only B's list remains: loopback is outside every list, refused before any frame is read.
    {:ok, peer} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    assert_receive {^b, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 1_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
  end

  test "a peer in neither registration's list is refused before reading", c do
    {a, port} = register!(c, "contact-a", 1, allowed: ["10.1.0.0/16"])
    {b, ^port} = register!(c, "contact-b", 2, allowed: ["10.2.0.0/16"])

    {:ok, peer} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    assert_receive {^a, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 1_000
    assert_receive {^b, {:peer_refused, "127.0.0.1", :peer_not_allowed}}, 1_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
  end

  test "two bindings never cross: a SCID only picks a contact of the binding it reached", c do
    other = %{c | profile: c.profile <> "-other"}
    {a, port_a} = register!(c, "contact-a", 1)
    {b, port_b} = register!(other, "contact-b", 2)
    assert port_a != port_b

    # SCID 1 is binding A's contact; sent to binding B's listener it matches nothing there.
    _peer = connect!(port_b, frame(1))
    assert_receive {^b, {:peer_refused, _, {:unregistered_scid, 1}}}, 2_000
    refute_receive {^a, _any}, 200
  end

  test "a registration from another binding is never a candidate on this binding's acceptor", c do
    {a, port} = register!(c, "contact-a", 1, provider_binding_id: "some-other-binding")
    peer = connect!(port, frame(1))

    # The peer is closed unrouted: the foreign registration is neither handed it nor told.
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
    refute_receive {^a, {:peer_accepted, _, _, _, _}}, 200
  end

  # api-ops review: an adapter monitors the acceptor only after register returns. Register names
  # the process that stored the registration, so if it died in between the monitor still reports
  # it and the adapter registers again (no lookup that could return nil or a newer acceptor).
  test "register names the acceptor that took it; dead before the caller monitors, DOWN still comes",
       c do
    registration = %{
      adapter: self(),
      realized_contact_id: "contact-a",
      path_id: "downlink",
      scid: 1,
      allowed_peers: @loopback,
      frame_size: @frame_size
    }

    listen = %{port: 0, host: "127.0.0.1"}

    assert {:ok, _port, acceptor} =
             ProfileAcceptor.register(c.namespace, c.mission, c.profile, listen, registration)

    assert acceptor == ProfileAcceptor.whereis(c.namespace, c.mission, c.profile)

    :ok =
      DynamicSupervisor.terminate_child(ProfileAcceptor.supervisor_name(c.namespace), acceptor)

    refute Process.alive?(acceptor)
    ref = Process.monitor(acceptor)
    assert_receive {:DOWN, ^ref, :process, ^acceptor, :noproc}, 1_000
  end

  # api-ops, lead: the linger fires just as the next contact on the profile registers, so
  # start_child hands back the dying acceptor and the call exits :normal. Held suspended, the
  # acceptor has its linger message queued ahead of the register call, so it ends first.
  test "an acceptor whose linger fires as the next contact registers is replaced; it registers",
       c do
    listen = %{port: 0, host: "127.0.0.1", linger_ms: 50}
    {a, _port} = register!(c, "contact-a", 1, listen: listen)
    dying = ProfileAcceptor.whereis(c.namespace, c.mission, c.profile)
    stop_adapter(a)

    assert eventually(fn -> :sys.get_state(dying).linger_ref != nil end)
    :ok = :sys.suspend(dying)
    Process.sleep(100)

    registration = %{
      adapter: self(),
      realized_contact_id: "contact-b",
      path_id: "downlink",
      scid: 2,
      allowed_peers: @loopback,
      frame_size: @frame_size
    }

    task =
      Task.async(fn ->
        ProfileAcceptor.register(c.namespace, c.mission, c.profile, listen, registration)
      end)

    # The linger message, then the register call, wait in the suspended acceptor's mailbox.
    assert eventually(fn ->
             match?({:message_queue_len, 2}, Process.info(dying, :message_queue_len))
           end)

    :ok = :sys.resume(dying)

    assert {:ok, _port, fresh} = Task.await(task, 2_000)
    refute Process.alive?(dying)
    assert fresh != dying
    assert fresh == ProfileAcceptor.whereis(c.namespace, c.mission, c.profile)
  end

  # api-ops: a profile's quiet_connection_ms is a positive integer; a numeric string is coerced.
  test "a shared-listener adapter refuses a quiet_connection_ms that isn't an integer", c do
    opts = fn quiet ->
      [
        mission_id: c.mission,
        realized_contact_id: "contact-config",
        path_id: "downlink",
        provider_binding_id: c.profile,
        direction: :downlink,
        ingress_executor_name: :unused,
        configuration: %{
          mode: :listen,
          expected_peer_addresses: ["127.0.0.1/32", "::1/128"],
          listener: "shared",
          port: 0,
          frame_size: @frame_size,
          quiet_connection_ms: quiet
        }
      ]
    end

    for bad <- ["soon", "30s", 0, -1, 1.5] do
      assert {:error,
              {:tcp_provider_invalid_configuration, _profile, {:quiet_connection_ms, ^bad}}} =
               GenServer.start(TCPSocket, opts.(bad))
    end

    # null (the key present) is the default, not a refusal (api-ops): the start gets past the
    # configuration check and stops later, here on the ingress dependency this test leaves out.
    assert {:error, {:tcp_provider_missing_ingress_dependency, _profile, _reason}} =
             GenServer.start(TCPSocket, opts.(nil))
  end

  # A crashing acceptor isn't restarted by its supervisor (adapters register again on :DOWN, which
  # starts a fresh one). Restarts raced them for the port, failed :eaddrinuse and took the
  # DynamicSupervisor past max_restarts; Runtime.Supervisor is one_for_all.
  test "a killed acceptor is not restarted by its supervisor, which survives repeated kills", c do
    supervisor = GenServer.whereis(ProfileAcceptor.supervisor_name(c.namespace))

    for round <- 1..5 do
      {_adapter, _port} = register!(c, "contact-#{round}", round)
      acceptor = ProfileAcceptor.whereis(c.namespace, c.mission, c.profile)
      ref = Process.monitor(acceptor)
      Process.exit(acceptor, :kill)
      assert_receive {:DOWN, ^ref, :process, ^acceptor, :killed}, 1_000

      assert eventually(fn ->
               ProfileAcceptor.whereis(c.namespace, c.mission, c.profile) == nil
             end)
    end

    assert GenServer.whereis(ProfileAcceptor.supervisor_name(c.namespace)) == supervisor
    assert Process.alive?(supervisor)
  end

  test "the listener closes after the last contact leaves (linger) and frees its port", c do
    listen = %{port: 0, host: "127.0.0.1", linger_ms: 50}
    {a, port} = register!(c, "contact-a", 1, listen: listen)
    stop_adapter(a)

    assert eventually(fn ->
             match?({:error, _}, :gen_tcp.connect(~c"127.0.0.1", port, [], 100))
           end)
  end

  # A stand-in adapter: registers, then forwards what the acceptor sends it to the test.
  defp register!(c, contact, scid, opts \\ []) do
    test = self()
    listen = Keyword.get(opts, :listen, %{port: 0, host: "127.0.0.1"})

    adapter =
      spawn(fn ->
        receive do
          {:register, from} ->
            registration = %{
              adapter: self(),
              realized_contact_id: contact,
              path_id: "downlink",
              scid: scid,
              provider_binding_id: Keyword.get(opts, :provider_binding_id, c.profile),
              allowed_peers:
                opts
                |> Keyword.get(:allowed, ["127.0.0.1/32", "::1/128"])
                |> PeerAddresses.ranges(),
              frame_size: Keyword.get(opts, :frame_size, @frame_size)
            }

            send(
              from,
              {:registered,
               ProfileAcceptor.register(c.namespace, c.mission, c.profile, listen, registration)}
            )

            forward(test)
        end
      end)

    send(adapter, {:register, self()})
    assert_receive {:registered, {:ok, port, acceptor}}, 2_000
    assert acceptor == ProfileAcceptor.whereis(c.namespace, c.mission, c.profile)
    {adapter, port}
  end

  defp forward(test) do
    receive do
      {:recv, socket, from} ->
        send(from, {:received, :gen_tcp.recv(socket, 0, 2_000)})
        forward(test)

      :stop ->
        :ok

      message ->
        send(test, {self(), message})
        forward(test)
    end
  end

  # The adapter owns the socket, so it reads on the test's behalf.
  defp recv_as(adapter, socket) do
    send(adapter, {:recv, socket, self()})
    assert_receive {:received, result}, 2_000
    result
  end

  defp stop_adapter(adapter) do
    ref = Process.monitor(adapter)
    send(adapter, :stop)
    assert_receive {:DOWN, ^ref, :process, ^adapter, _}, 2_000
  end

  defp connect!(port, first) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    if first != "", do: :ok = :gen_tcp.send(socket, first)
    socket
  end

  # A TM transfer frame header with `scid`, padded to the frame size.
  defp frame(scid), do: <<0::2, scid::10, 0::3, 0::1, 0::16, 0::64>> <> <<0::16>>

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end
end
