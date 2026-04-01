defmodule Cadence.Time.Timer.Real do
  @moduledoc false

  @behaviour Cadence.Time.Timer

  @impl Cadence.Time.Timer
  def send_after(pid, msg, timeout_ms), do: Process.send_after(pid, msg, timeout_ms)

  @impl Cadence.Time.Timer
  def send_interval(timeout_ms, pid, msg), do: :timer.send_interval(timeout_ms, pid, msg)

  @impl Cadence.Time.Timer
  def cancel(ref), do: Process.cancel_timer(ref)
end
