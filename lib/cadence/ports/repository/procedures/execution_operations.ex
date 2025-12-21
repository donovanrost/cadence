defmodule Cadence.Ports.Repository.Procedures.ExecutionOperations do
  @moduledoc """
  Port (behavior) defining the contract for procedure execution persistence operations.

  This narrow interface follows the Interface Segregation Principle, allowing
  use cases to depend only on the execution operations they need.

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository` - Production
  - `Cadence.Test.Adapters.InMemoryProcedureRepository` - Testing
  """

  alias Cadence.Procedures.ProcedureExecution
  alias Cadence.Procedures.ProcedureLog

  @type id :: String.t()
  @type execution_id :: String.t()
  @type error :: :not_found | {:validation, map()} | term()

  # ============================================================================
  # Execution Operations
  # ============================================================================

  @doc """
  Finds an execution record by ID.

  Returns `{:ok, execution}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find_execution(id()) :: {:ok, ProcedureExecution.t()} | {:error, :not_found}

  @doc """
  Lists execution records with optional filtering.

  ## Options

  - `:mission_id` - Filter by mission
  - `:procedure_id` - Filter by procedure
  - `:status` - Filter by execution status
  - `:limit` - Maximum number of results (default: 50)
  - `:preload` - Associations to preload
  """
  @callback list_executions(opts :: keyword()) :: [ProcedureExecution.t()]

  @doc """
  Creates a new execution record.

  Returns `{:ok, execution}` on success, `{:error, reason}` on failure.
  """
  @callback create_execution(attrs :: map()) ::
              {:ok, ProcedureExecution.t()} | {:error, error()}

  @doc """
  Updates an execution's status and related fields.

  Returns `{:ok, execution}` on success, `{:error, reason}` on failure.
  """
  @callback update_execution(id(), attrs :: map()) ::
              {:ok, ProcedureExecution.t()} | {:error, error()}

  @doc """
  Lists executions currently in running status.

  Useful for recovery after restarts.
  """
  @callback list_running_executions() :: [ProcedureExecution.t()]

  # ============================================================================
  # Log Operations
  # ============================================================================

  @doc """
  Lists log entries for an execution.

  ## Options

  - `:level` - Filter by log level (:debug, :info, :warn, :error)
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Pagination offset
  """
  @callback list_logs(execution_id(), opts :: keyword()) :: [ProcedureLog.t()]

  @doc """
  Creates a log entry for an execution.

  Returns `{:ok, log}` on success, `{:error, reason}` on failure.
  """
  @callback create_log(attrs :: map()) :: {:ok, ProcedureLog.t()} | {:error, error()}

  @doc """
  Returns the configured execution operations implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :execution_operations,
      Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository
    )
  end
end
