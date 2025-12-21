defmodule Cadence.Application.Schedules.ScheduleQueries do
  @moduledoc """
  Use case module for querying schedules.

  This module provides read-only operations for listing, counting,
  and finding schedules. It works with domain entities and uses
  repository ports for data access.

  ## Usage

      # List schedules for an organization
      schedules = ScheduleQueries.list(organization_id)

      # List with filters
      schedules = ScheduleQueries.list(org_id, mission_id: mission_id, enabled_only: true)

      # Find specific schedule
      {:ok, schedule} = ScheduleQueries.find(id, organization_id)
  """

  alias Cadence.Schedules.Schedule

  @type id :: String.t()
  @type organization_id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()

  # Get configured repository (allows for DI in tests)
  defp repo do
    Application.get_env(
      :cadence,
      :schedule_repository,
      Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository
    )
  end

  @doc """
  Finds a schedule by ID scoped to an organization.

  Returns `{:ok, schedule}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(id(), organization_id()) :: {:ok, Schedule.t()} | {:error, :not_found}
  def find(id, organization_id), do: repo().find(id, organization_id)

  @doc """
  Finds a schedule by ID scoped to an organization, raising if not found.
  """
  @spec find!(id(), organization_id()) :: Schedule.t()
  def find!(id, organization_id) do
    case find(id, organization_id) do
      {:ok, schedule} -> schedule
      {:error, :not_found} -> raise "Schedule not found: #{id}"
    end
  end

  @doc """
  Finds a schedule by ID without organization scoping.

  WARNING: Only use for internal operations where organization context is verified elsewhere.
  """
  @spec find_unscoped(id()) :: {:ok, Schedule.t()} | {:error, :not_found}
  def find_unscoped(id), do: repo().find_unscoped(id)

  @doc """
  Lists schedules for an organization.

  ## Options

  - `:mission_id` - Filter by mission
  - `:procedure_id` - Filter by procedure
  - `:enabled_only` - Only return enabled schedules
  - `:limit` - Maximum number of results
  - `:offset` - Offset for pagination

  ## Examples

      # All schedules
      ScheduleQueries.list(org_id)

      # Only enabled schedules for a mission
      ScheduleQueries.list(org_id, mission_id: mission_id, enabled_only: true)
  """
  @spec list(organization_id(), opts()) :: [Schedule.t()]
  def list(organization_id, opts \\ []) do
    repo().list(organization_id, opts)
  end

  @doc """
  Gets all enabled cron schedules for registration with Oban.

  Returns a list of tuples: {cron_expression, {worker_module, args}}
  """
  @spec list_cron_jobs() :: [{String.t(), {module(), keyword()}}]
  def list_cron_jobs do
    repo().list_enabled_cron()
  end

  @doc """
  Lists one-time schedules that are due for execution.

  Returns enabled schedules of type :once where scheduled_at <= now
  and last_run_at is nil.
  """
  @spec list_due_once() :: [Schedule.t()]
  def list_due_once do
    repo().list_due_once()
  end

  @doc """
  Counts schedules by schedule type for an organization.

  Returns a map of schedule_type to count.

  ## Example

      %{
        cron: 5,
        once: 3
      }
  """
  @spec count_by_type(organization_id()) :: map()
  def count_by_type(organization_id) do
    list(organization_id)
    |> Enum.group_by(& &1.schedule_type)
    |> Enum.into(%{}, fn {type, schedules} -> {type, length(schedules)} end)
  end

  @doc """
  Counts enabled schedules for an organization.
  """
  @spec count_enabled(organization_id()) :: non_neg_integer()
  def count_enabled(organization_id) do
    list(organization_id, enabled_only: true)
    |> length()
  end
end
