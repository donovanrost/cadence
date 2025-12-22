defmodule Cadence.Ports.Repository.Schedules.ScheduleRepository do
  @moduledoc """
  Port (behavior) defining the contract for schedule persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryScheduleRepository` - In-memory for tests
  """

  alias Cadence.Domain.Schedules.Entities.Schedule

  @type id :: String.t()
  @type organization_id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds a schedule by its ID scoped to an organization.

  Returns `{:ok, schedule}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id(), organization_id()) :: {:ok, Schedule.t()} | {:error, :not_found}

  @doc """
  Finds a schedule by ID without organization scoping.

  WARNING: Only use for internal operations where organization context is verified elsewhere.
  """
  @callback find_unscoped(id()) :: {:ok, Schedule.t()} | {:error, :not_found}

  @doc """
  Lists schedules for an organization with optional filtering.

  ## Options

  - `:mission_id` - Filter by specific mission
  - `:procedure_id` - Filter by specific procedure
  - `:enabled_only` - Only return enabled schedules
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list(organization_id(), opts()) :: [Schedule.t()]

  @doc """
  Lists all enabled cron schedules across all organizations.

  Used by the Oban cron plugin for registration.
  Returns tuples of {cron_expression, {worker_module, args}}.
  """
  @callback list_enabled_cron() :: [{String.t(), {module(), keyword()}}]

  @doc """
  Lists one-time schedules that are due for execution.

  Returns enabled schedules of type :once where scheduled_at <= now
  and last_run_at is nil.
  """
  @callback list_due_once() :: [Schedule.t()]

  @doc """
  Persists a schedule (insert or update).

  Returns `{:ok, schedule}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(Schedule.t()) :: {:ok, Schedule.t()} | {:error, error()}

  @doc """
  Deletes a schedule.

  Returns `{:ok, schedule}` with the deleted entity, or `{:error, :not_found}`.
  """
  @callback delete(Schedule.t()) :: {:ok, Schedule.t()} | {:error, error()}

  @doc """
  Records that a schedule was executed.

  Updates last_run_at, next_run_at, and increments run_count.
  """
  @callback record_run(Schedule.t(), DateTime.t() | nil) :: {:ok, Schedule.t()} | {:error, error()}

  @doc """
  Enables a schedule.
  """
  @callback enable(Schedule.t()) :: {:ok, Schedule.t()} | {:error, error()}

  @doc """
  Disables a schedule.
  """
  @callback disable(Schedule.t()) :: {:ok, Schedule.t()} | {:error, error()}

  @doc """
  Returns the configured schedule repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :schedule_repository,
      Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository
    )
  end
end
