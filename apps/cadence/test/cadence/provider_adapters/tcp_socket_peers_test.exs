defmodule Cadence.ProviderAdapters.TCPSocketPeersTest do
  @moduledoc """
  DECISIONS #67: a listening provider never refuses a second peer silently, and drops a peer
  that qualification couldn't verify so the attested one can connect (qa #38 positive test).
  """
  use Cadence.DataCase, async: false

  import ExUnit.CaptureLog
  import Cadence.DataCase, only: [persist_mission_scope: 2]

  alias Cadence.ProviderAdapters.TCPSocket

  alias Cadence.Runtime.{
    CapabilityRegistry,
    MissionRuntime,
    ProcessNamespace,
    ProviderIngressExecutor,
    SessionReadiness
  }

  setup do
    persist_mission_scope("peers-org", "peers-mission")

    namespace =
      ProcessNamespace.new!(
        root_supervisor: __MODULE__.Root,
        registry: __MODULE__.Registry,
        mission_supervisor: __MODULE__.Missions,
        capability_registry: __MODULE__.Capabilities
      )

    start_supervised!({Registry, keys: :unique, name: namespace.registry})
    start_supervised!({CapabilityRegistry, name: namespace.capability_registry})

    start_supervised!(
      {SessionReadiness,
       name: SessionReadiness.name(namespace), policy: Cadence.SessionTestSupport}
    )

    executor =
      start_supervised!(
        {ProviderIngressExecutor,
         mission_id: "peers-mission",
         realized_contact_id: "peers-contact",
         path_id: "path",
         provider_binding_id: "provider",
         persistence_projector_name: nil}
      )

    provider =
      start_supervised!(
        {TCPSocket,
         process_namespace: namespace,
         name:
           MissionRuntime.provider_runtime_name(
             namespace,
             "peers-mission",
             "peers-contact",
             "path",
             "provider"
           ),
         mission_id: "peers-mission",
         realized_contact_id: "peers-contact",
         path_id: "path",
         provider_binding_id: "provider",
         direction: :uplink,
         ingress_executor_name: executor,
         configuration: %{
           mode: :listen,
           host: "127.0.0.1",
           port: 0,
           uplink_resource_id: "peers-vc"
         }}
      )

    %{provider: provider, port: :sys.get_state(provider).port}
  end

  test "a second peer is refused with a warning naming it; an unverified peer is dropped and the next one connects",
       c do
    stray = connect!(c.port)
    stray_address = local_address(stray)
    assert eventually(fn -> :sys.get_state(c.provider).session_peer == stray_address end)

    # The attested peer arrives second: refused (closed), never left waiting in the backlog.
    log =
      capture_log(fn ->
        attested = connect!(c.port)
        assert {:error, :closed} = :gen_tcp.recv(attested, 0, 2_000)
        :gen_tcp.close(attested)
      end)

    assert log =~ "refused a second connection from 127.0.0.1:"
    assert log =~ "#{stray_address} is connected"

    # Qualification couldn't verify the stray: drop it and keep accepting.
    log =
      capture_log(fn ->
        assert {:error, :peer_not_connected} =
                 TCPSocket.drop_unverified_peer(c.provider, "127.0.0.1:1", :mismatch)

        assert :ok =
                 TCPSocket.drop_unverified_peer(
                   c.provider,
                   stray_address,
                   :attestation_peer_mismatch
                 )
      end)

    assert log =~ "dropped unverified peer #{stray_address}"
    assert {:error, :closed} = :gen_tcp.recv(stray, 0, 2_000)

    assert {:ok, %{uplink_session: %{status: :blocked, reason: :unverified_peer_connected}}} =
             TCPSocket.snapshot(c.provider)

    attested = connect!(c.port)
    attested_address = local_address(attested)
    assert eventually(fn -> :sys.get_state(c.provider).session_peer == attested_address end)
    assert {:ok, _handle} = TCPSocket.uplink_session(c.provider)
  end

  test "repeat warnings about the same peer address are rate-limited", c do
    _holder = connect!(c.port)
    assert eventually(fn -> is_binary(:sys.get_state(c.provider).session_peer) end)

    log =
      capture_log(fn ->
        for _attempt <- 1..3 do
          extra = connect!(c.port)
          assert {:error, :closed} = :gen_tcp.recv(extra, 0, 2_000)
        end
      end)

    assert length(Regex.scan(~r/refused a second connection/, log)) == 1
  end

  defp connect!(port) do
    {:ok, socket} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: 0], 2_000)

    on_exit(fn -> :gen_tcp.close(socket) end)
    socket
  end

  defp local_address(socket) do
    {:ok, {ip, port}} = :inet.sockname(socket)
    "#{:inet.ntoa(ip)}:#{port}"
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end
end
