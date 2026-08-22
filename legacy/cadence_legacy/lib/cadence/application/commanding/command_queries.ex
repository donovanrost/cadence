defmodule Cadence.Application.Commanding.CommandQueries do
  @moduledoc """
  Use case module for querying command queue entries.

  Provides read-only operations for listing, counting, and finding
  queued commands and their execution status.

  ## Usage

      # List pending commands for a target
      commands = CommandQueries.list_pending(target_id)

      # Count by status
      counts = CommandQueries.count_by_status(target_id)

      # Find specific entry
      {:ok, entry} = CommandQueries.find(entry_id)
  """

  alias Cadence.Domain.Commanding.Entities.QueuedCommand

  @type target_id :: String.t()
  @type entry_id :: String.t()
  @type opts :: keyword()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :queue_repository,
      Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository
    )
  end

  @doc """
  Finds a queue entry by ID.

  Returns `{:ok, entry}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(entry_id()) :: {:ok, QueuedCommand.t()} | {:error, :not_found}
  def find(id), do: repo().find(id)

  @doc """
  Finds a queue entry by ID, raising if not found.
  """
  @spec find!(entry_id()) :: QueuedCommand.t()
  def find!(id) do
    case find(id) do
      {:ok, entry} -> entry
      {:error, :not_found} -> raise "Queue entry not found: #{id}"
    end
  end

  @doc """
  Lists pending commands for a target.

  Returns commands in priority order (highest priority first).

  ## Options

  - `:limit` - Maximum number of results (default: 100)
  - `:include_scheduled` - Include future-scheduled commands (default: false)

  ## Examples

      # Ready-to-execute commands
      CommandQueries.list_pending(target_id)

      # Include scheduled commands
      CommandQueries.list_pending(target_id, include_scheduled: true)
  """
  @spec list_pending(target_id(), opts()) :: [QueuedCommand.t()]
  def list_pending(target_id, opts \\ []) do
    repo().list_pending(target_id, opts)
  end

  @doc """
  Counts queue entries by status for a target.

  Returns a map of status to count.

  ## Example

      %{
        pending: 5,
        executing: 1,
        completed: 42,
        failed: 2,
        cancelled: 0,
        expired: 1
      }
  """
  @spec count_by_status(target_id()) :: map()
  def count_by_status(target_id) do
    repo().count_by_status(target_id)
  end

  @doc """
  Counts total pending commands for a target.
  """
  @spec count_pending(target_id()) :: non_neg_integer()
  def count_pending(target_id) do
    counts = count_by_status(target_id)
    counts[:pending] || 0
  end

  @doc """
  Checks if the queue is empty for a target.
  """
  @spec queue_empty?(target_id()) :: boolean()
  def queue_empty?(target_id) do
    count_pending(target_id) == 0
  end

  @doc """
  Gets the next command that would be executed.

  Returns the highest priority, earliest sequence pending command
  that is ready (not scheduled for the future, not expired).

  Does NOT claim the command - use ManageQueue.claim_next/1 for that.
  """
  @spec peek_next(target_id()) :: QueuedCommand.t() | nil
  def peek_next(target_id) do
    case list_pending(target_id, limit: 1) do
      [cmd] -> cmd
      [] -> nil
    end
  end

  @doc """
  Checks if there are any emergency (priority 0) commands pending.
  """
  @spec has_emergency?(target_id()) :: boolean()
  def has_emergency?(target_id) do
    case peek_next(target_id) do
      %QueuedCommand{priority: 0} -> true
      _ -> false
    end
  end
end
