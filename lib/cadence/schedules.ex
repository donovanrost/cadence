defmodule Cadence.Schedules do
  @moduledoc """
  The Schedules context.

  Manages scheduled procedure executions. Schedules can be:
  - Recurring via cron expressions
  - One-time at a specific datetime

  Schedules are registered with Oban's Cron plugin for automatic execution.

  This module serves as the public API facade, delegating to:
  - `Cadence.Application.Schedules.ScheduleQueries` for read operations
  - `Cadence.Application.Schedules.ScheduleOperations` for write operations
  """

  alias Cadence.Application.Schedules.ScheduleOperations
  alias Cadence.Application.Schedules.ScheduleQueries
  alias Cadence.Domain.Schedules.Entities.Schedule

  # ============================================================================
  # Schedule Queries
  # ============================================================================

  @doc """
  Lists schedules for an organization, optionally filtered.

  ## Options

  - `:mission_id` - Filter by mission
  - `:procedure_id` - Filter by procedure
  - `:enabled_only` - Only return enabled schedules
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @spec list_schedules(String.t(), keyword()) :: [Schedule.t()]
  def list_schedules(organization_id, opts \\ []) do
    ScheduleQueries.list(organization_id, opts)
  end

  @doc """
  Gets a single schedule scoped to an organization.

  Returns `nil` if not found or if the schedule doesn't belong to the organization.
  """
  @spec get_schedule(String.t(), String.t()) :: Schedule.t() | nil
  def get_schedule(id, organization_id) do
    case ScheduleQueries.find(id, organization_id) do
      {:ok, schedule} -> schedule
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a single schedule by ID without organization scoping.

  WARNING: Only use for internal operations where organization context is verified elsewhere.
  """
  @spec get_schedule_unscoped(String.t()) :: Schedule.t() | nil
  def get_schedule_unscoped(id) do
    case ScheduleQueries.find_unscoped(id) do
      {:ok, schedule} -> schedule
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a single schedule, raises if not found.
  """
  @spec get_schedule!(String.t(), String.t()) :: Schedule.t()
  def get_schedule!(id, organization_id) do
    ScheduleQueries.find!(id, organization_id)
  end

  # ============================================================================
  # Schedule Operations
  # ============================================================================

  @doc """
  Creates a schedule.
  """
  @spec create_schedule(map()) :: {:ok, Schedule.t()} | {:error, term()}
  def create_schedule(attrs) do
    ScheduleOperations.create(attrs)
  end

  @doc """
  Updates a schedule.
  """
  @spec update_schedule(Schedule.t(), map()) :: {:ok, Schedule.t()} | {:error, term()}
  def update_schedule(%Schedule{} = schedule, attrs) do
    ScheduleOperations.update(schedule, attrs)
  end

  @doc """
  Deletes a schedule.
  """
  @spec delete_schedule(Schedule.t()) :: {:ok, Schedule.t()} | {:error, term()}
  def delete_schedule(%Schedule{} = schedule) do
    ScheduleOperations.delete(schedule)
  end

  @doc """
  Enables a schedule.
  """
  @spec enable_schedule(Schedule.t()) :: {:ok, Schedule.t()} | {:error, term()}
  def enable_schedule(%Schedule{} = schedule) do
    ScheduleOperations.enable(schedule)
  end

  @doc """
  Disables a schedule.
  """
  @spec disable_schedule(Schedule.t()) :: {:ok, Schedule.t()} | {:error, term()}
  def disable_schedule(%Schedule{} = schedule) do
    ScheduleOperations.disable(schedule)
  end

  @doc """
  Records that a schedule was executed.
  """
  @spec record_run(Schedule.t(), DateTime.t() | nil) :: {:ok, Schedule.t()} | {:error, term()}
  def record_run(%Schedule{} = schedule, next_run_at \\ nil) do
    ScheduleOperations.record_run(schedule, next_run_at)
  end

  # ============================================================================
  # Cron Registration
  # ============================================================================

  @doc """
  Gets all enabled cron schedules for registration with Oban.

  Returns a list of tuples: {cron_expression, {worker_module, args}}
  """
  @spec get_cron_jobs() :: [{String.t(), {module(), keyword()}}]
  def get_cron_jobs do
    ScheduleQueries.list_cron_jobs()
  end

  @doc """
  Gets one-time schedules that are due for execution.
  """
  @spec get_due_once_schedules() :: [Schedule.t()]
  def get_due_once_schedules do
    ScheduleQueries.list_due_once()
  end

  @doc """
  Enqueues a schedule for immediate execution.
  """
  @spec enqueue_schedule(Schedule.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_schedule(%Schedule{} = schedule) do
    ScheduleOperations.enqueue(schedule)
  end

  @doc """
  Enqueues all due one-time schedules for execution.

  Called periodically by a background job.
  """
  @spec enqueue_due_once_schedules() :: {:ok, non_neg_integer()}
  def enqueue_due_once_schedules do
    ScheduleOperations.enqueue_due_once_schedules()
  end
end
