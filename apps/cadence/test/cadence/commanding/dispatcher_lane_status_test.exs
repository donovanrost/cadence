defmodule Cadence.Commanding.DispatcherLaneStatusTest do
  @moduledoc "#38: reconcile_now reports each pending lane's last result and next timer."
  use Cadence.UnitCase, async: true

  alias Cadence.Commanding.{Dispatcher, DispatchSupervisor, LaneDispatcher, ProcessNamespace}

  @organization_id "status-organization"
  @mission_id "status-mission"
  @lane_key "spacecraft_runtime:status-sc"

  test "a manual reconcile names what each lane last saw and when it dispatches next" do
    namespace =
      ProcessNamespace.new!(
        root_supervisor: __MODULE__.DispatchSupervisor,
        registry: __MODULE__.DispatchRegistry,
        lane_supervisor: __MODULE__.LaneDispatcherSupervisor,
        dispatcher: __MODULE__.Dispatcher,
        verifier_scheduler: __MODULE__.VerifierScheduler
      )

    lane = %{
      organization_id: @organization_id,
      mission_id: @mission_id,
      queue_lane_key: @lane_key
    }

    start_supervised!(
      {DispatchSupervisor,
       process_namespace: namespace,
       auto_schedule?: false,
       run_on_boot?: false,
       lane_safety_poll_interval_ms: 60_000,
       dispatch_fun: fn _org, mission, _lane, _released_by, _opts ->
         {:error, {:command_queue_lane_no_release_target, "endpoint-010", mission}}
       end,
       lane_dispatcher_opts: [run_on_boot?: false],
       requeue_release_pending_fun: fn -> 0 end,
       list_pending_queue_lanes_fun: fn -> [lane] end}
    )

    # Started, not yet dispatched: nothing to report but the lane itself.
    assert {:ok, %{pending_lane_count: 1, lanes: [first]}} = Dispatcher.reconcile_now(namespace)
    assert %{queue_lane_key: @lane_key, last_result: nil, next_dispatch: nil} = first

    {:ok, pid} =
      DispatchSupervisor.lane_dispatcher(namespace, @organization_id, @mission_id, @lane_key)

    before = DateTime.utc_now()
    assert {:ok, %{status: :waiting_for_release_target}} = LaneDispatcher.drain(pid)

    assert {:ok, %{lanes: [status]}} = Dispatcher.reconcile_now(namespace)

    assert %{
             last_result: %{result: {:no_release_target, "endpoint-010"}, at: %DateTime{}},
             next_dispatch: %{reason: :safety, at: %DateTime{} = next_at},
             waiting: :no_release_target
           } = status

    assert DateTime.diff(next_at, before, :second) in 59..61
  end
end
