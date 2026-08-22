defmodule Cadence.Time do
  @moduledoc false

  @callback now() :: DateTime.t()
  @callback monotonic(System.time_unit()) :: integer()
  @callback system_time(System.time_unit()) :: integer()

  @spec now() :: DateTime.t()
  def now, do: impl().now()

  @spec monotonic(System.time_unit()) :: integer()
  def monotonic(unit \\ :millisecond), do: impl().monotonic(unit)

  @spec system_time(System.time_unit()) :: integer()
  def system_time(unit \\ :millisecond), do: impl().system_time(unit)

  defp impl do
    Application.fetch_env!(:cadence, __MODULE__)[:impl]
  end
end
