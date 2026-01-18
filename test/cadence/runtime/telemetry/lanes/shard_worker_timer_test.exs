defmodule Cadence.Runtime.Telemetry.Lanes.ShardWorkerTimerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Telemetry.Lanes.{Event, ShardWorker}
  alias Cadence.Telemetry.{Packet, PipelineMetrics}
  alias Cadence.TestSupport.FakeLaneRouter

  setup_virtual_time()

  test "flushes buffered events after virtual time advances" do
    {mission_id, lanes, worker_pid} =
      start_worker(max_batch_size: 10, max_batch_delay_ms: 1_000)

    event = build_event(mission_id, lanes, "target-1")

    GenServer.cast(worker_pid, {:telemetry_event, event})

    Cadence.PureCase.assert_eventually(
      fn -> :sys.get_state(worker_pid).buffer_size == 1 end,
      timeout: 1000
    )

    :ok = Time.advance(1_000)

    Cadence.PureCase.assert_eventually(
      fn -> :sys.get_state(worker_pid).buffer_size == 0 end,
      timeout: 1000
    )
  end

  test "flushes immediately when max batch size is reached" do
    {mission_id, lanes, worker_pid} =
      start_worker(max_batch_size: 2, max_batch_delay_ms: 60_000)

    event1 = build_event(mission_id, lanes, "target-1")
    event2 = build_event(mission_id, lanes, "target-1")

    GenServer.cast(worker_pid, {:telemetry_event, event1})

    Cadence.PureCase.assert_eventually(
      fn -> :sys.get_state(worker_pid).buffer_size == 1 end,
      timeout: 1000
    )

    GenServer.cast(worker_pid, {:telemetry_event, event2})

    Cadence.PureCase.assert_eventually(
      fn ->
        state = :sys.get_state(worker_pid)
        state.buffer_size == 0 and is_nil(state.flush_timer)
      end,
      timeout: 1000
    )
  end

  defp start_worker(opts) do
    mission_id = random_id()
    router_pid = start_supervised!({FakeLaneRouter, queue_depths: %{}})

    lanes = [
      %{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}
    ]

    :ok = PipelineMetrics.init_lanes(mission_id, lanes)

    max_batch_size = Keyword.get(opts, :max_batch_size, 10)
    max_batch_delay_ms = Keyword.get(opts, :max_batch_delay_ms, 1_000)

    {:ok, worker_pid} =
      start_supervised(
        {ShardWorker,
         mission_id: mission_id,
         lane: :primary,
         shard_id: 0,
         router: router_pid,
         max_batch_size: max_batch_size,
         max_batch_delay_ms: max_batch_delay_ms,
         max_inflight: 100}
      )

    {mission_id, lanes, worker_pid}
  end

  defp build_event(mission_id, lanes, target_id) do
    packet = %Packet{raw: <<1>>, target_id: target_id}

    Event.new(packet, %{target_id: target_id}, %{
      mission_id: mission_id,
      lanes: lanes,
      router_version: 1,
      config_version: 0
    })
  end
end
