defmodule Cadence.Schedules.Workers.CheckDueSchedulesWorker do
  @moduledoc """
  Oban worker that checks for and enqueues due one-time schedules.

  This runs periodically to find one-time schedules whose scheduled_at
  time has passed and enqueues them for execution.
  """

  use Oban.Worker,
    queue: :schedules,
    max_attempts: 1

  require Logger

  alias Cadence.Schedules

  @impl Oban.Worker
  def perform(_job) do
    due_schedules = Schedules.get_due_once_schedules()

    Logger.debug("Found #{length(due_schedules)} due one-time schedules")

    Enum.each(due_schedules, fn schedule ->
      case Schedules.enqueue_schedule(schedule) do
        {:ok, _job} ->
          Logger.info("Enqueued one-time schedule: #{schedule.name}")

        {:error, reason} ->
          Logger.error("Failed to enqueue schedule #{schedule.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
