defmodule Cadence.Procedures.V2.ExecutionPersistence do
  @moduledoc """
  Persistence operations for V2 procedure executions.

  All database writes for V2 execution go through this module, ensuring:
  - Atomic transactions via Ecto.Multi
  - Consistent broadcast-after-commit pattern
  - Single source of truth for execution mutations

  ## Design Principles

  1. **Atomic Operations**: Each public function wraps its changes in an Ecto.Multi
     transaction. If any step fails, all changes are rolled back.

  2. **Broadcast After Commit**: PubSub broadcasts only happen after the transaction
     commits successfully, preventing clients from seeing state that may be rolled back.

  3. **No Business Logic**: This module only handles persistence. Business rules
     (e.g., "can this step be completed?") belong in the context or process layer.

  4. **Clear Return Types**: All functions return `{:ok, result}` or `{:error, reason}`.
  """

  alias Cadence.Procedures.{
    BlockExecution,
    Procedure,
    ProcedureExecution,
    ProcedureSection,
    ProcedureStep,
    ProcedureVersion,
    StepExecution,
    StepSignoff
  }

  alias Cadence.Procedures.Events.ProcedureExecutionEvent

  alias Cadence.Repo
  alias Cadence.Time, as: CadenceTime
  alias Ecto.Multi

  import Ecto.Query

  require Logger

  # ============================================================================
  # Execution Lifecycle
  # ============================================================================

  @doc """
  Creates a new execution with all step and block executions.

  This is an atomic operation that creates:
  - The ProcedureExecution record
  - StepExecution records for each step in the version
  - BlockExecution records for each block in each step

  ## Options

  - `:target_id` - Target spacecraft ID
  - `:user_id` - User starting the execution
  - `:triggered_by` - Trigger type (:manual, :schedule, :event)
  - `:trigger_context` - Additional trigger context map

  ## Returns

  - `{:ok, execution}` - Fully loaded execution with step_executions
  - `{:error, reason}` - If creation fails
  """
  @spec create_execution(ProcedureVersion.t(), map(), keyword()) ::
          {:ok, ProcedureExecution.t()} | {:error, term()}
  def create_execution(procedure_version, params, opts \\ []) do
    now = utc_now()

    Multi.new()
    |> Multi.insert(:execution, fn _changes ->
      build_execution_changeset(procedure_version, params, opts, now)
    end)
    |> Multi.run(:step_executions, fn repo, %{execution: execution} ->
      create_step_executions(repo, execution, procedure_version, now)
    end)
    |> Multi.run(:block_executions, fn repo, %{step_executions: step_executions} ->
      create_block_executions(repo, step_executions, procedure_version, now)
    end)
    |> Repo.transaction()
    |> handle_transaction_result(:execution, :execution_started)
  end

  @doc """
  Updates execution status.

  Handles status transitions like pause, resume, complete, and fail.

  ## Status-specific fields

  - `:running` - Sets started_at if transitioning from pending
  - `:completed` - Sets completed_at
  - `:failed` - Accepts error_message option
  - `:paused` / `:pausing` - No additional fields

  ## Options

  - `:error_message` - Error message for failed status
  - `:error_step_index` - Which step failed
  """
  @spec update_execution_status(ProcedureExecution.t(), atom(), keyword()) ::
          {:ok, ProcedureExecution.t()} | {:error, term()}
  def update_execution_status(execution, status, opts \\ []) do
    now = utc_now()

    changes =
      case status do
        :running when execution.status == :pending ->
          %{status: :running, started_at: now}

        :running ->
          %{status: :running}

        :completed ->
          %{status: :completed, completed_at: now}

        :failed ->
          %{
            status: :failed,
            error_message: opts[:error_message],
            error_step_index: opts[:error_step_index]
          }

        :pausing ->
          %{status: :pausing}

        :paused ->
          %{status: :paused}

        :cancelled ->
          %{status: :cancelled, completed_at: now}
      end

    Multi.new()
    |> Multi.update(:execution, ProcedureExecution.status_changeset(execution, changes))
    |> Repo.transaction()
    |> handle_transaction_result(:execution, {:execution_status_changed, status})
  end

  # ============================================================================
  # Step Operations
  # ============================================================================

  @doc """
  Activates a step, setting status to :active and started_at.

  Broadcasts `:step_activated` after commit.
  """
  @spec activate_step(StepExecution.t()) :: {:ok, StepExecution.t()} | {:error, term()}
  def activate_step(step_execution) do
    Multi.new()
    |> Multi.update(:step, StepExecution.activate_changeset(step_execution))
    |> Repo.transaction()
    |> handle_transaction_result(:step, :step_activated)
  end

  @doc """
  Marks step as awaiting signoff.
  """
  @spec awaiting_signoff(StepExecution.t()) :: {:ok, StepExecution.t()} | {:error, term()}
  def awaiting_signoff(step_execution) do
    Multi.new()
    |> Multi.update(:step, StepExecution.awaiting_signoff_changeset(step_execution))
    |> Repo.transaction()
    |> handle_transaction_result(:step, :step_awaiting_signoff)
  end

  @doc """
  Completes a step.

  Broadcasts `:step_completed` after commit.
  """
  @spec complete_step(StepExecution.t(), atom()) :: {:ok, StepExecution.t()} | {:error, term()}
  def complete_step(step_execution, result \\ :pass) do
    Multi.new()
    |> Multi.update(:step, StepExecution.complete_changeset(step_execution, result))
    |> Repo.transaction()
    |> handle_transaction_result(:step, :step_completed)
  end

  @doc """
  Skips a step with a reason.

  ## Attributes

  - `:skipped_reason` - Required reason for skip
  - `:skipped_by_id` - User who skipped
  """
  @spec skip_step(StepExecution.t(), map()) :: {:ok, StepExecution.t()} | {:error, term()}
  def skip_step(step_execution, attrs) do
    Multi.new()
    |> Multi.update(:step, StepExecution.skip_changeset(step_execution, attrs))
    |> Repo.transaction()
    |> handle_transaction_result(:step, :step_skipped)
  end

  @doc """
  Fails a step with an error message.
  """
  @spec fail_step(StepExecution.t(), String.t()) :: {:ok, StepExecution.t()} | {:error, term()}
  def fail_step(step_execution, error_message) do
    Multi.new()
    |> Multi.update(:step, StepExecution.fail_changeset(step_execution, error_message))
    |> Repo.transaction()
    |> handle_transaction_result(:step, :step_failed)
  end

  @doc """
  Resets a step and all its blocks to pending for retry.
  """
  @spec reset_step_for_retry(StepExecution.t()) :: {:ok, StepExecution.t()} | {:error, term()}
  def reset_step_for_retry(step_execution) do
    now = utc_now()

    Multi.new()
    |> Multi.update_all(
      :reset_blocks,
      from(be in BlockExecution, where: be.step_execution_id == ^step_execution.id),
      set: [
        status: :pending,
        value: nil,
        command_result: nil,
        passed: nil,
        validation_message: nil,
        telemetry_reading: nil,
        started_at: nil,
        completed_at: nil,
        updated_at: now
      ]
    )
    |> Multi.update(:step, fn _changes ->
      step_execution
      |> Ecto.Changeset.change(%{
        status: :active,
        result: nil,
        error_message: nil,
        started_at: now,
        completed_at: nil
      })
    end)
    |> Repo.transaction()
    |> handle_transaction_result(:step, :step_reset)
  end

  # ============================================================================
  # Block Operations
  # ============================================================================

  @doc """
  Updates a block execution with a user-entered value.

  For input blocks (text_input, number_input, checkbox, select).
  """
  @spec update_block_value(BlockExecution.t(), map(), String.t() | nil) ::
          {:ok, BlockExecution.t()} | {:error, term()}
  def update_block_value(block_execution, value, user_id \\ nil) do
    Multi.new()
    |> Multi.update(:block, BlockExecution.enter_value_changeset(block_execution, value, user_id))
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_updated)
  end

  @doc """
  Updates a block execution with a command result.

  For command blocks after execution.
  """
  @spec update_block_command_result(BlockExecution.t(), map()) ::
          {:ok, BlockExecution.t()} | {:error, term()}
  def update_block_command_result(block_execution, result) do
    Multi.new()
    |> Multi.update(:block, BlockExecution.command_result_changeset(block_execution, result))
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_updated)
  end

  @doc """
  Updates a block execution with a telemetry reading.

  For telemetry value blocks.
  """
  @spec update_block_telemetry_reading(BlockExecution.t(), map(), boolean() | nil) ::
          {:ok, BlockExecution.t()} | {:error, term()}
  def update_block_telemetry_reading(block_execution, reading, passed \\ nil) do
    Multi.new()
    |> Multi.update(
      :block,
      BlockExecution.telemetry_reading_changeset(block_execution, reading, passed)
    )
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_updated)
  end

  @doc """
  Updates a block execution with a telemetry check result.

  For telemetry check blocks.
  """
  @spec update_block_telemetry_check(BlockExecution.t(), map(), boolean(), String.t() | nil) ::
          {:ok, BlockExecution.t()} | {:error, term()}
  def update_block_telemetry_check(block_execution, reading, passed, validation_message \\ nil) do
    Multi.new()
    |> Multi.update(
      :block,
      BlockExecution.telemetry_check_changeset(
        block_execution,
        reading,
        passed,
        validation_message
      )
    )
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_updated)
  end

  @doc """
  Marks a block as failed with an error message.
  """
  @spec fail_block(BlockExecution.t(), String.t()) ::
          {:ok, BlockExecution.t()} | {:error, term()}
  def fail_block(block_execution, error_message) do
    Multi.new()
    |> Multi.update(:block, BlockExecution.fail_changeset(block_execution, error_message))
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_failed)
  end

  @doc """
  Skips a block.
  """
  @spec skip_block(BlockExecution.t()) :: {:ok, BlockExecution.t()} | {:error, term()}
  def skip_block(block_execution) do
    Multi.new()
    |> Multi.update(:block, BlockExecution.skip_changeset(block_execution))
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_skipped)
  end

  @doc """
  Resets a block to pending for retry.
  """
  @spec reset_block_for_retry(BlockExecution.t()) :: {:ok, BlockExecution.t()} | {:error, term()}
  def reset_block_for_retry(block_execution) do
    changes = %{
      status: :pending,
      value: nil,
      command_result: nil,
      passed: nil,
      validation_message: nil,
      telemetry_reading: nil,
      started_at: nil,
      completed_at: nil
    }

    Multi.new()
    |> Multi.update(:block, Ecto.Changeset.change(block_execution, changes))
    |> Repo.transaction()
    |> handle_transaction_result(:block, :block_reset)
  end

  # ============================================================================
  # Signoff Operations
  # ============================================================================

  @doc """
  Creates a signoff for a step.
  """
  @spec create_signoff(StepExecution.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, StepSignoff.t()} | {:error, term()}
  def create_signoff(step_execution, user_id, role, note \\ nil) do
    attrs = %{
      step_execution_id: step_execution.id,
      user_id: user_id,
      role: role,
      note: note
    }

    Multi.new()
    |> Multi.insert(:signoff, StepSignoff.changeset(%StepSignoff{}, attrs))
    |> Repo.transaction()
    |> handle_transaction_result(:signoff, :signoff_added)
  end

  # ============================================================================
  # Private Helpers - Execution Creation
  # ============================================================================

  defp build_execution_changeset(procedure_version, params, opts, now) do
    # Ensure procedure is loaded for IDs
    procedure_version = Repo.preload(procedure_version, :procedure)
    procedure = procedure_version.procedure

    attrs = %{
      procedure_id: procedure.id,
      procedure_version_id: procedure_version.id,
      organization_id: procedure.organization_id,
      mission_id: procedure.mission_id,
      target_id: opts[:target_id],
      triggered_by_user_id: opts[:user_id],
      parameters: params,
      status: :running,
      started_at: now,
      triggered_by: opts[:triggered_by] || :manual,
      trigger_context: opts[:trigger_context] || %{}
    }

    ProcedureExecution.changeset(%ProcedureExecution{}, attrs)
  end

  defp create_step_executions(repo, execution, procedure_version, now) do
    # Load all sections and steps for this version
    sections =
      ProcedureSection
      |> where([s], s.procedure_version_id == ^procedure_version.id)
      |> order_by([s], s.position)
      |> preload(steps: ^from(st in ProcedureStep, order_by: st.position))
      |> repo.all()

    step_attrs =
      sections
      |> Enum.flat_map(& &1.steps)
      |> Enum.map(fn step ->
        %{
          id: Ecto.UUID.generate(),
          procedure_execution_id: execution.id,
          step_id: step.id,
          status: :pending,
          inserted_at: now,
          updated_at: now
        }
      end)

    case step_attrs do
      [] ->
        {:ok, []}

      attrs ->
        {_count, inserted} = repo.insert_all(StepExecution, attrs, returning: true)
        {:ok, inserted}
    end
  end

  defp create_block_executions(repo, step_executions, procedure_version, now) do
    # Build a map of step_id -> step_execution_id
    step_exec_map = Map.new(step_executions, &{&1.step_id, &1.id})

    # Load steps with blocks
    sections =
      ProcedureSection
      |> where([s], s.procedure_version_id == ^procedure_version.id)
      |> preload(
        steps: [blocks: ^from(b in Cadence.Procedures.ProcedureBlock, order_by: b.position)]
      )
      |> repo.all()

    block_attrs =
      sections
      |> Enum.flat_map(& &1.steps)
      |> Enum.flat_map(fn step ->
        step_exec_id = step_exec_map[step.id]

        (step.blocks || [])
        |> Enum.map(fn block ->
          %{
            id: Ecto.UUID.generate(),
            step_execution_id: step_exec_id,
            block_id: block.id,
            status: :pending,
            inserted_at: now,
            updated_at: now
          }
        end)
      end)

    case block_attrs do
      [] ->
        {:ok, []}

      attrs ->
        {count, _} = repo.insert_all(BlockExecution, attrs)
        {:ok, count}
    end
  end

  # ============================================================================
  # Private Helpers - Transaction Handling
  # ============================================================================

  # Handles successful transaction, extracts result, and broadcasts event
  defp handle_transaction_result({:ok, changes}, result_key, event_type) do
    result = Map.get(changes, result_key)

    # Reload with associations for proper broadcasting
    result = maybe_reload_with_associations(result)

    # Broadcast after commit
    broadcast_event(result, event_type)

    {:ok, result}
  end

  defp handle_transaction_result({:error, _step, changeset, _changes}, _result_key, _event_type) do
    {:error, changeset}
  end

  defp handle_transaction_result({:error, changeset}, _result_key, _event_type) do
    {:error, changeset}
  end

  # Reloads records with standard associations for broadcasting
  defp maybe_reload_with_associations(%ProcedureExecution{id: id}) do
    ProcedureExecution
    |> Repo.get!(id)
    |> Repo.preload([
      :procedure,
      :procedure_version,
      step_executions: [:step, :block_executions, :signoffs]
    ])
  end

  defp maybe_reload_with_associations(%StepExecution{id: id}) do
    StepExecution
    |> Repo.get!(id)
    |> Repo.preload([:step, :block_executions, :signoffs])
    |> then(fn se -> %{se | step: Repo.preload(se.step, :blocks)} end)
  end

  defp maybe_reload_with_associations(%BlockExecution{id: id}) do
    BlockExecution
    |> Repo.get!(id)
    |> Repo.preload(:block)
  end

  defp maybe_reload_with_associations(%StepSignoff{id: id}) do
    StepSignoff
    |> Repo.get!(id)
    |> Repo.preload(:user)
  end

  defp maybe_reload_with_associations(other), do: other

  # Broadcasts event via PubSub
  defp broadcast_event(%ProcedureExecution{id: id} = execution, event_type) do
    do_broadcast("execution:#{id}", {event_type, execution})
    maybe_broadcast_mission_event(execution, event_type)
  end

  defp broadcast_event(%StepExecution{procedure_execution_id: exec_id} = step, event_type) do
    do_broadcast("execution:#{exec_id}", {event_type, step})
    maybe_broadcast_step_event(step, event_type)
  end

  defp broadcast_event(%BlockExecution{} = block, event_type) do
    block = Repo.preload(block, step_execution: [])
    exec_id = block.step_execution.procedure_execution_id
    do_broadcast("execution:#{exec_id}", {event_type, block})
  end

  defp broadcast_event(%StepSignoff{} = signoff, event_type) do
    signoff = Repo.preload(signoff, step_execution: [])
    exec_id = signoff.step_execution.procedure_execution_id
    do_broadcast("execution:#{exec_id}", {event_type, signoff})
  end

  defp broadcast_event(_result, _event_type), do: :ok

  defp do_broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Cadence.PubSub, topic, message)
  end

  defp maybe_broadcast_mission_event(execution, :execution_started) do
    event = ProcedureExecutionEvent.started(execution)
    broadcast_procedure_event(execution.mission_id, event)
  end

  defp maybe_broadcast_mission_event(execution, {:execution_status_changed, status}) do
    event_type =
      case status do
        :completed -> :completed
        :failed -> :failed
        :paused -> :paused
        :pausing -> :pausing
        :cancelled -> :cancelled
        :running -> :resumed
        _ -> nil
      end

    if event_type do
      event =
        ProcedureExecutionEvent.new(%{
          event_type: event_type,
          execution_id: execution.id,
          procedure_id: execution.procedure_id,
          procedure_name: safe_procedure_name(execution),
          mission_id: execution.mission_id,
          organization_id: execution.organization_id,
          target_id: execution.target_id,
          status: execution.status,
          triggered_by: execution.triggered_by,
          triggered_by_user_id: execution.triggered_by_user_id,
          parameters: execution.parameters,
          error_message: execution.error_message,
          step_index: execution.error_step_index,
          started_at: execution.started_at,
          completed_at: execution.completed_at
        })

      broadcast_procedure_event(execution.mission_id, event)
    end
  end

  defp maybe_broadcast_mission_event(_execution, _event_type), do: :ok

  defp maybe_broadcast_step_event(step_exec, :step_activated) do
    execution = load_execution_for_step(step_exec)
    step_info = step_info(step_exec)
    event = ProcedureExecutionEvent.step_started(execution, step_info.position, step_info)
    broadcast_procedure_event(execution.mission_id, event)
  end

  defp maybe_broadcast_step_event(step_exec, :step_completed) do
    execution = load_execution_for_step(step_exec)
    step_info = step_info(step_exec)
    event = ProcedureExecutionEvent.step_completed(execution, step_info.position, step_info)
    broadcast_procedure_event(execution.mission_id, event)
  end

  defp maybe_broadcast_step_event(_step_exec, _event_type), do: :ok

  defp broadcast_procedure_event(mission_id, event) do
    do_broadcast("mission:#{mission_id}:procedures", {:procedure_event, event})
  end

  defp load_execution_for_step(step_exec) do
    ProcedureExecution
    |> Repo.get!(step_exec.procedure_execution_id)
    |> Repo.preload(:procedure)
  end

  defp step_info(step_exec) do
    step = step_exec.step || Repo.preload(step_exec, :step).step

    %{
      id: step.id,
      name: step.name,
      title: step.title,
      position: step.position || 0
    }
  end

  defp safe_procedure_name(%ProcedureExecution{procedure: %Procedure{name: name}}), do: name
  defp safe_procedure_name(_), do: nil

  # Helper to get current UTC time without microseconds (for Ecto :utc_datetime fields)
  defp utc_now do
    CadenceTime.now() |> DateTime.truncate(:second)
  end
end
