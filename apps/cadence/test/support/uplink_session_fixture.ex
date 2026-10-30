defmodule Cadence.UplinkSessionFixture do
  @moduledoc false
  import ExUnit.Callbacks
  import Cadence.DataCase, only: [persist_mission_scope: 2]
  alias Cadence.ProviderAdapters.TCPSocket

  alias Cadence.Runtime.{
    CapabilityRegistry,
    MissionRuntime,
    PartitionKey,
    ProcessNamespace,
    ProviderIngressExecutor,
    SessionReadiness,
    TransportRuntime
  }

  alias Cadence.SessionTestSupport

  def setup do
    persist_mission_scope("gate-org", "gate-mission")

    namespace =
      ProcessNamespace.new!(
        root_supervisor: __MODULE__.Root,
        registry: __MODULE__.Registry,
        mission_supervisor: __MODULE__.Missions,
        capability_registry: __MODULE__.Capabilities
      )

    start_supervised!({Registry, keys: :unique, name: namespace.registry})
    start_supervised!({CapabilityRegistry, name: namespace.capability_registry})

    gate =
      start_supervised!(
        {SessionReadiness, name: SessionReadiness.name(namespace), policy: SessionTestSupport}
      )

    executor =
      start_supervised!(
        {ProviderIngressExecutor,
         mission_id: "gate-mission",
         realized_contact_id: "gate-contact",
         path_id: "path",
         provider_binding_id: "provider",
         persistence_projector_name: nil}
      )

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: 0])
    {:ok, {_, port}} = :inet.sockname(listener)

    provider =
      start_supervised!(
        {TCPSocket,
         process_namespace: namespace,
         name:
           MissionRuntime.provider_runtime_name(
             namespace,
             "gate-mission",
             "gate-contact",
             "path",
             "provider"
           ),
         mission_id: "gate-mission",
         realized_contact_id: "gate-contact",
         path_id: "path",
         provider_binding_id: "provider",
         direction: :uplink,
         ingress_executor_name: executor,
         configuration: %{
           mode: :connect,
           host: "127.0.0.1",
           port: port,
           uplink_resource_id: "physical-vc"
         }}
      )

    {:ok, peer} = :gen_tcp.accept(listener)

    on_exit(fn ->
      :gen_tcp.close(peer)
      :gen_tcp.close(listener)
    end)

    runtime =
      start_supervised!(
        {TransportRuntime,
         process_namespace: namespace,
         mission_id: "gate-mission",
         realized_contact_id: "gate-contact",
         path_id: "path",
         activation_id: "activation",
         binding_set_id: "binding",
         binding_set_version: 1,
         capability_instance_id: "uplink",
         family_key: :uplink_gateway,
         configuration: %{
           service_name: "cop1",
           frame_size: 12,
           segment_header_flag: 1,
           cop1_mode: :fop,
           cop1_window_size: 4,
           cop1_timeout_ms: 100,
           cop1_max_retransmit: 2,
           provider_binding_id: "provider",
           provider_adapter_key: :tcp_socket
         },
         scope_ref: "path",
         partition_key: PartitionKey.new(%{affinity: :path, value: "path"}),
         clock_mode: :replay,
         initial_time: ~U[2026-10-27 00:00:00Z],
         persist_runtime_records?: false}
      )

    %{
      namespace: namespace,
      runtime: runtime,
      provider: provider,
      peer: peer,
      listener: listener,
      gate: gate
    }
  end
end
