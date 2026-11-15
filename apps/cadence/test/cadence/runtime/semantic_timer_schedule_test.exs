defmodule Cadence.Runtime.PartitionOwner.SemanticTimerScheduleTest do
  @moduledoc "Live semantic timers skip to now: at most one late tick, then the grid (director 11-15)."
  use ExUnit.Case, async: true

  alias Cadence.Runtime.PartitionOwner.SemanticTimerSchedule

  @interval_ms 60_000
  @activated_at ~U[2026-11-14 12:00:00.000000Z]

  test "a partition starting a day after activation fires once, not once per missed minute" do
    now = DateTime.add(@activated_at, 24 * 3_600 + 30, :second)

    assert fires(@activated_at, now) == 1

    # Before the fix: every tick since activation, back to back.
    assert div(DateTime.diff(now, @activated_at, :millisecond), @interval_ms) == 1_440
  end

  test "the late tick is the latest grid tick, and the next one is back on the grid" do
    now = DateTime.add(@activated_at, 3_600 + 30, :second)
    late = SemanticTimerSchedule.first_due(@activated_at, @interval_ms, now, true)

    assert late == DateTime.add(@activated_at, 3_600, :second)

    assert SemanticTimerSchedule.next_due(late, @interval_ms, now, true) ==
             DateTime.add(@activated_at, 3_660, :second)
  end

  test "a timer that isn't late keeps its first tick" do
    now = DateTime.add(@activated_at, 10, :second)

    assert SemanticTimerSchedule.first_due(@activated_at, @interval_ms, now, true) ==
             DateTime.add(@activated_at, 60, :second)
  end

  test "a tick that ran late resumes at the next grid tick after now" do
    due = DateTime.add(@activated_at, 60, :second)
    now = DateTime.add(@activated_at, 300 + 5, :second)

    assert SemanticTimerSchedule.next_due(due, @interval_ms, now, true) ==
             DateTime.add(@activated_at, 360, :second)
  end

  test "a replay clock (not live) keeps every tick" do
    now = DateTime.add(@activated_at, 3_600, :second)

    assert SemanticTimerSchedule.first_due(@activated_at, @interval_ms, now, false) ==
             DateTime.add(@activated_at, 60, :second)

    assert SemanticTimerSchedule.next_due(
             DateTime.add(@activated_at, 60, :second),
             @interval_ms,
             now,
             false
           ) == DateTime.add(@activated_at, 120, :second)
  end

  # How many ticks fire at `now` (a due time at or before now fires at once, as the owner's
  # send_after with a delay clamped to 0 does).
  defp fires(anchor, now) do
    anchor
    |> SemanticTimerSchedule.first_due(@interval_ms, now, true)
    |> Stream.iterate(&SemanticTimerSchedule.next_due(&1, @interval_ms, now, true))
    |> Enum.take_while(&(DateTime.compare(&1, now) != :gt))
    |> length()
  end
end
