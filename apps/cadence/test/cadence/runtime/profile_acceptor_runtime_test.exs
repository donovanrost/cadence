defmodule Cadence.Runtime.ProfileAcceptorRuntimeTest do
  @moduledoc """
  DECISIONS #87 (A), through real contacts: two overlapping passes for two spacecraft on ONE
  listen-mode profile with "listener" => "shared" both run (no :eaddrinuse), and each receives its
  own spacecraft's frames; a crashed acceptor is replaced without dropping either session.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, ProviderBinding, ScheduledContact}
  alias Cadence.ProviderAdapters.TCPSocket
  alias Cadence.Runtime.{ProcessNamespace, ProfileAcceptor}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  @frame_size 10
  @apid 42

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
    acceptor = ProfileAcceptor.whereis(ProcessNamespace.default(), ctx.mission_id, ctx.profile_id)
    Process.exit(acceptor, :kill)

    assert_eventually(fn ->
      replaced =
        ProfileAcceptor.whereis(ProcessNamespace.default(), ctx.mission_id, ctx.profile_id)

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
    acceptor = ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id)

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
      fn -> is_pid(ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id)) end,
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
    acceptor = ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id)

    :ok = :sys.suspend(adapter)
    :ok = DynamicSupervisor.terminate_child(ProfileAcceptor.supervisor_name(namespace), acceptor)
    squatter = squat!(port)
    :ok = :sys.resume(adapter)

    # The re-registration on :DOWN fails while the port is held; free it at once.
    Process.sleep(100)
    :ok = :gen_tcp.close(squatter)

    # Registered again well before the 5 s backoff would have allowed.
    assert_eventually(
      fn -> is_pid(ProfileAcceptor.whereis(namespace, ctx.mission_id, ctx.profile_id)) end,
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

  defp adapter(ctx, scheduled) do
    key =
      {:provider_runtime, ctx.mission_id, run_id(scheduled),
       "downlink-" <> scheduled.scheduled_contact_id, ctx.profile_id}

    [{pid, _}] = Registry.lookup(ProcessNamespace.default().registry, key)
    pid
  end

  defp received(ctx, scheduled) do
    path_id = "downlink-" <> scheduled.scheduled_contact_id

    case Cadence.Runtime.path_runtime_snapshot(ctx.mission_id, run_id(scheduled), path_id) do
      {:ok, snapshot} -> downlink_bytes(snapshot)
      _not_running -> 0
    end
  end

  defp downlink_bytes(%{downlink_bytes_received: bytes}) when is_integer(bytes), do: bytes

  defp downlink_bytes(map) when is_map(map),
    do: map |> Map.values() |> Enum.map(&downlink_bytes/1) |> Enum.sum()

  defp downlink_bytes(list) when is_list(list),
    do: list |> Enum.map(&downlink_bytes/1) |> Enum.sum()

  defp downlink_bytes(_other), do: 0

  defp connect!(port, first) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, first)
    socket
  end

  # A TM transfer frame header for `scid`, padded to the frame size.
  defp frame(scid), do: <<0::2, scid::10, 0::3, 0::1, 0::16, 0::16>> <> <<0::32>>

  defp endpoint!(ctx, name, scid) do
    spacecraft_id = "sc-#{name}-#{System.unique_integer([:positive])}"

    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        ctx.organization_id,
        Spacecraft.new(%{
          spacecraft_id: spacecraft_id,
          mission_id: ctx.mission_id,
          display_name: name,
          scid: scid
        })
      )

    {:ok, endpoint} =
      Cadence.SourceEndpoints.persist_source_endpoint(
        ctx.organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-#{name}-#{System.unique_integer([:positive])}",
          mission_id: ctx.mission_id,
          spacecraft_id: spacecraft_id,
          source_ref: "provider/tcp/#{name}"
        })
      )

    endpoint.source_endpoint_id
  end

  defp schedule!(ctx, endpoint_id, name, starts_at, ends_at, port, configuration \\ %{}) do
    id = "#{name}-#{System.unique_integer([:positive])}"

    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: id,
        mission_id: ctx.mission_id,
        source_endpoint_refs: [endpoint_id],
        starts_at: starts_at,
        ends_at: ends_at,
        paths: [
          Path.new(%{
            path_id: "downlink-#{id}",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: ctx.profile_id,
                adapter_key: :tcp_socket,
                configuration:
                  Map.merge(
                    %{
                      mode: :listen,
                      listener: "shared",
                      port: port,
                      ingress_protocol_family: :tm,
                      frame_size: @frame_size,
                      ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
                    },
                    configuration
                  )
              })
            ]
          })
        ]
      })

    {:ok, scheduled} = Contacts.persist_scheduled_contact(ctx.organization_id, contact)
    scheduled
  end

  defp run_id(%ScheduledContact{scheduled_contact_id: id}), do: id <> "_run"

  # The stopped acceptor's listener may still be closing: retry the bind briefly.
  defp squat!(port, attempts \\ 40) do
    case :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, reuseaddr: true]) do
      {:ok, socket} ->
        socket

      {:error, :eaddrinuse} when attempts > 0 ->
        Process.sleep(50)
        squat!(port, attempts - 1)
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp fixture! do
    organization_id = "org-start-#{System.unique_integer([:positive])}"
    suffix = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-start-" <> suffix
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-start-" <> suffix,
        mission_id: mission_id,
        display_name: "SC start"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    {:ok, endpoint} =
      Cadence.SourceEndpoints.persist_source_endpoint(
        organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-start-" <> suffix,
          mission_id: mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          source_ref: "provider/tcp"
        })
      )

    packet =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-start-" <> suffix,
        packet_name: "TMHK",
        apid: @apid,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    {:ok, binding_set} =
      Cadence.Governance.persist_binding_set(
        organization_id,
        BindingSet.new(%{
          mission_id: mission_id,
          binding_set_id: "start-basis-" <> suffix,
          version: 1,
          rules: [
            BindingRule.new(%{
              binding_rule_id: "start-telemetry-rule-" <> suffix,
              handler_key: :definition_bound_telemetry,
              packet_kind: :space_packet,
              apid: @apid,
              priority: 10,
              handler_configuration: packet
            })
          ]
        })
      )

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        organization_id,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        activated_by: %{"service_identity_id" => "svc-test"}
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      endpoint_id: endpoint.source_endpoint_id,
      profile_id: "provider-profile-" <> suffix
    }
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
