defmodule Cadence.Runtime.ProcessNamespaceTest do
  use ExUnit.Case, async: false

  alias Cadence.Control.MissionRuntime, as: ControlMissionRuntime
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Control.ProcessNamespace, as: ControlProcessNamespace
  alias Cadence.Control.Supervisor, as: ControlSupervisor
  alias Cadence.Runtime.CapabilityRegistry
  alias Cadence.Runtime.MissionCoordinator
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace
  alias Cadence.Runtime.RealizedContactRuntimeSpec
  alias Cadence.Runtime.Supervisor, as: RuntimeSupervisor

  @mission_id "shared-mission"

  test "default namespaces preserve production names and compatibility constructors" do
    assert RuntimeProcessNamespace.default() ==
             RuntimeProcessNamespace.new!(
               root_supervisor: Cadence.Runtime.Supervisor,
               registry: Cadence.Runtime.Registry,
               mission_supervisor: Cadence.Runtime.MissionSupervisor,
               capability_registry: Cadence.Runtime.CapabilityRegistry
             )

    assert ControlProcessNamespace.default() ==
             ControlProcessNamespace.new!(
               root_supervisor: Cadence.Control.Supervisor,
               registry: Cadence.Control.Registry,
               mission_supervisor: Cadence.Control.MissionSupervisor,
               mission_recovery: Cadence.Control.MissionRecovery,
               contact_fact_consumer: Cadence.Control.ContactFactConsumer,
               runtime_fact_consumer: Cadence.Control.RuntimeFactConsumer
             )

    assert MissionRuntime.runtime_name(@mission_id) ==
             {:via, Registry, {Cadence.Runtime.Registry, {:mission_runtime, @mission_id}}}

    assert ControlMissionRuntime.runtime_name(@mission_id) ==
             {:via, Registry, {Cadence.Control.Registry, {:mission_control_runtime, @mission_id}}}
  end

  test "two namespaced Runtime and Control roots own identical mission ids independently" do
    runtime_alpha = runtime_namespace(:alpha)
    runtime_bravo = runtime_namespace(:bravo)
    control_alpha = control_namespace(:alpha)
    control_bravo = control_namespace(:bravo)

    runtime_alpha_root = start_runtime_root(runtime_alpha)
    runtime_bravo_root = start_runtime_root(runtime_bravo)
    control_alpha_root = start_control_root(control_alpha, runtime_alpha)
    control_bravo_root = start_control_root(control_bravo, runtime_bravo)

    assert Process.whereis(runtime_alpha.root_supervisor) == runtime_alpha_root
    assert Process.whereis(runtime_bravo.root_supervisor) == runtime_bravo_root
    assert Process.whereis(control_alpha.root_supervisor) == control_alpha_root
    assert Process.whereis(control_bravo.root_supervisor) == control_bravo_root

    {runtime_alpha_registry, runtime_bravo_registry} =
      assert_distinct_named_processes(runtime_alpha.registry, runtime_bravo.registry)

    {runtime_alpha_mission_supervisor, runtime_bravo_mission_supervisor} =
      assert_distinct_named_processes(
        runtime_alpha.mission_supervisor,
        runtime_bravo.mission_supervisor
      )

    {runtime_alpha_capability_registry, runtime_bravo_capability_registry} =
      assert_distinct_named_processes(
        runtime_alpha.capability_registry,
        runtime_bravo.capability_registry
      )

    {control_alpha_registry, control_bravo_registry} =
      assert_distinct_named_processes(control_alpha.registry, control_bravo.registry)

    {control_alpha_mission_supervisor, control_bravo_mission_supervisor} =
      assert_distinct_named_processes(
        control_alpha.mission_supervisor,
        control_bravo.mission_supervisor
      )

    assert {:ok, runtime_alpha_mission} =
             Cadence.Runtime.ensure_mission_started(runtime_alpha, @mission_id)

    assert {:ok, runtime_bravo_mission} =
             Cadence.Runtime.ensure_mission_started(runtime_bravo, @mission_id)

    assert runtime_alpha_mission != runtime_bravo_mission

    assert GenServer.whereis(MissionRuntime.runtime_name(runtime_alpha, @mission_id)) ==
             runtime_alpha_mission

    assert GenServer.whereis(MissionRuntime.runtime_name(runtime_bravo, @mission_id)) ==
             runtime_bravo_mission

    runtime_alpha_coordinator =
      GenServer.whereis(MissionRuntime.coordinator_name(runtime_alpha, @mission_id))

    runtime_bravo_coordinator =
      GenServer.whereis(MissionRuntime.coordinator_name(runtime_bravo, @mission_id))

    assert is_pid(runtime_alpha_coordinator)
    assert is_pid(runtime_bravo_coordinator)
    assert runtime_alpha_coordinator != runtime_bravo_coordinator

    assert {:ok, _descriptor} =
             CapabilityRegistry.fetch_descriptor(
               runtime_alpha.capability_registry,
               :definition_bound_telemetry
             )

    assert {:ok, _descriptor} =
             CapabilityRegistry.fetch_descriptor(
               runtime_bravo.capability_registry,
               :definition_bound_telemetry
             )

    assert {:ok, realized_contact} = realized_contact_spec()

    assert {:ok, runtime_alpha_contact} =
             Cadence.Runtime.start_realized_contact(runtime_alpha, realized_contact)

    assert {:ok, runtime_bravo_contact} =
             Cadence.Runtime.start_realized_contact(runtime_bravo, realized_contact)

    assert runtime_alpha_contact != runtime_bravo_contact

    assert GenServer.whereis(
             MissionRuntime.realized_contact_runtime_name(
               runtime_alpha,
               @mission_id,
               realized_contact.realized_contact_id
             )
           ) == runtime_alpha_contact

    assert GenServer.whereis(
             MissionRuntime.realized_contact_runtime_name(
               runtime_bravo,
               @mission_id,
               realized_contact.realized_contact_id
             )
           ) == runtime_bravo_contact

    runtime_alpha_transport =
      GenServer.whereis(
        MissionRuntime.transport_runtime_name(
          runtime_alpha,
          @mission_id,
          realized_contact.realized_contact_id,
          "shared-path",
          "shared-heartbeat"
        )
      )

    runtime_bravo_transport =
      GenServer.whereis(
        MissionRuntime.transport_runtime_name(
          runtime_bravo,
          @mission_id,
          realized_contact.realized_contact_id,
          "shared-path",
          "shared-heartbeat"
        )
      )

    assert is_pid(runtime_alpha_transport)
    assert is_pid(runtime_bravo_transport)
    assert runtime_alpha_transport != runtime_bravo_transport

    assert {:ok, control_alpha_mission} =
             ControlMissions.ensure_started(control_alpha, @mission_id)

    assert {:ok, control_bravo_mission} =
             ControlMissions.ensure_started(control_bravo, @mission_id)

    assert control_alpha_mission != control_bravo_mission

    assert GenServer.whereis(ControlMissionRuntime.runtime_name(control_alpha, @mission_id)) ==
             control_alpha_mission

    assert GenServer.whereis(ControlMissionRuntime.runtime_name(control_bravo, @mission_id)) ==
             control_bravo_mission

    control_alpha_reconciler =
      GenServer.whereis(ControlMissionRuntime.reconciler_name(control_alpha, @mission_id))

    control_bravo_reconciler =
      GenServer.whereis(ControlMissionRuntime.reconciler_name(control_bravo, @mission_id))

    assert is_pid(control_alpha_reconciler)
    assert is_pid(control_bravo_reconciler)
    assert control_alpha_reconciler != control_bravo_reconciler

    assert %{mission_id: @mission_id, safety_timer_scheduled?: false} =
             MissionRuntimeReconciler.snapshot(control_alpha, @mission_id)

    assert %{mission_id: @mission_id, safety_timer_scheduled?: false} =
             MissionRuntimeReconciler.snapshot(control_bravo, @mission_id)

    assert :ok = stop_supervised(control_alpha.root_supervisor)
    assert :ok = stop_supervised(runtime_alpha.root_supervisor)

    refute Process.alive?(control_alpha_mission)
    refute Process.alive?(runtime_alpha_mission)
    refute Process.alive?(runtime_alpha_contact)
    refute Process.alive?(runtime_alpha_transport)
    refute Process.alive?(runtime_alpha_registry)
    refute Process.alive?(runtime_alpha_mission_supervisor)
    refute Process.alive?(runtime_alpha_capability_registry)
    refute Process.alive?(control_alpha_registry)
    refute Process.alive?(control_alpha_mission_supervisor)
    assert [] = ControlMissions.running_mission_ids(control_alpha)
    assert [] = Cadence.Runtime.running_mission_ids(runtime_alpha)

    assert Process.alive?(control_bravo_root)
    assert Process.alive?(runtime_bravo_root)
    assert Process.alive?(control_bravo_mission)
    assert Process.alive?(runtime_bravo_mission)
    assert Process.alive?(runtime_bravo_contact)
    assert Process.alive?(runtime_bravo_transport)
    assert Process.alive?(runtime_bravo_registry)
    assert Process.alive?(runtime_bravo_mission_supervisor)
    assert Process.alive?(runtime_bravo_capability_registry)
    assert Process.alive?(control_bravo_registry)
    assert Process.alive?(control_bravo_mission_supervisor)

    assert {:ok, ^control_bravo_mission} =
             ControlMissions.ensure_started(control_bravo, @mission_id)

    assert {:ok, ^runtime_bravo_mission} =
             Cadence.Runtime.ensure_mission_started(runtime_bravo, @mission_id)

    assert [@mission_id] = ControlMissions.running_mission_ids(control_bravo)
    assert [@mission_id] = Cadence.Runtime.running_mission_ids(runtime_bravo)

    assert {:ok, %{status: :settled, mission_id: @mission_id}} =
             ControlMissions.await_settled(control_bravo, @mission_id)

    assert {:error, :no_active_binding_set} =
             MissionCoordinator.active_spec(runtime_bravo, @mission_id)

    assert {:ok, %{transport_runtime_count: 1}} =
             Cadence.Runtime.path_runtime_snapshot(
               runtime_bravo,
               @mission_id,
               realized_contact.realized_contact_id,
               "shared-path"
             )

    assert {:ok, _descriptor} =
             CapabilityRegistry.fetch_descriptor(
               runtime_bravo.capability_registry,
               :definition_bound_telemetry
             )
  end

  defp start_runtime_root(process_namespace) do
    start_supervised!(
      {RuntimeSupervisor,
       process_namespace: process_namespace,
       resource_children: [],
       mission_runtime_opts: [persist_runtime_records?: false]}
    )
  end

  defp assert_distinct_named_processes(left_name, right_name) do
    left = Process.whereis(left_name)
    right = Process.whereis(right_name)

    assert is_pid(left)
    assert is_pid(right)
    assert left != right

    {left, right}
  end

  defp start_control_root(process_namespace, runtime_process_namespace) do
    start_supervised!(
      {ControlSupervisor,
       process_namespace: process_namespace,
       runtime_process_namespace: runtime_process_namespace,
       start_mission_recovery?: false,
       start_fact_consumers?: false,
       start_shared_resources?: false,
       mission_runtime_opts: [
         start_contact_scheduler?: false,
         reconciler_opts: [reconcile_on_start?: false, safety_poll?: false]
       ]}
    )
  end

  defp runtime_namespace(:alpha) do
    RuntimeProcessNamespace.new!(
      root_supervisor: Cadence.Runtime.ProcessNamespaceTest.RuntimeAlphaSupervisor,
      registry: Cadence.Runtime.ProcessNamespaceTest.RuntimeAlphaRegistry,
      mission_supervisor: Cadence.Runtime.ProcessNamespaceTest.RuntimeAlphaMissionSupervisor,
      capability_registry: Cadence.Runtime.ProcessNamespaceTest.RuntimeAlphaCapabilityRegistry
    )
  end

  defp runtime_namespace(:bravo) do
    RuntimeProcessNamespace.new!(
      root_supervisor: Cadence.Runtime.ProcessNamespaceTest.RuntimeBravoSupervisor,
      registry: Cadence.Runtime.ProcessNamespaceTest.RuntimeBravoRegistry,
      mission_supervisor: Cadence.Runtime.ProcessNamespaceTest.RuntimeBravoMissionSupervisor,
      capability_registry: Cadence.Runtime.ProcessNamespaceTest.RuntimeBravoCapabilityRegistry
    )
  end

  defp control_namespace(:alpha) do
    ControlProcessNamespace.new!(
      root_supervisor: Cadence.Runtime.ProcessNamespaceTest.ControlAlphaSupervisor,
      registry: Cadence.Runtime.ProcessNamespaceTest.ControlAlphaRegistry,
      mission_supervisor: Cadence.Runtime.ProcessNamespaceTest.ControlAlphaMissionSupervisor,
      mission_recovery: Cadence.Runtime.ProcessNamespaceTest.ControlAlphaMissionRecovery,
      contact_fact_consumer: Cadence.Runtime.ProcessNamespaceTest.ControlAlphaContactFactConsumer,
      runtime_fact_consumer: Cadence.Runtime.ProcessNamespaceTest.ControlAlphaRuntimeFactConsumer
    )
  end

  defp control_namespace(:bravo) do
    ControlProcessNamespace.new!(
      root_supervisor: Cadence.Runtime.ProcessNamespaceTest.ControlBravoSupervisor,
      registry: Cadence.Runtime.ProcessNamespaceTest.ControlBravoRegistry,
      mission_supervisor: Cadence.Runtime.ProcessNamespaceTest.ControlBravoMissionSupervisor,
      mission_recovery: Cadence.Runtime.ProcessNamespaceTest.ControlBravoMissionRecovery,
      contact_fact_consumer: Cadence.Runtime.ProcessNamespaceTest.ControlBravoContactFactConsumer,
      runtime_fact_consumer: Cadence.Runtime.ProcessNamespaceTest.ControlBravoRuntimeFactConsumer
    )
  end

  defp realized_contact_spec do
    RealizedContactRuntimeSpec.new(%{
      realized_contact_id: "shared-contact",
      mission_id: @mission_id,
      source_endpoint_refs: ["shared-source"],
      contact_intents: [:command_window],
      clock_mode: :replay,
      initial_time: DateTime.from_unix!(1_700_100_000, :second),
      paths: [
        %{
          path_id: "shared-path",
          direction: :uplink,
          selection_role: :selected,
          source_endpoint_ref: "shared-source",
          transport_bindings: [
            %{
              transport_binding_id: "shared-heartbeat",
              family_key: :heartbeat_monitor,
              target_scope: :path,
              configuration: %{"heartbeat_interval_ms" => 25}
            }
          ]
        }
      ]
    })
  end
end
