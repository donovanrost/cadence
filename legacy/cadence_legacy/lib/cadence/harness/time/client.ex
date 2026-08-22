defmodule Cadence.Harness.Time.Client do
  @moduledoc false

  @spec authority_name() :: GenServer.name()
  def authority_name do
    Application.get_env(:cadence, Cadence.Harness.Time, [])
    |> Keyword.get(:authority_name, {:global, Cadence.Harness.Time.Authority})
  end

  @spec now() :: DateTime.t()
  def now, do: call(:now)

  @spec monotonic(System.time_unit()) :: integer()
  def monotonic(unit \\ :millisecond), do: call({:monotonic, unit})

  @spec system_time(System.time_unit()) :: integer()
  def system_time(unit \\ :millisecond), do: call({:system_time, unit})

  @spec advance(non_neg_integer()) :: :ok | {:error, term()}
  def advance(ms), do: call({:advance, ms})

  @spec set(DateTime.t() | integer()) :: :ok | {:error, term()}
  def set(time), do: call({:set, time})

  @spec pause() :: :ok
  def pause, do: call(:pause)

  @spec resume() :: :ok
  def resume, do: call(:resume)

  @spec send_after(pid(), term(), non_neg_integer()) :: reference()
  def send_after(pid, msg, timeout_ms), do: call({:send_after, pid, msg, timeout_ms})

  @spec send_interval(non_neg_integer(), pid(), term()) :: reference()
  def send_interval(timeout_ms, pid, msg), do: call({:send_interval, timeout_ms, pid, msg})

  @spec cancel_timer(reference()) :: non_neg_integer() | false
  def cancel_timer(ref), do: call({:cancel, ref})

  defp call(message) do
    name = authority_name()

    case GenServer.whereis(name) do
      nil -> raise "Cadence time authority not running: #{inspect(name)}"
      _pid -> GenServer.call(name, message)
    end
  end
end
