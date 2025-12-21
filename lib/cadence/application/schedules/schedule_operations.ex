defmodule Cadence.Application.Schedules.ScheduleOperations do
  @moduledoc """
  Use case module for schedule CRUD and state operations.

  This module provides operations for creating, updating, deleting,
  enabling/disabling schedules, and recording execution events.

  All operations:
  1. Validate using schema/changeset logic
  2. Persist via repository
  3. Optionally broadcast for updates

  ## Usage

      # Create a schedule
      {:ok, schedule} = ScheduleOperations.create(attrs)

      # Enable a schedule
      {:ok, schedule} = ScheduleOperations.enable(schedule)

      # Record a run
      {:ok, schedule} = ScheduleOperations.record_run(schedule, next_run_at)
  """

  alias Cadence.Schedules.Schedule
  alias Cadence.Application.Schedules.ScheduleQueries

  @type schedule_id :: String.t()
  @type organization_id :: String.t()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :schedule_repository,
      Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository
    )
  end

  # Get configured event publisher
  defp event_publisher do
    Application.get_env(
      :cadence,
      :event_publisher,
      Cadence.Adapters.Messaging.PhoenixEventPublisher
    )
  end

  @doc """
  Creates a new schedule.

  ## Parameters

  - `attrs` - Map containing schedule attributes:
    - `:name` (required)
    - `:organization_id` (required)
    - `:schedule_type` (required) - :cron or :once
    - `:procedure_id` (required)
    - `:cron_expression` (required for cron schedules)
    - `:scheduled_at` (required for one-time schedules)
    - `:mission_id` (optional)
    - `:target_id` (optional)
    - `:timezone` (optional, default: "UTC")
    - `:parameters` (optional)
    - `:enabled` (optional, default: true)

  ## Returns

  - `{:ok, schedule}` - Successfully created
  - `{:error, changeset}` - Validation failed
  """
  @spec create(map()) :: {:ok, Schedule.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    schedule = struct(Schedule, attrs)

    case repo().save(schedule) do
      {:ok, saved} ->
        broadcast_change(saved, :created)
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Updates an existing schedule.

  ## Parameters

  - `schedule` - The schedule to update
  - `attrs` - Map of attributes to update

  ## Returns

  - `{:ok, schedule}` - Successfully updated
  - `{:error, changeset}` - Validation failed
  """
  @spec update(Schedule.t(), map()) :: {:ok, Schedule.t()} | {:error, Ecto.Changeset.t()}
  def update(%Schedule{} = schedule, attrs) do
    updated = struct(schedule, attrs)

    case repo().save(updated) do
      {:ok, saved} ->
        broadcast_change(saved, :updated)
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Deletes a schedule.

  ## Returns

  - `{:ok, schedule}` - Successfully deleted
  - `{:error, reason}` - Deletion failed
  """
  @spec delete(Schedule.t()) :: {:ok, Schedule.t()} | {:error, term()}
  def delete(%Schedule{} = schedule) do
    case repo().delete(schedule) do
      {:ok, deleted} ->
        broadcast_change(deleted, :deleted)
        {:ok, deleted}

      error ->
        error
    end
  end

  @doc """
  Enables a schedule.

  ## Returns

  - `{:ok, schedule}` - Successfully enabled
  - `{:error, changeset}` - Update failed
  """
  @spec enable(Schedule.t()) :: {:ok, Schedule.t()} | {:error, term()}
  def enable(%Schedule{} = schedule) do
    case repo().enable(schedule) do
      {:ok, enabled} ->
        broadcast_change(enabled, :enabled)
        {:ok, enabled}

      error ->
        error
    end
  end

  @doc """
  Disables a schedule.

  ## Returns

  - `{:ok, schedule}` - Successfully disabled
  - `{:error, changeset}` - Update failed
  """
  @spec disable(Schedule.t()) :: {:ok, Schedule.t()} | {:error, term()}
  def disable(%Schedule{} = schedule) do
    case repo().disable(schedule) do
      {:ok, disabled} ->
        broadcast_change(disabled, :disabled)
        {:ok, disabled}

      error ->
        error
    end
  end

  @doc """
  Records that a schedule was executed.

  Updates last_run_at, next_run_at, and increments run_count.

  ## Parameters

  - `schedule` - The schedule that was executed
  - `next_run_at` - Optional next run time (for cron schedules)

  ## Returns

  - `{:ok, schedule}` - Successfully recorded
  - `{:error, changeset}` - Update failed
  """
  @spec record_run(Schedule.t(), DateTime.t() | nil) :: {:ok, Schedule.t()} | {:error, term()}
  def record_run(%Schedule{} = schedule, next_run_at \\ nil) do
    case repo().record_run(schedule, next_run_at) do
      {:ok, updated} ->
        broadcast_change(updated, :executed)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Enqueues a schedule for immediate execution.

  Creates an Oban job for the schedule worker.

  ## Returns

  - `{:ok, job}` - Successfully enqueued
  - `{:error, changeset}` - Enqueue failed
  """
  @spec enqueue(Schedule.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(%Schedule{} = schedule) do
    %{schedule_id: schedule.id}
    |> Cadence.Schedules.Workers.ExecuteScheduleWorker.new()
    |> Oban.insert()
  end

  @doc """
  Enqueues all due one-time schedules for execution.

  Called periodically by a background job to check for and execute
  one-time schedules that have reached their scheduled_at time.

  ## Returns

  - `{:ok, count}` - Number of schedules enqueued
  """
  @spec enqueue_due_once_schedules() :: {:ok, non_neg_integer()}
  def enqueue_due_once_schedules do
    schedules = ScheduleQueries.list_due_once()

    Enum.each(schedules, &enqueue/1)

    {:ok, length(schedules)}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp broadcast_change(%Schedule{organization_id: org_id} = schedule, event_type) do
    topic = "organization:#{org_id}:schedules"

    event_publisher().publish(topic, %{
      type: :schedule_changed,
      event: event_type,
      schedule_id: schedule.id,
      name: schedule.name,
      enabled: schedule.enabled,
      schedule_type: schedule.schedule_type
    })
  rescue
    # Don't fail operations if broadcasting fails
    _ -> :ok
  end
end
