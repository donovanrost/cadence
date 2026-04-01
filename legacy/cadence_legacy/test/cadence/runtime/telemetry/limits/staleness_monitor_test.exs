defmodule Cadence.Runtime.Telemetry.Limits.StalenessMonitorTest do
  use Cadence.PureCase, async: false

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.{StalenessMonitor, StateTracker}

  setup_virtual_time(start_time: ~U[2024-01-01 00:00:00Z])
  setup_mission_registry()
  setup_limits_cache()

  test "marks stale items using virtual time" do
    mission_id = random_id()
    target_id = "SAT-1"
    packet_name = "HEALTH"
    item_name = "cpu_temp"
    qualified_item_name = "#{packet_name}.#{item_name}"

    start_supervised!({StateTracker, mission_id: mission_id})
    start_supervised!({CurrentValueTable, mission_id: mission_id})
    start_supervised!({StalenessMonitor, mission_id: mission_id, check_interval_ms: 60_000})

    :ets.insert(
      :limits_cache,
      {{mission_id, target_id}, %{}, "NOMINAL", Cadence.Time.monotonic(:millisecond)}
    )

    now_mono = Cadence.Time.monotonic(:millisecond)

    :ets.insert(
      String.to_atom("limits_state_#{mission_id}"),
      {{target_id, qualified_item_name},
       %{
         current_state: :green,
         pending_state: nil,
         violation_count: 0,
         persistence: 1,
         stale_timeout_ms: 1_000,
         last_update_mono: now_mono
       }}
    )

    CurrentValueTable.set(mission_id, target_id, packet_name, item_name, 42,
      limits_state: :green,
      received_time: Cadence.Time.now()
    )

    :ok = Time.advance(2_000)

    assert {:ok, 1} = StalenessMonitor.check_staleness(mission_id)
    assert {:ok, entry} = StateTracker.get_state(mission_id, target_id, qualified_item_name)
    assert entry.current_state == :blue

    assert {:ok, value} = CurrentValueTable.get(mission_id, target_id, packet_name, item_name)
    assert value.limits_state == :blue
  end
end
