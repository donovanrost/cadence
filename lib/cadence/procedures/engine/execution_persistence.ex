defmodule Cadence.Procedures.Engine.ExecutionPersistence do
  @moduledoc """
  Handles all database persistence for procedure executions.

  This module provides a centralized API for persisting execution state,
  ensuring proper transaction boundaries and atomic operations.

  ## Design Principles

  1. **Atomic operations** - Related writes happen in transactions
  2. **Broadcast after commit** - PubSub notifications only happen after DB commits
  3. **Idempotent where possible** - Safe to retry on transient failures
  4. **Outbox pattern** - All events persisted to outbox for reliable delivery

  ## Usage

      # Update status with a log entry atomically
      ExecutionPersistence.update_status_with_log(execution, :running, :info, "Started")

      # Persist a step event with its log entry
      ExecutionPersistence.persist_step_event(execution, "step_1", :completed, %{result: 42})
  """

  require Logger

  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Repo
  alias Cadence.Procedures
  alias Cadence.Procedures.ProcedureLog
  alias Cadence.Procedures.Events.StepEvent
  alias Cadence.Procedures.Events.ExecutionEvent
  alias Ecto.Multi

  @doc """
  Updates execution status and creates a log entry atomically.

  The status update, log entry, and outbox event are persisted in a single transaction.
  PubSub broadcast happens only after the transaction commits.

  ## Options

  - `:skip_outbox` - If true, don't persist to outbox (default: false)

  ## Examples

      {:ok, execution} = update_status_with_log(execution, :running, %{started_at: now}, :info, "Started")
      {:error, changeset} = update_status_with_log(execution, :completed, %{}, :info, "Done")
  """
  @spec update_status_with_log(
          Cadence.Procedures.ProcedureExecution.t(),
          atom(),
          map(),
          atom(),
          String.t(),
          keyword()
        ) ::
          {:ok, Cadence.Procedures.ProcedureExecution.t()} | {:error, term()}
  def update_status_with_log(
        execution,
        new_status,
        extra_attrs \\ %{},
        log_level,
        log_message,
        opts \\ []
      ) do
    attrs = Map.merge(%{status: new_status}, extra_attrs)
    skip_outbox = Keyword.get(opts, :skip_outbox, false)

    # Build the multi transaction
    multi =
      Multi.new()
      |> Multi.run(:execution, fn _repo, _changes ->
        Procedures.update_execution_status(execution, attrs)
      end)
      |> Multi.insert(:log, fn %{execution: updated} ->
        build_log_changeset(updated.id, log_level, log_message)
      end)

    # Add outbox event if not skipped
    multi =
      if skip_outbox do
        multi
      else
        Multi.insert(multi, :outbox_event, fn %{execution: updated} ->
          ExecutionEvent.new(updated, new_status, extra_attrs)
        end)
      end

    case Repo.transaction(multi) do
      {:ok, %{execution: updated_execution}} ->
        # Broadcast AFTER transaction commits
        broadcast_status_change(updated_execution, new_status)
        broadcast_log(updated_execution.id, log_level, log_message)
        {:ok, updated_execution}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp build_log_changeset(execution_id, level, message, step_index \\ nil) do
    attrs = %{
      execution_id: execution_id,
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      step_index: step_index
    }

    ProcedureLog.changeset(%ProcedureLog{}, attrs)
  end

  @doc """
  Creates a standalone log entry for an execution.

  Use this for log entries that don't need to be atomic with other operations.
  """
  @spec create_log_entry(String.t(), atom(), String.t(), integer() | nil) ::
          {:ok, ProcedureLog.t()} | {:error, Ecto.Changeset.t()}
  def create_log_entry(execution_id, level, message, step_index \\ nil) do
    attrs = %{
      execution_id: execution_id,
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      step_index: step_index
    }

    %ProcedureLog{}
    |> ProcedureLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a log entry and broadcasts it.

  Convenience function that combines persistence and broadcast.
  """
  @spec persist_and_broadcast_log(String.t(), atom(), String.t(), integer() | nil) :: :ok
  def persist_and_broadcast_log(execution_id, level, message, step_index \\ nil) do
    case create_log_entry(execution_id, level, message, step_index) do
      {:ok, _log} ->
        broadcast_log(execution_id, level, message)
        :ok

      {:error, reason} ->
        Logger.warning("Failed to persist log entry: #{inspect(reason)}")
        # Still broadcast even if persistence fails - better UX
        broadcast_log(execution_id, level, message)
        :ok
    end
  end

  @doc """
  Saves checkpoint state atomically.

  Used for pause/resume support to track execution progress.
  """
  @spec save_checkpoint(Cadence.Procedures.ProcedureExecution.t(), integer(), binary() | nil) ::
          {:ok, Cadence.Procedures.ProcedureExecution.t()} | {:error, term()}
  def save_checkpoint(execution, step_index, checkpoint_state \\ nil) do
    attrs = %{
      current_step_index: step_index,
      checkpoint_state: checkpoint_state
    }

    Procedures.update_execution_status(execution, attrs)
  end

  @doc """
  Persists a step event with its associated log entry atomically.

  This is the primary function for recording step state changes. It:
  1. Inserts the event to the outbox (source of truth)
  2. Creates a log entry for the step status change
  3. Optionally persists user log messages (for log steps)
  4. Broadcasts to PubSub after the transaction commits

  ## Options

  - `:idempotency_key` - Optional key for idempotent inserts (used in resume)

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec persist_step_event(
          Cadence.Procedures.ProcedureExecution.t(),
          String.t(),
          atom(),
          term(),
          keyword()
        ) :: :ok | {:error, term()}
  def persist_step_event(execution, step_name, status, data, opts \\ []) do
    {level, message} = step_status_to_log(status, step_name, data)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    # Build the multi transaction - all inserts are atomic
    multi =
      Multi.new()
      |> Multi.insert(
        :step_event,
        StepEvent.new(execution, step_name, status, data, idempotency_key: idempotency_key),
        upsert_opts(idempotency_key)
      )
      |> Multi.insert(:log, build_log_changeset(execution.id, level, message))

    # Add user log if this is a completed log step with a message
    multi = maybe_add_user_log_to_multi(multi, execution.id, status, data)

    case Repo.transaction(multi) do
      {:ok, results} ->
        # Broadcast AFTER transaction commits
        broadcast_step_event(execution.id, status, step_name, data)
        broadcast_log(execution.id, level, message)

        # Broadcast user log if it was added
        if Map.has_key?(results, :user_log) do
          {user_level, user_message} = extract_user_log_info(data)
          broadcast_log(execution.id, user_level, user_message)
        end

        :ok

      {:error, _step, reason, _changes} ->
        Logger.error("Failed to persist step event for #{step_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Generate upsert options for idempotent inserts
  defp upsert_opts(nil), do: []
  defp upsert_opts(_key), do: [on_conflict: :nothing, conflict_target: [:idempotency_key]]

  # Add user log to multi if this is a completed log step with a message
  defp maybe_add_user_log_to_multi(multi, execution_id, :completed, data) when is_map(data) do
    message = Map.get(data, :message) || Map.get(data, "message")

    if message do
      {level, _msg} = extract_user_log_info(data)
      Multi.insert(multi, :user_log, build_log_changeset(execution_id, level, message))
    else
      multi
    end
  end

  defp maybe_add_user_log_to_multi(multi, _execution_id, _status, _data), do: multi

  defp extract_user_log_info(data) do
    level = Map.get(data, :level) || Map.get(data, "level") || :info
    level = if is_binary(level), do: String.to_atom(level), else: level
    message = Map.get(data, :message) || Map.get(data, "message") || ""
    {level, message}
  end

  @doc """
  Persists DAG execution results atomically.

  Updates the execution record with all step tracking data, final status,
  and writes the corresponding outbox event for event sourcing.
  """
  @spec persist_dag_result(
          Cadence.Procedures.ProcedureExecution.t(),
          atom(),
          map()
        ) :: {:ok, Cadence.Procedures.ProcedureExecution.t()} | {:error, term()}
  def persist_dag_result(execution, final_status, result) do
    completed_at = if(final_status in [:completed, :failed, :cancelled], do: DateTime.utc_now())

    attrs = %{
      status: final_status,
      completed_at: completed_at,
      completed_steps: result.completed_steps,
      skipped_steps: result.skipped_steps,
      failed_steps: result.failed_steps,
      blocked_steps: result.blocked_steps,
      step_results: result.step_results
    }

    attrs =
      if final_status == :failed do
        failed_names = Enum.join(result.failed_steps || [], ", ")
        Map.put(attrs, :error_message, "Steps failed: #{failed_names}")
      else
        attrs
      end

    # Build transaction with execution update + outbox event
    multi =
      Multi.new()
      |> Multi.run(:execution, fn _repo, _changes ->
        Procedures.update_execution_status(execution, attrs)
      end)
      |> Multi.insert(:outbox_event, fn %{execution: updated} ->
        event_data = %{
          completed_at: completed_at,
          completed_steps: result.completed_steps,
          skipped_steps: result.skipped_steps,
          failed_steps: result.failed_steps,
          blocked_steps: result.blocked_steps,
          error_message: attrs[:error_message]
        }

        ExecutionEvent.new(updated, final_status, event_data)
      end)

    case Repo.transaction(multi) do
      {:ok, %{execution: updated}} ->
        broadcast_status_change(updated, final_status)
        {:ok, updated}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp step_status_to_log(:running, step_name, _data) do
    {:info, "Step started: #{step_name}"}
  end

  defp step_status_to_log(:completed, step_name, _data) do
    {:info, "Step completed: #{step_name}"}
  end

  defp step_status_to_log(:failed, step_name, data) do
    reason = extract_error_from_data(data)
    {:error, "Step failed: #{step_name} - #{reason}"}
  end

  defp step_status_to_log(:blocked, step_name, _data) do
    {:warn, "Step blocked: #{step_name}"}
  end

  defp step_status_to_log(:skipped, step_name, _data) do
    {:info, "Step skipped: #{step_name}"}
  end

  defp step_status_to_log(:timed_out, step_name, _data) do
    {:error, "Step timed out: #{step_name}"}
  end

  defp step_status_to_log(status, step_name, _data) do
    {:info, "Step #{status}: #{step_name}"}
  end

  defp extract_error_from_data(data) when is_map(data) do
    Map.get(data, :error) || Map.get(data, "error") || inspect(data)
  end

  defp extract_error_from_data(data), do: inspect(data)

  # ============================================================================
  # Broadcasting
  # ============================================================================

  defp event_publisher, do: EventPublisher.impl()

  defp broadcast_status_change(execution, new_status) do
    topic = "procedure:#{execution.id}"
    event_publisher().publish(topic, {:status_changed, new_status, execution})
  end

  defp broadcast_log(execution_id, level, message) do
    topic = "procedure:#{execution_id}"
    event_publisher().publish(topic, {:log, level, message})
  end

  defp broadcast_step_event(execution_id, status, step_name, data) do
    topic = "procedure:#{execution_id}"
    event = dag_status_to_event(status, step_name, data)
    event_publisher().publish(topic, event)
  end

  defp dag_status_to_event(:running, step_name, data), do: {:dag_step_started, step_name, data}

  defp dag_status_to_event(:completed, step_name, data),
    do: {:dag_step_completed, step_name, data}

  defp dag_status_to_event(:failed, step_name, data), do: {:dag_step_failed, step_name, data}
  defp dag_status_to_event(:blocked, step_name, data), do: {:dag_step_blocked, step_name, data}
  defp dag_status_to_event(:skipped, step_name, data), do: {:dag_step_skipped, step_name, data}

  defp dag_status_to_event(:timed_out, step_name, data),
    do: {:dag_step_timed_out, step_name, data}

  defp dag_status_to_event(status, step_name, data),
    do: {:dag_step_status, step_name, status, data}
end
