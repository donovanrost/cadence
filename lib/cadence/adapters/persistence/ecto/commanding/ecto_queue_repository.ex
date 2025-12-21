defmodule Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository do
  @moduledoc """
  Ecto-based implementation of the QueueRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for queued commands using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :queue_repository, Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository

  Then accessed via:

      repo = Application.get_env(:cadence, :queue_repository)
      {:ok, entries} = repo.list_pending(target_id, limit: 10)
  """

  @behaviour Cadence.Ports.Repository.Commanding.QueueRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Commands.QueueEntry, as: QueueEntrySchema
  alias Cadence.Domain.Commanding.Entities.QueuedCommand, as: QueuedCommandEntity

  # ===========================================================================
  # QueueRepository Implementation
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(QueueEntrySchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def save(%QueuedCommandEntity{id: nil} = entity) do
    # Insert new queue entry
    attrs = to_schema_attrs(entity)

    %QueueEntrySchema{}
    |> QueueEntrySchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%QueuedCommandEntity{id: id} = entity) do
    # Update existing queue entry
    case Repo.get(QueueEntrySchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> update_changeset(entity)
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def enqueue(%QueuedCommandEntity{} = entity) do
    # Assign next sequence number within the target's queue
    next_seq = get_next_sequence(entity.target_id)
    entity_with_seq = %{entity | sequence_number: next_seq}

    save(entity_with_seq)
  end

  @impl true
  def list_pending(target_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    include_scheduled = Keyword.get(opts, :include_scheduled, false)

    query =
      from q in QueueEntrySchema,
        where: q.target_id == ^target_id,
        where: q.status == :pending,
        order_by: [asc: q.priority, asc: q.sequence_number],
        limit: ^limit

    query =
      if include_scheduled do
        query
      else
        now = DateTime.utc_now()

        from q in query,
          where: is_nil(q.scheduled_at) or q.scheduled_at <= ^now
      end

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def claim_next(target_id) do
    now = DateTime.utc_now()

    # Find the highest priority, earliest sequence pending entry
    query =
      from q in QueueEntrySchema,
        where: q.target_id == ^target_id,
        where: q.status == :pending,
        where: is_nil(q.scheduled_at) or q.scheduled_at <= ^now,
        where: is_nil(q.expires_at) or q.expires_at > ^now,
        order_by: [asc: q.priority, asc: q.sequence_number],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED"

    Repo.transaction(fn ->
      case Repo.one(query) do
        nil ->
          {:error, :queue_empty}

        schema ->
          # Transition to executing
          attrs = %{
            status: :executing,
            attempts: schema.attempts + 1,
            last_attempt_at: now
          }

          case schema |> QueueEntrySchema.execution_changeset(attrs) |> Repo.update() do
            {:ok, updated} -> {:ok, to_entity(updated)}
            {:error, changeset} -> {:error, extract_errors(changeset)}
          end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def count_by_status(target_id) do
    query =
      from q in QueueEntrySchema,
        where: q.target_id == ^target_id,
        group_by: q.status,
        select: {q.status, count(q.id)}

    query
    |> Repo.all()
    |> Enum.into(%{})
  end

  @impl true
  def cancel_all_pending(target_id) do
    now = DateTime.utc_now()

    query =
      from q in QueueEntrySchema,
        where: q.target_id == ^target_id,
        where: q.status == :pending

    {count, _} =
      Repo.update_all(query,
        set: [status: :cancelled, updated_at: now]
      )

    {:ok, count}
  end

  @impl true
  def expire_old_entries(before_time) do
    query =
      from q in QueueEntrySchema,
        where: q.status == :pending,
        where: not is_nil(q.expires_at),
        where: q.expires_at < ^before_time

    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(query,
        set: [status: :expired, updated_at: now]
      )

    {:ok, count}
  end

  @impl true
  def list(mission_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    target_id = Keyword.get(opts, :target_id)
    priority = Keyword.get(opts, :priority)
    limit = Keyword.get(opts, :limit, 100)

    query =
      from q in QueueEntrySchema,
        where: q.mission_id == ^mission_id,
        order_by: [asc: q.priority, asc: q.sequence_number],
        limit: ^limit

    query = apply_filters(query, status: status, target_id: target_id, priority: priority)

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def list_for_target(target_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    priority = Keyword.get(opts, :priority)
    limit = Keyword.get(opts, :limit, 100)

    query =
      from q in QueueEntrySchema,
        where: q.target_id == ^target_id,
        order_by: [asc: q.priority, asc: q.sequence_number],
        limit: ^limit

    query = apply_filters(query, status: status, priority: priority)

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def reorder(id_sequence_pairs) do
    Repo.transaction(fn ->
      Enum.each(id_sequence_pairs, fn {id, new_seq} ->
        from(q in QueueEntrySchema, where: q.id == ^id)
        |> Repo.update_all(set: [sequence_number: new_seq, updated_at: DateTime.utc_now()])
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_expired do
    now = DateTime.utc_now()

    from(q in QueueEntrySchema,
      where: q.status == :pending,
      where: not is_nil(q.expires_at),
      where: q.expires_at < ^now
    )
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def delete(id) do
    case Repo.get(QueueEntrySchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(QueueEntrySchema.t()) :: QueuedCommandEntity.t()
  def to_entity(%QueueEntrySchema{} = schema) do
    %QueuedCommandEntity{
      id: schema.id,
      organization_id: schema.organization_id,
      mission_id: schema.mission_id,
      target_id: schema.target_id,
      user_id: schema.user_id,
      command_name: schema.command_name,
      parameters: schema.parameters || %{},
      status: schema.status,
      priority: schema.priority,
      sequence_number: schema.sequence_number,
      scheduled_at: schema.scheduled_at,
      expires_at: schema.expires_at,
      attempts: schema.attempts,
      max_attempts: schema.max_attempts,
      last_attempt_at: schema.last_attempt_at,
      last_error: schema.last_error,
      command_log_id: schema.command_log_id,
      dispatch_opts: schema.dispatch_opts || %{},
      metadata: schema.metadata || %{},
      created_at: schema.inserted_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for insertion.
  """
  @spec to_schema_attrs(QueuedCommandEntity.t()) :: map()
  def to_schema_attrs(%QueuedCommandEntity{} = entity) do
    %{
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      target_id: entity.target_id,
      user_id: entity.user_id,
      command_name: entity.command_name,
      parameters: entity.parameters,
      status: entity.status,
      priority: entity.priority,
      sequence_number: entity.sequence_number,
      scheduled_at: entity.scheduled_at,
      expires_at: entity.expires_at,
      max_attempts: entity.max_attempts,
      dispatch_opts: entity.dispatch_opts,
      metadata: entity.metadata
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_next_sequence(target_id) do
    query =
      from q in QueueEntrySchema,
        where: q.target_id == ^target_id,
        select: max(q.sequence_number)

    case Repo.one(query) do
      nil -> 1
      max_seq -> max_seq + 1
    end
  end

  defp update_changeset(schema, entity) do
    import Ecto.Changeset

    attrs = %{
      status: entity.status,
      priority: entity.priority,
      sequence_number: entity.sequence_number,
      attempts: entity.attempts,
      last_attempt_at: entity.last_attempt_at,
      last_error: entity.last_error,
      command_log_id: entity.command_log_id,
      metadata: entity.metadata
    }

    schema
    |> cast(attrs, Map.keys(attrs))
  end

  defp handle_result({:ok, schema}), do: {:ok, to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, nil}, q -> q
      {:status, statuses}, q when is_list(statuses) -> from(e in q, where: e.status in ^statuses)
      {:status, status}, q -> from(e in q, where: e.status == ^status)
      {:target_id, nil}, q -> q
      {:target_id, target_id}, q -> from(e in q, where: e.target_id == ^target_id)
      {:priority, nil}, q -> q
      {:priority, priorities}, q when is_list(priorities) -> from(e in q, where: e.priority in ^priorities)
      {:priority, priority}, q -> from(e in q, where: e.priority == ^priority)
    end)
  end
end
