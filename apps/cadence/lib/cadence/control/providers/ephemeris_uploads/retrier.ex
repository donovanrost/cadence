defmodule Cadence.Control.Providers.EphemerisUploads.Retrier do
  @moduledoc """
  Retries failed ephemeris uploads (#968): every minute it stages a run for the spacecraft whose
  failed upload is due (`Cadence.Control.Providers.EphemerisUploads.retry_due/1`). The first sweep is
  scheduled, never run from `init/1`, and a sweep that fails (a database outage, say) is logged
  and tried again at the next interval, so the process stays up.
  """

  use GenServer

  require Logger

  alias Cadence.Control.Providers.EphemerisUploads

  @default_interval_ms :timer.minutes(1)
  @default_first_check_ms :timer.seconds(30)

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      sweep: Keyword.get(opts, :sweep, fn -> EphemerisUploads.retry_due() end)
    }

    Process.send_after(
      self(),
      :sweep,
      Keyword.get(opts, :first_check_ms, @default_first_check_ms)
    )

    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(state.sweep)
    Process.send_after(self(), :sweep, state.interval_ms)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp sweep(fun) do
    fun.()
  rescue
    error -> warn(Exception.message(error), inspect(error.__struct__))
  catch
    :exit, reason -> warn("exited: #{inspect(reason)}", "exit")
  end

  defp warn(detail, error_class) do
    Logger.warning("Ephemeris upload retry sweep failed, retrying: " <> detail,
      cadence_event: "ephemeris_upload.retry_sweep_failed",
      error_class: error_class
    )
  end
end
