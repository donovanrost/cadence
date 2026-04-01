defmodule Cadence.Ports.Repository.Automations.AutomationRepository do
  @moduledoc """
  Port (behavior) defining the contract for automation persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryAutomationRepository` - In-memory for tests
  """

  alias Cadence.Domain.Automations.Entities.Automation

  @type id :: String.t()
  @type organization_id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds an automation by its ID scoped to an organization.

  Returns `{:ok, automation}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id(), organization_id()) :: {:ok, Automation.t()} | {:error, :not_found}

  @doc """
  Finds an automation by ID without organization scoping.

  WARNING: Only use for internal operations where organization context is verified elsewhere.
  """
  @callback find_unscoped(id()) :: {:ok, Automation.t()} | {:error, :not_found}

  @doc """
  Lists automations for an organization with optional filtering.

  ## Options

  - `:mission_id` - Filter by specific mission
  - `:enabled_only` - Only return enabled automations
  - `:trigger_type` - Filter by trigger type
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list(organization_id(), opts()) :: [Automation.t()]

  @doc """
  Lists enabled automations for a mission.

  Used by the automation engine to load automations into the ETS cache.
  """
  @callback list_enabled_for_mission(organization_id(), mission_id()) :: [Automation.t()]

  @doc """
  Persists an automation (insert or update).

  Returns `{:ok, automation}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(Automation.t()) :: {:ok, Automation.t()} | {:error, error()}

  @doc """
  Deletes an automation.

  Returns `{:ok, automation}` with the deleted entity, or `{:error, :not_found}`.
  """
  @callback delete(Automation.t()) :: {:ok, Automation.t()} | {:error, error()}

  @doc """
  Updates the trigger tracking fields after an automation fires.

  Increments trigger_count and sets last_triggered_at.
  """
  @callback record_trigger(Automation.t()) :: {:ok, Automation.t()} | {:error, error()}

  @doc """
  Enables an automation.
  """
  @callback enable(Automation.t()) :: {:ok, Automation.t()} | {:error, error()}

  @doc """
  Disables an automation.
  """
  @callback disable(Automation.t()) :: {:ok, Automation.t()} | {:error, error()}

  @doc """
  Returns the configured automation repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :automation_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository
    )
  end
end
