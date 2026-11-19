defmodule Cadence.Runtime.PartitionOwner.SemanticTimerSchedule do
  @moduledoc """
  When a semantic algorithm timer fires next, on its grid (anchor + k * interval).

  Live timers skip to now (director 11-15): a partition starting long after its activation, or
  after downtime, fires at most ONE late tick and then resumes on the grid. Before, a timer
  without a saved cursor anchored at `activated_at` and fired every missed tick back to back,
  (now - activated_at) / interval times. A replay clock (not live) keeps every tick, so replays
  stay deterministic.
  """

  @doc """
  The first due time: `anchor + interval` when that's still ahead; otherwise the latest grid tick
  at or before `now` (it fires at once, the one late tick).
  """
  @spec first_due(DateTime.t(), pos_integer(), DateTime.t(), boolean()) :: DateTime.t()
  def first_due(%DateTime{} = anchor, interval_ms, %DateTime{} = now, live?)
      when is_integer(interval_ms) and interval_ms > 0 do
    first = DateTime.add(anchor, interval_ms, :millisecond)

    if live? and DateTime.compare(first, now) != :gt do
      ticks = div(DateTime.diff(now, anchor, :millisecond), interval_ms)
      DateTime.add(anchor, ticks * interval_ms, :millisecond)
    else
      first
    end
  end

  @doc """
  The due time after a tick at `due_at`: the next grid tick, or, when that's already past (live),
  the first grid tick after `now`, so a late tick never starts a catch-up run.
  """
  @spec next_due(DateTime.t(), pos_integer(), DateTime.t(), boolean()) :: DateTime.t()
  def next_due(%DateTime{} = due_at, interval_ms, %DateTime{} = now, live?)
      when is_integer(interval_ms) and interval_ms > 0 do
    next = DateTime.add(due_at, interval_ms, :millisecond)

    if live? and DateTime.compare(next, now) != :gt do
      ticks = div(DateTime.diff(now, due_at, :millisecond), interval_ms) + 1
      DateTime.add(due_at, ticks * interval_ms, :millisecond)
    else
      next
    end
  end
end
