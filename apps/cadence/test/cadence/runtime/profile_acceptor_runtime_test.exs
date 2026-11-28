defmodule Cadence.Runtime.ProfileAcceptorRuntimeTest do
  @moduledoc """
  DECISIONS #87 (A), through real contacts: two overlapping passes for two spacecraft on ONE
  listen-mode profile with "listener" => "shared" both run (no :eaddrinuse), and each receives its
  own spacecraft's frames; a crashed acceptor is replaced without dropping either session.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.SharedListenerFixtures

  alias Cadence.Contacts
  alias Cadence.ProviderAdapters.TCPSocket
  alias Cadence.Runtime.{ProcessNamespace, ProfileAcceptor}

  setup do
    settlement = Application.get_env(:cadence, :contact_settlement)
    Application.put_env(:cadence, :contact_settlement, deadline_ms: 2_000)
    on_exit(fn -> restore(:contact_settlement, settlement) end)

    ctx = fixture!()
    alpha = endpoint!(ctx, "alpha", 1)
    bravo = endpoint!(ctx, "bravo", 2)
    Map.merge(ctx, %{alpha: alpha, bravo: bravo})
  end

  test "two overlapping passes on one shared profile both run and get their own frames", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()

    first =
      schedule!(ctx, ctx.alpha, "alpha", DateTime.add(now, -60), DateTime.add(now, 600), port)

    second =
      schedule!(ctx, ctx.bravo, "bravo", DateTime.add(now, -30), DateTime.add(now, 600), port)

    assert {:ok, %{errors: [], realized_scheduled_contact_ids: realized}} =
             Contacts.reconcile(ctx.mission_id, now)

    assert Enum.sort(realized) == Enum.sort([run_id(first), run_id(second)])

    peer_alpha = connect!(port, frame(1))
    peer_bravo = connect!(port, frame(2))

    assert_eventually(fn -> received(ctx, first) > 0 and received(ctx, second) > 0 end)

    # The acceptor crashes: both sessions live on (their sockets are the adapters'), the adapters
    # register again, and a new peer still reaches its contact.
    acceptor =
      ProfileAcceptor.whereis(ProcessNamespace.default(), ctx.mission_id, ctx.profile_id, %{
        host: "127.0.0.1",
        port: port
      })

    Process.exit(acceptor, :kill)

    assert_eventually(fn ->
      replaced =
        ProfileAcceptor.whereis(ProcessNamespace.default(), ctx.mission_id, ctx.profile_id, %{
          host: "127.0.0.1",
          port: port
        })

      # Both contacts registered again: one may first hit :eaddrinuse while the killed
      # listener closes and come back on its quick (250 ms) retry.
      is_pid(replaced) and replaced != acceptor and
        length(GenServer.call(replaced, :routing).registrations) == 2
    end)

    before = received(ctx, first)
    :ok = :gen_tcp.send(peer_alpha, frame(1))
    assert_eventually(fn -> received(ctx, first) > before end)

    :ok = :gen_tcp.close(peer_bravo)
    later = received(ctx, second)
    _again = connect!(port, frame(2))
    assert_eventually(fn -> received(ctx, second) > later end)

    for scheduled <- [first, second],
        do: :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(scheduled))
  end

  test "a failed re-registration keeps the live session and retries until it registers", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()

    pass =
      schedule!(ctx, ctx.alpha, "alpha", DateTime.add(now, -60), DateTime.add(now, 600), port)

    assert {:ok, %{errors: []}} = Contacts.reconcile(ctx.mission_id, now)
    peer = connect!(port, frame(1))
    assert_eventually(fn -> received(ctx, pass) > 0 end)

    namespace = ProcessNamespace.default()
    adapter = adapter(ctx, pass)

    acceptor =
      ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id, %{
        host: "127.0.0.1",
        port: port
      })

    # The adapter can't register again while something else holds the port.
    :ok = :sys.suspend(adapter)
    :ok = DynamicSupervisor.terminate_child(ProfileAcceptor.supervisor_name(namespace), acceptor)
    squatter = squat!(port)
    on_exit(fn -> :gen_tcp.close(squatter) end)
    :ok = :sys.resume(adapter)

    # It keeps its session (no stop), and its own peer's frames still arrive.
    Process.sleep(200)
    assert Process.alive?(adapter)
    before = received(ctx, pass)
    :ok = :gen_tcp.send(peer, frame(1))
    assert_eventually(fn -> received(ctx, pass) > before end)

    # Once the port is free, the retry (5 s backoff) registers it again.
    :ok = :gen_tcp.close(squatter)

    assert_eventually(
      fn ->
        is_pid(
          ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id, %{
            host: "127.0.0.1",
            port: port
          })
        )
      end,
      400
    )

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(pass))
  end

  # ux U50: a second connection identified as this pass's is counted; it opens the refusal
  # window (the listener_refusal item) only when the pass's own connection has gone quiet.
  describe "a second connection for a pass" do
    test "while its own connection is receiving is counted only, with no refusal window", ctx do
      {pass, port} = start_pass!(ctx, quiet_connection_ms: 60_000)
      _own = connect!(port, frame(1))
      assert_eventually(fn -> received(ctx, pass) > 0 end)

      _duplicate = connect!(port, frame(1))
      adapter = adapter(ctx, pass)
      assert_eventually(fn -> snapshot!(adapter).second_connections_refused == 1 end)

      snapshot = snapshot!(adapter)
      assert snapshot.refusals == nil
      assert snapshot.peers_refused == 1
      assert snapshot.connected?

      :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(pass))
    end

    test "after its own connection went quiet opens the window, with when it went quiet", ctx do
      # A numeric string from a profile is coerced (api-ops).
      {pass, port} = start_pass!(ctx, quiet_connection_ms: "100")
      _own = connect!(port, frame(1))
      assert_eventually(fn -> received(ctx, pass) > 0 end)
      adapter = adapter(ctx, pass)
      Process.sleep(250)

      refused_after = DateTime.utc_now()
      _reconnect = connect!(port, frame(1))
      assert_eventually(fn -> snapshot!(adapter).second_connections_refused == 1 end)

      assert %{
               count: 1,
               resolved: nil,
               last: %{reason: "second_connection", own_quiet_since: %DateTime{} = quiet_since}
             } = snapshot!(adapter).refusals

      assert DateTime.diff(refused_after, quiet_since, :millisecond) >= 100
      assert snapshot!(adapter).connected?

      :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(pass))
    end
  end

  # api-ops, lead: after a kill the old listener can still be closing when the adapter binds, so
  # the first retry is quick (250 ms), not the 5 s backoff.
  test "after a failed re-registration the first retry comes quickly", ctx do
    {pass, port} = start_pass!(ctx, [])
    _peer = connect!(port, frame(1))
    assert_eventually(fn -> received(ctx, pass) > 0 end)

    namespace = ProcessNamespace.default()
    adapter = adapter(ctx, pass)

    acceptor =
      ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id, %{
        host: "127.0.0.1",
        port: port
      })

    :ok = :sys.suspend(adapter)
    :ok = DynamicSupervisor.terminate_child(ProfileAcceptor.supervisor_name(namespace), acceptor)
    squatter = squat!(port)
    :ok = :sys.resume(adapter)

    # The re-registration on :DOWN fails while the port is held; free it at once.
    Process.sleep(100)
    :ok = :gen_tcp.close(squatter)

    # Registered again well before the 5 s backoff would have allowed.
    assert_eventually(
      fn ->
        is_pid(
          ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id, %{
            host: "127.0.0.1",
            port: port
          })
        )
      end,
      30
    )

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(pass))
  end

  defp start_pass!(ctx, configuration) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()

    pass =
      schedule!(
        ctx,
        ctx.alpha,
        "alpha",
        DateTime.add(now, -60),
        DateTime.add(now, 600),
        port,
        Map.new(configuration)
      )

    assert {:ok, %{errors: []}} = Contacts.reconcile(ctx.mission_id, now)
    {pass, port}
  end

  defp snapshot!(adapter) do
    {:ok, snapshot} = TCPSocket.snapshot(adapter)
    snapshot
  end

  defp assert_eventually(fun, attempts \\ 200)
  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)
end
