defmodule Cadence.Time.Virtual do
  @moduledoc false

  @behaviour Cadence.Time

  alias Cadence.Harness.Time

  @impl Cadence.Time
  def now, do: Time.now()

  @impl Cadence.Time
  def monotonic(unit), do: Time.monotonic(unit)

  @impl Cadence.Time
  def system_time(unit), do: Time.system_time(unit)
end
