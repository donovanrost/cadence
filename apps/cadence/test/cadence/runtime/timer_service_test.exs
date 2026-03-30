defmodule Cadence.Runtime.TimerServiceTest do
  use ExUnit.Case, async: true

  alias Cadence.ActionRequests.{CancelTimer, ScheduleTimer}
  alias Cadence.Runtime.TimerService

  test "replaces an existing timer entry and rejects stale timer firings" do
    assert {:ok, timer_service, first_timer} =
             TimerService.schedule(
               TimerService.new(),
               "capability-instance",
               ScheduleTimer.new(%{timer_key: "flush", delay_ms: 10_000})
             )

    assert {:ok, timer_service, second_timer} =
             TimerService.schedule(
               timer_service,
               "capability-instance",
               ScheduleTimer.new(%{timer_key: "flush", delay_ms: 10_000})
             )

    assert first_timer.timer_id != second_timer.timer_id
    assert TimerService.count(timer_service) == 1

    assert {:error, :stale_timer} =
             TimerService.fire(
               timer_service,
               "capability-instance",
               "flush",
               first_timer.timer_id
             )

    assert {:ok, timer_service, fired_timer} =
             TimerService.fire(
               timer_service,
               "capability-instance",
               "flush",
               second_timer.timer_id
             )

    assert fired_timer.timer_id == second_timer.timer_id
    assert TimerService.count(timer_service) == 0
  end

  test "cancels all timers owned by one capability instance" do
    assert {:ok, timer_service, _timer_a} =
             TimerService.schedule(
               TimerService.new(),
               "capability-a",
               ScheduleTimer.new(%{timer_key: "flush", delay_ms: 10_000})
             )

    assert {:ok, timer_service, _timer_b} =
             TimerService.schedule(
               timer_service,
               "capability-b",
               ScheduleTimer.new(%{timer_key: "flush", delay_ms: 10_000})
             )

    assert TimerService.count(timer_service) == 2

    timer_service = TimerService.cancel_capability_instance(timer_service, "capability-a")

    assert TimerService.count(timer_service) == 1

    assert {:ok, timer_service} =
             TimerService.cancel(
               timer_service,
               "capability-b",
               CancelTimer.new(%{timer_key: "flush"})
             )

    assert TimerService.count(timer_service) == 0
  end

  test "uses logical replay time for replay-mode timer scheduling" do
    current_time = DateTime.from_unix!(1_700_010_000, :second)

    assert {:ok, timer_service, timer_entry} =
             TimerService.schedule(
               TimerService.new(mode: :replay, current_time: current_time),
               "capability-instance",
               ScheduleTimer.new(%{timer_key: "flush", delay_ms: 25})
             )

    assert timer_entry.timer_ref == nil
    assert timer_entry.due_at == DateTime.add(current_time, 25, :millisecond)

    timer_service = TimerService.advance_to(timer_service, timer_entry.due_at)

    assert TimerService.current_time(timer_service) == timer_entry.due_at

    assert {:ok, timer_service, fired_timer} =
             TimerService.fire(
               timer_service,
               "capability-instance",
               "flush",
               timer_entry.timer_id
             )

    assert fired_timer.timer_id == timer_entry.timer_id
    assert TimerService.count(timer_service) == 0
  end
end
