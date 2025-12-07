defmodule Cadence.Procedures.Runtime do
  @moduledoc """
  Runtime operations for procedure executions.

  Provides a clean API for interacting with running executions,
  abstracting away process management details. LiveViews and other
  consumers should use this module rather than directly querying
  the ExecutionCoordinator or process registries.

  ## Why This Module Exists

  The ExecutionCoordinator is a per-mission GenServer that may or may not
  be running depending on mission state. This module handles the
  "coordinator not running" case gracefully, returning sensible defaults
  instead of requiring callers to handle nil PIDs.

  ## Example

      # Instead of:
      case ExecutionCoordinator.whereis(mission_id) do
        nil -> %{running: 0, paused: 0, pending: 0}
        _pid -> ExecutionCoordinator.get_counts(mission_id)
      end

      # Use:
      Runtime.get_execution_counts(mission_id)
  """

  alias Cadence.Procedures.Engine.ExecutionCoordinator
  alias Cadence.Procedures.ProcedureExecution

  @type mission_id :: String.t()
  @type execution_id :: String.t()
  @type procedure_id :: String.t()

  @doc """
  Gets execution counts for a mission.

  Returns counts even if no coordinator is running (all zeros).
  This is safe to call at any time regardless of mission state.

  ## Example

      iex> Runtime.get_execution_counts(mission_id)
      %{running: 2, paused: 1, pending: 0}
  """
  @spec get_execution_counts(mission_id()) :: %{running: integer(), paused: integer(), pending: integer()}
  def get_execution_counts(mission_id) do
    case coordinator_pid(mission_id) do
      nil -> %{running: 0, paused: 0, pending: 0}
      _pid -> ExecutionCoordinator.get_counts(mission_id)
    end
  end

  @doc """
  Lists active executions for a mission.

  Returns an empty list if the coordinator is not running.

  ## Example

      iex> Runtime.list_active_executions(mission_id)
      [%ProcedureExecution{status: :running, ...}, ...]
  """
  @spec list_active_executions(mission_id()) :: [ProcedureExecution.t()]
  def list_active_executions(mission_id) do
    case coordinator_pid(mission_id) do
      nil -> []
      _pid -> ExecutionCoordinator.list_active(mission_id)
    end
  end

  @doc """
  Starts a new procedure execution.

  Returns an error if the coordinator is not available (mission not started/running).

  ## Options

  - `:version_id` - Specific version to run (defaults to current approved)
  - `:target_id` - Target for target-scoped procedures
  - `:parameters` - Runtime parameters
  - `:user_id` - User initiating the execution
  - `:triggered_by` - Trigger type (:manual, :schedule, :event)
  - `:resume_from_execution_id` - Copy completed step events from a previous execution

  ## Returns

  - `{:ok, %ProcedureExecution{}}` - Execution started successfully
  - `{:error, :mission_not_running}` - Mission coordinator not available
  - `{:error, :at_concurrency_limit}` - Too many concurrent executions
  - `{:error, :procedure_not_found}` - Procedure doesn't exist
  - `{:error, :no_approved_version}` - No approved version available

  ## Example

      iex> Runtime.start_execution(mission_id, procedure_id, user_id: user.id)
      {:ok, %ProcedureExecution{status: :pending, ...}}
  """
  @spec start_execution(mission_id(), procedure_id(), keyword()) ::
          {:ok, ProcedureExecution.t()} | {:error, term()}
  def start_execution(mission_id, procedure_id, opts \\ []) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.start_execution(mission_id, procedure_id, opts)
    end
  end

  @doc """
  Pauses an execution at the next safe point.

  The execution will transition to `:pausing` immediately, then to `:paused`
  once the current step completes.

  ## Returns

  - `:ok` - Pause signal sent successfully
  - `{:error, :mission_not_running}` - Mission coordinator not available
  - `{:error, :not_found}` - Execution not found or not active

  ## Example

      iex> Runtime.pause_execution(mission_id, execution_id)
      :ok
  """
  @spec pause_execution(mission_id(), execution_id()) :: :ok | {:error, term()}
  def pause_execution(mission_id, execution_id) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.pause(mission_id, execution_id)
    end
  end

  @doc """
  Resumes a paused execution.

  ## Returns

  - `:ok` - Resume signal sent successfully
  - `{:error, :mission_not_running}` - Mission coordinator not available
  - `{:error, :not_found}` - Execution not found or not paused

  ## Example

      iex> Runtime.resume_execution(mission_id, execution_id)
      :ok
  """
  @spec resume_execution(mission_id(), execution_id()) :: :ok | {:error, term()}
  def resume_execution(mission_id, execution_id) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.resume(mission_id, execution_id)
    end
  end

  @doc """
  Aborts an execution immediately.

  Running steps will be cancelled and the execution will transition to `:cancelled`.

  ## Returns

  - `:ok` - Abort signal sent successfully
  - `{:error, :mission_not_running}` - Mission coordinator not available
  - `{:error, :not_found}` - Execution not found or not active

  ## Example

      iex> Runtime.abort_execution(mission_id, execution_id)
      :ok
  """
  @spec abort_execution(mission_id(), execution_id()) :: :ok | {:error, term()}
  def abort_execution(mission_id, execution_id) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.abort(mission_id, execution_id)
    end
  end

  @doc """
  Checks if a mission's execution coordinator is running.

  ## Example

      iex> Runtime.coordinator_running?(mission_id)
      true
  """
  @spec coordinator_running?(mission_id()) :: boolean()
  def coordinator_running?(mission_id) do
    coordinator_pid(mission_id) != nil
  end

  # Private helpers

  defp coordinator_pid(mission_id) do
    ExecutionCoordinator.whereis(mission_id)
  end
end
