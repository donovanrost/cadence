defmodule Cadence.Runtime.Telemetry.Lanes.AutoscalerTimerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Telemetry.Lanes.Autoscaler
  alias Cadence.TestSupport.FakeLaneRouter

  setup_virtual_time()
  setup_mission_registry()

  test "ticks on virtual time interval and updates inflight" do
    mission_id = random_id()
    router_pid = start_supervised!({FakeLaneRouter, queue_depths: %{"primary" => 90}})

    lanes = [
      %{name: "primary", max_queue_depth: 100, max_inflight: 1_000}
    ]

    {:ok, _pid} =
      start_supervised(
        {Autoscaler,
         mission_id: mission_id,
         router: router_pid,
         lanes: lanes,
         interval_ms: 1_000,
         scale_step: 100,
         min_inflight: 500,
         max_inflight: 2_000,
         scale_up_threshold: 0.7,
         scale_down_threshold: 0.3}
      )

    assert FakeLaneRouter.updates(router_pid) == []

    :ok = Time.advance(1_000)

    Cadence.PureCase.assert_eventually(
      fn -> FakeLaneRouter.updates(router_pid) == [{"primary", 1_100}] end,
      timeout: 1000
    )
  end
end
