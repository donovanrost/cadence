defmodule Cadence.Ports.Repository.Automations.AutomationExecutionRepository do
  @moduledoc """
  Port (behavior) defining the contract for automation execution persistence.

  This behavior abstracts the persistence layer for tracking automation executions.

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationExecutionRepository` - Production
  - `Cadence.Test.Adapters.InMemoryAutomationExecutionRepository` - In-memory for tests
  """

  alias Cadence.Domain.Automations.Entities.AutomationExecution

  @type id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | :duplicate | {:validation, map()} | term()

  @doc """
  Finds an execution by ID.
  """
  @callback find(id()) :: {:ok, AutomationExecution.t()} | {:error, :not_found}

  @doc """
  Finds an execution by ID with preloaded associations.
  """
  @callback find_with_automation(id()) :: {:ok, AutomationExecution.t()} | {:error, :not_found}

  @doc """
  Lists executions with optional filtering.

  ## Options

  - `:organization_id` - Filter by organization
  - `:mission_id` - Filter by mission
  - `:automation_id` - Filter by specific automation
  - `:status` - Filter by status
  - `:limit` - Maximum results (default 50)
  """
  @callback list(opts()) :: [AutomationExecution.t()]

  @doc """
  Counts executions for an automation within a time window.

  Used for rate limiting checks.
  """
  @callback count_recent(String.t(), DateTime.t()) :: non_neg_integer()

  @doc """
  Persists an execution (insert or update).

  Returns `{:error, :duplicate}` if idempotency key already exists.
  """
  @callback save(AutomationExecution.t()) :: {:ok, AutomationExecution.t()} | {:error, error()}

  @doc """
  Returns the configured execution repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :automation_execution_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationExecutionRepository
    )
  end
end
