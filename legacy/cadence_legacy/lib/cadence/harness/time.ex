defmodule Cadence.Harness.Time do
  @moduledoc false

  alias Cadence.Harness.Time.{Authority, Client}

  @spec start_authority(keyword()) :: GenServer.on_start()
  def start_authority(opts \\ []) do
    Authority.start_link(opts)
  end

  @spec now() :: DateTime.t()
  def now, do: Client.now()

  @spec monotonic(System.time_unit()) :: integer()
  def monotonic(unit \\ :millisecond), do: Client.monotonic(unit)

  @spec system_time(System.time_unit()) :: integer()
  def system_time(unit \\ :millisecond), do: Client.system_time(unit)

  @spec advance(non_neg_integer()) :: :ok | {:error, term()}
  def advance(ms), do: Client.advance(ms)

  @spec set(DateTime.t() | integer()) :: :ok | {:error, term()}
  def set(time), do: Client.set(time)

  @spec pause() :: :ok
  def pause, do: Client.pause()

  @spec resume() :: :ok
  def resume, do: Client.resume()

  @spec send_after(pid(), term(), non_neg_integer()) :: reference()
  def send_after(pid, msg, timeout_ms), do: Client.send_after(pid, msg, timeout_ms)

  @spec send_interval(non_neg_integer(), pid(), term()) :: reference()
  def send_interval(timeout_ms, pid, msg), do: Client.send_interval(timeout_ms, pid, msg)

  @spec cancel_timer(reference()) :: non_neg_integer() | false
  def cancel_timer(ref), do: Client.cancel_timer(ref)
end
