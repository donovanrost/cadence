defmodule Cadence.Time.Timer do
  @moduledoc false

  @callback send_after(pid(), term(), non_neg_integer()) :: reference()
  @callback send_interval(non_neg_integer(), pid(), term()) :: reference()
  @callback cancel(reference()) :: non_neg_integer() | false

  @spec send_after(pid(), term(), non_neg_integer()) :: reference()
  def send_after(pid, msg, timeout_ms), do: impl().send_after(pid, msg, timeout_ms)

  @spec send_interval(non_neg_integer(), pid(), term()) :: reference()
  def send_interval(timeout_ms, pid, msg), do: impl().send_interval(timeout_ms, pid, msg)

  @spec cancel(reference()) :: non_neg_integer() | false
  def cancel(ref), do: impl().cancel(ref)

  defp impl do
    Application.fetch_env!(:cadence, __MODULE__)[:impl]
  end
end
