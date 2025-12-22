defmodule Cadence.Ports.Repository.Commanding.QueueRepository do
  @moduledoc """
  Port (behavior) defining the contract for command queue persistence operations.

  This behavior abstracts the queue storage from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryQueueRepository` - In-memory for tests
  """

  alias Cadence.Domain.Commanding.Entities.QueuedCommand

  @type id :: String.t()
  @type mission_id :: String.t()
  @type target_id :: String.t()
  @type status :: :pending | :executing | :completed | :failed | :cancelled | :expired
  @type priority :: 0..5
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds a queue entry by ID.

  Returns `{:ok, entry}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, QueuedCommand.t()} | {:error, :not_found}

  @doc """
  Persists a queue entry (insert or update).

  Returns `{:ok, entry}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(QueuedCommand.t()) :: {:ok, QueuedCommand.t()} | {:error, error()}

  @doc """
  Lists queue entries for a mission with optional filtering.

  ## Options

  - `:status` - Filter by status(es)
  - `:target_id` - Filter by specific target
  - `:priority` - Filter by priority level(s)
  - `:limit` - Maximum number of results
  - `:order` - Sort order (default: priority ASC, sequence_number ASC)
  """
  @callback list(mission_id(), opts()) :: [QueuedCommand.t()]

  @doc """
  Lists queue entries for a specific target.
  """
  @callback list_for_target(target_id(), opts()) :: [QueuedCommand.t()]

  @doc """
  Gets the next entry ready for execution.

  Returns the highest-priority, oldest entry that is:
  - Status is :pending
  - scheduled_at is nil or in the past
  - Not expired

  Atomically marks the entry as :executing to prevent double-dispatch.
  """
  @callback claim_next(target_id()) :: {:ok, QueuedCommand.t()} | {:error, :queue_empty}

  @doc """
  Counts entries by status for a target.

  Returns a map like `%{pending: 5, executing: 1, completed: 100, ...}`.
  """
  @callback count_by_status(target_id()) :: %{status() => non_neg_integer()}

  @doc """
  Counts entries by status for a mission (all targets).

  Returns a map like `%{pending: 5, executing: 1, completed: 100, ...}`.
  """
  @callback count_by_status_for_mission(mission_id()) :: %{status() => non_neg_integer()}

  @doc """
  Enqueues a new command, assigning it the next sequence number.

  Returns `{:ok, entry}` with the persisted entity including sequence number.
  """
  @callback enqueue(QueuedCommand.t()) :: {:ok, QueuedCommand.t()} | {:error, error()}

  @doc """
  Lists pending entries for a target ready for execution.

  ## Options

  - `:limit` - Maximum number of results
  - `:include_scheduled` - Include future-scheduled entries (default: false)
  """
  @callback list_pending(target_id(), opts()) :: [QueuedCommand.t()]

  @doc """
  Cancels all pending entries for a target.

  Used when a target goes offline or queue is cleared.
  Returns the count of cancelled entries.
  """
  @callback cancel_all_pending(target_id()) :: {:ok, non_neg_integer()}

  @doc """
  Expires entries that have passed their expiration time.

  Returns the count of expired entries.
  """
  @callback expire_old_entries(DateTime.t()) :: {:ok, non_neg_integer()}

  @doc """
  Reorders entries in the queue.

  Takes a list of `{entry_id, new_sequence_number}` tuples.
  """
  @callback reorder([{id(), non_neg_integer()}]) :: :ok | {:error, term()}

  @doc """
  Lists expired entries that should be marked as expired.
  """
  @callback list_expired() :: [QueuedCommand.t()]

  @doc """
  Deletes a queue entry by ID.
  """
  @callback delete(id()) :: {:ok, QueuedCommand.t()} | {:error, :not_found}

  @doc """
  Returns the configured queue repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(:cadence, :queue_repository, Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository)
  end
end
