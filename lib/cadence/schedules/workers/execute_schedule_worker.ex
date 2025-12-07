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

  alias Cadence.Schedules
  alias Cadence.Procedures
  alias Cadence.Procedures.Engine.ExecutionCoordinator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"schedule_id" => schedule_id}}) do
    case Schedules.get_schedule(schedule_id) do
      nil ->
        Logger.warning("Schedule #{schedule_id} not found, skipping execution")
        :ok

      schedule ->
        execute_schedule(schedule)
    end
  end

  defp execute_schedule(schedule) do
    if schedule.enabled do
      Logger.info("Executing scheduled procedure: #{schedule.name}")

      procedure = Procedures.get_procedure(schedule.procedure_id)

      if procedure do
        case start_procedure_execution(schedule, procedure) do
          {:ok, execution} ->
            Logger.info("Started scheduled execution #{execution.id} for #{schedule.name}")

            # Update schedule tracking
            next_run = calculate_next_run(schedule)
            Schedules.record_run(schedule, next_run)

            # Disable one-time schedules after execution
            if schedule.schedule_type == :once do
              Schedules.disable_schedule(schedule)
            end

            :ok

          {:error, reason} ->
            Logger.error("Failed to start scheduled execution: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Logger.warning("Procedure #{schedule.procedure_id} not found for schedule #{schedule.id}")
        {:error, :procedure_not_found}
      end
    else
      Logger.debug("Schedule #{schedule.id} is disabled, skipping")
      :ok
    end
  end

  defp start_procedure_execution(schedule, procedure) do
    # Get the mission_id from either the schedule or procedure
    mission_id = schedule.mission_id || procedure.mission_id

    if mission_id do
      ExecutionCoordinator.start_execution(
        mission_id,
        schedule.procedure_id,
        parameters: schedule.parameters || %{},
        target_id: schedule.target_id,
        triggered_by: :schedule,
        trigger_event_id: schedule.id
      )
    else
      Logger.error("No mission_id available for schedule #{schedule.id}")
      {:error, :no_mission_id}
    end
  end

  defp calculate_next_run(%{schedule_type: :once}), do: nil

  defp calculate_next_run(%{schedule_type: :cron, cron_expression: cron}) when is_binary(cron) do
    case Oban.Plugins.Cron.parse(cron) do
      {:ok, crontab} ->
        now = DateTime.utc_now()
        # Calculate next occurrence using next_at/2
        Oban.Plugins.Cron.next_at(crontab, now)

      {:error, _} ->
        nil
    end
  end

  defp calculate_next_run(_), do: nil
end
