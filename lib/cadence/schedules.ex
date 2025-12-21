defmodule Cadence.Schedules do
  @moduledoc """
  The Schedules context.

  Manages scheduled procedure executions. Schedules can be:
  - Recurring via cron expressions
  - One-time at a specific datetime

  Schedules are registered with Oban's Cron plugin for automatic execution.
  """

  import Ecto.Query
  alias Cadence.Repo
  alias Cadence.Schedules.Schedule

  # ============================================================================
  # Schedules
  # ============================================================================

  @doc """
  Lists schedules for an organization, optionally filtered.
  """
  def list_schedules(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)

    Schedule
    |> where([s], s.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> maybe_filter_by_procedure(procedure_id)
    |> maybe_filter_enabled(enabled_only)
    |> order_by([s], asc: s.name)
    |> Repo.all()
    |> Repo.preload(:procedure)
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [s], s.mission_id == ^mission_id or is_nil(s.mission_id))
  end

  defp maybe_filter_by_procedure(query, nil), do: query

  defp maybe_filter_by_procedure(query, procedure_id) do
    where(query, [s], s.procedure_id == ^procedure_id)
  end

  defp maybe_filter_enabled(query, false), do: query
  defp maybe_filter_enabled(query, true), do: where(query, [s], s.enabled == true)

  @doc """
  Gets a single schedule.
  """
  def get_schedule(id), do: Repo.get(Schedule, id)

  @doc """
  Gets a single schedule, raises if not found.
  """
  def get_schedule!(id) do
    Schedule
    |> Repo.get!(id)
    |> Repo.preload(:procedure)
  end

  @doc """
  Creates a schedule.
  """
  def create_schedule(attrs) do
    result =
      %Schedule{}
      |> Schedule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, schedule} ->
        schedule = Repo.preload(schedule, :procedure)
        {:ok, schedule}

      error ->
        error
    end
  end

  @doc """
  Updates a schedule.
  """
  def update_schedule(%Schedule{} = schedule, attrs) do
    result =
      schedule
      |> Schedule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, schedule} ->
        schedule = Repo.preload(schedule, :procedure)
        {:ok, schedule}

      error ->
        error
    end
  end

  @doc """
  Deletes a schedule.
  """
  def delete_schedule(%Schedule{} = schedule) do
    Repo.delete(schedule)
  end

  @doc """
  Enables a schedule.
  """
  def enable_schedule(%Schedule{} = schedule) do
    update_schedule(schedule, %{enabled: true})
  end

  @doc """
  Disables a schedule.
  """
  def disable_schedule(%Schedule{} = schedule) do
    update_schedule(schedule, %{enabled: false})
  end

  @doc """
  Records that a schedule was executed.
  """
  def record_run(%Schedule{} = schedule, next_run_at \\ nil) do
    schedule
    |> Schedule.run_changeset(%{
      last_run_at: DateTime.utc_now(),
      next_run_at: next_run_at,
      run_count: (schedule.run_count || 0) + 1
    })
    |> Repo.update()
  end

  # ============================================================================
  # Cron Registration
  # ============================================================================

  @doc """
  Gets all enabled cron schedules for registration with Oban.

  Returns a list of tuples: {cron_expression, worker_module, args}
  """
  def get_cron_jobs do
    Schedule
    |> where([s], s.enabled == true)
    |> where([s], s.schedule_type == :cron)
    |> where([s], not is_nil(s.cron_expression))
    |> Repo.all()
    |> Enum.map(&schedule_to_cron_job/1)
  end

  defp schedule_to_cron_job(%Schedule{} = schedule) do
    {schedule.cron_expression,
     {Cadence.Schedules.Workers.ExecuteScheduleWorker,
      [schedule_id: schedule.id, name: "schedule:#{schedule.id}"]}}
  end

  @doc """
  Gets one-time schedules that are due for execution.
  """
  def get_due_once_schedules do
    now = DateTime.utc_now()

    Schedule
    |> where([s], s.enabled == true)
    |> where([s], s.schedule_type == :once)
    |> where([s], s.scheduled_at <= ^now)
    |> where([s], is_nil(s.last_run_at))
    |> Repo.all()
    |> Repo.preload(:procedure)
  end

  @doc """
  Enqueues a one-time schedule for immediate execution.
  """
  def enqueue_schedule(%Schedule{} = schedule) do
    %{schedule_id: schedule.id}
    |> Cadence.Schedules.Workers.ExecuteScheduleWorker.new()
    |> Oban.insert()
  end
end
