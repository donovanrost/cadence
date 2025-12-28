defmodule Cadence.Procedures.V2.ExecutionQueries do
  @moduledoc """
  Read-only queries for V2 procedure executions.

  This module provides all query operations for executions, steps, blocks,
  and signoffs. It is the single source of truth for how execution data
  is loaded and preloaded.

  ## Design Principles

  1. **Read-Only**: This module never modifies data. All writes go through
     `ExecutionPersistence`.

  2. **Consistent Preloads**: Standard preload configurations ensure data
     is loaded consistently across the application.

  3. **Composable Queries**: Query functions return queryables where possible,
     allowing callers to add additional constraints.
  """

  import Ecto.Query

  alias Cadence.Outbox.Event, as: OutboxEvent
  alias Cadence.Procedures.{
    BlockExecution,
    ProcedureBlock,
    ProcedureExecution,
    StepExecution,
    StepSignoff
  }

  alias Cadence.Repo

  # ============================================================================
  # Execution Queries
  # ============================================================================

  @doc """
  Gets an execution by ID with full associations for runtime use.

  Loads:
  - procedure_version with procedure
  - step_executions with step, blocks, block_executions, signoffs
  """
  @spec get_execution(String.t()) :: ProcedureExecution.t() | nil
  def get_execution(execution_id) do
    ProcedureExecution
    |> Repo.get(execution_id)
    |> maybe_preload_execution()
  end

  @doc """
  Gets an execution by ID, raising if not found.
  """
  @spec get_execution!(String.t()) :: ProcedureExecution.t()
  def get_execution!(execution_id) do
    ProcedureExecution
    |> Repo.get!(execution_id)
    |> preload_execution()
  end

  @doc """
  Reloads an execution with fresh data and associations.

  Use this after mutations to get current state.
  """
  @spec reload_execution(String.t() | ProcedureExecution.t()) :: ProcedureExecution.t()
  def reload_execution(%ProcedureExecution{id: id}), do: reload_execution(id)

  def reload_execution(execution_id) when is_binary(execution_id) do
    get_execution!(execution_id)
  end

  @doc """
  Lists executions for a procedure with optional filters.

  ## Options

  - `:status` - Filter by status (atom or list)
  - `:limit` - Maximum number of results
  - `:order_by` - Order field (default: inserted_at desc)
  """
  @spec list_executions_for_procedure(String.t(), keyword()) :: [ProcedureExecution.t()]
  def list_executions_for_procedure(procedure_id, opts \\ []) do
    ProcedureExecution
    |> where([e], e.procedure_id == ^procedure_id)
    |> apply_execution_filters(opts)
    |> order_by([e], desc: e.inserted_at)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
    |> Enum.map(&preload_execution/1)
  end

  @doc """
  Lists executions for a mission.
  """
  @spec list_executions_for_mission(String.t(), keyword()) :: [ProcedureExecution.t()]
  def list_executions_for_mission(mission_id, opts \\ []) do
    ProcedureExecution
    |> where([e], e.mission_id == ^mission_id)
    |> apply_execution_filters(opts)
    |> order_by([e], desc: e.inserted_at)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
    |> Enum.map(&preload_execution/1)
  end

  @doc """
  Checks if an execution exists and is in a given status.
  """
  @spec execution_in_status?(String.t(), atom() | [atom()]) :: boolean()
  def execution_in_status?(execution_id, status) when is_atom(status) do
    execution_in_status?(execution_id, [status])
  end

  def execution_in_status?(execution_id, statuses) when is_list(statuses) do
    ProcedureExecution
    |> where([e], e.id == ^execution_id and e.status in ^statuses)
    |> Repo.exists?()
  end

  # ============================================================================
  # Step Execution Queries
  # ============================================================================

  @doc """
  Gets a step execution by ID with associations.

  Loads:
  - step with blocks
  - block_executions with block
  - signoffs with user
  """
  @spec get_step_execution(String.t()) :: StepExecution.t() | nil
  def get_step_execution(step_execution_id) do
    StepExecution
    |> Repo.get(step_execution_id)
    |> maybe_preload_step_execution()
  end

  @doc """
  Gets a step execution by ID, raising if not found.
  """
  @spec get_step_execution!(String.t()) :: StepExecution.t()
  def get_step_execution!(step_execution_id) do
    StepExecution
    |> Repo.get!(step_execution_id)
    |> preload_step_execution()
  end

  @doc """
  Lists step executions for an execution.
  """
  @spec list_step_executions(String.t()) :: [StepExecution.t()]
  def list_step_executions(execution_id) do
    StepExecution
    |> where([se], se.procedure_execution_id == ^execution_id)
    |> Repo.all()
    |> Enum.map(&preload_step_execution/1)
  end

  @doc """
  Lists step executions in a given status.
  """
  @spec list_step_executions_by_status(String.t(), atom() | [atom()]) :: [StepExecution.t()]
  def list_step_executions_by_status(execution_id, status) when is_atom(status) do
    list_step_executions_by_status(execution_id, [status])
  end

  def list_step_executions_by_status(execution_id, statuses) when is_list(statuses) do
    StepExecution
    |> where([se], se.procedure_execution_id == ^execution_id and se.status in ^statuses)
    |> Repo.all()
    |> Enum.map(&preload_step_execution/1)
  end

  @doc """
  Gets step executions that are pending and have satisfied dependencies.

  This is used to determine which steps can be activated next.
  """
  @spec get_activatable_steps(String.t()) :: [StepExecution.t()]
  def get_activatable_steps(execution_id) do
    execution = get_execution!(execution_id)

    execution.step_executions
    |> Enum.filter(fn step_exec ->
      step_exec.status == :pending and dependencies_satisfied?(step_exec, execution)
    end)
  end

  @doc """
  Checks if all dependencies for a step execution are satisfied.
  """
  @spec dependencies_satisfied?(StepExecution.t(), ProcedureExecution.t()) :: boolean()
  def dependencies_satisfied?(step_execution, execution) do
    step = step_execution.step || Repo.preload(step_execution, :step).step
    depends_on = step.depends_on || []

    if Enum.empty?(depends_on) do
      true
    else
      Enum.all?(depends_on, fn dep_step_id ->
        dep_exec = Enum.find(execution.step_executions, &(&1.step_id == dep_step_id))
        dep_exec && dep_exec.status in [:completed, :skipped]
      end)
    end
  end

  # ============================================================================
  # Block Execution Queries
  # ============================================================================

  @doc """
  Gets a block execution by step execution ID and block ID.
  """
  @spec get_block_execution(String.t(), String.t()) ::
          {:ok, BlockExecution.t()} | {:error, :not_found}
  def get_block_execution(step_execution_id, block_id) do
    case Repo.get_by(BlockExecution, step_execution_id: step_execution_id, block_id: block_id) do
      nil -> {:error, :not_found}
      block_exec -> {:ok, Repo.preload(block_exec, :block)}
    end
  end

  @doc """
  Gets a block execution by ID.
  """
  @spec get_block_execution_by_id(String.t()) :: BlockExecution.t() | nil
  def get_block_execution_by_id(block_execution_id) do
    BlockExecution
    |> Repo.get(block_execution_id)
    |> maybe_preload(&Repo.preload(&1, :block))
  end

  @doc """
  Lists block executions for a step execution.
  """
  @spec list_block_executions(String.t()) :: [BlockExecution.t()]
  def list_block_executions(step_execution_id) do
    BlockExecution
    |> where([be], be.step_execution_id == ^step_execution_id)
    |> Repo.all()
    |> Repo.preload(:block)
  end

  @doc """
  Gets blocks that need user input (pending input blocks).
  """
  @spec get_pending_input_blocks(String.t()) :: [BlockExecution.t()]
  def get_pending_input_blocks(step_execution_id) do
    input_types = [:text_input, :number_input, :checkbox, :select]

    BlockExecution
    |> join(:inner, [be], b in ProcedureBlock, on: be.block_id == b.id)
    |> where([be, b], be.step_execution_id == ^step_execution_id)
    |> where([be, b], be.status == :pending)
    |> where([be, b], b.block_type in ^input_types)
    |> Repo.all()
    |> Repo.preload(:block)
  end

  @doc """
  Gets blocks that can be automated (command, wait, telemetry, etc.).
  """
  @spec get_automatable_blocks(String.t()) :: [BlockExecution.t()]
  def get_automatable_blocks(step_execution_id) do
    automatable_types = [
      :command,
      :command_sequence,
      :wait,
      :wait_for,
      :telemetry_check,
      :telemetry_value,
      :script
    ]

    BlockExecution
    |> join(:inner, [be], b in ProcedureBlock, on: be.block_id == b.id)
    |> where([be, b], be.step_execution_id == ^step_execution_id)
    |> where([be, b], be.status == :pending)
    |> where([be, b], b.block_type in ^automatable_types)
    |> order_by([be, b], asc: b.position)
    |> Repo.all()
    |> Repo.preload(:block)
  end

  # ============================================================================
  # Signoff Queries
  # ============================================================================

  @doc """
  Lists signoffs for a step execution.
  """
  @spec list_signoffs(String.t()) :: [StepSignoff.t()]
  def list_signoffs(step_execution_id) do
    StepSignoff
    |> where([s], s.step_execution_id == ^step_execution_id)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Gets signoff summary for a step execution.

  Returns a map with:
  - `:required_roles` - Roles required for signoff
  - `:signoff_logic` - :any or :all
  - `:signoffs` - Current signoffs
  - `:is_complete` - Whether signoff requirements are met
  - `:missing_roles` - Roles still needed
  """
  @spec get_signoff_summary(String.t()) :: map()
  def get_signoff_summary(step_execution_id) do
    step_execution =
      StepExecution
      |> Repo.get!(step_execution_id)
      |> Repo.preload([:step, :signoffs])

    step = step_execution.step
    signoffs = step_execution.signoffs
    required_roles = step.required_roles || []
    signoff_logic = step.signoff_logic || :any

    %{
      required_roles: required_roles,
      signoff_logic: signoff_logic,
      signoffs: signoffs,
      is_complete: StepSignoff.requirements_met?(signoffs, required_roles, signoff_logic),
      missing_roles: StepSignoff.missing_roles(signoffs, required_roles, signoff_logic)
    }
  end

  @doc """
  Checks if signoff requirements are met for a step.
  """
  @spec signoff_requirements_met?(String.t()) :: boolean()
  def signoff_requirements_met?(step_execution_id) do
    get_signoff_summary(step_execution_id).is_complete
  end

  # ============================================================================
  # Command Lifecycle Queries
  # ============================================================================

  @doc """
  Gets command lifecycle events for a queue entry.

  Returns a list of lifecycle events ordered by timestamp, each containing:
  - `:state` - The command state (:queued, :executing, :sent, :completed, :failed)
  - `:timestamp` - When the state transition occurred
  - `:details` - Additional event details (command_name, etc.)

  ## Parameters

  - `queue_entry_id` - The queue entry ID (stored as command_id in block execution result)

  ## Example

      iex> get_command_lifecycle("abc-123")
      [
        %{state: :queued, timestamp: ~U[2024-01-01 10:00:00Z], details: %{...}},
        %{state: :executing, timestamp: ~U[2024-01-01 10:00:01Z], details: %{...}},
        %{state: :sent, timestamp: ~U[2024-01-01 10:00:02Z], details: %{...}}
      ]
  """
  @spec get_command_lifecycle(String.t()) :: [map()]
  def get_command_lifecycle(queue_entry_id) do
    OutboxEvent
    |> where([e], e.aggregate_id == ^queue_entry_id)
    |> where([e], e.aggregate_type == "command_queue_entry")
    |> where([e], e.event_type in ["command_enqueued", "command_status_changed"])
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
    |> Enum.map(&format_lifecycle_event/1)
  end

  @doc """
  Gets command lifecycles for multiple queue entries at once.

  Returns a map of queue_entry_id => lifecycle events list.
  More efficient than calling get_command_lifecycle/1 multiple times.
  """
  @spec get_command_lifecycles([String.t()]) :: %{String.t() => [map()]}
  def get_command_lifecycles([]), do: %{}

  def get_command_lifecycles(queue_entry_ids) do
    OutboxEvent
    |> where([e], e.aggregate_id in ^queue_entry_ids)
    |> where([e], e.aggregate_type == "command_queue_entry")
    |> where([e], e.event_type in ["command_enqueued", "command_status_changed"])
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.aggregate_id)
    |> Enum.map(fn {id, events} ->
      {id, Enum.map(events, &format_lifecycle_event/1)}
    end)
    |> Map.new()
  end

  defp format_lifecycle_event(%OutboxEvent{} = event) do
    %{
      state: extract_state(event),
      timestamp: event.inserted_at,
      details: %{
        command_name: get_in(event.payload, ["command_name"]),
        command_log_id: get_in(event.payload, ["command_log_id"]),
        target_id: get_in(event.payload, ["target_id"]),
        error: get_in(event.payload, ["last_error"])
      }
    }
  end

  defp extract_state(%OutboxEvent{event_type: "command_enqueued"}), do: :queued

  defp extract_state(%OutboxEvent{event_type: "command_status_changed", payload: payload}) do
    case payload["status"] do
      "pending" -> :queued
      "executing" -> :executing
      "completed" -> :sent
      "failed" -> :failed
      "cancelled" -> :cancelled
      "expired" -> :expired
      _ -> :unknown
    end
  end

  # ============================================================================
  # Private Helpers - Preloading
  # ============================================================================

  defp maybe_preload_execution(nil), do: nil
  defp maybe_preload_execution(execution), do: preload_execution(execution)

  defp preload_execution(execution) do
    Repo.preload(execution,
      procedure_version: :procedure,
      step_executions: [
        step: [
          :section,
          blocks: from(b in ProcedureBlock, order_by: b.position)
        ],
        block_executions: :block,
        signoffs: :user
      ]
    )
  end

  defp maybe_preload_step_execution(nil), do: nil
  defp maybe_preload_step_execution(step_exec), do: preload_step_execution(step_exec)

  defp preload_step_execution(step_execution) do
    step_execution
    |> Repo.preload(
      step: [blocks: from(b in ProcedureBlock, order_by: b.position)],
      block_executions: :block,
      signoffs: :user
    )
  end

  defp maybe_preload(nil, _fun), do: nil
  defp maybe_preload(record, fun), do: fun.(record)

  # ============================================================================
  # Private Helpers - Query Building
  # ============================================================================

  defp apply_execution_filters(query, opts) do
    query
    |> maybe_filter_by_status(opts[:status])
  end

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, status) when is_atom(status) do
    where(query, [e], e.status == ^status)
  end

  defp maybe_filter_by_status(query, statuses) when is_list(statuses) do
    where(query, [e], e.status in ^statuses)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)
end
