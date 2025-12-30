defmodule Cadence.Application.Commanding.ManageQueue do
  @moduledoc """
  Use case module for managing the command execution queue.

  This module provides operations for queue lifecycle management:
  - Claiming commands for execution
  - Marking commands as completed/failed
  - Retrying failed commands
  - Cancelling pending commands
  - Queue maintenance operations

  ## Usage

      # Claim next command for execution
      {:ok, entry} = ManageQueue.claim_next(target_id)

      # Mark as completed
      {:ok, entry} = ManageQueue.complete(entry_id, command_log_id)

      # Mark as failed (may retry)
      {:ok, entry} = ManageQueue.fail(entry_id, "Connection timeout")

      # Cancel pending commands
      {:ok, count} = ManageQueue.cancel_all_pending(target_id)
  """

  alias Cadence.Application.Commanding.CommandQueries
  alias Cadence.Domain.Commanding.Entities.QueuedCommand
  alias Cadence.Ports.Recordings.EventRecorder

  @type target_id :: String.t()
  @type entry_id :: String.t()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :queue_repository,
      Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository
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

  # Get configured event recorder
  defp recorder do
    EventRecorder.impl()
  end

  # ===========================================================================
  # Execution Lifecycle
  # ===========================================================================

  @doc """
  Claims the next pending command for execution.

  Atomically transitions the highest priority pending command
  to `:executing` status. Uses row-level locking to prevent
  double-claiming in concurrent scenarios.

  ## Parameters

  - `target_id` - Target UUID

  ## Returns

  - `{:ok, entry}` - Successfully claimed
  - `{:error, :queue_empty}` - No pending commands
  - `{:error, reason}` - Other error
  """
  @spec claim_next(target_id()) :: {:ok, QueuedCommand.t()} | {:error, term()}
  def claim_next(target_id) do
    case repo().claim_next(target_id) do
      {:ok, entry} ->
        broadcast_claimed(entry)
        {:ok, entry}

      error ->
        error
    end
  end

  @doc """
  Marks a command as successfully completed.

  Records the command log ID for reference and transitions
  to terminal `:completed` status.

  ## Parameters

  - `entry_id` - Queue entry UUID
  - `command_log_id` - Optional command log reference

  ## Returns

  - `{:ok, entry}` - Successfully completed
  - `{:error, :not_found}` - Entry not found
  - `{:error, {:invalid_transition, from, to}}` - Not in executing status
  """
  @spec complete(entry_id(), String.t() | nil) :: {:ok, QueuedCommand.t()} | {:error, term()}
  def complete(entry_id, command_log_id \\ nil) do
    with {:ok, entry} <- CommandQueries.find(entry_id),
         {:ok, updated} <- QueuedCommand.complete(entry, command_log_id),
         {:ok, saved} <- repo().save(updated) do
      broadcast_completed(saved)
      {:ok, saved}
    end
  end

  @doc """
  Marks a command as failed.

  Records the error message. The command may be automatically
  retried if under the max_attempts limit.

  ## Parameters

  - `entry_id` - Queue entry UUID
  - `error_message` - Description of the failure

  ## Returns

  - `{:ok, entry}` - Marked as failed
  - `{:error, :not_found}` - Entry not found
  - `{:error, {:invalid_transition, from, to}}` - Not in executing status
  """
  @spec fail(entry_id(), String.t()) :: {:ok, QueuedCommand.t()} | {:error, term()}
  def fail(entry_id, error_message) do
    with {:ok, entry} <- CommandQueries.find(entry_id),
         {:ok, updated} <- QueuedCommand.fail(entry, error_message),
         {:ok, saved} <- repo().save(updated) do
      broadcast_failed(saved)
      {:ok, saved}
    end
  end

  @doc """
  Retries a failed command.

  Returns the command to `:pending` status so it can be
  claimed again. Only works if attempts < max_attempts.

  ## Parameters

  - `entry_id` - Queue entry UUID

  ## Returns

  - `{:ok, entry}` - Successfully returned to pending
  - `{:error, :not_found}` - Entry not found
  - `{:error, :max_attempts_exceeded}` - Already at max attempts
  - `{:error, {:not_retriable, status}}` - Not in failed status
  """
  @spec retry(entry_id()) :: {:ok, QueuedCommand.t()} | {:error, term()}
  def retry(entry_id) do
    with {:ok, entry} <- CommandQueries.find(entry_id),
         {:ok, updated} <- QueuedCommand.retry(entry),
         {:ok, saved} <- repo().save(updated) do
      broadcast_retried(saved)
      {:ok, saved}
    end
  end

  # ===========================================================================
  # Cancellation
  # ===========================================================================

  @doc """
  Cancels a specific queue entry.

  Can cancel entries in `:pending` or `:failed` status.

  ## Parameters

  - `entry_id` - Queue entry UUID

  ## Returns

  - `{:ok, entry}` - Successfully cancelled
  - `{:error, :not_found}` - Entry not found
  - `{:error, {:invalid_transition, from, to}}` - Cannot cancel this status
  """
  @spec cancel(entry_id()) :: {:ok, QueuedCommand.t()} | {:error, term()}
  def cancel(entry_id) do
    with {:ok, entry} <- CommandQueries.find(entry_id),
         {:ok, updated} <- QueuedCommand.cancel(entry),
         {:ok, saved} <- repo().save(updated) do
      broadcast_cancelled(saved)
      {:ok, saved}
    end
  end

  @doc """
  Cancels all pending commands for a target.

  Used when a target goes offline or queue processing is stopped.

  ## Parameters

  - `target_id` - Target UUID

  ## Returns

  - `{:ok, count}` - Number of entries cancelled
  """
  @spec cancel_all_pending(target_id()) :: {:ok, non_neg_integer()}
  def cancel_all_pending(target_id) do
    case repo().cancel_all_pending(target_id) do
      {:ok, count} ->
        event_publisher().publish("target:#{target_id}:queue", {:commands_cleared, target_id})
        {:ok, count}

      error ->
        error
    end
  end

  # ===========================================================================
  # Priority Management
  # ===========================================================================

  @doc """
  Updates the priority of a pending command.

  ## Parameters

  - `entry_id` - Queue entry UUID
  - `priority` - New priority level (0-5)

  ## Returns

  - `{:ok, entry}` - Priority updated
  - `{:error, :not_found}` - Entry not found
  - `{:error, {:cannot_change_priority, status}}` - Not pending
  - `{:error, :invalid_priority}` - Invalid priority value
  """
  @spec set_priority(entry_id(), 0..5) :: {:ok, QueuedCommand.t()} | {:error, term()}
  def set_priority(entry_id, priority) do
    with {:ok, entry} <- CommandQueries.find(entry_id),
         {:ok, updated} <- QueuedCommand.set_priority(entry, priority),
         {:ok, saved} <- repo().save(updated) do
      broadcast_reordered(saved)
      {:ok, saved}
    end
  end

  # ===========================================================================
  # Maintenance
  # ===========================================================================

  @doc """
  Expires all entries that have passed their expiration time.

  Called periodically by a background job.

  ## Returns

  - `{:ok, count}` - Number of entries expired
  """
  @spec expire_old_entries() :: {:ok, non_neg_integer()}
  def expire_old_entries do
    repo().expire_old_entries(DateTime.utc_now())
  end

  @doc """
  Retries all failed entries that haven't exceeded max attempts.

  Called periodically for automatic retry of transient failures.

  ## Parameters

  - `target_id` - Target UUID

  ## Returns

  - `{:ok, count}` - Number of entries retried
  """
  @spec retry_all_retriable(target_id()) :: {:ok, non_neg_integer()}
  def retry_all_retriable(target_id) do
    # Get failed entries, filter retriable, retry each
    count =
      target_id
      |> list_failed()
      |> Enum.filter(&QueuedCommand.retriable?/1)
      |> Enum.count(fn entry ->
        case retry(entry.id) do
          {:ok, _} -> true
          _ -> false
        end
      end)

    {:ok, count}
  end

  defp list_failed(target_id) do
    # TODO: Add list_by_status to repository
    repo().list_pending(target_id, limit: 1000)
    |> Enum.filter(&(&1.status == :failed))
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp broadcast_claimed(%QueuedCommand{target_id: target_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_claimed, entry})
  rescue
    _ -> :ok
  end

  defp broadcast_completed(%QueuedCommand{target_id: target_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_completed, entry})

    # Record the dequeue event
    recorder().record(:command_dequeued, entry, nil, %{reason: "completed"})
  rescue
    _ -> :ok
  end

  defp broadcast_failed(%QueuedCommand{target_id: target_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_failed, entry})

    # Record the dequeue event
    recorder().record(:command_dequeued, entry, nil, %{reason: "failed"})
  rescue
    _ -> :ok
  end

  defp broadcast_cancelled(%QueuedCommand{target_id: target_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_cancelled, entry})

    # Record the dequeue event
    recorder().record(:command_dequeued, entry, nil, %{reason: "cancelled"})
  rescue
    _ -> :ok
  end

  defp broadcast_retried(%QueuedCommand{target_id: target_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_retried, entry})
  rescue
    _ -> :ok
  end

  defp broadcast_reordered(%QueuedCommand{target_id: target_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_reordered, entry})
  rescue
    _ -> :ok
  end
end
