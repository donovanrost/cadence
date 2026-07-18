defmodule Cadence.Runtime.TransportRuntimeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Runtime.{PartitionKey, TransportRuntime}

  test "runs a live transport extension and keeps its heartbeat timer armed" do
    path_ref = "path-live-alpha"

    transport_runtime =
      start_supervised!(
        {TransportRuntime,
         mission_id: "mission-live",
         activation_id: "activation-live",
         binding_set_id: "binding-set-live",
         binding_set_version: 1,
         capability_instance_id: "heartbeat-live-instance",
         family_key: :heartbeat_monitor,
         configuration: %{"heartbeat_interval_ms" => 25},
         scope_ref: path_ref,
         partition_key: PartitionKey.new(%{affinity: :path, value: path_ref})}
      )

    assert {:ok, initial_snapshot} = TransportRuntime.snapshot(transport_runtime)
    assert initial_snapshot.family_key == :heartbeat_monitor
    assert initial_snapshot.state.heartbeat_count == 0
    assert initial_snapshot.state.active?
    assert initial_snapshot.timer_count == 1

    assert {:ok, heartbeat_snapshot} =
             await_snapshot(transport_runtime, fn snapshot ->
               snapshot.state.heartbeat_count >= 1 and snapshot.timer_count == 1
             end)

    assert heartbeat_snapshot.clock_mode == :live
    assert heartbeat_snapshot.state.last_transport_event_at == nil
  end

  test "replay transport runtime advances logical time deterministically" do
    path_ref = "path-replay-alpha"
    start_time = DateTime.from_unix!(1_700_020_000, :second)

    transport_runtime =
      start_supervised!(
        {TransportRuntime,
         mission_id: "mission-replay",
         activation_id: "activation-replay",
         binding_set_id: "binding-set-replay",
         binding_set_version: 1,
         capability_instance_id: "heartbeat-replay-instance",
         family_key: :heartbeat_monitor,
         configuration: %{"heartbeat_interval_ms" => 25},
         scope_ref: path_ref,
         partition_key: PartitionKey.new(%{affinity: :path, value: path_ref}),
         clock_mode: :replay,
         initial_time: start_time}
      )

    assert {:ok, initial_snapshot} = TransportRuntime.snapshot(transport_runtime)
    assert initial_snapshot.clock_mode == :replay
    assert DateTime.compare(initial_snapshot.current_time, start_time) == :eq
    assert initial_snapshot.state.heartbeat_count == 0
    assert initial_snapshot.timer_count == 1

    [initial_timer] = initial_snapshot.timers

    assert DateTime.compare(initial_timer.due_at, DateTime.add(start_time, 25, :millisecond)) ==
             :eq

    assert :ok =
             TransportRuntime.advance_time(
               transport_runtime,
               DateTime.add(start_time, 60, :millisecond)
             )

    assert {:ok, advanced_snapshot} = TransportRuntime.snapshot(transport_runtime)

    assert DateTime.compare(
             advanced_snapshot.current_time,
             DateTime.add(start_time, 60, :millisecond)
           ) == :eq

    assert advanced_snapshot.state.heartbeat_count == 2
    assert advanced_snapshot.timer_count == 1

    [rescheduled_timer] = advanced_snapshot.timers

    assert DateTime.compare(rescheduled_timer.due_at, DateTime.add(start_time, 75, :millisecond)) ==
             :eq

    assert {:ok, []} =
             TransportRuntime.handle_transport_event(
               transport_runtime,
               %{kind: :frame_received},
               occurred_at: DateTime.add(start_time, 60, :millisecond)
             )

    assert {:ok, event_snapshot} = TransportRuntime.snapshot(transport_runtime)
    assert event_snapshot.state.last_transport_event_kind == :frame_received

    assert DateTime.compare(
             event_snapshot.state.last_transport_event_at,
             DateTime.add(start_time, 60, :millisecond)
           ) == :eq

    assert {:ok, []} =
             TransportRuntime.handle_control_input(
               transport_runtime,
               %{command: :pause},
               occurred_at: DateTime.add(start_time, 70, :millisecond)
             )

    assert {:ok, paused_snapshot} = TransportRuntime.snapshot(transport_runtime)
    assert paused_snapshot.state.last_control_command == :pause
    refute paused_snapshot.state.active?
    assert paused_snapshot.timer_count == 0

    assert DateTime.compare(
             paused_snapshot.current_time,
             DateTime.add(start_time, 70, :millisecond)
           ) == :eq

    assert {:ok, []} =
             TransportRuntime.handle_control_input(
               transport_runtime,
               %{command: :resume},
               occurred_at: DateTime.add(start_time, 80, :millisecond)
             )

    assert {:ok, resumed_snapshot} = TransportRuntime.snapshot(transport_runtime)
    assert resumed_snapshot.state.last_control_command == :resume
    assert resumed_snapshot.state.active?
    assert resumed_snapshot.timer_count == 1

    [resumed_timer] = resumed_snapshot.timers

    assert DateTime.compare(resumed_timer.due_at, DateTime.add(start_time, 105, :millisecond)) ==
             :eq

    assert :ok =
             TransportRuntime.advance_time(
               transport_runtime,
               DateTime.add(start_time, 200, :millisecond)
             )

    assert {:ok, final_snapshot} = TransportRuntime.snapshot(transport_runtime)

    assert DateTime.compare(
             final_snapshot.current_time,
             DateTime.add(start_time, 200, :millisecond)
           ) == :eq

    assert final_snapshot.state.heartbeat_count == 6
    assert final_snapshot.timer_count == 1

    [next_timer] = final_snapshot.timers
    assert DateTime.compare(next_timer.due_at, DateTime.add(start_time, 205, :millisecond)) == :eq
  end

  defp await_snapshot(transport_runtime, predicate, attempts \\ 20)

  defp await_snapshot(_transport_runtime, _predicate, 0), do: {:error, :snapshot_timeout}

  defp await_snapshot(transport_runtime, predicate, attempts) do
    case TransportRuntime.snapshot(transport_runtime) do
      {:ok, snapshot} ->
        if predicate.(snapshot) do
          {:ok, snapshot}
        else
          Process.sleep(10)
          await_snapshot(transport_runtime, predicate, attempts - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
