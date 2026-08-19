defmodule Cadence.Commanding.ProcessOwnersTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Commanding.{
    CommandVerifierInstance,
    Dispatcher,
    DispatchSupervisor,
    LaneDispatcher,
    ProcessNamespace,
    VerifierScheduler
  }

  @organization_id "shared-organization"
  @mission_id "shared-mission"
  @lane_key "shared-lane"

  test "default namespace preserves production addresses and validates existing names" do
    assert ProcessNamespace.default() ==
             ProcessNamespace.new!(
               root_supervisor: Cadence.Commanding.DispatchSupervisor,
               registry: Cadence.Commanding.DispatchRegistry,
               lane_supervisor: Cadence.Commanding.LaneDispatcherSupervisor,
               dispatcher: Cadence.Commanding.Dispatcher,
               verifier_scheduler: Cadence.Commanding.VerifierScheduler
             )

    assert_raise ArgumentError,
                 ~r/dispatcher must be an existing atom or registered server name/,
                 fn ->
                   ProcessNamespace.new!(
                     root_supervisor: __MODULE__.InvalidRoot,
                     registry: __MODULE__.InvalidRegistry,
                     lane_supervisor: __MODULE__.InvalidLaneSupervisor,
                     dispatcher: "dynamically-derived-name",
                     verifier_scheduler: __MODULE__.InvalidVerifierScheduler
                   )
                 end
  end

  test "two dispatch roots and verifier schedulers isolate identical owner keys" do
    test_pid = self()
    namespace_alpha = namespace(:alpha)
    namespace_bravo = namespace(:bravo)

    attach_scheduler_telemetry(test_pid)

    dispatch_root_alpha = start_dispatch_root(namespace_alpha, :alpha, test_pid)
    dispatch_root_bravo = start_dispatch_root(namespace_bravo, :bravo, test_pid)

    assert_receive {:dispatcher_requeue, :alpha, dispatcher_alpha}
    assert_receive {:dispatcher_requeue, :bravo, dispatcher_bravo}
    assert dispatcher_alpha == Process.whereis(namespace_alpha.dispatcher)
    assert dispatcher_bravo == Process.whereis(namespace_bravo.dispatcher)

    assert {:ok, %{pending_lane_count: 1}} = Dispatcher.reconcile_now(namespace_alpha)
    assert {:ok, %{pending_lane_count: 1}} = Dispatcher.reconcile_now(namespace_bravo)
    assert_receive {:dispatcher_list_pending_lanes, :alpha, ^dispatcher_alpha}
    assert_receive {:dispatcher_list_pending_lanes, :bravo, ^dispatcher_bravo}

    assert {:ok, lane_alpha} =
             DispatchSupervisor.lane_dispatcher(
               namespace_alpha,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert {:ok, lane_bravo} =
             DispatchSupervisor.lane_dispatcher(
               namespace_bravo,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert lane_alpha != lane_bravo

    assert :ok =
             DispatchSupervisor.ensure_lane_dispatcher_started(
               namespace_alpha,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert {:ok, ^lane_alpha} =
             DispatchSupervisor.lane_dispatcher(
               namespace_alpha,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert {:ok, ^lane_bravo} =
             DispatchSupervisor.lane_dispatcher(
               namespace_bravo,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert {:ok, %{status: :waiting_for_release_target}} = LaneDispatcher.drain(lane_alpha)
    assert {:ok, %{status: :waiting_for_release_target}} = LaneDispatcher.drain(lane_bravo)
    assert_receive {:lane_dispatch, :alpha, ^lane_alpha, @organization_id, @mission_id, @lane_key}
    assert_receive {:lane_dispatch, :bravo, ^lane_bravo, @organization_id, @mission_id, @lane_key}
    assert %{dispatch_timer: %{ref: alpha_lane_timer}} = :sys.get_state(lane_alpha)
    assert %{dispatch_timer: %{ref: bravo_lane_timer}} = :sys.get_state(lane_bravo)
    assert is_reference(alpha_lane_timer)
    assert is_reference(bravo_lane_timer)

    verifier_instance = verifier_instance()
    reference_time = ~U[2026-08-19 12:00:00Z]

    scheduler_alpha =
      start_verifier_scheduler(
        namespace_alpha,
        :alpha,
        test_pid,
        reference_time,
        verifier_instance
      )

    scheduler_bravo =
      start_verifier_scheduler(
        namespace_bravo,
        :bravo,
        test_pid,
        reference_time,
        verifier_instance
      )

    assert_receive {:scheduler_bootstrap_waiting, :alpha, ^scheduler_alpha}
    assert_receive {:scheduler_bootstrap_waiting, :bravo, ^scheduler_bravo}
    refute_received {:scheduler_projection_query, _owner, _scheduler}

    send(scheduler_alpha, {:release_scheduler_bootstrap, :alpha})
    send(scheduler_bravo, {:release_scheduler_bootstrap, :bravo})

    verifier_instance_id = verifier_instance.command_verifier_instance_id

    assert %{
             projected_verifier_instance_ids: [^verifier_instance_id],
             projected_verifier_count: 1,
             timeout_timer_count: 1
           } = VerifierScheduler.snapshot(namespace_alpha)

    assert %{
             projected_verifier_instance_ids: [^verifier_instance_id],
             projected_verifier_count: 1,
             timeout_timer_count: 1
           } = VerifierScheduler.snapshot(namespace_bravo)

    assert_receive {:scheduler_projection_query, :alpha, ^scheduler_alpha}
    assert_receive {:scheduler_projection_query, :bravo, ^scheduler_bravo}
    assert_receive {:scheduler_projection_rebuild, :alpha, ^scheduler_alpha}
    assert_receive {:scheduler_projection_rebuild, :bravo, ^scheduler_bravo}

    alpha_root_monitor = Process.monitor(dispatch_root_alpha)
    bravo_root_monitor = Process.monitor(dispatch_root_bravo)
    alpha_scheduler_monitor = Process.monitor(scheduler_alpha)
    bravo_scheduler_monitor = Process.monitor(scheduler_bravo)

    assert :ok = stop_supervised(namespace_alpha.root_supervisor)
    assert_receive {:DOWN, ^alpha_root_monitor, :process, ^dispatch_root_alpha, _reason}
    assert :ok = stop_supervised(namespace_alpha.verifier_scheduler)
    assert_receive {:DOWN, ^alpha_scheduler_monitor, :process, ^scheduler_alpha, _reason}

    assert is_nil(Process.whereis(namespace_alpha.registry))

    assert :error =
             DispatchSupervisor.lane_dispatcher(
               namespace_alpha,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert Process.alive?(dispatch_root_bravo)
    assert Process.alive?(scheduler_bravo)
    refute_received {:DOWN, ^bravo_root_monitor, :process, ^dispatch_root_bravo, _reason}
    refute_received {:DOWN, ^bravo_scheduler_monitor, :process, ^scheduler_bravo, _reason}

    assert {:ok, ^lane_bravo} =
             DispatchSupervisor.lane_dispatcher(
               namespace_bravo,
               @organization_id,
               @mission_id,
               @lane_key
             )

    assert %{dispatch_timer: %{ref: surviving_lane_timer}} = :sys.get_state(lane_bravo)
    assert is_reference(surviving_lane_timer)

    assert %{
             projected_verifier_instance_ids: [^verifier_instance_id],
             projected_verifier_count: 1,
             timeout_timer_count: 1
           } = VerifierScheduler.snapshot(namespace_bravo)

    assert {:ok, %{status: :waiting_for_release_target}} = LaneDispatcher.drain(lane_bravo)
    assert_receive {:lane_dispatch, :bravo, ^lane_bravo, @organization_id, @mission_id, @lane_key}

    assert {:ok, []} = VerifierScheduler.reconcile_now(namespace_bravo, reference_time)
    assert_receive {:scheduler_timeout_reconcile, :bravo, ^scheduler_bravo, ^reference_time}
    assert_receive {:scheduler_projection_query, :bravo, ^scheduler_bravo}

    satisfied_instance = %CommandVerifierInstance{verifier_instance | lifecycle_state: :satisfied}

    assert :ok =
             VerifierScheduler.notify_verifier_instances_changed(
               satisfied_instance,
               namespace_bravo
             )

    assert %{
             projected_verifier_instance_ids: [],
             projected_verifier_count: 0,
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(namespace_bravo)
  end

  defp start_dispatch_root(process_namespace, owner, test_pid) do
    dispatch_fun = fn organization_id, mission_id, lane_key, _released_by, _opts ->
      send(
        test_pid,
        {:lane_dispatch, owner, self(), organization_id, mission_id, lane_key}
      )

      {:error, {:command_queue_lane_no_release_target, lane_key, mission_id}}
    end

    start_supervised!(
      {DispatchSupervisor,
       process_namespace: process_namespace,
       auto_schedule?: false,
       run_on_boot?: false,
       dispatch_fun: dispatch_fun,
       lane_dispatcher_opts: [run_on_boot?: false],
       requeue_release_pending_fun: fn ->
         send(test_pid, {:dispatcher_requeue, owner, self()})
         0
       end,
       list_pending_queue_lanes_fun: fn ->
         send(test_pid, {:dispatcher_list_pending_lanes, owner, self()})

         [
           %{
             organization_id: @organization_id,
             mission_id: @mission_id,
             queue_lane_key: @lane_key
           }
         ]
       end}
    )
  end

  defp start_verifier_scheduler(
         process_namespace,
         owner,
         test_pid,
         reference_time,
         verifier_instance
       ) do
    child_spec =
      Supervisor.child_spec(
        {VerifierScheduler,
         process_namespace: process_namespace,
         auto_schedule?: true,
         run_on_boot?: false,
         safety_poll_interval_ms: :timer.hours(1),
         reference_time_fun: fn -> reference_time end,
         bootstrap_gate_fun: fn ->
           send(test_pid, {:scheduler_bootstrap_waiting, owner, self()})

           receive do
             {:release_scheduler_bootstrap, ^owner} -> :ok
           end
         end,
         projection_query_fun: fn ->
           send(test_pid, {:scheduler_projection_query, owner, self()})
           [verifier_instance]
         end,
         timeout_reconcile_fun: fn reconcile_time ->
           send(test_pid, {:scheduler_timeout_reconcile, owner, self(), reconcile_time})
           {:ok, []}
         end,
         telemetry_metadata: %{test_owner: owner}},
        id: process_namespace.verifier_scheduler
      )

    start_supervised!(child_spec)
  end

  defp attach_scheduler_telemetry(test_pid) do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :commanding, :verifier_scheduler, :projection_rebuild],
        fn _event, _measurements, metadata, _config ->
          case metadata do
            %{test_owner: owner} ->
              send(test_pid, {:scheduler_projection_rebuild, owner, self()})

            _other ->
              :ok
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp verifier_instance do
    CommandVerifierInstance.new(%{
      command_verifier_instance_id: "shared-verifier-instance",
      organization_id: @organization_id,
      mission_id: @mission_id,
      command_request_id: "shared-command-request",
      command_release_attempt_id: "shared-release-attempt",
      source_endpoint_ref: @lane_key,
      mission_model_revision_id: "shared-mission-model-revision",
      command_id: "shared-command",
      command_name: "Shared Command",
      verifier_id: "shared-verifier",
      verifier_name: "Shared Verifier",
      phase: :completion,
      timeout_at: ~U[2026-08-19 13:00:00Z],
      lifecycle_state: :pending
    })
  end

  defp namespace(:alpha) do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaDispatchSupervisor,
      registry: __MODULE__.AlphaDispatchRegistry,
      lane_supervisor: __MODULE__.AlphaLaneDispatcherSupervisor,
      dispatcher: __MODULE__.AlphaDispatcher,
      verifier_scheduler: __MODULE__.AlphaVerifierScheduler
    )
  end

  defp namespace(:bravo) do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoDispatchSupervisor,
      registry: __MODULE__.BravoDispatchRegistry,
      lane_supervisor: __MODULE__.BravoLaneDispatcherSupervisor,
      dispatcher: __MODULE__.BravoDispatcher,
      verifier_scheduler: __MODULE__.BravoVerifierScheduler
    )
  end
end
