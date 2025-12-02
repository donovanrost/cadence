defmodule Cadence.Outbox do
  @moduledoc """
  Context module for the transactional outbox pattern.

  The outbox pattern ensures reliable event delivery by storing events in the
  same database transaction as the domain operation. A separate processor
  consumes these events and broadcasts them via PubSub.

  ## Architecture

      ┌─────────────────────────────────────────────────────────────┐
      │ Domain Operation (Ecto.Multi)                               │
      │                                                             │
      │  Multi.new()                                                │
      │  |> Multi.insert(:entry, queue_entry_changeset)             │
      │  |> Outbox.append(multi, :outbox, %{...})                  │
      │  |> Repo.transaction()                                      │
      └─────────────────────────────────────────────────────────────┘
                           │
                           ▼
      ┌─────────────────────────────────────────────────────────────┐
      │ Outbox.Processor (GenServer)                                │
      │                                                             │
      │  - Polls for unprocessed events                             │
      │  - Writes to audit_logs                                     │
      │  - Broadcasts to PubSub                                     │
      │  - Marks as processed                                       │
      └─────────────────────────────────────────────────────────────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
      audit_logs      PubSub Topics   (future)
      (persistent)

  ## PubSub Topics

  Events are broadcast to multiple topics for flexible subscription:

  - `outbox:event:{event_type}` - Subscribe to specific event types
  - `outbox:mission:{mission_id}` - Subscribe to all events for a mission
  - `outbox:org:{organization_id}` - Subscribe to all events for an organization

  ## Usage

      # In a context module with Ecto.Multi
      def enqueue_command(mission, command_name, params, opts) do
        Multi.new()
        |> Multi.insert(:entry, build_entry_changeset(...))
        |> Outbox.append(:outbox, fn %{entry: entry} ->
          %{
            organization_id: mission.organization_id,
            mission_id: mission.id,
            event_type: "command_enqueued",
            aggregate_type: "command_queue_entry",
            aggregate_id: entry.id,
            actor_id: opts[:user_id],
            actor_type: "user",
            payload: %{command_name: command_name, priority: entry.priority}
          }
        end)
        |> Repo.transaction()
      end
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Outbox.Event
  alias Ecto.Multi

  @pubsub Cadence.PubSub
  @max_attempts 5

  # ============================================================================
  # Multi Integration
  # ============================================================================

  @doc """
  Appends an outbox event to an Ecto.Multi.

  The attrs can be a map or a function that receives the results of previous
  Multi operations and returns a map.

  ## Example

      Multi.new()
      |> Multi.insert(:entry, entry_changeset)
      |> Outbox.append(:outbox, fn %{entry: entry} ->
        %{
          organization_id: org_id,
          event_type: "command_enqueued",
          aggregate_type: "command_queue_entry",
          aggregate_id: entry.id
        }
      end)
      |> Repo.transaction()
  """
  @spec append(Multi.t(), atom(), map() | (map() -> map())) :: Multi.t()
  def append(multi, name, attrs) when is_map(attrs) do
    Multi.insert(multi, name, Event.new(attrs))
  end

  def append(multi, name, attrs_fn) when is_function(attrs_fn, 1) do
    Multi.insert(multi, name, fn changes ->
      attrs = attrs_fn.(changes)
      Event.new(attrs)
    end)
  end

  # ============================================================================
  # Direct Insert (for simple cases without Multi)
  # ============================================================================

  @doc """
  Inserts an outbox event directly.

  Prefer using `append/3` with Ecto.Multi for transactional guarantees.
  This function is useful for standalone events that don't need to be
  part of a larger transaction.
  """
  @spec insert(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    attrs
    |> Event.new()
    |> Repo.insert()
  end

  # ============================================================================
  # Event Queries
  # ============================================================================

  @doc """
  Fetches a batch of unprocessed events for processing.

  Events are returned in insertion order to maintain causality.
  """
  @spec fetch_pending(keyword()) :: [Event.t()]
  def fetch_pending(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(e in Event,
      where: is_nil(e.processed_at),
      where: is_nil(e.dead_lettered_at),
      order_by: [asc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Fetches pending events for a specific mission.
  """
  @spec fetch_pending_for_mission(String.t(), keyword()) :: [Event.t()]
  def fetch_pending_for_mission(mission_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(e in Event,
      where: e.mission_id == ^mission_id,
      where: is_nil(e.processed_at),
      where: is_nil(e.dead_lettered_at),
      order_by: [asc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Fetches dead-lettered events for review.
  """
  @spec fetch_dead_letters(keyword()) :: [Event.t()]
  def fetch_dead_letters(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    org_id = Keyword.get(opts, :organization_id)

    query =
      from(e in Event,
        where: not is_nil(e.dead_lettered_at),
        order_by: [desc: e.dead_lettered_at],
        limit: ^limit
      )

    query =
      if org_id do
        from(e in query, where: e.organization_id == ^org_id)
      else
        query
      end

    Repo.all(query)
  end

  # ============================================================================
  # Event Processing
  # ============================================================================

  @doc """
  Marks an event as successfully processed.
  """
  @spec mark_processed(Event.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def mark_processed(%Event{} = event) do
    event
    |> Event.processed_changeset()
    |> Repo.update()
  end

  @doc """
  Records a processing failure for an event.

  If the event has exceeded max attempts, it will be dead-lettered.
  """
  @spec mark_failed(Event.t(), term()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def mark_failed(%Event{} = event, error) do
    if event.attempts >= @max_attempts - 1 do
      event
      |> Event.dead_letter_changeset(error)
      |> Repo.update()
    else
      event
      |> Event.failure_changeset(error)
      |> Repo.update()
    end
  end

  @doc """
  Retries a dead-lettered event by resetting its state.
  """
  @spec retry_dead_letter(Event.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def retry_dead_letter(%Event{dead_lettered_at: dead_lettered_at} = event)
      when not is_nil(dead_lettered_at) do
    event
    |> Ecto.Changeset.change(%{
      dead_lettered_at: nil,
      attempts: 0,
      last_error: nil
    })
    |> Repo.update()
  end

  def retry_dead_letter(_event), do: {:error, :not_dead_lettered}

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  @doc """
  Broadcasts an event to all relevant PubSub topics.

  Events are broadcast to:
  - `outbox:event:{event_type}`
  - `outbox:org:{organization_id}`
  - `outbox:mission:{mission_id}` (if mission-scoped)
  """
  @spec broadcast(Event.t()) :: :ok
  def broadcast(%Event{} = event) do
    message = {:outbox_event, event}

    topics = [
      "outbox:event:#{event.event_type}",
      "outbox:org:#{event.organization_id}"
    ]

    topics =
      if event.mission_id do
        ["outbox:mission:#{event.mission_id}" | topics]
      else
        topics
      end

    Enum.each(topics, fn topic ->
      Phoenix.PubSub.broadcast(@pubsub, topic, message)
    end)
  end

  @doc """
  Subscribes the current process to outbox events for a mission.
  """
  @spec subscribe_mission(String.t()) :: :ok | {:error, term()}
  def subscribe_mission(mission_id) do
    Phoenix.PubSub.subscribe(@pubsub, "outbox:mission:#{mission_id}")
  end

  @doc """
  Subscribes the current process to outbox events for an organization.
  """
  @spec subscribe_organization(String.t()) :: :ok | {:error, term()}
  def subscribe_organization(organization_id) do
    Phoenix.PubSub.subscribe(@pubsub, "outbox:org:#{organization_id}")
  end

  @doc """
  Subscribes the current process to a specific event type.
  """
  @spec subscribe_event_type(String.t()) :: :ok | {:error, term()}
  def subscribe_event_type(event_type) do
    Phoenix.PubSub.subscribe(@pubsub, "outbox:event:#{event_type}")
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Returns counts of events by processing state.
  """
  @spec stats(keyword()) :: map()
  def stats(opts \\ []) do
    org_id = Keyword.get(opts, :organization_id)

    base_query =
      if org_id do
        from(e in Event, where: e.organization_id == ^org_id)
      else
        from(e in Event)
      end

    pending =
      from(e in base_query,
        where: is_nil(e.processed_at),
        where: is_nil(e.dead_lettered_at),
        select: count(e.id)
      )
      |> Repo.one()

    processed =
      from(e in base_query,
        where: not is_nil(e.processed_at),
        select: count(e.id)
      )
      |> Repo.one()

    dead_lettered =
      from(e in base_query,
        where: not is_nil(e.dead_lettered_at),
        select: count(e.id)
      )
      |> Repo.one()

    %{
      pending: pending,
      processed: processed,
      dead_lettered: dead_lettered,
      total: pending + processed + dead_lettered
    }
  end

  # ============================================================================
  # Cleanup
  # ============================================================================

  @doc """
  Deletes processed events older than the specified age.

  This is useful for periodic cleanup to prevent unbounded table growth.

  ## Options

  - `:older_than` - Delete events processed before this DateTime (required)
  - `:organization_id` - Limit to specific organization
  - `:batch_size` - Max events to delete per call (default: 1000)
  """
  @spec cleanup_processed(keyword()) :: {:ok, non_neg_integer()}
  def cleanup_processed(opts) do
    older_than = Keyword.fetch!(opts, :older_than)
    org_id = Keyword.get(opts, :organization_id)
    batch_size = Keyword.get(opts, :batch_size, 1000)

    query =
      from(e in Event,
        where: not is_nil(e.processed_at),
        where: e.processed_at < ^older_than,
        limit: ^batch_size
      )

    query =
      if org_id do
        from(e in query, where: e.organization_id == ^org_id)
      else
        query
      end

    {count, _} = Repo.delete_all(query)
    {:ok, count}
  end
end
