defmodule Cadence.TestSupport.VirtualTime do
  @moduledoc false

  alias Cadence.Harness.Time.Authority

  @spec setup(keyword()) :: %{
          cleanup: (-> any()),
          authority_name: term(),
          start_time: DateTime.t()
        }
  def setup(opts \\ []) do
    previous = %{
      time: Application.get_env(:cadence, Cadence.Time),
      timer: Application.get_env(:cadence, Cadence.Time.Timer),
      harness: Application.get_env(:cadence, Cadence.Harness.Time)
    }

    authority_name = Keyword.get(opts, :authority_name, default_authority_name())
    start_time = Keyword.get(opts, :start_time, ~U[2024-01-01 00:00:00Z])

    Application.put_env(:cadence, Cadence.Time, impl: Cadence.Time.Virtual)
    Application.put_env(:cadence, Cadence.Time.Timer, impl: Cadence.Time.Timer.Virtual)
    Application.put_env(:cadence, Cadence.Harness.Time, authority_name: authority_name)

    {pid, started?} = start_authority(authority_name, start_time)

    cleanup = fn ->
      if started? and is_pid(pid) and Process.alive?(pid) do
        GenServer.stop(pid)
      end

      restore_env(Cadence.Time, previous.time)
      restore_env(Cadence.Time.Timer, previous.timer)
      restore_env(Cadence.Harness.Time, previous.harness)
    end

    %{authority_name: authority_name, start_time: start_time, cleanup: cleanup}
  end

  defp default_authority_name do
    {:global, {Authority, System.unique_integer([:positive])}}
  end

  defp start_authority(authority_name, start_time) do
    case Authority.start_link(name: authority_name, start_time: start_time) do
      {:ok, pid} -> {pid, true}
      {:error, {:already_started, pid}} -> {pid, false}
      {:error, reason} -> raise "Failed to start time authority: #{inspect(reason)}"
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cadence, key)
  defp restore_env(key, value), do: Application.put_env(:cadence, key, value)
end
