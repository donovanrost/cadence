defmodule Cadence.Time.Real do
  @moduledoc false

  @behaviour Cadence.Time

  @impl Cadence.Time
  def now, do: DateTime.utc_now()

  @impl Cadence.Time
  def monotonic(unit), do: System.monotonic_time(unit)

  @impl Cadence.Time
  def system_time(unit), do: System.system_time(unit)
end
