defmodule Cadence.Application.Commanding.EnqueueCommand do
  @moduledoc """
  Use case module for adding commands to the execution queue.

  This module handles queuing commands for later execution,
  including priority assignment, scheduling, and validation.

  ## Usage

      # Queue a command with normal priority
      {:ok, entry} = EnqueueCommand.enqueue(%{
        organization_id: org_id,
        mission_id: mission_id,
        target_id: target_id,
        user_id: user_id,
        command_name: "POWER_ON",
        parameters: %{"subsystem" => "camera"}
      })

      # Queue with high priority
      {:ok, entry} = EnqueueCommand.enqueue(%{...}, priority: 1)

      # Schedule for future execution
      {:ok, entry} = EnqueueCommand.schedule(%{...}, scheduled_at)
  """

  alias Cadence.Domain.Commanding.Entities.QueuedCommand
  alias Cadence.Ports.Recordings.EventRecorder

  @type enqueue_attrs :: %{
          required(:organization_id) => String.t(),
          required(:mission_id) => String.t(),
          required(:target_id) => String.t(),
          required(:command_name) => String.t(),
          optional(:user_id) => String.t() | nil,
          optional(:parameters) => map(),
          optional(:dispatch_opts) => map(),
          optional(:metadata) => map()
        }

  @type enqueue_opts :: [
          priority: 0..5,
          scheduled_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          max_attempts: pos_integer()
        ]

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

  @doc """
  Enqueues a command for execution.

  Creates a new queue entry with the specified attributes and options.
  The command will be executed when the target's queue processor
  reaches it (based on priority and sequence).

  ## Parameters

  - `attrs` - Command attributes (see type spec)
  - `opts` - Queue options:
    - `:priority` - Priority level 0-5 (default: 3)
    - `:scheduled_at` - Earliest execution time
    - `:expires_at` - Expiration time
    - `:max_attempts` - Maximum retry attempts (default: 3)

  ## Returns

  - `{:ok, entry}` - Successfully queued
  - `{:error, reason}` - Validation or other error
  """
  @spec enqueue(enqueue_attrs(), enqueue_opts()) ::
          {:ok, QueuedCommand.t()} | {:error, term()}
  def enqueue(attrs, opts \\ []) do
    entity_attrs = build_entity_attrs(attrs, opts)

    with {:ok, command} <- QueuedCommand.new(entity_attrs),
         {:ok, saved} <- repo().enqueue(command) do
      broadcast_enqueued(saved)
      {:ok, saved}
    end
  end

  @doc """
  Schedules a command for future execution.

  Convenience function that sets the scheduled_at time.

  ## Parameters

  - `attrs` - Command attributes
  - `scheduled_at` - When to execute the command
  - `opts` - Additional queue options
  """
  @spec schedule(enqueue_attrs(), DateTime.t(), enqueue_opts()) ::
          {:ok, QueuedCommand.t()} | {:error, term()}
  def schedule(attrs, scheduled_at, opts \\ []) do
    enqueue(attrs, Keyword.put(opts, :scheduled_at, scheduled_at))
  end

  @doc """
  Enqueues an emergency command (priority 0).

  Emergency commands bypass the normal queue and execute immediately.
  Use sparingly - typically for safety-critical operations.

  ## Parameters

  - `attrs` - Command attributes
  - `opts` - Additional queue options (priority is forced to 0)
  """
  @spec enqueue_emergency(enqueue_attrs(), enqueue_opts()) ::
          {:ok, QueuedCommand.t()} | {:error, term()}
  def enqueue_emergency(attrs, opts \\ []) do
    enqueue(attrs, Keyword.put(opts, :priority, 0))
  end

  @doc """
  Enqueues multiple commands as a batch.

  All commands are queued with sequential sequence numbers
  to maintain ordering within the same priority level.

  ## Parameters

  - `commands` - List of `{attrs, opts}` tuples
  - `base_opts` - Options applied to all commands

  ## Returns

  - `{:ok, entries}` - All successfully queued
  - `{:error, {index, reason}}` - Failed at specified index
  """
  @spec enqueue_batch([{enqueue_attrs(), enqueue_opts()}], enqueue_opts()) ::
          {:ok, [QueuedCommand.t()]} | {:error, {non_neg_integer(), term()}}
  def enqueue_batch(commands, base_opts \\ []) do
    commands
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{attrs, opts}, index}, {:ok, acc} ->
      merged_opts = Keyword.merge(base_opts, opts)

      case enqueue(attrs, merged_opts) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> {:halt, {:error, {index, reason}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_entity_attrs(attrs, opts) do
    %{
      organization_id: attrs[:organization_id],
      mission_id: attrs[:mission_id],
      target_id: attrs[:target_id],
      user_id: attrs[:user_id],
      command_name: attrs[:command_name],
      parameters: attrs[:parameters] || %{},
      priority: Keyword.get(opts, :priority, 3),
      scheduled_at: Keyword.get(opts, :scheduled_at),
      expires_at: Keyword.get(opts, :expires_at),
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      dispatch_opts: attrs[:dispatch_opts] || %{},
      metadata: attrs[:metadata] || %{}
    }
  end

  defp broadcast_enqueued(%QueuedCommand{target_id: target_id, user_id: user_id} = entry) do
    topic = "target:#{target_id}:queue"
    event_publisher().publish(topic, {:command_enqueued, entry})

    # Record the enqueue event
    recorder().record(:command_queued, entry, user_id, %{})
  rescue
    _ -> :ok
  end
end
