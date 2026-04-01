defmodule Cadence.Schedules.Workers.ExecuteScheduleWorker do
  @moduledoc """
  Oban worker that executes scheduled procedures.

  This worker is triggered by Oban's Cron plugin for recurring schedules
  or manually enqueued for one-time schedules.
  """

  use Oban.Worker,
    queue: :schedules,
    max_attempts: 3

  require Logger

  alias Cadence.Procedures
  alias Cadence.Schedules
  alias Cadence.Time, as: CadenceTime

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"schedule_id" => schedule_id}}) do
    case Schedules.get_schedule_unscoped(schedule_id) do
      nil ->
        Logger.warning("Schedule #{schedule_id} not found, skipping execution")
        :ok

      schedule ->
        execute_schedule(schedule)
    end
  end

  defp execute_schedule(schedule) do
    if schedule.enabled do
      start_scheduled_execution(schedule)
    else
      Logger.debug("Schedule #{schedule.id} is disabled, skipping")
      :ok
    end
  end

  defp start_scheduled_execution(schedule) do
    Logger.info("Executing scheduled procedure: #{schedule.name}")

    case Procedures.get_procedure(schedule.procedure_id) do
      nil ->
        Logger.warning("Procedure #{schedule.procedure_id} not found for schedule #{schedule.id}")
        {:error, :procedure_not_found}

      procedure ->
        case start_procedure_execution(schedule, procedure) do
          {:ok, execution} ->
            Logger.info("Started scheduled execution #{execution.id} for #{schedule.name}")
            finalize_schedule_run(schedule)
            :ok

          {:error, reason} ->
            Logger.error("Failed to start scheduled execution: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp finalize_schedule_run(schedule) do
    next_run = calculate_next_run(schedule)
    Schedules.record_run(schedule, next_run)

    if schedule.schedule_type == :once do
      Schedules.disable_schedule(schedule)
    end
  end

  defp start_procedure_execution(schedule, _procedure) do
    Procedures.start_execution(
      schedule.procedure_id,
      parameters: schedule.parameters || %{},
      target_id: schedule.target_id,
      triggered_by: :schedule,
      trigger_context: %{"schedule_id" => schedule.id}
    )
  end

  defp calculate_next_run(%{schedule_type: :once}), do: nil

  defp calculate_next_run(%{schedule_type: :cron, cron_expression: _cron}) do
    # Oban's cron plugin handles the actual scheduling.
    # For display purposes, we estimate next run as now + 1 minute minimum.
    # A proper implementation would use the crontab library for accurate calculation.
    CadenceTime.now() |> DateTime.add(60, :second)
  end

  defp calculate_next_run(_), do: nil
end
