defmodule Cadence.Time.Timer.Virtual do
  @moduledoc false

  @behaviour Cadence.Time.Timer

  alias Cadence.Harness.Time

  @impl Cadence.Time.Timer
  def send_after(pid, msg, timeout_ms), do: Time.send_after(pid, msg, timeout_ms)

  @impl Cadence.Time.Timer
  def send_interval(timeout_ms, pid, msg), do: Time.send_interval(timeout_ms, pid, msg)

  @impl Cadence.Time.Timer
  def cancel(ref), do: Time.cancel_timer(ref)
end
