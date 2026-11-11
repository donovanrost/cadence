defmodule Cadence.ProviderAdapters.TCPSocketPeersTest do
  @moduledoc """
  A listening provider never refuses a second peer silently: it is closed and logged with its
  address, never left in the listen backlog believing it is connected.
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

  test "a second peer is refused with a warning naming it, and the first keeps the session", c do
    first = connect!(c.port)
    first_address = local_address(first)
    assert eventually(fn -> :sys.get_state(c.provider).session_peer == first_address end)

    log =
      capture_log(fn ->
        second = connect!(c.port)
        assert {:error, :closed} = :gen_tcp.recv(second, 0, 2_000)
        :gen_tcp.close(second)
      end)

    assert log =~ "refused a second connection from 127.0.0.1:"
    assert log =~ "#{first_address} is connected"
    assert :sys.get_state(c.provider).session_peer == first_address
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
